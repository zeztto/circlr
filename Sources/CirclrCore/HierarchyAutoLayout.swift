import Foundation

public enum HierarchyAutoLayoutMode:String,CaseIterable {
    case radial,horizontal,vertical
}

/// Explicit layout changes only saved visual positions, in one atomic project update.
public enum HierarchyAutoLayout {
    public static func apply(_ mode:HierarchyAutoLayoutMode,addresses:Set<CircleAddress>,in project:inout Project)throws {
        guard addresses.count>=2 else{throw CirclrError("자동 배치할 같은 부모의 서클을 두 개 이상 선택하세요")}
        let encoder=JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        let ordered=try addresses.map{($0,String(decoding:try encoder.encode($0),as:UTF8.self))}.sorted{$0.1<$1.1}.map(\.0)
        let scene=try HierarchySceneBuilder.build(project,revealing:ordered[0])
        let nodes=try ordered.map { address -> CircleSceneNode in
            guard let node=scene.node(address),node.parent != nil,node.scale.isFinite,node.scale>0,node.outerRadius.isFinite,node.outerRadius>0 else{throw CirclrError("배치할 서클을 찾을 수 없습니다")}
            return node
        }
        guard let parentID=nodes[0].parent,let parent=scene.node(parentID),nodes.allSatisfy({$0.parent==parentID}) else{throw CirclrError("같은 부모의 서클만 자동 배치하세요")}
        let obstacles=scene.children(of:parentID).filter{!addresses.contains($0.id)}
        // Edges between selected siblings supply flow rank. Cycles break at the first stable ID.
        let edges=scene.edges.filter{$0.kind != .sidechain && (mode != .radial || $0.kind != .flow)}
        let structure=flowStructure(ordered:ordered,edges:edges),ranks=structure.ranks
        let gap=100.0,maxRadius=nodes.map(\.outerRadius).max()!,pitch=maxRadius*2+gap
        let capacity=Set(ranks.values).map{rank in nodes.filter{ranks[$0.id]==rank}.count}.max()!
        var radialOffsets:[Int:Double]=[:],previousRadius=0.0,radialOffset=0.0
        for rank in Set(ranks.values).sorted() {
            let radius=nodes.filter{ranks[$0.id]==rank}.map(\.outerRadius).max()!
            if rank>0 {radialOffset+=previousRadius+radius+gap}
            radialOffsets[rank]=radialOffset;previousRadius=radius
        }
        var angles:[CircleAddress:Double]=[:]
        for rank in Set(ranks.values).sorted() {
            let row=nodes.filter{ranks[$0.id]==rank}
            var occupied=Set<Int>()
            for (index,node) in row.enumerated() {
                let predecessorAngles=edges.filter{$0.to==node.id}.compactMap{angles[$0.from]}
                let preferred:Double
                if let first=predecessorAngles.first {
                    let x=predecessorAngles.map(cos).reduce(0,+),y=predecessorAngles.map(sin).reduce(0,+)
                    preferred=hypot(x,y)<0.001 ? first:atan2(y,x)
                }else{preferred = -Double.pi/2+Double(index)*2*Double.pi/Double(row.count)}
                let slot=(0..<capacity).filter{!occupied.contains($0)}.min{a,b in
                    func distance(_ slot:Int)->Double {
                        let delta = -Double.pi/2+Double(slot)*2*Double.pi/Double(capacity)-preferred
                        return abs(atan2(sin(delta),cos(delta)))
                    }
                    let left=distance(a),right=distance(b)
                    return abs(left-right)<1e-10 ? a<b:left<right
                }!
                occupied.insert(slot);angles[node.id] = -Double.pi/2+Double(slot)*2*Double.pi/Double(capacity)
            }
        }
        var targets:[CircleAddress:Point]=[:]
        var placed=false
        for expansion in 0..<512 {
            targets=[:]
            for rank in Set(ranks.values).sorted() {
                let row=nodes.filter{ranks[$0.id]==rank}
                for node in row {
                    let depth=parent.outerRadius+maxRadius+gap+Double(rank+expansion)*pitch
                    switch mode {
                    case .horizontal:
                        targets[node.id]=Point(parent.center.x+depth,parent.center.y+structure.lanes[node.id]!*pitch)
                    case .vertical:
                        targets[node.id]=Point(parent.center.x+structure.lanes[node.id]!*pitch,parent.center.y+depth)
                    case .radial:
                        // Shared generous shells prevent adjacent rank rings from crossing.
                        let population=capacity
                        let shell=max(parent.outerRadius+maxRadius+gap,pitch/max(0.01,2*sin(.pi/Double(max(2,population)))))
                        let radius=shell+radialOffsets[rank]!+Double(expansion)*pitch
                        let angle=angles[node.id]!
                        targets[node.id]=Point(parent.center.x+cos(angle)*radius,parent.center.y+sin(angle)*radius)
                    }
                }
            }
            let avoidsObstacles=nodes.allSatisfy {node in
                let p=targets[node.id]!
                return obstacles.allSatisfy{hypot(p.x-$0.center.x,p.y-$0.center.y)>=node.outerRadius+$0.outerRadius+gap}
            }
            if avoidsObstacles {placed=true;break}
        }
        guard placed else{throw CirclrError("주변 서클과 겹치지 않는 배치 공간을 찾을 수 없습니다")}
        var candidate=project
        for node in nodes {
            let target=targets[node.id]!,old=try HierarchyEditing.position(node.id,in:project)
            try HierarchyEditing.move(node.id,to:Point(old.x+(target.x-node.center.x)/node.scale,old.y+(target.y-node.center.y)/node.scale),in:&candidate)
        }
        let final=try HierarchySceneBuilder.build(candidate,revealing:ordered[0])
        let result=try ordered.map{address -> CircleSceneNode in
            guard let node=final.node(address) else{throw CirclrError("배치 후 서클을 찾을 수 없습니다")};return node
        }
        for (index,node) in result.enumerated() {
            for other in result.dropFirst(index+1)+final.children(of:parentID).filter({!addresses.contains($0.id)}) {
                guard hypot(node.center.x-other.center.x,node.center.y-other.center.y)>=node.outerRadius+other.outerRadius+gap-0.001 else{throw CirclrError("자동 배치 결과가 겹쳐 변경하지 않았습니다")}
            }
        }
        project=candidate
    }
    /// Stable roots retain their cross-axis lane through ordinary one-in/one-out chains.
    /// Forks take the nearest free lane; merges converge on their incoming barycenter.
    static func flowStructure(ordered:[CircleAddress],edges allEdges:[CircleSceneEdge])->(ranks:[CircleAddress:Int],lanes:[CircleAddress:Double]) {
        let selected=Set(ordered)
        let edges=allEdges.filter{$0.kind != .sidechain && selected.contains($0.from) && selected.contains($0.to) && $0.from != $0.to}
        var remaining=selected,ranks:[CircleAddress:Int]=[:],lanes:[CircleAddress:Double]=[:]
        while !remaining.isEmpty {
            let ready=ordered.filter{node in remaining.contains(node) && !edges.contains{remaining.contains($0.from) && $0.to==node}}
            for address in ready.isEmpty ? [ordered.first{remaining.contains($0)}!] : ready {
                ranks[address]=(edges.filter{$0.to==address}.compactMap{ranks[$0.from]}.max().map{$0+1}) ?? 0
                remaining.remove(address)
            }
        }
        for rank in Set(ranks.values).sorted() {
            let row=ordered.filter{ranks[$0]==rank}
            var desired:[CircleAddress:Double]=[:],straight=Set<CircleAddress>()
            for (index,address) in row.enumerated() {
                let predecessors=Set(edges.filter{$0.to==address}.map(\.from))
                let incoming=ordered.filter{predecessors.contains($0)}.compactMap{lanes[$0]}
                desired[address]=incoming.isEmpty ? Double(index)-Double(row.count-1)/2:incoming.reduce(0,+)/Double(incoming.count)
                if predecessors.count==1,let predecessor=predecessors.first,Set(edges.filter{$0.from==predecessor}.map(\.to)).count==1 {straight.insert(address)}
            }
            let prioritized=row.filter{straight.contains($0)}+row.filter{!straight.contains($0)}
            var occupied:[Double]=[]
            for address in prioritized {
                let preferred=desired[address]!
                var lane=preferred
                if occupied.contains(where:{abs($0-lane)<0.999999}) {
                    for step in 1...(ordered.count*2) {
                        let candidate=preferred+Double(step%2==1 ? -(step+1)/2:step/2)
                        if occupied.allSatisfy({abs($0-candidate)>=0.999999}) {lane=candidate;break}
                    }
                }
                lanes[address]=lane;occupied.append(lane)
            }
        }
        return (ranks,lanes)
    }

}
