import Foundation

/// Mirrors the compiler's next-edge decision without changing the viewed arrangement.
public enum SectionFlowSelection {
    public static func edge(_ id:CircleConnectionID,in project:Project)->FlowEdge? {
        guard case .section(let ai,let from)=id.from,case .section(let bi,let to)=id.to,ai==bi,
              let arrangement=project.arrangements.first(where:{$0.id==ai}),
              arrangement.uses.contains(where:{$0.id==from}),arrangement.uses.contains(where:{$0.id==to}) else{return nil}
        return arrangement.edges.first{$0.id==id.edgeID && $0.from==from && $0.to==to}
    }
    public static func isSelected(_ id:CircleConnectionID,in project:Project)->Bool {
        guard let edge=edge(id,in:project),case .section(let ai,_)=id.from,
              let arrangement=project.arrangements.first(where:{$0.id==ai}),
              let use=arrangement.uses.first(where:{$0.id==edge.from}),!use.isEnd else{return false}
        return arrangement.edges.filter{$0.from==edge.from}.count==1 || arrangement.chosenEdges[edge.from]==edge.id
    }
    @discardableResult public static func choose(_ id:CircleConnectionID,in project:inout Project)throws->Bool {
        guard let edge=edge(id,in:project),case .section(let ai,_)=id.from,
              let index=project.arrangements.firstIndex(where:{$0.id==ai}),
              let use=project.arrangements[index].uses.firstIndex(where:{$0.id==edge.from}) else{throw CirclrError("재생 경로의 섹션과 케이블을 다시 확인하세요")}
        guard !isSelected(id,in:project) else{return false}
        project.arrangements[index].chosenEdges[edge.from]=edge.id
        project.arrangements[index].uses[use].isEnd=false
        return true
    }
}
