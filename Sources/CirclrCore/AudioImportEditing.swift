import Foundation

public enum AudioImportDestination {
    case section(arrangementID:ID,useID:ID,trackID:ID?,beat:Double,position:Point?,original:Bool)
    case pattern(id:ID,beat:Double)
}
public enum AudioImportEditing {
    /// Call once inside the document's mutation so the complete batch has one Undo.
    public static func apply(_ assets:[Asset],to target:AudioImportDestination,projectID:ID,revision:Int,in project:inout Project)throws->[ID] {
        guard project.id==projectID,project.musicRevision==revision else {throw CirclrError("파일을 읽는 동안 프로젝트가 변경됐습니다. 다시 가져오세요")}
        guard !assets.isEmpty,assets.count<=64,Set(assets.map(\.id)).count==assets.count,
              Set(assets.map(\.id)).isDisjoint(with:Set(project.assets.map(\.id))) else {throw CirclrError("한 번에 1–64개 파일을 가져오세요")}
        guard assets.allSatisfy({!$0.name.isEmpty && $0.name.count<=1024 && $0.duration.isFinite && $0.duration>0 && $0.duration<=3600 && $0.sampleRate.isFinite && $0.sampleRate>0}) else {throw CirclrError("오디오의 이름·길이·샘플레이트를 확인하세요")}
        var p=project;let previousArrangement=p.activeArrangementID,previousSignalPositions=p.signal.layout.positions
        p.assets+=assets
        var clips:[ID]=[]
        switch target {
        case .pattern(let id,let beat):
            guard let i=p.patterns.firstIndex(where:{$0.id==id}),beat.isFinite,beat>=0,beat<p.patterns[i].length else {throw CirclrError("리듬 패턴과 시작 박을 확인하세요")}
            for asset in assets {var clip=AudioClip(assetID:asset.id,duration:asset.duration,beat:beat);clip.sourceBPM=p.global.tempo;p.patterns[i].audio.append(clip);clips.append(clip.id)}
        case .section(let ai,let ui,let targetTrack,let beat,let position,let original):
            guard p.arrangements.contains(where:{$0.id==ai}),let use=p.arrangements.first(where:{$0.id==ai})?.uses.first(where:{$0.id==ui}) else {throw CirclrError("오디오를 넣을 섹션을 찾을 수 없습니다")}
            let (section,context,clock)=try ArrangementCompiler.context(project:p,use:use,arrangementID:ai)
            guard beat.isFinite,beat>=0,beat<clock.beats,targetTrack==nil || p.tracks.contains(where:{$0.id==targetTrack}) else {throw CirclrError("대상 트랙과 시작 박을 확인하세요")}
            p.activeArrangementID=ai
            for (index,asset) in assets.enumerated() {
                let track=assets.count==1 ? (targetTrack ?? p.addTrack(name:asset.name)):p.addTrack(name:asset.name)
                var lane=(original ? section.lanes:try ArrangementCompiler.effectiveLanes(section:section,use:use)).first(where:{$0.trackID==track}) ?? Lane(trackID:track)
                var clip=AudioClip(assetID:asset.id,duration:asset.duration,beat:beat);clip.sourceBPM=context.tempo
                lane.audio.append(clip);try ProjectEditing.setLane(lane,for:ui,original:original,in:&p);clips.append(clip.id)
                if let current=p.active.uses.first(where:{$0.id==ui}),let definition=p.sections.first(where:{$0.id==current.sectionID}),
                   var graph=original ? definition.graph:try SectionGraphEditing.effective(section:definition,use:current),let i=graph.nodes.firstIndex(where:{$0.id=="audio:\(clip.id)"}) {
                    graph.nodes[i].name=asset.name
                    if let position,!p.usesOrbits {graph.layout.positions[graph.nodes[i].id]=Point(position.x+Double(index%4)*220,position.y+Double(index/4)*220)}
                    try SectionGraphEditing.set(graph,useID:ui,original:original,in:&p)
                }
            }
        }
        p.activeArrangementID=previousArrangement
        p.signal.layout.positions.merge(previousSignalPositions){_,previous in previous}
        try ProjectStore.validateStructure(p);project=p;return clips
    }
}
