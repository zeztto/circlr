import Foundation
import CryptoKit
import Darwin

public struct LoadedProject { public var project: Project; public var root: URL }

/// A prepared package is immutable to callers and safe to transfer from a
/// detached preparation task back to the document owner. Publication and
/// discard serialize through the lock; the contained Project is never mutated
/// after initialization. The owner must explicitly discard a rejected stage.
public final class StagedProjectSave: @unchecked Sendable {
    public let target: URL
    public let savedProject: Project
    fileprivate let staging: URL
    fileprivate let portableProject: Project
    fileprivate let expectedTarget: ProjectStore.TargetFingerprint?
    fileprivate let expectedStage: ProjectStore.TargetFingerprint
    fileprivate let stageIdentity: ProjectStore.StageIdentity
    fileprivate let stagedFiles: [String: ProjectStore.StageFileIdentity]
    fileprivate let lock = NSLock()
    fileprivate var consumed = false

    internal init(target: URL, staging: URL, portableProject: Project,
                  savedProject: Project, expectedTarget: ProjectStore.TargetFingerprint?,
                  expectedStage: ProjectStore.TargetFingerprint,
                  stageIdentity: ProjectStore.StageIdentity,
                  stagedFiles: [String: ProjectStore.StageFileIdentity]) {
        self.target = target
        self.staging = staging
        self.portableProject = portableProject
        self.savedProject = savedProject
        self.expectedTarget = expectedTarget
        self.expectedStage = expectedStage
        self.stageIdentity = stageIdentity
        self.stagedFiles = stagedFiles
    }
}

public enum ProjectStore {
    private static let maximumManifestBytes = 50_000_000

