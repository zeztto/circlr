import Foundation
import Darwin
import CirclrCore

/// Publishes an app-selected WAV without following a replacement export folder.
/// The destination is captured when the trusted turn is issued, before a model
/// request or asynchronous render can run.
enum TrustedExportPublisher {
    struct Destination: Equatable, Sendable {
        fileprivate let path: String
        fileprivate let parentPath: String
        fileprivate let fileName: String
        fileprivate let device: Int64
        fileprivate let inode: UInt64

        var url: URL { URL(fileURLWithPath: path) }
    }

    /// Capture both the selected pathname and the identity of its real parent.
    /// A symlink as the final parent component is never an export capability.
    static func capture(destination: URL) throws -> Destination {
        guard destination.isFileURL else { throw invalidDestination() }
        let url = destination.standardizedFileURL
        let parent = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        guard url.pathExtension == "wav", !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), parent.path != url.path else {
            throw invalidDestination()
        }
        let identity = try openMatchingParent(path: parent.path, expected: nil)
        defer { Darwin.close(identity.fd) }
        return Destination(path: url.path, parentPath: parent.path, fileName: name,
                           device: identity.device, inode: identity.inode)
    }

    /// Copy a private render stage into an exclusively created, hidden file in
    /// the pinned directory. This method is intended for a detached worker.
    static func prepare(source: URL, destination: Destination,
                        checkCancellation: @Sendable () throws -> Void = {}) throws -> Prepared {
        try checkCancellation()
        let parent = try openMatchingParent(path: destination.parentPath,
                                            expected: destination)
        let directoryFD = parent.fd
        let temporaryName = ".circlr-agent-export-\(UUID().uuidString).tmp"
        let outputFD = Darwin.openat(directoryFD, temporaryName,
                                     O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                     mode_t(0o600))
        guard outputFD >= 0 else {
            let error = posixError()
            Darwin.close(directoryFD)
            throw error
        }
        var keepTemporary = false
        defer {
            Darwin.close(outputFD)
            if !keepTemporary {
                Darwin.unlinkat(directoryFD, temporaryName, 0)
                Darwin.close(directoryFD)
            }
        }
        let sourceFD = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard sourceFD >= 0 else { throw posixError() }
        defer { Darwin.close(sourceFD) }
        var sourceInfo = stat()
        guard Darwin.fstat(sourceFD, &sourceInfo) == 0 else { throw posixError() }
        guard (sourceInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw CirclrError("WAV 임시 파일이 일반 파일이 아닙니다")
        }

        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            try checkCancellation()
            let count = Darwin.read(sourceFD, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if count == 0 { break }
            var written = 0
            while written < count {
                try checkCancellation()
                let step = buffer.withUnsafeBytes { raw -> Int in
                    Darwin.write(outputFD, raw.baseAddress! + written, count - written)
                }
                if step < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                guard step > 0 else { throw CirclrError("WAV 임시 파일을 복사하지 못했습니다") }
                written += step
            }
        }
        try checkCancellation()
        guard Darwin.fsync(outputFD) == 0 else { throw posixError() }
        try checkCancellation()
        keepTemporary = true
        return Prepared(destination: destination, directoryFD: directoryFD,
                        temporaryName: temporaryName)
    }

    /// Owns exactly one hidden temporary name and directory descriptor. The
    /// lock makes cancellation cleanup and final publication mutually exclusive.
    final class Prepared: @unchecked Sendable {
        private let destination: Destination
        private let temporaryName: String
        private let lock = NSLock()
        private var directoryFD: Int32
        private var consumed = false

        fileprivate init(destination: Destination, directoryFD: Int32,
                         temporaryName: String) {
            self.destination = destination
            self.directoryFD = directoryFD
            self.temporaryName = temporaryName
        }

        /// Call on the MainActor after the current lease/revision checks.
        /// `linkat` fails when any file, directory or symlink has appeared at
        /// the destination; an existing WAV is never replaced.
        func publish(authorize: () throws -> Void) throws {
            lock.lock()
            defer { lock.unlock() }
            guard !consumed, directoryFD >= 0 else { throw CancellationError() }
            let current = try TrustedExportPublisher.openMatchingParent(
                path: destination.parentPath, expected: destination)
            defer { Darwin.close(current.fd) }
            // Authorize immediately before the atomic exclusive operation.
            try authorize()
            guard Darwin.linkat(directoryFD, temporaryName,
                                directoryFD, destination.fileName, 0) == 0 else {
                if errno == EEXIST {
                    throw CirclrError("선택한 WAV 파일 이름이 이미 사용 중입니다")
                }
                throw TrustedExportPublisher.posixError()
            }
            consumed = true
            // A failed temp cleanup does not turn a published export into a
            // failed one. `discard`/deinit can still retry on the pinned fd.
            if Darwin.unlinkat(directoryFD, temporaryName, 0) == 0 {
                Darwin.close(directoryFD)
                directoryFD = -1
            }
        }

        /// Remove only the hidden file created by prepare; never the final WAV.
        func discard() {
            lock.lock()
            defer { lock.unlock() }
            guard directoryFD >= 0 else { return }
            Darwin.unlinkat(directoryFD, temporaryName, 0)
            Darwin.close(directoryFD)
            directoryFD = -1
            consumed = true
        }

        deinit { discard() }
    }

    private struct OpenParent {
        let fd: Int32
        let device: Int64
        let inode: UInt64
    }

    private static func openMatchingParent(path: String,
                                           expected: Destination?) throws -> OpenParent {
        var linkInfo = stat()
        guard Darwin.lstat(path, &linkInfo) == 0,
              (linkInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw CirclrError("선택한 WAV 폴더가 사라졌거나 변경되었습니다")
        }
        let fd = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            throw CirclrError("선택한 WAV 폴더를 안전하게 열지 못했습니다")
        }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0 else {
            let error = posixError()
            Darwin.close(fd)
            throw error
        }
        let device = Int64(info.st_dev)
        let inode = UInt64(info.st_ino)
        guard linkInfo.st_dev == info.st_dev, linkInfo.st_ino == info.st_ino,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              expected.map({ $0.device == device && $0.inode == inode }) ?? true else {
            Darwin.close(fd)
            throw CirclrError("선택한 WAV 폴더가 렌더 중 변경되었습니다")
        }
        return OpenParent(fd: fd, device: device, inode: inode)
    }

    private static func invalidDestination() -> CirclrError {
        CirclrError("사용자가 선택한 .wav 내보내기 위치가 필요합니다")
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
