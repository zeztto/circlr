import Foundation

public enum SourceCircleEditing {
    /// Only new sources acquire default routes; explicit disconnections stay disconnected.
    static func merge(_ defaults:SectionGraph,adding ids:Set<ID>,into graph:inout SectionGraph) {
        graph.nodes += defaults.nodes.filter{ids.contains($0.id)}
        for edge in defaults.edges where ids.contains(edge.from) {
            if !graph.edges.contains(where:{$0.id==edge.id}) {graph.edges.append(edge)}
        }
        for id in ids.sorted() {
            var point=defaults.layout.positions[id] ?? Point()
            while graph.layout.positions.contains(where:{$0.key != id && hypot($0.value.x-point.x,$0.value.y-point.y)<180}) {point.y+=200}
            graph.layout.positions[id]=point
        }
    }
    /// Explicit pattern creation can add an instrument to a previously audio-only source.
    @discardableResult public static func ensureRhythmMIDI(trackID:ID,useID:ID,in project:inout Project)throws->ID {
        guard let track=project.tracks.first(where:{$0.id==trackID}),let use=project.active.uses.first(where:{$0.id==useID}),
              let section=project.sections.first(where:{$0.id==use.sectionID}),var graph=try SectionGraphEditing.effective(section:section,use:use) else {throw CirclrError("리듬을 만들 트랙과 섹션을 확인하세요")}
        let defaults=SectionGraphMigration.graph(lanes:[],tracks:[track],effects:[])
        let added=Set(defaults.nodes.map(\.id)).subtracting(graph.nodes.map(\.id))
        merge(defaults,adding:added,into:&graph)
        var candidate=project
        try SectionGraphEditing.set(graph,useID:useID,original:false,in:&candidate)
        try ProjectStore.validateStructure(candidate);project=candidate
        return "rhythm-midi:\(trackID)"
    }
}