    internal struct StageIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        let mediaDevice: UInt64
        let mediaInode: UInt64
        init(root: stat, media: stat) {
            device = UInt64(root.st_dev)
            inode = UInt64(root.st_ino)
            mediaDevice = UInt64(media.st_dev)
            mediaInode = UInt64(media.st_ino)
        }
        func matchesRoot(_ info: stat) -> Bool { device == UInt64(info.st_dev) && inode == UInt64(info.st_ino) }
        func matchesMedia(_ info: stat) -> Bool { mediaDevice == UInt64(info.st_dev) && mediaInode == UInt64(info.st_ino) }
    }

    internal struct StageFileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        init(_ info: stat) {
            device = UInt64(info.st_dev)
            inode = UInt64(info.st_ino)
        }
        func matches(_ info: stat) -> Bool { device == UInt64(info.st_dev) && inode == UInt64(info.st_ino) }
    }

    private static func stageFileIdentity(_ url: URL) throws -> StageFileIdentity {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw CirclrError("저장 준비 파일을 확인할 수 없습니다")
        }
        return StageFileIdentity(info)
    }

    private static func stageIdentity(_ url: URL) throws -> StageIdentity {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw CirclrError("저장 준비 폴더를 확인할 수 없습니다")
        }
        var mediaInfo = stat()
        let media = url.appendingPathComponent("media")
        guard Darwin.lstat(media.path, &mediaInfo) == 0,
              mediaInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw CirclrError("저장 준비 미디어 폴더를 확인할 수 없습니다")
        }
        return StageIdentity(root: info, media: mediaInfo)
    }

    /// Quarantine atomically, then remove only our known files through pinned
    /// directory descriptors. Path replacement cannot redirect recursive
    /// deletion into someone else's directory; the final rmdir is non-recursive.
    private static func discardStage(at staging: URL, identity: StageIdentity,
                                     files: [String: StageFileIdentity]) {
        let quarantine = staging.deletingLastPathComponent()
            .appendingPathComponent(".circlr-discard-\(newID())")
        guard Darwin.renameatx_np(AT_FDCWD, staging.path, AT_FDCWD,
                                  quarantine.path, UInt32(RENAME_EXCL)) == 0 else { return }
        guard (try? stageIdentity(quarantine)) == identity else {
            if Darwin.renameatx_np(AT_FDCWD, quarantine.path, AT_FDCWD,
                                   staging.path, UInt32(RENAME_EXCL)) != 0 {
                FileHandle.standardError.write(Data(("circlr: 다른 저장 준비 폴더를 \(quarantine.path)에 보존했습니다\n").utf8))
            }
            return
        }
        let parentFD = Darwin.open(quarantine.deletingLastPathComponent().path,
                                   O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { return }
        defer { _ = Darwin.close(parentFD) }
        let name = quarantine.lastPathComponent
        let rootFD = Darwin.openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { return }
        defer { _ = Darwin.close(rootFD) }
        let mediaFD = Darwin.openat(rootFD, "media", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard mediaFD >= 0 else { return }
        defer { _ = Darwin.close(mediaFD) }
        var rootInfo = stat(), mediaInfo = stat()
        guard Darwin.fstat(rootFD, &rootInfo) == 0, identity.matchesRoot(rootInfo),
              Darwin.fstat(mediaFD, &mediaInfo) == 0, identity.matchesMedia(mediaInfo) else { return }
        var cleanupFailed = false
        for (relative, expectedFile) in files {
            let fd: Int32
            let basename: String
            if relative == "manifest.json" {
                fd = rootFD; basename = relative
            } else if relative.hasPrefix("media/") && relative.dropFirst(6).allSatisfy({ $0 != "/" }) {
                fd = mediaFD; basename = String(relative.dropFirst(6))
            } else {
                cleanupFailed = true; continue
            }
            var currentFile = stat()
            if Darwin.fstatat(fd, basename, &currentFile, AT_SYMLINK_NOFOLLOW) != 0 {
                if errno != ENOENT { cleanupFailed = true }
                continue
            }
            guard currentFile.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  expectedFile.matches(currentFile) else {
                cleanupFailed = true; continue
            }
            if Darwin.unlinkat(fd, basename, 0) != 0 && errno != ENOENT { cleanupFailed = true }
        }
        var currentMedia = stat(), currentRoot = stat()
        if !cleanupFailed,
           Darwin.fstatat(rootFD, "media", &currentMedia, AT_SYMLINK_NOFOLLOW) == 0,
           identity.matchesMedia(currentMedia),
           Darwin.unlinkat(rootFD, "media", AT_REMOVEDIR) == 0,
           Darwin.fstatat(parentFD, name, &currentRoot, AT_SYMLINK_NOFOLLOW) == 0,
           identity.matchesRoot(currentRoot),
           Darwin.unlinkat(parentFD, name, AT_REMOVEDIR) == 0 {
            return
        }
        FileHandle.standardError.write(Data(("circlr: 저장 준비 폴더를 \(quarantine.path)에 보존했습니다\n").utf8))
    }

    internal struct TargetFingerprint: Equatable {
        struct Stamp: Equatable {
            let device: UInt64
            let inode: UInt64
            let size: Int64
            let modifiedSeconds: Int64
            let modifiedNanoseconds: Int64

            init(_ value: stat) {
                device = UInt64(value.st_dev)
                inode = UInt64(value.st_ino)
                size = Int64(value.st_size)
                modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
                modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
            }
        }

        let root: Stamp
        let manifest: Stamp
        let manifestChecksum: String
        let media: [String: Stamp]
    }

    /// Snapshot only package-owned paths. This makes a slow preparation fail
    /// closed if another writer replaces or edits its target before publish.
    private static func targetFingerprint(_ url: URL) throws -> TargetFingerprint? {
        var rootInfo = stat()
        if Darwin.lstat(url.path, &rootInfo) != 0 {
            if errno == ENOENT { return nil }
            throw CirclrError("기존 곡 폴더를 확인할 수 없습니다")
        }
        guard rootInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw CirclrError("기존 일반 폴더를 프로젝트로 덮어쓸 수 없습니다")
        }
        let previous = try load(url)
        try requireOnlyProjectFiles(in: url, project: previous.project)
        let manifest = url.appendingPathComponent("manifest.json")
        var manifestInfo = stat()
        guard Darwin.lstat(manifest.path, &manifestInfo) == 0,
              manifestInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw CirclrError("프로젝트 manifest는 일반 파일이어야 합니다")
        }
        let manifestBytes = try readManifest(manifest)
        let manifestChecksum = SHA256.hash(data: manifestBytes).map { String(format: "%02x", $0) }.joined()
        var media: [String: TargetFingerprint.Stamp] = [:]
        for asset in previous.project.assets {
            let path = url.appendingPathComponent(asset.path)
            var info = stat()
            guard Darwin.lstat(path.path, &info) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
                throw CirclrError("기존 곡 미디어를 확인할 수 없습니다")
            }
            media[asset.path] = TargetFingerprint.Stamp(info)
        }
        return TargetFingerprint(root: .init(rootInfo), manifest: .init(manifestInfo),
                                 manifestChecksum: manifestChecksum, media: media)
    }

    private static func readManifest(_ url: URL) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW)
        guard fd >= 0 else { throw CirclrError("프로젝트 manifest는 일반 파일이어야 합니다") }
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw CirclrError("프로젝트 manifest는 일반 파일이어야 합니다")
        }
        guard info.st_size < maximumManifestBytes else { throw CirclrError("프로젝트 manifest가 너무 큽니다") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var data = Data()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            guard data.count + chunk.count < maximumManifestBytes else {
                throw CirclrError("프로젝트 manifest가 너무 큽니다")
            }
            data.append(chunk)
        }
        return data
    }

    private static func ownedPaths(in root: URL, project: Project) throws -> (files: Set<String>, directories: Set<String>) {
        var allowedFiles: Set<String> = ["manifest.json"]
        var allowedDirectories: Set<String> = ["media"]
        for asset in project.assets {
            let parts = asset.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !asset.path.hasPrefix("/"), !parts.isEmpty,
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  asset.path != "manifest.json" else {
                throw CirclrError("곡 미디어 경로를 확인할 수 없습니다")
            }
            let relative = asset.path
            allowedFiles.insert(relative)
            if parts.count > 1 {
                for count in 1..<parts.count {
                    allowedDirectories.insert(parts.prefix(count).joined(separator: "/"))
                }
            }
        }
        return (allowedFiles, allowedDirectories)
    }

    private static func requireOnlyProjectFiles(in root: URL, project: Project) throws {
        let (allowedFiles, allowedDirectories) = try ownedPaths(in: root, project: project)
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        var traversalFailed = false
        guard let entries = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
            errorHandler: { _, _ in traversalFailed = true; return false }) else {
            throw CirclrError("곡 폴더의 파일을 확인할 수 없습니다")
        }
        for case let entry as URL in entries {
            let entryPath = entry.standardizedFileURL.resolvingSymlinksInPath().path
            guard entryPath.hasPrefix(rootPath + "/") else {
                throw CirclrError("곡 폴더의 파일 경로를 확인할 수 없습니다")
            }
            let relative = String(entryPath.dropFirst(rootPath.count + 1))
            let kind = try entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            if kind.isSymbolicLink == true {
                throw CirclrError("곡 폴더에 링크가 있어 덮어쓸 수 없습니다. 다른 이름으로 저장하세요")
            }
            if kind.isDirectory == true {
                guard allowedDirectories.contains(relative) else {
                    throw CirclrError("곡 폴더에 프로젝트 외 파일이 있어 덮어쓸 수 없습니다. 다른 이름으로 저장하세요")
                }
            } else if kind.isRegularFile == true {
                guard allowedFiles.contains(relative) else {
                    throw CirclrError("곡 폴더에 프로젝트 외 파일이 있어 덮어쓸 수 없습니다. 다른 이름으로 저장하세요")
                }
            } else {
                throw CirclrError("곡 폴더에 일반 파일이 아닌 항목이 있어 덮어쓸 수 없습니다")
            }
        }
        guard !traversalFailed else { throw CirclrError("곡 폴더의 파일을 확인할 수 없습니다") }
    }

    /// Open each parent beneath the backup without following links. A late
    /// symlink in a parent component must never redirect cleanup outside it.
    private static func directoryFD(_ components: ArraySlice<Substring>, rootFD: Int32) throws -> Int32 {
        var fd = Darwin.dup(rootFD)
        guard fd >= 0 else { throw CirclrError("이전 곡 사본을 열 수 없습니다") }
        for component in components {
            let next = Darwin.openat(fd, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            _ = Darwin.close(fd)
            guard next >= 0 else { throw CirclrError("이전 곡 사본의 폴더가 변경됐습니다") }
            fd = next
        }
        return fd
    }

    /// Remove only known package paths; never recurse into newly added files.
    /// A failure can leave a *partial* backup, so callers report it as such.
    private static func discardOwnedBackup(_ root: URL, project: Project) throws {
        let (files, directories) = try ownedPaths(in: root, project: project)
        let rootFD = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw CirclrError("이전 곡 사본을 열 수 없습니다") }
        defer { _ = Darwin.close(rootFD) }
        for relative in files {
            let parts = relative.split(separator: "/")
            let parentFD = try directoryFD(parts.dropLast(), rootFD: rootFD)
            let result = Darwin.unlinkat(parentFD, String(parts.last!), 0)
            let unlinkError = errno
            _ = Darwin.close(parentFD)
            guard result == 0 || unlinkError == ENOENT else {
                throw CirclrError("이전 곡 사본을 정리하지 못했습니다")
            }
        }
        for relative in directories.sorted(by: {
            let left = $0.split(separator: "/").count, right = $1.split(separator: "/").count
            return left == right ? $0 > $1 : left > right
        }) {
            let parts = relative.split(separator: "/")
            let parentFD = try directoryFD(parts.dropLast(), rootFD: rootFD)
            let result = Darwin.unlinkat(parentFD, String(parts.last!), AT_REMOVEDIR)
            let unlinkError = errno
            _ = Darwin.close(parentFD)
            guard result == 0 || unlinkError == ENOENT else {
                throw CirclrError("이전 곡 사본의 일부를 정리하지 못했습니다")
            }
        }
        guard Darwin.rmdir(root.path) == 0 else {
            throw CirclrError("이전 곡 사본의 일부를 정리하지 못했습니다")
        }
    }

    public static func assetURL(_ asset: Asset, root: URL?) throws -> URL {
        if asset.path.hasPrefix("/") { return URL(fileURLWithPath: asset.path) }
        guard let root else { throw CirclrError("\(asset.name)의 프로젝트 위치를 찾을 수 없습니다") }
        let url = root.appendingPathComponent(asset.path).standardizedFileURL.resolvingSymlinksInPath()
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard url.path.hasPrefix(base) else { throw CirclrError("프로젝트 밖으로 벗어나는 미디어 참조입니다") }
        return url
    }
    public static func checksum(_ url: URL) throws -> String {
        try checksum(url, checkCancellation: {})
    }
    private static func checksum(_ url: URL, checkCancellation: () throws -> Void) throws -> String {
        try checkCancellation()
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while true {
            try checkCancellation()
            guard let data = try file.read(upToCount: 1_048_576), !data.isEmpty else { break }
            hash.update(data: data)
        }
        try checkCancellation()
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Foundation's copyItem may enter clonefileat and block the save on some
    /// macOS volumes. Stream the staged media bytes explicitly instead.
    private static func copyAssetBytes(from source: URL, to destination: URL,
                                       checkCancellation: () throws -> Void,
                                       onCreated: (StageFileIdentity) -> Void) throws {
        try checkCancellation()
        let sourceFD = Darwin.open(source.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW)
        guard sourceFD >= 0 else { throw CirclrError("곡 미디어는 일반 파일이어야 합니다") }
        defer { _ = Darwin.close(sourceFD) }
        var sourceInfo = stat()
        guard Darwin.fstat(sourceFD, &sourceInfo) == 0,
              sourceInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw CirclrError("곡 미디어는 일반 파일이어야 합니다")
        }
        let input = FileHandle(fileDescriptor: sourceFD, closeOnDealloc: false)
        let destinationFD = Darwin.open(destination.path,
                                        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                                        mode_t(0o600))
        guard destinationFD >= 0 else {
            throw CirclrError("곡 미디어 복사 파일을 만들 수 없습니다")
        }
        defer { _ = Darwin.close(destinationFD) }
        var destinationInfo = stat()
        guard Darwin.fstat(destinationFD, &destinationInfo) == 0,
              destinationInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw CirclrError("곡 미디어 복사 파일을 확인할 수 없습니다")
        }
        onCreated(StageFileIdentity(destinationInfo))
        let output = FileHandle(fileDescriptor: destinationFD, closeOnDealloc: false)
        while true {
            try checkCancellation()
            guard let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty else { break }
            try output.write(contentsOf: chunk)
            try checkCancellation()
        }
        try output.synchronize()
        try checkCancellation()
    }
    public static func rootURL(for url: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CirclrError("선택한 곡 파일 또는 폴더를 찾을 수 없습니다")
        }
        if isDirectory.boolValue {
            return url
        } else if url.lastPathComponent == "manifest.json" {
            return url.deletingLastPathComponent()
        } else {
            throw CirclrError(".circlr 곡 폴더 또는 그 안의 manifest.json을 선택하세요")
        }
    }
    public static func load(_ url: URL) throws -> LoadedProject {
        let root = try rootURL(for: url)
        let manifest = root.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw CirclrError("선택한 폴더에 manifest.json이 없습니다. .circlr 곡 폴더를 선택하세요")
        }
        let data = try readManifest(manifest)
        struct Header:Decodable {let schemaVersion:Int}
        let header=try JSONDecoder().decode(Header.self,from:data)
        guard (1...7).contains(header.schemaVersion) else {throw CirclrError("더 새로운 프로젝트 형식입니다. 원본을 덮어쓰지 마세요")}
        let project = try JSONDecoder().decode(Project.self, from: data)
        guard (1...7).contains(project.schemaVersion) else { throw CirclrError("더 새로운 프로젝트 형식입니다. 원본을 덮어쓰지 마세요") }
        guard !project.arrangements.isEmpty, project.arrangements.contains(where: { $0.id == project.activeArrangementID }) else { throw CirclrError("유효한 편곡안이 없습니다") }
        try validateStructure(project)
        for asset in project.assets {
            guard !asset.path.hasPrefix("/") else { throw CirclrError("저장된 프로젝트의 미디어는 내부 상대 경로여야 합니다") }
            _ = try assetURL(asset, root: root)
        }
        return LoadedProject(project: project, root: root)
    }
    public static func validateStructure(_ p:Project) throws {
        guard (1...7).contains(p.schemaVersion) else {throw CirclrError("지원하지 않는 프로젝트 형식입니다")}
        try AutomationCompiler.validateTargets(in:p)
        try MIDIPitchBendStorage.validate(in:p)
        try MIDISustainStorage.validate(in:p)
        try p.portLayout?.validate()
        func unique(_ ids:[ID]) throws { guard ids.allSatisfy({!$0.isEmpty}),Set(ids).count==ids.count else { throw CirclrError("프로젝트에 비어 있거나 중복된 ID가 있습니다") } }
        func layout(_ l:Layout) throws { guard OrbitLayoutOffsets.isValid(l), l.zoom.isFinite,(0.25...2.5).contains(l.zoom),l.spacing.isFinite,(12...256).contains(l.spacing),l.pan.x.isFinite,l.pan.y.isFinite,l.positions.values.allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<1e7 && abs($0.y)<1e7}) else { throw CirclrError("Canvas 좌표를 확인하세요") };try unique(l.groups.map(\.id)) }
        try ContextResolver.validate(p.global)
        guard p.album == nil || p.schemaVersion >= 2 else { throw CirclrError("앨범은 version 2 프로젝트로 저장해야 합니다") }
        if let album = p.album {
            try album.validate(arrangements: p.arrangements)
            for composition in album.compositions { _ = try album.path(to: composition.id).reduce(p.global) { try ContextResolver.inheriting(global: p.global, parent: $0, settings: $1.settings) } }
        }
        try unique(p.tracks.map(\.id));try unique(p.sections.map(\.id));try unique(p.patterns.map(\.id));try unique(p.assets.map(\.id));try unique(p.arrangements.map(\.id));try unique(p.signal.nodes.map(\.id));try unique(p.signal.edges.map(\.id));try layout(p.signal.layout)
        for track in p.tracks {
            if let bankLSB=track.instrument.bankLSB,!(0...127).contains(bankLSB) {throw CirclrError("Sound Bank 변형 번호는 0–127이어야 합니다")}
            if track.instrument.kind == .soundBank,!(0...127).contains(track.instrument.program) {throw CirclrError("Sound Bank 음색 번호를 확인하세요")}
            if track.instrument.kind == .synthesizer {try (track.instrument.synth ?? SynthPatch()).validate()}
            if track.instrument.kind == .sampler {
                guard let sample=track.instrument.sample,(0...127).contains(sample.rootPitch),p.assets.contains(where:{$0.id==sample.assetID}) else {throw CirclrError("샘플 악기의 원본·기준음을 확인하세요")}
                let zones=sample.zones ?? []
                guard zones.count<=128,Set(zones.map(\.pitch)).count==zones.count,zones.allSatisfy({zone in (0...127).contains(zone.pitch) && p.assets.contains{$0.id==zone.assetID}}) else {throw CirclrError("드럼 샘플의 음정 매핑을 확인하세요")}
            }
        }
        guard p.tracks.allSatisfy({$0.gain.isFinite && (0...4).contains($0.gain)}),p.assets.allSatisfy({$0.duration.isFinite && $0.duration>0 && $0.sampleRate.isFinite && $0.sampleRate>0}) else { throw CirclrError("트랙 또는 미디어 속성이 유효하지 않습니다") }
        for section in p.sections {
            if let graph = section.graph {
                guard p.schemaVersion >= 2 else { throw CirclrError("음악 그래프는 version 2 프로젝트로 저장해야 합니다") }
                _ = try SectionGraphValidator.sorted(graph)
                for node in graph.nodes {try AutomationCompiler.validate(node,project:p)}
            }
        }
        for a in p.arrangements {
            try unique(a.uses.map(\.id)); try unique(a.edges.map(\.id)); try layout(a.layout)
            for u in a.uses {
                let (section, context, clock) = try ArrangementCompiler.context(project:p,use:u,arrangementID:a.id)
                _ = try SectionGraphCompiler.compile(project:p,section:section,use:u,context:context,clock:clock)
                if u.tempoOverride != nil {try UseTempoOverrideEditing.validateAudio(in:p,useID:u.id,arrangementID:a.id)}
            }
        }
        for pattern in p.patterns {try ArrangementCompiler.validatePattern(pattern,project:p)}
    }
    @discardableResult public static func save(_ project: Project, to url: URL, mediaRoot: URL?) throws -> Project {
        try saveReportingCleanup(project, to: url, mediaRoot: mediaRoot) {
            FileHandle.standardError.write(Data(("circlr: \($0)\n").utf8))
        }
    }

    @discardableResult public static func saveReportingCleanup(_ project: Project, to url: URL, mediaRoot: URL?, onCleanupWarning: (String) -> Void) throws -> Project {
        let staged = try prepareSave(project, to: url, mediaRoot: mediaRoot)
        defer { discard(staged) }
        return try publishSessionSaveReportingCleanup(staged, onCleanupWarning: onCleanupWarning)
    }

    /// Perform all media copying, checksumming and manifest validation before
    /// a document owner commits to replacing the target. The target itself is
    /// never modified by this method.
    public static func prepareSave(_ project: Project, to url: URL, mediaRoot: URL?) throws -> StagedProjectSave {
        try prepareSave(project, to: url, mediaRoot: mediaRoot, preserveLocalAssetPaths: false,
                        checkCancellation: {})
    }

    /// A trusted background worker can make STOP observable during large
    /// media copies and checksums. Legacy interactive saves use the no-op path.
    public static func prepareSessionSave(_ project: Project, to target: URL, mediaRoot: URL?,
                                          checkCancellation: () throws -> Void) throws -> StagedProjectSave {
        try prepareSave(project, to: target, mediaRoot: mediaRoot, preserveLocalAssetPaths: true,
                        checkCancellation: checkCancellation)
    }

    internal static func prepareSave(_ project: Project, to url: URL, mediaRoot: URL?,
                                     preserveLocalAssetPaths: Bool,
                                     checkCancellation: () throws -> Void = {}) throws -> StagedProjectSave {
        try checkCancellation()
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let expectedTarget = try targetFingerprint(url)
        try checkCancellation()
        let staging = parent.appendingPathComponent(".circlr-save-\(newID())")
        try fm.createDirectory(at: staging.appendingPathComponent("media"), withIntermediateDirectories: true)
        let identity = try stageIdentity(staging)
        var completed = false
        var stagedFiles: [String: StageFileIdentity] = [:]
        defer { if !completed { discardStage(at: staging, identity: identity, files: stagedFiles) } }
        var output = project
        guard Set(project.assets.map(\.id)).count == project.assets.count else { throw CirclrError("미디어 ID가 중복되었습니다") }
        for i in output.assets.indices {
            try checkCancellation()
            let asset = project.assets[i]
            let source = try assetURL(asset, root: mediaRoot)
            guard fm.fileExists(atPath: source.path) else { throw CirclrError("\(asset.name)을 찾을 수 없습니다. 파일을 다시 연결하세요") }
            let safeID = asset.id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            guard safeID == asset.id, !safeID.isEmpty else { throw CirclrError("잘못된 미디어 ID입니다") }
            let ext = source.pathExtension.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let relative = "media/\(safeID).\(ext.isEmpty ? "audio" : ext)"
            let destination = staging.appendingPathComponent(relative)
            try copyAssetBytes(from: source, to: destination, checkCancellation: checkCancellation) {
                stagedFiles[relative] = $0
            }
            output.assets[i].path = relative
            output.assets[i].checksum = try checksum(destination, checkCancellation: checkCancellation)
        }
        try checkCancellation()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(output).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        stagedFiles["manifest.json"] = try stageFileIdentity(staging.appendingPathComponent("manifest.json"))
        try checkCancellation()
        guard try stageIdentity(staging) == identity else {
            throw CirclrError("저장 준비 폴더가 변경되었습니다")
        }
        guard let expectedStage = try targetFingerprint(staging) else {
            throw CirclrError("저장 준비 파일을 확인할 수 없습니다")
        }
        try checkCancellation()
        var saved = output
        if preserveLocalAssetPaths {
            let localPaths = Dictionary(uniqueKeysWithValues: project.assets.filter { $0.path.hasPrefix("/") }.map { ($0.id, $0.path) })
            for i in saved.assets.indices {
                if let source = localPaths[saved.assets[i].id] { saved.assets[i].path = source }
            }
        }
        completed = true
        return StagedProjectSave(target: url, staging: staging, portableProject: output,
                                 savedProject: saved, expectedTarget: expectedTarget,
                                 expectedStage: expectedStage, stageIdentity: identity,
                                 stagedFiles: stagedFiles)
    }

    /// Discard a rejected or cancelled stage. This never visits the target.
    public static func discard(_ staged: StagedProjectSave) {
        staged.lock.lock()
        defer { staged.lock.unlock() }
        guard !staged.consumed else { return }
        staged.consumed = true
        discardStage(at: staged.staging, identity: staged.stageIdentity, files: staged.stagedFiles)
    }

    /// Call only after the app has rechecked its run lease, active document,
    /// revision and STOP state. This is synchronous so no actor suspension can
    /// interleave between that check and replacement.
    @discardableResult public static func publishSessionSaveReportingCleanup(
        _ staged: StagedProjectSave, onCleanupWarning: (String) -> Void
    ) throws -> Project {
        staged.lock.lock()
        defer { staged.lock.unlock() }
        guard !staged.consumed else { throw CirclrError("이미 사용한 저장 준비 결과입니다") }
        staged.consumed = true
        let fm = FileManager.default
        let url = staged.target
        let staging = staged.staging
        let backup = url.deletingLastPathComponent().appendingPathComponent(".circlr-backup-\(newID())")
        var movedOld = false, completed = false
        var previousProject: Project?
        defer {
            if !completed {
                discardStage(at: staging, identity: staged.stageIdentity, files: staged.stagedFiles)
            }
        }
        guard try targetFingerprint(url) == staged.expectedTarget else {
            throw CirclrError("저장 준비 중 기존 곡이 변경되었습니다. 다시 저장하세요")
        }
        guard try targetFingerprint(staging) == staged.expectedStage else {
            throw CirclrError("저장 준비 파일이 변경되었습니다")
        }
        if fm.fileExists(atPath: url.path) {
            guard fm.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else { throw CirclrError("기존 일반 폴더를 프로젝트로 덮어쓸 수 없습니다") }
            let previous = try load(url)
            try requireOnlyProjectFiles(in: url, project: previous.project)
            try fm.moveItem(at: url, to: backup); movedOld = true
            do {
                try requireOnlyProjectFiles(in: backup, project: previous.project)
                guard try targetFingerprint(backup) == staged.expectedTarget else {
                    throw CirclrError("저장 준비 중 기존 곡이 변경되었습니다. 다시 저장하세요")
                }
            }
            catch {
                do { try fm.moveItem(at: backup, to: url); movedOld = false }
                catch { throw CirclrError("기존 곡 폴더를 \(backup.path)에 보존했습니다. 저장하지 않았습니다") }
                throw error
            }
            previousProject = previous.project
        }
        do { try fm.moveItem(at: staging, to: url); completed = true }
        catch {
            if movedOld {
                do { try fm.moveItem(at: backup, to: url) }
                catch { throw CirclrError("기존 곡 폴더를 \(backup.path)에 보존했습니다. 저장하지 않았습니다") }
            }
            throw error
        }
        if movedOld, let previousProject {
            do {
                try requireOnlyProjectFiles(in: backup, project: previousProject)
                try discardOwnedBackup(backup, project: previousProject)
            } catch {
                onCleanupWarning("저장은 완료됐습니다. 이전 곡 사본의 일부가 \(backup.path)에 남아 있을 수 있습니다")
            }
        }
        return staged.savedProject
    }
}
