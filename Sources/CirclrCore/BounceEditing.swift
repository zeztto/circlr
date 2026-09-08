import Foundation

public struct BounceSource: Codable, Equatable {
    public var outputNodeID:ID
    public var replacedInputs:[MusicConnection]
    public var sourceRevision:Int
    public var bodySeconds:Double
    public var tailSeconds:Double
    public var familyID:ID?
}
public enum BounceEditing {
    /// Captures a track's section output before track gain and global routing.
    /// Disconnects its former inputs without destroying their nodes or note data.
    @discardableResult public static func apply(asset:Asset,trackID:ID,useID:ID,bodySeconds:Double,tailSeconds:Double,in project:inout Project) throws -> ID {
        var candidate=project
        guard let use=candidate.active.uses.first(where:{$0.id==useID}),let section=candidate.sections.first(where:{$0.id==use.sectionID}),var graph=try SectionGraphEditing.effective(section:section,use:use) else {throw CirclrError("바운스할 섹션을 찾을 수 없습니다")}
        let outputs=graph.nodes.filter{if case .output(let id)=$0.content{return id==trackID};return false}
        guard outputs.count==1,let output=outputs.first else {throw CirclrError("바운스할 트랙의 출력 서클을 하나로 연결하세요")}
        let inputs=graph.edges.filter{$0.to==output.id}
        guard !inputs.isEmpty else {throw CirclrError("출력에 연결된 연주가 없습니다")}
        var lane=Lane(trackID:trackID),clip=AudioClip(assetID:asset.id,duration:asset.duration)
        clip.preservesTail=true;lane.audio=[clip]
        var node=MusicCircle(name:"\(asset.name)",content:.audio(laneID:lane.id,clipID:clip.id))
        node.bounce=BounceSource(outputNodeID:output.id,replacedInputs:inputs,sourceRevision:project.musicRevision,bodySeconds:bodySeconds,tailSeconds:tailSeconds)
        candidate.assets.append(asset)
        // Lane edit can introduce automatic routes; finish with our exact graph below.
        try ProjectEditing.setLane(lane,for:useID,original:false,in:&candidate)
        graph.edges.removeAll{$0.to==output.id}
        graph.nodes.append(node);graph.edges.append(MusicConnection(from:node.id,to:output.id,signal:.audio))
        let position=graph.layout.positions[output.id] ?? Point();graph.layout.positions[node.id]=Point(position.x-240,position.y-220)
        try SectionGraphEditing.set(graph,useID:useID,original:false,in:&candidate)
        try ProjectStore.validateStructure(candidate);project=candidate;return node.id
    }
    public static func restore(nodeID:ID,useID:ID,in project:inout Project) throws {
        var candidate=project
        guard let use=candidate.active.uses.first(where:{$0.id==useID}),let section=candidate.sections.first(where:{$0.id==use.sectionID}),var graph=try SectionGraphEditing.effective(section:section,use:use),let node=graph.nodes.first(where:{$0.id==nodeID}),let source=node.bounce else {throw CirclrError("바운스 원본을 찾을 수 없습니다")}
        let family=Set(graph.nodes.filter{n in n.id==nodeID || (source.familyID != nil && n.bounce?.familyID==source.familyID && n.bounce?.outputNodeID==source.outputNodeID && n.bounce?.replacedInputs==source.replacedInputs)}.map(\.id))
        guard source.replacedInputs.allSatisfy({edge in graph.nodes.contains{$0.id==edge.from} && graph.nodes.contains{$0.id==edge.to}}),graph.edges.filter({$0.to==source.outputNodeID}).allSatisfy({family.contains($0.from)}) else {throw CirclrError("바운스 이후 출력 연결이 변경되었습니다. 연결을 정리하거나 Undo로 복원하세요")}
        graph.edges.removeAll{$0.to==source.outputNodeID}
        graph.edges.append(contentsOf:source.replacedInputs)
        // Keep the rendered audio circle as a disconnected, reusable archive.
        for i in graph.nodes.indices where family.contains(graph.nodes[i].id) {graph.nodes[i].muted=true;graph.nodes[i].bounce=nil}
        try SectionGraphEditing.set(graph,useID:useID,original:false,in:&candidate)
        try ProjectStore.validateStructure(candidate);project=candidate
    }
}
