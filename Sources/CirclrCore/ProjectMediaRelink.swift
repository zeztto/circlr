import Foundation
import Darwin
import AVFoundation

public enum ProjectMediaRelink {
    public struct Issue: Equatable {
        public let assetID: ID
        public let displayName: String
        public let reason: String
    }

    /// Reports missing/unreadable sources without guessing replacements by filename.
    public static func diagnostics(project: Project, root: URL?, checkCancellation: () throws -> Void = {}) throws -> [Issue] {
        try project.assets.compactMap { asset in
            try checkCancellation()
            do {
                let url = try ProjectStore.assetURL(asset, root: root)
                _ = try ProjectStore.regularMediaSize(url)
                if !asset.checksum.isEmpty {
                    let actual = try ProjectStore.checksum(url, checkCancellation: checkCancellation)
                    if actual.lowercased() != asset.checksum.lowercased() {
                        return Issue(assetID: asset.id, displayName: asset.name, reason: "미디어 내용이 저장된 원본과 다릅니다")
                    }
                }
                return nil
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return Issue(assetID: asset.id, displayName: asset.name, reason: "원본 미디어를 읽을 수 없습니다")
            }
        }
    }

    public struct PreparedRelink {
        public let project: Project
        private let candidate: URL
        private let identity: MediaFileIdentity
        fileprivate init(project: Project, candidate: URL, identity: MediaFileIdentity) {
            self.project = project; self.candidate = candidate; self.identity = identity
        }
        /// Fast document-commit guard after detached verification.
        public func validateCandidate() throws {
            guard try MediaFileIdentity.read(candidate) == identity else {
                throw CirclrError("확인한 미디어가 변경되었습니다. 다시 연결하세요")
            }
        }
    }

    /// Content equality preserves duration/format and all clip references. A legacy
    /// asset without a fingerprint cannot safely be identified as the same source.
    public static func relink(project: Project, root: URL?, assetID: ID, candidate: URL, allowUnverified: Bool = false, checkCancellation: () throws -> Void = {}) throws -> Project {
        try prepareRelink(project: project, root: root, assetID: assetID, candidate: candidate,
                          allowUnverified: allowUnverified, checkCancellation: checkCancellation).project
    }

    public static func prepareRelink(project: Project, root: URL?, assetID: ID, candidate: URL,
                                     allowUnverified: Bool = false,
                                     checkCancellation: () throws -> Void = {}) throws -> PreparedRelink {
        try checkCancellation()
        let candidateIdentity = try MediaFileIdentity.read(candidate)
        guard let index = project.assets.firstIndex(where: { $0.id == assetID }) else {
            throw CirclrError("재연결할 미디어가 없습니다")
        }
        let asset = project.assets[index]
        guard candidate.isFileURL else { throw CirclrError("로컬 미디어 파일을 선택하세요") }
        _ = try ProjectStore.regularMediaSize(candidate)
        let actualChecksum = try ProjectStore.checksum(candidate, checkCancellation: checkCancellation)
        if asset.checksum.isEmpty && allowUnverified {
            let audio = try AVAudioFile(forReading: candidate)
            let rate = audio.processingFormat.sampleRate
            let duration = Double(audio.length) / rate
            guard rate.isFinite, rate > 0, duration.isFinite,
                  abs(rate - asset.sampleRate) < 0.01,
                  abs(duration - asset.duration) <= max(1 / rate, 0.001) else {
                throw CirclrError("선택한 파일의 재생 시간 또는 sample rate가 원본과 다릅니다")
            }
        } else {
            guard asset.checksum.count == 64, asset.checksum.allSatisfy({ $0.isHexDigit }) else {
                throw CirclrError("원본 확인 정보가 없어 같은 파일인지 검증할 수 없습니다. 확인 후 다시 연결하세요")
            }
            guard actualChecksum.lowercased() == asset.checksum.lowercased() else {
                throw CirclrError("선택한 파일의 내용이 원본과 다릅니다. 이름이 같아도 재연결할 수 없습니다")
            }
        }
        try checkCancellation()
        var result = project
        result.assets[index].path = candidate.standardizedFileURL.path
        result.assets[index].checksum = actualChecksum
        let receipt = PreparedRelink(project: result, candidate: candidate, identity: candidateIdentity)
        try receipt.validateCandidate()
        return receipt
    }
}

public extension ProjectStore {
    struct PortableCopyPreflight: Equatable {
        public let assetCount: Int
        public let mediaBytes: Int64
        public let requiredBytes: Int64
        public let availableBytes: Int64
    }

    /// The full package is staged beside its destination; existing files are not
    /// reclaimed until publication. Preflight is advisory: writes remain fallible.
    static func portableCopyPreflight(project: Project, mediaRoot: URL?, destination: URL, checkCancellation: () throws -> Void = {}) throws -> PortableCopyPreflight {
        try checkCancellation()
        guard destination.isFileURL else { throw CirclrError("로컬 저장 위치를 선택하세요") }
        var bytes: Int64 = 0
        for asset in project.assets {
            try checkCancellation()
            let size = try regularMediaSize(assetURL(asset, root: mediaRoot))
            let (next, overflow) = bytes.addingReportingOverflow(size)
            guard !overflow else { throw CirclrError("미디어 복사 크기가 너무 큽니다") }
            bytes = next
        }
        let manifestBytes = try JSONEncoder().encode(project).count
        let (required, overflow) = bytes.addingReportingOverflow(Int64(manifestBytes) + 1_048_576)
        guard !overflow else { throw CirclrError("미디어 복사 크기가 너무 큽니다") }
        var parent = destination.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: parent.path), parent.path != "/" {
            parent.deleteLastPathComponent()
        }
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw CirclrError("선택한 위치에 쓸 권한이 없습니다")
        }
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: parent.path)
        guard let free = attributes[.systemFreeSize] as? NSNumber else {
            throw CirclrError("저장 위치의 여유 공간을 확인할 수 없습니다")
        }
        let available = free.int64Value
        guard required <= available else { throw CirclrError("전체 미디어 사본을 저장할 여유 공간이 부족합니다") }
        return PortableCopyPreflight(assetCount: project.assets.count, mediaBytes: bytes,
                                     requiredBytes: required, availableBytes: available)
    }

    internal static func regularMediaSize(_ url: URL) throws -> Int64 {
        let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW)
        guard fd >= 0 else { throw CirclrError("미디어 파일을 읽을 수 없습니다: \(url.lastPathComponent)") }
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size >= 0 else {
            throw CirclrError("미디어는 읽을 수 있는 일반 파일이어야 합니다")
        }
        return Int64(info.st_size)
    }
}

/// Metadata receipt includes ctime so in-place edits cannot hide by restoring mtime.
internal struct MediaFileIdentity: Equatable {
    let device: UInt64, inode: UInt64
    let size: Int64, modifiedSeconds: Int64, modifiedNanos: Int64, changedSeconds: Int64, changedNanos: Int64
    init(_ info: stat) {
        device = UInt64(info.st_dev); inode = UInt64(info.st_ino); size = Int64(info.st_size)
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec); modifiedNanos = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec); changedNanos = Int64(info.st_ctimespec.tv_nsec)
    }
    static func read(_ url: URL) throws -> Self {
        guard url.isFileURL else { throw CirclrError("로컬 미디어 파일을 선택하세요") }
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_size >= 0 else {
            throw CirclrError("미디어는 일반 파일이어야 합니다")
        }
        return Self(info)
    }
}
