import Foundation

public enum MusicContextField: String, CaseIterable {
    case tempo, meter, scale, beatGrid, rhythm
}

public enum MusicContextChange {
    case tempo(Double), numerator(Int), denominator(Int), scaleRoot(Int), scaleMode(String)
    case subdivisions(Int), swing(Double), accents(String), rhythm(ID?)
    case source(MusicContextField, SettingSource)

    public var field: MusicContextField {
        switch self {
        case .tempo: return .tempo
        case .numerator, .denominator: return .meter
        case .scaleRoot, .scaleMode: return .scale
        case .subdivisions, .swing, .accents: return .beatGrid
        case .rhythm: return .rhythm
        case .source(let field, _): return field
        }
    }
}

public struct MusicContextSnapshot {
    public let context: MusicContext
    public let settings: ContextSettings?
    public func source(_ field: MusicContextField) -> SettingSource? {
        guard let settings else {return nil}
        switch field {
        case .tempo: return settings.tempo.source
        case .meter: return settings.meter.source
        case .scale: return settings.scale.source
        case .beatGrid: return settings.beatGrid.source
        case .rhythm: return settings.rhythm.source
        }
    }
}

/// Edits one musical property from the current model, including hidden or alternative uses.
/// Layout, graph overrides and unrelated settings are not copied from a displayed snapshot.
public enum MusicContextEditing {
    public static func snapshot(at address: CircleAddress, original: Bool = false, in project: Project) throws -> MusicContextSnapshot {
        switch address {
        case .album: return MusicContextSnapshot(context:project.global,settings:nil)
        case .composition(let id):
            guard let album=project.album else {throw CirclrError("앨범을 찾을 수 없습니다")}
            let path=try album.path(to:id)
            let context=try path.reduce(project.global) {try ContextResolver.inheriting(global:project.global,parent:$0,settings:$1.settings)}
            return MusicContextSnapshot(context:context,settings:path.last!.settings)
        case .section(let arrangementID,let useID), .music(let arrangementID,let useID,_):
            let (ai,ui,si)=try indices(arrangementID:arrangementID,useID:useID,in:project)
            let use=project.arrangements[ai].uses[ui],section=project.sections[si]
            let (_,parent,_)=try ArrangementCompiler.context(project:project,use:use,arrangementID:arrangementID)
            if case .music(_,_,let nodeID)=address {
                let graph=try original ? section.graph:SectionGraphEditing.effective(section:section,use:use)
                guard let node=graph?.nodes.first(where:{$0.id==nodeID}) else {throw CirclrError(original ? "공유 원본에 없는 서클입니다. 이번 사용 편집으로 바꾸세요":"음악 서클을 찾을 수 없습니다")}
                return MusicContextSnapshot(context:try ContextResolver.inheriting(global:project.global,parent:parent,settings:node.settings),settings:node.settings)
            }
            return MusicContextSnapshot(context:parent,settings:use.settings)
        case .sound, .signal, .group:
            throw CirclrError("이 서클은 음악 설정의 대상이 아닙니다")
        }
    }

    public static func parseAccents(_ text: String) throws -> [Int] {
        let text=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if text.isEmpty {return []}
        guard text.count<=512 else {throw CirclrError("강세는 64개 묶음 이내로 입력하세요")}
        let groups=text.components(separatedBy:"+")
        guard groups.count<=64 else {throw CirclrError("강세는 64개 묶음 이내로 입력하세요")}
        return try groups.map {part in
            guard let value=Int(part.trimmingCharacters(in:.whitespaces)),(1...64).contains(value) else {
                throw CirclrError("강세는 1–64의 정수를 +로 연결하세요. 예: 2+2+3")
            }
            return value
        }
    }

