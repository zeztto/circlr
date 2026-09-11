import Foundation

public extension SectionSignalPlan {
    /// Keep the exact dependencies of one output, including MIDI and sidechain.
    /// Router traversal is by bus endpoint, never by its aggregate node membership.
    func selectingOutput(_ outputNodeID:ID)throws->SectionSignalPlan {
        let nodes=Dictionary(uniqueKeysWithValues:orderedNodes.map{($0.id,$0)})
        guard let output=nodes[outputNodeID],case .output=output.content else {
            throw CirclrError("선택한 섹션 출력을 찾을 수 없습니다")
        }
        let incoming=Dictionary(grouping:connections,by:{$0.to.nodeID})
        var pending=[MusicBusEndpoint(nodeID:outputNodeID,portID:CirclePort.audioInput)]
        var visited=Set<MusicBusEndpoint>(),nodeIDs=Set<ID>(),edgeIDs=Set<ID>()
        while let endpoint=pending.popLast() {
            guard visited.insert(endpoint).inserted else{continue}
            guard let node=nodes[endpoint.nodeID] else{throw CirclrError("출력 경로의 서클을 찾을 수 없습니다")}
            nodeIDs.insert(node.id)
            let allowedInputs:Set<String>?
            if case .router(let router)=node.content {
                allowedInputs=Set(router.routes.filter{$0.output==endpoint.portID}.map(\.input))
            }else{allowedInputs=nil}
            for edge in incoming[node.id] ?? [] {
                if let allowedInputs,!allowedInputs.contains(edge.to.portID){continue}
                edgeIDs.insert(edge.id);pending.append(edge.from)
            }
        }
        var result=self
        result.orderedNodes=orderedNodes.filter{nodeIDs.contains($0.id)}
        result.graph.nodes=graph.nodes.filter{nodeIDs.contains($0.id)}
        result.graph.edges=graph.edges.filter{edgeIDs.contains($0.id)}
        result.connections=connections.filter{edgeIDs.contains($0.id)}
        result.contexts=contexts.filter{nodeIDs.contains($0.key)}
        result.midi=midi.filter{nodeIDs.contains($0.key)}
        result.audio=audio.filter{nodeIDs.contains($0.key)}
        result.automation=automation.filter{nodeIDs.contains($0.key)}
        return result
    }
}
