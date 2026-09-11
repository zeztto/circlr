import Foundation

public struct MusicGraphTarget:Equatable {
    public let address:CircleAddress
    public let original:Bool
    public init(address:CircleAddress,original:Bool) {self.address=address;self.original=original}
}

/// Resolves the requested graph scope before callers construct any partial edit.
public enum MusicGraphEditing {
    private static func scope(_ target:MusicGraphTarget,in project:Project)throws->(graph:SectionGraph,useID:ID) {
        let arrangementID:ID,useID:ID,nodeID:ID?
        switch target.address {
        case .music(let arrangement,let use,let node):arrangementID=arrangement;useID=use;nodeID=node
        case .section(let arrangement,let use):arrangementID=arrangement;useID=use;nodeID=nil
        default:throw CirclrError("편집할 섹션 또는 음악 서클을 선택하세요")
        }
        guard arrangementID==project.activeArrangementID,
              project.arrangements.filter({$0.id==arrangementID}).count==1,
              let arrangement=project.arrangements.first(where:{$0.id==arrangementID}),
              arrangement.uses.filter({$0.id==useID}).count==1,
              let use=arrangement.uses.first(where:{$0.id==useID}),
              project.sections.filter({$0.id==use.sectionID}).count==1,
              let section=project.sections.first(where:{$0.id==use.sectionID}) else {
            throw CirclrError("음악 편집의 편곡·섹션 대상이 변경되었습니다")
        }
        guard let graph=try target.original ? section.graph:SectionGraphEditing.effective(section:section,use:use) else {
            throw CirclrError("편집할 음악 그래프 원본이 없습니다")
        }
        if let nodeID {
            guard graph.nodes.filter({$0.id==nodeID}).count==1 else {
                throw CirclrError(target.original ? "공유 원본에 없는 서클입니다. 이번 사용 편집으로 전환하세요":"편집할 음악 서클을 찾을 수 없습니다")
            }
        }
        return (graph,useID)
    }
    public static func snapshot(_ target:MusicGraphTarget,in project:Project)throws->SectionGraph {
        try scope(target,in:project).graph
    }
    public static func node(_ target:MusicGraphTarget,in project:Project)throws->MusicCircle {
        guard case .music(_,_,let nodeID)=target.address else{throw CirclrError("음악 서클을 선택하세요")}
        let graph=try snapshot(target,in:project)
        guard let node=graph.nodes.first(where:{$0.id==nodeID}) else{throw CirclrError("편집할 음악 서클을 찾을 수 없습니다")}
        return node
    }
    public static func replace(_ target:MusicGraphTarget,graph:SectionGraph,expected:SectionGraph,in project:inout Project)throws {
        let current=try scope(target,in:project)
        guard current.graph==expected else{throw CirclrError("음악 그래프가 변경되었습니다. 현재 값에서 다시 편집하세요")}
        guard graph != current.graph else{return}
        try SectionGraphEditing.set(graph,useID:current.useID,original:target.original,in:&project)
    }
}
