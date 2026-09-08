import Foundation

public struct StudioDestination:Identifiable {
    public var id:CircleAddress
    public var name:String
    public var role:String
    public var connected:Bool
}
public struct StudioTrackRoute:Identifiable {
    public var id:ID
    public var name:String
    public var destinations:[StudioDestination]
}
public struct StudioSectionRoute:Identifiable {
    public var id:CircleAddress
    public var name:String
    public var path:String
    public var tracks:[StudioTrackRoute]
}

/// Navigation uses actual lane ownership and audible output paths; it never edits music.
public enum StudioNavigation {
    public static func outputTracks(from id:ID,graph:SectionGraph)->Set<ID> {
        var frontier=[id],visited=Set<ID>(),result=Set<ID>()
        let nodes=Dictionary(uniqueKeysWithValues:graph.nodes.map{($0.id,$0)})
        while let current=frontier.popLast(),visited.count<=graph.nodes.count {
            guard visited.insert(current).inserted,let node=nodes[current] else{continue}
            if case .output(let track)=node.content {result.insert(track)}
            frontier += graph.edges.filter{$0.from==current && !$0.sidechain}.map(\.to)
        }
        return result
    }
    public static func build(_ project:Project)throws->[StudioSectionRoute] {
        guard let album=project.album else{return []}
        var result:[StudioSectionRoute]=[]
        func visit(_ ids:[ID])throws {
            for id in ids {
                guard let composition=album.composition(id) else{continue}
                if !composition.children.isEmpty {try visit(composition.children);continue}
                guard let arrangement=project.arrangements.first(where:{$0.id==composition.selectedArrangementID}) else{continue}
                let path=try album.path(to:id).map(\.name).joined(separator:" › ")
                for use in arrangement.uses {
                    guard let section=project.sections.first(where:{$0.id==use.sectionID}),let graph=try SectionGraphEditing.effective(section:section,use:use) else{continue}
                    let lanes=try ArrangementCompiler.effectiveLanes(section:section,use:use)
                    let ordered=try SectionGraphValidator.sorted(graph)
                    let outgoing=Dictionary(grouping:graph.edges.filter{!$0.sidechain},by:\.from)
                    var outputs:[ID:Set<ID>]=[:]
                    for node in ordered.reversed() {
                        var tracks=Set<ID>()
                        if case .output(let track)=node.content {tracks.insert(track)}
                        for edge in outgoing[node.id] ?? [] {tracks.formUnion(outputs[edge.to] ?? [])}
                        outputs[node.id]=tracks
                    }
                    var tracks:[StudioTrackRoute]=[]
                    for track in project.tracks {
                        let laneIDs=Set(lanes.filter{$0.trackID==track.id}.map(\.id))
                        let destinations=ordered.compactMap { node->StudioDestination? in
                            let owned:Bool
                            switch node.content {
                            case .midi(let lane),.audio(let lane,_):owned=laneIDs.contains(lane)
                            case .instrument(let id),.output(let id):owned=id==track.id
                            case .rhythmMIDI,.rhythmAudio:return nil
                            case .effect,.mix:owned=outputs[node.id]?.contains(track.id)==true
                            }
                            guard owned else{return nil}
                            return StudioDestination(id:.music(arrangementID:arrangement.id,useID:use.id,nodeID:node.id),name:node.name,role:node.content.label,connected:outputs[node.id]?.contains(track.id)==true)
                        }
                        if !destinations.isEmpty {tracks.append(StudioTrackRoute(id:track.id,name:track.name,destinations:destinations))}
                    }
                    result.append(StudioSectionRoute(id:.section(arrangementID:arrangement.id,useID:use.id),name:use.name,path:path,tracks:tracks))
                }
            }
        }
        try visit(album.children);return result
    }
    /// Expand only containing layout groups; use candidate copy so a failed route stays atomic.
    public static func reveal(_ target:CircleAddress,in project:inout Project)throws {
        var candidate=project,cursor=target,seen=Set<CircleAddress>()
        while cursor != .album,seen.insert(cursor).inserted {
            let scope=try HierarchyEditing.scope(of:cursor,in:candidate)
            if let member=HierarchyEditing.memberID(cursor) {
                let layout=try HierarchyEditing.layout(for:scope,in:candidate)
                if layout.groups.contains(where:{$0.collapsed && $0.members.contains(member)}) {
                    try HierarchyEditing.editLayout(scope,in:&candidate) {layout in
                        for i in layout.groups.indices where layout.groups[i].members.contains(member) {layout.groups[i].collapsed=false}
                    }
                }
            }
            cursor=scope
        }
        guard try HierarchySceneBuilder.build(candidate).node(target) != nil else{throw CirclrError("이 서클은 현재 편곡에서 사용할 수 없습니다")}
        project=candidate
    }
}
