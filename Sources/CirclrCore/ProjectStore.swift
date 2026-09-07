import Foundation
import CryptoKit

public struct LoadedProject { public var project: Project; public var root: URL }
public enum ProjectStore {
    public static func assetURL(_ asset: Asset, root: URL?) throws -> URL {
        if asset.path.hasPrefix("/") { return URL(fileURLWithPath: asset.path) }
        guard let root else { throw CirclrError("\(asset.name)의 프로젝트 위치를 찾을 수 없습니다") }
        let url = root.appendingPathComponent(asset.path).standardizedFileURL.resolvingSymlinksInPath()
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard url.path.hasPrefix(base) else { throw CirclrError("프로젝트 밖으로 벗어나는 미디어 참조입니다") }
        return url
    }
    public static func checksum(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func load(_ url: URL) throws -> LoadedProject {
        let manifest = url.appendingPathComponent("manifest.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: manifest.path)
        guard (attrs[.size] as? NSNumber)?.intValue ?? 0 < 50_000_000 else { throw CirclrError("프로젝트 manifest가 너무 큽니다") }
        let data = try Data(contentsOf: manifest)
        let project = try JSONDecoder().decode(Project.self, from: data)
        guard (1...2).contains(project.schemaVersion) else { throw CirclrError("더 새로운 프로젝트 형식입니다. 원본을 덮어쓰지 마세요") }
        guard !project.arrangements.isEmpty, project.arrangements.contains(where: { $0.id == project.activeArrangementID }) else { throw CirclrError("유효한 편곡안이 없습니다") }
        try validateStructure(project)
        for asset in project.assets {
            guard !asset.path.hasPrefix("/") else { throw CirclrError("저장된 프로젝트의 미디어는 내부 상대 경로여야 합니다") }
            _ = try assetURL(asset, root: url)
        }
        return LoadedProject(project: project, root: url)
    }
    public static func validateStructure(_ p:Project) throws {
        func unique(_ ids:[ID]) throws { guard ids.allSatisfy({!$0.isEmpty}),Set(ids).count==ids.count else { throw CirclrError("프로젝트에 비어 있거나 중복된 ID가 있습니다") } }
        func layout(_ l:Layout) throws { guard l.zoom.isFinite,(0.25...2.5).contains(l.zoom),l.spacing.isFinite,(12...256).contains(l.spacing),l.pan.x.isFinite,l.pan.y.isFinite,l.positions.values.allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<1e7 && abs($0.y)<1e7}) else { throw CirclrError("Canvas 좌표를 확인하세요") };try unique(l.groups.map(\.id)) }
        try ContextResolver.validate(p.global)
        guard p.album == nil || p.schemaVersion >= 2 else { throw CirclrError("앨범은 version 2 프로젝트로 저장해야 합니다") }
        if let album = p.album {
            try album.validate(arrangements: p.arrangements)
            for composition in album.compositions { _ = try album.path(to: composition.id).reduce(p.global) { try ContextResolver.inheriting(global: p.global, parent: $0, settings: $1.settings) } }
        }
        try unique(p.tracks.map(\.id));try unique(p.sections.map(\.id));try unique(p.patterns.map(\.id));try unique(p.assets.map(\.id));try unique(p.arrangements.map(\.id));try unique(p.signal.nodes.map(\.id));try unique(p.signal.edges.map(\.id));try layout(p.signal.layout)
        for track in p.tracks {
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
            }
        }
        for a in p.arrangements {
            try unique(a.uses.map(\.id)); try unique(a.edges.map(\.id)); try layout(a.layout)
            for u in a.uses {
                let (section, context, clock) = try ArrangementCompiler.context(project:p,use:u,arrangementID:a.id)
                _ = try SectionGraphCompiler.compile(project:p,section:section,use:u,context:context,clock:clock)
            }
        }
        for pattern in p.patterns {try ArrangementCompiler.validatePattern(pattern,project:p)}
    }
    @discardableResult public static func save(_ project: Project, to url: URL, mediaRoot: URL?) throws -> Project {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".circlr-save-\(newID())")
        let backup = parent.appendingPathComponent(".circlr-backup-\(newID())")
        try fm.createDirectory(at: staging.appendingPathComponent("media"), withIntermediateDirectories: true)
        var movedOld = false, completed = false
        defer { if !completed { try? fm.removeItem(at: staging) } }
        var output = project
        guard Set(project.assets.map(\.id)).count == project.assets.count else { throw CirclrError("미디어 ID가 중복되었습니다") }
        for i in output.assets.indices {
            let asset = project.assets[i]
            let source = try assetURL(asset, root: mediaRoot)
            guard fm.fileExists(atPath: source.path) else { throw CirclrError("\(asset.name)을 찾을 수 없습니다. 파일을 다시 연결하세요") }
            let safeID = asset.id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            guard safeID == asset.id, !safeID.isEmpty else { throw CirclrError("잘못된 미디어 ID입니다") }
            let ext = source.pathExtension.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let relative = "media/\(safeID).\(ext.isEmpty ? "audio" : ext)"
            let destination = staging.appendingPathComponent(relative)
            try fm.copyItem(at: source, to: destination)
            output.assets[i].path = relative; output.assets[i].checksum = try checksum(destination)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(output).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        _ = try load(staging)
        if fm.fileExists(atPath: url.path) {
            guard fm.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else { throw CirclrError("기존 일반 폴더를 프로젝트로 덮어쓸 수 없습니다") }
            _ = try load(url)
            try fm.moveItem(at: url, to: backup); movedOld = true
        }
        do { try fm.moveItem(at: staging, to: url); completed = true }
        catch { if movedOld { try? fm.moveItem(at: backup, to: url) }; throw error }
        if movedOld { try? fm.removeItem(at: backup) }
        return output
    }
}
