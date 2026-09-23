import Foundation
import Darwin
import CryptoKit

@_silgen_name("flock") private func systemFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

/// Owns the current recovery-v2 file for the life of the process. The exclusive
/// lock keeps another current-version instance from claiming its autosave.
/// Older versions only use the separate, read-only-to-us recovery.json inbox.
public final class RecoveryFileStore {
    public enum StoreError: Error {
        case alreadyInUse
        case cannotOpenLock(Int32)
        case cannotLock(Int32)
        case legacyPathMatchesCurrent
        case cannotReadFile(URL, Int32)
        case notRegularFile(URL)
        case fileTooLarge(URL)
        case invalidDirectory(URL)
    }

    /// Recovery JSON is metadata, never embedded media. Reject unbounded input
    /// before allocating it, including files that grow while being read.
    private static let maximumRecoveryBytes = 64 * 1024 * 1024
    private static let maximumAcknowledgementBytes = 4 * 1024

    /// Only the shipped bundle ID may share the production recovery directory.
    /// Unexpected and QA bundle IDs remain deterministic but isolated.
    public static func storageDirectoryName(for bundleID: String?) -> String {
        guard let bundleID else { return "circlr-unknown-bundle" }
        if bundleID == "com.circlr.desktop" { return "circlr" }
        if bundleID.hasPrefix("com.circlr."), bundleID.hasSuffix("qa") {
            let name = String(bundleID.dropFirst("com.circlr.".count).dropLast(2))
            if !name.isEmpty, name.utf8.count <= 48,
               name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) {
                return "circlr-\(name)-qa"
            }
        }
        return "circlr-unrecognized-\(sha256(Data(bundleID.utf8)))"
    }

    public struct LegacySnapshot {
        public let data: Data
        public let sha256: String
    }
    private struct LegacyAcknowledgement: Codable { let sha256: String }
    private struct LegacyRecovery: Decodable {
        let project: Project
        let root: URL?
        let date: Date
    }

    public let url: URL
    public let legacyURL: URL
    private let lockDescriptor: Int32
    private let acknowledgementURL: URL
    private var ownedBytes: Data?

    public init(url: URL, legacyURL: URL? = nil) throws {
        self.url = url
        self.legacyURL = legacyURL ?? url.deletingLastPathComponent().appendingPathComponent("recovery.json")
        guard url.standardizedFileURL != self.legacyURL.standardizedFileURL else {throw StoreError.legacyPathMatchesCurrent}
        acknowledgementURL = url.deletingLastPathComponent().appendingPathComponent("legacy-recovery-ack.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let storageDirectory=url.deletingLastPathComponent()
        var directoryInfo=stat()
        guard Darwin.lstat(storageDirectory.path,&directoryInfo) == 0,
              directoryInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw StoreError.invalidDirectory(storageDirectory)
        }
        let lockURL = url.deletingPathExtension().appendingPathExtension("lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw StoreError.cannotOpenLock(errno) }
        guard systemFlock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            if code == EWOULDBLOCK { throw StoreError.alreadyInUse }
            throw StoreError.cannotLock(code)
        }
        lockDescriptor = descriptor
    }

    deinit {
        _ = systemFlock(lockDescriptor, LOCK_UN)
        _ = Darwin.close(lockDescriptor)
    }

    /// Reading alone does not grant permission to overwrite or delete a recovery.
    public func read() throws -> Data? {
        try Self.readRegularFile(at: url, maximumBytes: Self.maximumRecoveryBytes)
    }

    /// Claim exactly the file that was presented in the user's recovery prompt.
    @discardableResult public func adopt(_ expected: Data) throws -> Bool {
        guard try read() == expected else { return false }
        ownedBytes = expected
        return true
    }

    /// Write only when no other writer has replaced the last file this session owned.
    @discardableResult public func write(_ data: Data) throws -> Bool {
        guard data.count <= Self.maximumRecoveryBytes else {throw StoreError.fileTooLarge(url)}
        guard try read() == ownedBytes else { return false }
        try data.write(to: url, options: .atomic)
        ownedBytes = data
        return true
    }

    /// Delete only a snapshot written or explicitly adopted by this session.
    @discardableResult public func removeOwned() throws -> Bool {
        guard let ownedBytes, try read() == ownedBytes else { return false }
        try FileManager.default.removeItem(at: url)
        self.ownedBytes = nil
        return true
    }

    /// Discard only the exact snapshot the user was offered at startup.
    @discardableResult public func removeUnchanged(_ expected: Data) throws -> Bool {
        guard try read() == expected else { return false }
        try FileManager.default.removeItem(at: url)
        ownedBytes = nil
        return true
    }

    /// Keep unreadable/unknown-schema bytes outside the live recovery slot.
    /// The source is renamed only if it still equals the snapshot just read.
    public func quarantineUnchanged(_ expected: Data) throws -> URL? {
        guard try read() == expected else { return nil }
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent("recovery-v2-unreadable-\(UUID().uuidString).json")
        try FileManager.default.moveItem(at: url, to: destination)
        ownedBytes = nil
        return destination
    }

    /// Legacy recovery is an inbox owned by older app versions. Never mutate it.
    public func pendingLegacy() throws -> LegacySnapshot? {
        guard let data=try Self.readRegularFile(at:legacyURL,maximumBytes:Self.maximumRecoveryBytes) else{return nil}
        let hash=Self.sha256(data)
        let acknowledgementData=try Self.readRegularFile(at:acknowledgementURL,maximumBytes:Self.maximumAcknowledgementBytes)
        let acknowledged=acknowledgementData.flatMap{try? JSONDecoder().decode(LegacyAcknowledgement.self,from:$0)}
        guard acknowledged?.sha256 != hash else{return nil}
        return LegacySnapshot(data:data,sha256:hash)
    }

    /// A legacy file may be kept indefinitely after ACK. Preserve a managed
    /// demo copy only if that recovery names its root, or if it cannot be read.
    public func legacyMayReference(_ root:URL) -> Bool {
        do {
            guard let data=try Self.readRegularFile(at:legacyURL,maximumBytes:Self.maximumRecoveryBytes) else{return false}
            let recovery=try JSONDecoder().decode(LegacyRecovery.self,from:data)
            guard let recordedRoot=recovery.root else{return false}
            return recordedRoot.standardizedFileURL.resolvingSymlinksInPath()
                == root.standardizedFileURL.resolvingSymlinksInPath()
        } catch {return true}
    }

    /// A foreign or unreadable v2 snapshot may still own the old media root.
    /// Only this session's decodable snapshot can prove it is unrelated.
    public func currentMayReference(_ root:URL) -> Bool {
        do {
            guard let data=try read() else{return false}
            guard let ownedBytes,data==ownedBytes else{return true}
            let recovery=try JSONDecoder().decode(LegacyRecovery.self,from:data)
            guard let recordedRoot=recovery.root else{return false}
            return recordedRoot.standardizedFileURL.resolvingSymlinksInPath()
                == root.standardizedFileURL.resolvingSymlinksInPath()
        } catch {return true}
    }

    /// The ACK records only the reviewed bytes. If an older app later writes new
    /// bytes, its new hash remains unacknowledged and its file remains untouched.
    @discardableResult public func acknowledgeLegacy(_ snapshot:LegacySnapshot) throws -> Bool {
        // An existing acknowledgement must not be a symlink, pipe, or oversized
        // input. The atomic replacement below then keeps the ACK local to us.
        _ = try Self.readRegularFile(at:acknowledgementURL,maximumBytes:Self.maximumAcknowledgementBytes)
        let acknowledgement=try JSONEncoder().encode(LegacyAcknowledgement(sha256:snapshot.sha256))
        try acknowledgement.write(to:acknowledgementURL,options:.atomic)
        guard let current=try Self.readRegularFile(at:legacyURL,maximumBytes:Self.maximumRecoveryBytes) else{return false}
        return Self.sha256(current)==snapshot.sha256
    }

    /// Open without following the final path component or blocking on FIFOs.
    /// fstat prevents reads from devices/sockets; the loop also enforces the
    /// limit if another process extends a regular file after the initial stat.
    private static func readRegularFile(at fileURL:URL,maximumBytes:Int) throws -> Data? {
        let descriptor=Darwin.open(fileURL.path,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0 {
            if errno == ENOENT {return nil}
            throw StoreError.cannotReadFile(fileURL,errno)
        }
        defer{_ = Darwin.close(descriptor)}
        var fileInfo=stat()
        guard Darwin.fstat(descriptor,&fileInfo) == 0 else {throw StoreError.cannotReadFile(fileURL,errno)}
        guard fileInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {throw StoreError.notRegularFile(fileURL)}
        guard fileInfo.st_size >= 0, fileInfo.st_size <= maximumBytes else {throw StoreError.fileTooLarge(fileURL)}
        var data=Data()
        data.reserveCapacity(Int(fileInfo.st_size))
        var chunk=[UInt8](repeating:0,count:64 * 1024)
        while true {
            let bytesRead=chunk.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor,buffer.baseAddress,buffer.count)
            }
            if bytesRead < 0 {
                if errno == EINTR {continue}
                throw StoreError.cannotReadFile(fileURL,errno)
            }
            if bytesRead == 0 {return data}
            guard bytesRead <= maximumBytes - data.count else {throw StoreError.fileTooLarge(fileURL)}
            data.append(contentsOf:chunk.prefix(bytesRead))
        }
    }

    private static func sha256(_ data:Data)->String {
        SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
}
