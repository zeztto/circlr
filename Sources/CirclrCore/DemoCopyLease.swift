import Foundation
import Darwin

/// Owns only a newly created demo copy. Existing projects are never enrolled or swept.
/// Readers must call retainIfManaged before loading a managed copy. That permanently
/// excludes it from automatic reclamation, including after another session exits.
public final class DemoCopyLease {
    public let root: URL
    private let baseline: Project
    private let token = UUID().uuidString
    private let inventory: [String: String]
    private var finished = false

    public init(root: URL, project: Project) throws {
        self.root = root.standardizedFileURL
        baseline = project
        inventory = try Self.inventory(self.root)
        try Self.withLock(self.root) {
            let owner = Self.sidecar(self.root, "owner")
            guard !FileManager.default.fileExists(atPath: owner.path) else { throw CirclrError("데모 사본 소유권이 이미 있습니다") }
            try Self.writeExclusive(Data(token.utf8), to: owner)
        }
    }

    /// Fail closed. A retained marker is deliberately not removed by session cleanup.
    public static func retainIfManaged(_ root: URL) throws {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: sidecar(root, "owner").path) else { return }
        try withLock(root) {
            guard FileManager.default.fileExists(atPath: sidecar(root, "owner").path) else { return }
            let retained = sidecar(root, "retained")
            if !FileManager.default.fileExists(atPath: retained.path) {
                try writeExclusive(Data("external-reader\n".utf8), to: retained)
            }
        }
    }

    /// Call only after all current-session jobs have released the old media root and
    /// recovery has been cleared. Any uncertainty keeps the copy. Errors are nonfatal.
    @discardableResult public func releaseIfPristine(project: Project, recoveryPresent: Bool) -> Bool {
        guard !finished else { return false }
        finished = true
        var currentContent = project, originalContent = baseline
        // Camera/editor restoration is transient; musical/layout edits are not.
        currentContent.hierarchyView = nil; originalContent.hierarchyView = nil
        guard !recoveryPresent, currentContent == originalContent else { return false }
        do {
            return try Self.withLock(root) {
                guard !FileManager.default.fileExists(atPath: Self.sidecar(root, "retained").path),
                      try Data(contentsOf: Self.sidecar(root, "owner")) == Data(token.utf8),
                      try Self.inventory(root) == inventory else { return false }
                try FileManager.default.removeItem(at: root)
                // Keep lock/owner tombstones: removing a lock inode while another
                // reader waits on it would allow two independent locks for one path.
                return true
            }
        } catch { return false }
    }

    private static func sidecar(_ root: URL, _ suffix: String) -> URL {
        root.deletingLastPathComponent().appendingPathComponent(".circlr-demo-\(root.lastPathComponent).\(suffix)")
    }
    private static func writeExclusive(_ data: Data, to url: URL) throws {
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CirclrError("데모 사본 보호 정보를 기록할 수 없습니다") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        try file.write(contentsOf: data)
    }
    private static func withLock<T>(_ root: URL, _ body: () throws -> T) throws -> T {
        let fd = Darwin.open(sidecar(root, "lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CirclrError("데모 사본 잠금을 열 수 없습니다") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw CirclrError("데모 사본 잠금을 얻을 수 없습니다") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    private static func inventory(_ root: URL) throws -> [String: String] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        let rootValues = try root.resourceValues(forKeys: keys)
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true,
              root.resolvingSymlinksInPath().path == root.path else { throw CirclrError("데모 사본 경로를 확인하세요") }
        var enumerationFailed = false
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), errorHandler: { _, _ in enumerationFailed = true; return false }) else { throw CirclrError("데모 사본을 확인할 수 없습니다") }
        var result: [String: String] = [:]
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw CirclrError("링크가 포함된 데모 사본은 정리하지 않습니다") }
            let relative = String(file.path.dropFirst(root.path.count + 1))
            if values.isDirectory == true { result[relative] = "directory" }
            else if values.isRegularFile == true { result[relative] = try ProjectStore.checksum(file) }
            else { throw CirclrError("일반 파일이 아닌 데모 자산은 정리하지 않습니다") }
        }
        guard !enumerationFailed else { throw CirclrError("데모 사본 전체를 확인할 수 없습니다") }
        return result
    }
}