    public static func apply(_ change: MusicContextChange, at address: CircleAddress, original: Bool = false, in project: inout Project) throws {
        let before=try snapshot(at:address,original:original,in:project)
        var context=before.context,settings=before.settings
        if case .source(let field,let source)=change {
            guard var local=settings else {throw CirclrError("앨범 기본값에는 상속 출처가 없습니다")}
            func changeSource<T>(_ setting: inout Setting<T>, _ fallback:T) {
                if source == .local,setting.value==nil {setting.value=fallback}
                setting.source=source
            }
            switch field {
            case .tempo: changeSource(&local.tempo,context.tempo)
            case .meter: changeSource(&local.meter,context.meter)
            case .scale: changeSource(&local.scale,context.scale)
            case .beatGrid: changeSource(&local.beatGrid,context.beatGrid)
            case .rhythm: changeSource(&local.rhythm,context.rhythm)
            }
            settings=local
        } else {
            switch change {
            case .tempo(let value): context.tempo=value
            case .numerator(let value): context.meter.numerator=value
            case .denominator(let value): context.meter.denominator=value
            case .scaleRoot(let value): context.scale.root=value
            case .scaleMode(let value):
                guard let mode=Scale.modes.first(where:{$0.0==value}) else {throw CirclrError("스케일 종류를 확인하세요")}
                context.scale.name=mode.0;context.scale.intervals=mode.1
            case .subdivisions(let value): context.beatGrid.subdivisions=value
            case .swing(let value): context.beatGrid.swing=value
            case .accents(let text): context.beatGrid.accents=try parseAccents(text)
            case .rhythm(let id):
                guard id==nil || project.patterns.contains(where:{$0.id==id}) else {throw CirclrError("리듬 패턴을 찾을 수 없습니다")}
                context.rhythm.patternID=id
            case .source: break
            }
            try ContextResolver.validate(context)
            if var local=settings {
                switch change.field {
                case .tempo: local.tempo = .local(context.tempo)
                case .meter: local.meter = .local(context.meter)
                case .scale: local.scale = .local(context.scale)
                case .beatGrid: local.beatGrid = .local(context.beatGrid)
                case .rhythm: local.rhythm = .local(context.rhythm)
                }
                settings=local
            }
        }
        var candidate=project
        switch address {
        case .album: candidate.global=context
        case .composition(let id):
            guard let i=candidate.album?.compositions.firstIndex(where:{$0.id==id}),let settings else {throw CirclrError("곡을 찾을 수 없습니다")}
            candidate.album?.compositions[i].settings=settings
        case .section(let arrangementID,let useID), .music(let arrangementID,let useID,_):
            let (ai,ui,si)=try indices(arrangementID:arrangementID,useID:useID,in:candidate)
            guard let settings else {throw CirclrError("음악 설정을 찾을 수 없습니다")}
            if case .music(_,_,let nodeID)=address {
                let section=candidate.sections[si],use=candidate.arrangements[ai].uses[ui]
                guard var graph=try original ? section.graph:SectionGraphEditing.effective(section:section,use:use),
                      let ni=graph.nodes.firstIndex(where:{$0.id==nodeID}) else {throw CirclrError("음악 원본을 찾을 수 없습니다")}
                graph.nodes[ni].settings=settings
                let active=candidate.activeArrangementID;candidate.activeArrangementID=arrangementID
                try SectionGraphEditing.set(graph,useID:useID,original:original,in:&candidate)
                candidate.activeArrangementID=active
            } else {candidate.arrangements[ai].uses[ui].settings=settings}
        case .sound, .signal, .group: throw CirclrError("음악 설정의 대상이 아닙니다")
        }
        if candidate==project {return}
        try UseTempoOverrideEditing.validateChanges(from:project,to:candidate)
        // Global and parent edits can affect arrangements which are not currently selected.
        for arrangement in candidate.arrangements {_ = try ArrangementCompiler.compile(candidate,arrangementID:arrangement.id)}
        if candidate.album != nil {_ = try AlbumCompiler.compile(candidate)}
        project=candidate
    }

    private static func indices(arrangementID: ID, useID: ID, in project: Project) throws -> (Int,Int,Int) {
        guard let ai=project.arrangements.firstIndex(where:{$0.id==arrangementID}),
              let ui=project.arrangements[ai].uses.firstIndex(where:{$0.id==useID}),
              let si=project.sections.firstIndex(where:{$0.id==project.arrangements[ai].uses[ui].sectionID}) else {throw CirclrError("섹션을 찾을 수 없습니다")}
        return (ai,ui,si)
    }
}
