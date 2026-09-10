import Foundation

/// Saved view state; restoring it never edits or starts the music graph.
public struct StudioWorkspace:Codable,Equatable {
    public enum Page:String,Codable {case content,connections,transition,automation,settings,pitchBend}
    public var page:Page
    public var original=false
    public var transitionID:ID?
    public var connection:ConnectionWorkspaceState?
    public var automationParameter=AutomationParameter.gain
    public var selection:EditorSelectionState?
    public var editor:EditorViewportState?
    public var automationViewport:AutomationViewport?
    public var pitchBend:PitchBendWorkspaceState?
    public init(page:Page = .content){self.page=page}
    enum CodingKeys:String,CodingKey {case page,original,transitionID,connection,automationParameter,editor,automationViewport,selection,pitchBend}
    public init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        page=(try? c.decode(Page.self,forKey:.page)) ?? .content
        pitchBend=(try? c.decode(PitchBendWorkspaceState.self,forKey:.pitchBend))?.validated()
        original=(try? c.decode(Bool.self,forKey:.original)) ?? false
        transitionID=try? c.decode(ID.self,forKey:.transitionID)
        connection=try? c.decode(ConnectionWorkspaceState.self,forKey:.connection)
        automationParameter=(try? c.decode(AutomationParameter.self,forKey:.automationParameter)) ?? .gain
        selection=try? c.decode(EditorSelectionState.self,forKey:.selection)
        editor=try? c.decode(EditorViewportState.self,forKey:.editor)
        automationViewport=(try? c.decode(AutomationViewport.self,forKey:.automationViewport))?.validated
    }
    public func restored(at address:CircleAddress,in project:Project)->Self {
        guard let scene=try? StudioNavigation.scene(revealing:address,in:project),let node=scene.node(address) else{return .init()}
        var next=self
        if page == .pitchBend {
            switch node.music?.content {case .midi,.rhythmMIDI:break;default:next.page = .content;next.pitchBend=nil}
        }
        if let music=node.music,!next.automationParameter.supports(node:music,in:project) {next.automationParameter = .gain}
        if let id=transitionID {
            if case .section(let ai,let ui)=address,
               project.arrangements.first(where:{$0.id==ai})?.edges.contains(where:{$0.id==id && $0.from==ui})==true {} else {next.transitionID=nil}
        }
        if page == .transition && next.transitionID==nil {next.page = .settings}
        if page == .automation && node.music?.supportsAutomation != true {next.page = .content}
        if page == .connections && node.ports.isEmpty && node.role != .group {next.page = .content}
        if let remembered=connection {
            let own=CirclePortEndpoint(node:address,portID:remembered.ownPortID)
            let targets=scene.nodes.flatMap { target in target.ports.compactMap { port->ConnectionTargetChoice? in
                let endpoint=CirclePortEndpoint(node:target.id,portID:port.id)
                guard (try? CirclePortCatalog.normalize(own,endpoint,in:project)) != nil else{return nil}
                return ConnectionTargetSearch.choice(endpoint,name:target.title,port:port.name,in:project)
            }}
            let edges=((try? AgentPortEditing.snapshot(at:address,in:project))?.connections ?? []).map(\.connection)
            next.connection=remembered.restored(ports:node.ports,targets:targets,connections:edges)
        }
        return next
    }
    public static func restoredSelection(_ preferred:CircleAddress,in project:Project)->CircleAddress {
        var candidate=preferred,visited=Set<CircleAddress>()
        while visited.insert(candidate).inserted {
            if (try? StudioNavigation.scene(revealing:candidate,in:project)) != nil {return candidate}
            switch candidate {
            case .music(let ai,let ui,_):candidate = .section(arrangementID:ai,useID:ui)
            case .section(let ai,_):
                candidate=project.album?.compositions.first(where:{$0.arrangementIDs.contains(ai)}).map{.composition($0.id)} ?? .album
            case .group(let parent,_):candidate=parent
            case .signal:candidate = .sound
            case .composition,.sound,.album:candidate = .album
            }
        }
        return .album
    }
}
