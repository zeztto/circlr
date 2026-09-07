import Foundation

public enum OrbitEditing {
    public static func snappedBeat(seconds: Double, clock: MusicClock, subdivisions: Int) -> Double {
        let grid=Double(max(1,subdivisions))
        return max(0,min(clock.beats-1/grid,(clock.beat(atSeconds:seconds)*grid).rounded()/grid))
    }
    public static func setStart(_ address: CircleAddress, seconds: Double, original: Bool = false, in project: inout Project) throws {
        guard seconds.isFinite, case .music(let ai,let ui,let ni)=address,
              let use=project.arrangements.first(where:{$0.id==ai})?.uses.first(where:{$0.id==ui}) else {throw CirclrError("음악 소스의 시간 손잡이를 선택하세요")}
        let (section,context,clock)=try ArrangementCompiler.context(project:project,use:use,arrangementID:ai)
        guard var graph=try SectionGraphEditing.effective(section:section,use:use),let i=graph.nodes.firstIndex(where:{$0.id==ni}),graph.nodes[i].content.input == nil else {throw CirclrError("이 서클은 시간 소스가 아닙니다")}
        graph.nodes[i].startBeat=snappedBeat(seconds:seconds,clock:clock,subdivisions:context.beatGrid.subdivisions)
        var candidate=project
        let active=candidate.activeArrangementID;candidate.activeArrangementID=ai
        try SectionGraphEditing.set(graph,useID:ui,original:original,in:&candidate)
        candidate.activeArrangementID=active;project=candidate
    }

    /// Reorders a complete simple chain only; branching needs an explicit flow edit.
    public static func reorderSection(_ address: CircleAddress, before target: ID?, in project: inout Project) throws {
        guard case .section(let ai,let ui)=address,let index=project.arrangements.firstIndex(where:{$0.id==ai}) else {throw CirclrError("섹션을 선택하세요")}
        let a=project.arrangements[index],plan=try ArrangementCompiler.compile(project,arrangementID:ai)
        var seen=Set<ID>(),order=plan.occurrences.compactMap {seen.insert($0.use.id).inserted ? $0.use.id:nil}
        guard order.contains(ui),order.count==a.uses.count,a.edges.count==max(0,order.count-1),
              a.uses.allSatisfy({u in a.edges.filter{$0.from==u.id}.count<=1 && a.edges.filter{$0.to==u.id}.count<=1}),
              target == nil || order.contains(target!) else {throw CirclrError("분기 없는 전체 섹션 경로에서 순서를 옮길 수 있습니다")}
        guard target != ui else {return}
        order.removeAll{$0==ui};order.insert(ui,at:target.flatMap{order.firstIndex(of:$0)} ?? order.count)
        if let last=order.last,let outgoing=a.edges.first(where:{$0.from==last}),outgoing.transition.length>0 {
            throw CirclrError("전환이 있는 섹션을 맨 끝으로 옮기려면 전환을 먼저 편집하세요")
        }
        var candidate=project
        // The transition stays with the outgoing section. The final section has no outgoing edge.
        var edges: [FlowEdge]=[]
        for (from,to) in zip(order,order.dropFirst()) {
            var edge=a.edges.first{$0.from==from} ?? FlowEdge(from:from,to:to)
            edge.to=to;edges.append(edge)
        }
        candidate.arrangements[index].edges=edges;candidate.arrangements[index].startID=order.first
        candidate.arrangements[index].chosenEdges=[:]
        for i in candidate.arrangements[index].uses.indices {candidate.arrangements[index].uses[i].isEnd=candidate.arrangements[index].uses[i].id==order.last}
        _=try ArrangementCompiler.compile(candidate,arrangementID:ai)
        project=candidate
    }
}
