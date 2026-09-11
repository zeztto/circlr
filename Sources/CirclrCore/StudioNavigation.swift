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

/// Navigation uses lane ownership and structural main-output paths; it never edits music.
public enum StudioNavigation {
    public static func outputTracks(from id:ID,graph:SectionGraph)->Set<ID> {
        (try? SectionGraphReachability(graph:graph).outputTracks(from:id)) ?? []
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
                    let reachability=try SectionGraphReachability(graph:graph)
                    let ordered=reachability.orderedNodes
                    let (_,context,_)=try ArrangementCompiler.context(project:project,use:use,arrangementID:arrangement.id)
                    // Match scene visibility: a rhythm source needs its resolved pattern;
                    // audio additionally needs clips, while empty MIDI remains editable.
                    let visible=try ordered.filter { node in
                        switch node.content {
                        case .rhythmMIDI(let trackID),.rhythmAudio(let trackID):
                            let resolved=try ContextResolver.inheriting(global:project.global,parent:context,settings:node.settings)
                            guard let pattern=project.patterns.first(where:{$0.id==resolved.rhythm.patternID && $0.trackID==trackID}) else{return false}
                            if case .rhythmAudio=node.content{return !pattern.audio.isEmpty}
                            return true
                        default:return true
                        }
                    }
                    let outputs=Dictionary(uniqueKeysWithValues:ordered.map{($0.id,reachability.outputTracks(from:$0.id))})
                    var tracks:[StudioTrackRoute]=[]
                    for track in project.tracks {
                        let laneIDs=Set(lanes.filter{$0.trackID==track.id}.map(\.id))
                        let destinations=visible.compactMap { node->StudioDestination? in
                            let owned:Bool
                            var name=node.name,role=node.content.label
                            switch node.content {
                            case .midi(let lane),.audio(let lane,_):owned=laneIDs.contains(lane)
                            case .instrument(let id),.output(let id):owned=id==track.id
                            case .rhythmMIDI(let id):owned=id==track.id;name += " · 공유 리듬";role="MIDI"
                            case .rhythmAudio(let id):owned=id==track.id;name += " · 공유 리듬";role="오디오"
                            case .effect,.mix,.router:owned=outputs[node.id]?.contains(track.id)==true
                            }
                            guard owned else{return nil}
                            return StudioDestination(id:.music(arrangementID:arrangement.id,useID:use.id,nodeID:node.id),name:name,role:role,connected:outputs[node.id]?.contains(track.id)==true)
                        }
                        if !destinations.isEmpty {tracks.append(StudioTrackRoute(id:track.id,name:track.name,destinations:destinations))}
                    }
                    result.append(StudioSectionRoute(id:.section(arrangementID:arrangement.id,useID:use.id),name:use.name,path:path,tracks:tracks))
                }
            }
        }
        try visit(album.children);return result
    }
    /// Reveal a selection path in the scene without creating document layout overrides.
    public static func containingGroups(of target:CircleAddress?,in project:Project)throws->Set<CircleAddress> {
        guard var cursor=target else{return []}
        var seen=Set<CircleAddress>(),groups=Set<CircleAddress>()
        while cursor != .album,seen.insert(cursor).inserted {
            let scope=try HierarchyEditing.scope(of:cursor,in:project)
            if let member=HierarchyEditing.memberID(cursor) {
                let layout=try HierarchyEditing.layout(for:scope,in:project)
                for group in layout.groups where group.collapsed && group.members.contains(member) {
                    groups.insert(.group(parent:scope,id:group.id))
                }
            }
            cursor=scope
        }
        return groups
    }
    public static func scene(revealing target:CircleAddress,in project:Project)throws->HierarchyScene {
        let scene=try HierarchySceneBuilder.build(project,revealing:target)
        guard scene.node(target) != nil else{throw CirclrError("이 서클은 현재 편곡에서 사용할 수 없습니다")}
        return scene
    }
}
