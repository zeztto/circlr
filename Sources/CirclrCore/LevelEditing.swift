import Foundation

public enum LevelTarget:Equatable {
    case circle(CircleAddress,original:Bool)
    case track(ID)
}
public struct LevelSnapshot:Equatable {
    public var gain:Double
    public var muted:Bool
    public init(gain:Double,muted:Bool){self.gain=gain;self.muted=muted}
}
public enum LevelEditing {
    private static func circle(_ address:CircleAddress,original:Bool,project:Project)throws->(SectionGraph,Int,ID) {
        guard case .music(let arrangementID,let useID,let nodeID)=address,
              arrangementID==project.activeArrangementID,
              let use=project.active.uses.first(where:{$0.id==useID}),let section=project.sections.first(where:{$0.id==use.sectionID}),
              let graph=try original ? section.graph:SectionGraphEditing.effective(section:section,use:use),
              let index=graph.nodes.firstIndex(where:{$0.id==nodeID}),graph.nodes[index].content.output != .midi
        else{throw CirclrError("레벨을 편집할 오디오 서클을 찾을 수 없습니다")}
        return (graph,index,useID)
    }
    public static func snapshot(_ target:LevelTarget,in project:Project)throws->LevelSnapshot {
        switch target {
        case .track(let id):
            guard let track=project.tracks.first(where:{$0.id==id}) else{throw CirclrError("트랙을 찾을 수 없습니다")}
            return LevelSnapshot(gain:track.gain,muted:track.muted)
        case .circle(let address,let original):
            let (graph,i,_)=try circle(address,original:original,project:project)
            return LevelSnapshot(gain:graph.nodes[i].gain,muted:graph.nodes[i].muted)
        }
    }
    public static func set(_ target:LevelTarget,gain:Double?=nil,muted:Bool?=nil,in project:inout Project)throws {
        guard gain != nil || muted != nil,gain.map({$0.isFinite && (0...GainScale.maximum).contains($0)}) ?? true else{throw CirclrError("레벨은 −∞–12.0412 dB 범위로 입력하세요")}
        let before=try snapshot(target,in:project)
        let changedGain=gain.map({$0 != before.gain}) ?? false,changedMute=muted.map({$0 != before.muted}) ?? false
        guard changedGain || changedMute else{return}
        switch target {
        case .track(let id):
            guard let i=project.tracks.firstIndex(where:{$0.id==id}) else{throw CirclrError("트랙을 찾을 수 없습니다")}
            if let gain{project.tracks[i].gain=gain};if let muted{project.tracks[i].muted=muted}
        case .circle(let address,let original):
            let (base,index,useID)=try circle(address,original:original,project:project)
            var graph=base
            if let gain{graph.nodes[index].gain=gain};if let muted{graph.nodes[index].muted=muted}
            try SectionGraphEditing.set(graph,useID:useID,original:original,in:&project)
        }
    }
}
