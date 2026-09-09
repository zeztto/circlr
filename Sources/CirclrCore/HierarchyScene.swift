import Foundation

public enum CircleAddress: Hashable, Codable, Sendable {
    case album
    case sound
    case signal(ID)
    case composition(ID)
    case section(arrangementID: ID, useID: ID)
    case music(arrangementID: ID, useID: ID, nodeID: ID)
    indirect case group(parent: CircleAddress, id: ID)
}
public enum CircleRole { case album, song, movement, section, music, group, sound }
public struct CircleSceneNode: Identifiable {
    public var id: CircleAddress
    public var parent: CircleAddress?
    public var center: Point
    public var radius: Double
    public var scale: Double
    public var depth: Int
    public var title: String
    public var subtitle: String
    public var role: CircleRole
    public var repeatCount: Int
    public var childCount: Int
    public var context: MusicContext
    public var clock: MusicClock?
    public var music: MusicCircle?
    public var signal: SignalNode?
    public var timeline: OrbitTimeline?
    public var orbit: OrbitPlacement?
    public var exposedPorts:[CirclePort]? = nil
    public var ports:[CirclePort] {
        if let exposedPorts {return exposedPorts}
        if let signal {return CirclePort.ports(for:signal)}
        if let music {return CirclePort.ports(for:music.content)}
        return role == .song || role == .movement || role == .section ? CirclePort.flowPorts:[]
    }
    // The canvas queries these every frame; do not allocate descriptor arrays on that path.
    public var acceptsInput: Bool {exposedPorts.map{$0.contains{$0.direction == .input}} ?? (signal.map{$0.kind != .source} ?? (music?.content.input != nil || role == .song || role == .movement || role == .section))}
    public var providesOutput: Bool {exposedPorts.map{$0.contains{$0.direction == .output}} ?? (signal.map{$0.kind != .master} ?? (music?.content.output != nil || role == .song || role == .movement || role == .section))}
    public var outerRadius: Double { radius + (SectionRings(repeats: repeatCount).outerRadius-80) * scale }
}
public struct CircleSceneEdge: Identifiable {
    public enum Kind { case flow, midi, audio, sidechain }
    public var id: String
    public var from: CircleAddress
    public var to: CircleAddress
    public var kind: Kind
    public var gain: Double = 1
    public var connectionID:CircleConnectionID?
    public var placement=CircleConnectionPlacement()
    public var explicitFromPortID:String?
    public var explicitToPortID:String?
    public var fromPortID:String {explicitFromPortID ?? (kind == .flow ? CirclePort.flowOutput:kind == .midi ? CirclePort.midiOutput:CirclePort.audioOutput)}
    public var toPortID:String {explicitToPortID ?? (kind == .flow ? CirclePort.flowInput:kind == .midi ? CirclePort.midiInput:kind == .sidechain ? CirclePort.sidechainInput:CirclePort.audioInput)}
}
public struct HierarchyScene {
    public let nodes: [CircleSceneNode]
    public let edges: [CircleSceneEdge]
    private let nodesByID: [CircleAddress: CircleSceneNode]
    private let childrenByParent: [CircleAddress: [CircleSceneNode]]
    public init(nodes: [CircleSceneNode], edges: [CircleSceneEdge]) {
        self.nodes = nodes; self.edges = edges
        nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var children: [CircleAddress: [CircleSceneNode]] = [:]
        for node in nodes { if let parent = node.parent { children[parent, default: []].append(node) } }
        childrenByParent = children
    }
    public func node(_ address: CircleAddress) -> CircleSceneNode? { nodesByID[address] }
    public func children(of address: CircleAddress) -> [CircleSceneNode] { childrenByParent[address] ?? [] }
    public func path(to address: CircleAddress) -> [CircleSceneNode] {
        var result: [CircleSceneNode] = [], cursor: CircleAddress? = address
        while let current = cursor, let node = node(current), result.count < 68 { result.append(node); cursor = node.parent }
        return result.reversed()
    }
}

public enum HierarchySceneBuilder {
    public static let childScale = 0.3
    private struct Tree {
        var node: CircleSceneNode
        var position = Point()
        var children: [Tree] = []
        var childScale = HierarchySceneBuilder.childScale
        var layoutRadius: Double?
    }
    public static func build(_ project: Project, revealing selection: CircleAddress? = nil) throws -> HierarchyScene {
        try project.portLayout?.validate()
        guard let album = project.album else { throw CirclrError("앨범 서클 모델이 없습니다") }
        try album.validate(arrangements: project.arrangements)
        let revealedGroups = (try? StudioNavigation.containingGroups(of: selection, in: project)) ?? []
        var edges: [CircleSceneEdge] = []
        var hiddenOwners: [CircleAddress: CircleAddress] = [:]
        func node(_ address: CircleAddress, title: String, subtitle: String, role: CircleRole,
                  context: MusicContext, repeats: Int = 1, clock: MusicClock? = nil, music: MusicCircle? = nil, signal: SignalNode? = nil) -> CircleSceneNode {
            CircleSceneNode(id: address, center: Point(), radius: role == .music ? 80 : 200, scale: 1, depth: 0,
                            title: title, subtitle: subtitle, role: role, repeatCount: repeats, childCount: 0, context: context, clock: clock, music: music, signal: signal)
        }
        func finish(_ input: Tree) -> Tree {
            var tree = input
            tree.node.childCount = tree.children.count
            for child in tree.children {
                let extent = hypot(child.position.x, child.position.y) + child.node.outerRadius
                tree.node.radius = max(tree.node.radius, extent * tree.childScale + 60)
            }
            return tree
        }
        func orbiting(_ input: Tree) -> Tree {
            guard project.usesOrbits else {return input}
            var tree=input
            let untimed=tree.children.filter{$0.node.orbit == nil}
            var edge=untimed.map{hypot($0.position.x,$0.position.y)+($0.layoutRadius ?? $0.node.outerRadius)}.max() ?? 60
            for i in tree.children.indices where tree.children[i].node.orbit != nil {
                let extent=tree.children[i].layoutRadius ?? tree.children[i].node.outerRadius
                let radius=edge+extent+70
                let orbit=tree.children[i].node.orbit!
                tree.children[i].position=orbit.timeline.point(at:orbit.anchor,radius:radius)
                tree.children[i].node.orbit?.radius=radius
                edge=radius+extent+40
            }
            return tree
        }
        func sequence(_ input: Tree) -> Tree {
            var tree=input
            guard tree.children.allSatisfy({$0.node.timeline != nil}) else {return tree}
            let duration=tree.children.reduce(0){$0+($1.node.timeline?.duration ?? 0)*Double($1.node.repeatCount)}
            guard duration>0 else {tree.node.timeline=OrbitTimeline(duration:0);return tree}
            var cursor=0.0,ticks:[OrbitTimeline.Tick]=[]
            for child in tree.children {
                ticks.append(.init(cursor,child.node.title));cursor+=(child.node.timeline?.duration ?? 0)*Double(child.node.repeatCount)
            }
            let timeline=OrbitTimeline(duration:duration,ticks:ticks);tree.node.timeline=timeline;cursor=0
            for i in tree.children.indices {
                let length=tree.children[i].node.timeline!.duration
                guard length>0 else {continue}
                let intervals=(0..<tree.children[i].node.repeatCount).map{OrbitInterval(cursor+Double($0)*length,cursor+Double($0+1)*length)}
                tree.children[i].node.orbit=OrbitPlacement(owner:tree.node.id,timeline:timeline,anchor:cursor,intervals:intervals)
                cursor+=length*Double(tree.children[i].node.repeatCount)
            }
            return tree
        }
        func grouped(_ input: Tree, layout: Layout) -> Tree {
            var tree = input
            for group in layout.groups {
                let members = tree.children.filter { child in HierarchyEditing.memberID(child.node.id).map(group.members.contains) == true }
                guard !members.isEmpty else { continue }
                let center = Point(members.map(\.position.x).reduce(0,+)/Double(members.count), members.map(\.position.y).reduce(0,+)/Double(members.count))
                let address = CircleAddress.group(parent: tree.node.id, id: group.id)
                let collapsed = group.collapsed && !revealedGroups.contains(address)
                var container = Tree(node: node(address, title: group.name,
                                                subtitle: "\(members.count)개 서클" + (collapsed ? " · 접힘" : ""), role: .group, context: tree.node.context), position: center)
                container.childScale = 1
                container.node.exposedPorts = try? GroupPortEditing.ports(at:container.node.id,in:project)
                container.children = members.map { item in var copy = item; copy.position = Point(item.position.x-center.x,item.position.y-center.y); return copy }
                container = finish(container)
                if collapsed {
                    func hide(_ child: Tree) { hiddenOwners[child.node.id] = container.node.id; for nested in child.children { hide(nested) } }
                    for child in container.children { hide(child) }
                    container.children = []; container.node.radius = 100; container.node.childCount = 0
                }
                let ids = Set(members.map(\.node.id)); tree.children.removeAll { ids.contains($0.node.id) }; tree.children.append(container)
            }
            return tree
        }
        func seal(_ input: Tree, layout: Layout) -> Tree {
            let positioned=orbiting(input)
            var natural=positioned.node.radius
            for child in positioned.children {natural=max(natural,(hypot(child.position.x,child.position.y)+(child.layoutRadius ?? child.node.outerRadius))*positioned.childScale+60)}
            var result=finish(grouped(positioned,layout:layout))
            // Visual group padding must not relocate an ancestor or change a time angle.
            result.layoutRadius=natural+(positioned.node.outerRadius-positioned.node.radius)
            return result
        }
        func section(_ use: SectionUse, arrangement: Arrangement) throws -> Tree {
            let address = CircleAddress.section(arrangementID: arrangement.id, useID: use.id)
            let (definition, context, clock) = try ArrangementCompiler.context(project: project, use: use, arrangementID: arrangement.id)
            var tree = Tree(node: node(address, title: use.name, subtitle: "\(clock.meters.count)마디 · \(use.repeatCount)회", role: .section,
                                       context: context, repeats: use.repeatCount, clock: clock), position: arrangement.layout.positions[use.id] ?? Point())
            tree.node.timeline=OrbitTimeline(clock:clock)
            let lanes=try ArrangementCompiler.effectiveLanes(section:definition,use:use)
            var sectionLayout = Layout()
            if let graph = try SectionGraphEditing.effective(section: definition, use: use) {
                sectionLayout = graph.layout
                for music in graph.nodes {
                    let resolved = try ContextResolver.inheriting(global: project.global, parent: context, settings: music.settings)
                    switch music.content {
                    case .rhythmMIDI(let trackID), .rhythmAudio(let trackID):
                        guard let pattern = project.patterns.first(where: { $0.id == resolved.rhythm.patternID && $0.trackID == trackID }) else { continue }
                        if case .rhythmAudio = music.content, pattern.audio.isEmpty { continue }
                    default: break
                    }
                    var ownClock: MusicClock?
                    if music.content.input == nil {
                        var ownContext=resolved
                        let length=music.lengthBeats ?? clock.beats
                        if music.settings.tempo.source == .inherit {ownContext.tempo=clock.bpm(at:music.startBeat)}
                        ownClock=try? MusicClock(parent:clock,start:music.startBeat,length:length,context:ownContext,
                                                inheritTempo:music.settings.tempo.source == .inherit,inheritMeter:music.settings.meter.source == .inherit)
                    }
                    let id = CircleAddress.music(arrangementID: arrangement.id, useID: use.id, nodeID: music.id)
                    var child=Tree(node:node(id,title:music.name,subtitle:music.content.label,role:.music,
                                             context:resolved,repeats:music.repeatCount,clock:ownClock,music:music),position:graph.layout.positions[music.id] ?? Point())
                    if let ownClock {child.node.timeline=OrbitTimeline(clock:ownClock)}
                    if music.content.input == nil {
                        let clips:[AudioClip]
                        switch music.content {
                        case .audio(let lane,let clip): clips=lanes.first{$0.id==lane}?.audio.filter{$0.id==clip} ?? []
                        case .rhythmAudio(let track): clips=project.patterns.first{$0.id==resolved.rhythm.patternID && $0.trackID==track}?.audio ?? []
                        default: clips=[]
                        }
                        child.node.orbit=OrbitPlacement(owner:address,timeline:OrbitTimeline(clock:clock),anchor:min(clock.seconds,clock.seconds(at:music.startBeat)),
                                                       intervals:OrbitTiming.intervals(node:music,context:resolved,clock:clock,clips:clips))
                    }
                    tree.children.append(child)
                }
                let visible = Set(tree.children.map(\.node.id))
                for edge in graph.edges {
                    let from = CircleAddress.music(arrangementID: arrangement.id, useID: use.id, nodeID: edge.from)
                    let to = CircleAddress.music(arrangementID: arrangement.id, useID: use.id, nodeID: edge.to)
                    if visible.contains(from), visible.contains(to) {
                        edges.append(CircleSceneEdge(id: "\(arrangement.id):\(use.id):\(edge.id)", from: from, to: to,
                                                     kind: edge.sidechain ? .sidechain : (edge.signal == .midi ? .midi : .audio), gain: edge.gain,
                                                     connectionID:.init(edgeID:edge.id,from:from,to:to),explicitFromPortID:edge.fromPortID,explicitToPortID:edge.toPortID))
                    }
                }
            }
            return seal(tree,layout:sectionLayout)
        }
        func compositions(_ ids: [ID], parentContext: MusicContext, layout: Layout, depth: Int) throws -> [Tree] {
            guard depth <= 64 else { throw CirclrError("앨범의 서클 계층이 너무 깊습니다") }
            var trees: [Tree] = []
            for id in ids {
                guard let composition = album.composition(id) else { throw CirclrError("곡·악장 서클이 없습니다") }
                let context = try ContextResolver.inheriting(global: project.global, parent: parentContext, settings: composition.settings)
                var tree = Tree(node: node(.composition(id), title: composition.name, subtitle: composition.kind.label,
                                           role: composition.kind == .song ? .song : .movement, context: context, repeats: composition.repeatCount),
                                position: layout.positions[id] ?? Point())
                if !composition.children.isEmpty {
                    tree.children = try compositions(composition.children, parentContext: context, layout: composition.layout, depth: depth + 1)
                    tree=sequence(tree)
                } else if let arrangement = project.arrangements.first(where: { $0.id == composition.selectedArrangementID }) {
                    tree.children = try arrangement.uses.map { try section($0, arrangement: arrangement) }
                    if let plan=try? ArrangementCompiler.compile(project,arrangementID:arrangement.id) {
                        let timeline=OrbitTimeline(duration:plan.duration,ticks:plan.occurrences.map{.init($0.start,$0.use.name)})
                        tree.node.timeline=timeline
                        for i in tree.children.indices {
                            guard case .section(_,let useID)=tree.children[i].node.id else {continue}
                            let spans=plan.occurrences.filter{$0.use.id==useID}.map{OrbitInterval($0.start,$0.end)}
                            if let first=spans.first {tree.children[i].node.orbit=OrbitPlacement(owner:tree.node.id,timeline:timeline,anchor:first.start,intervals:spans)}
                            else {tree.children[i].node.subtitle += " · 경로 밖"}
                        }
                    } else if !arrangement.uses.isEmpty {tree.node.subtitle += " · 재생 경로 확인"}
                    for edge in arrangement.edges {
                        let from=CircleAddress.section(arrangementID:arrangement.id,useID:edge.from),to=CircleAddress.section(arrangementID:arrangement.id,useID:edge.to)
                        edges.append(CircleSceneEdge(id:edge.id,from:from,to:to,kind:.flow,connectionID:.init(edgeID:edge.id,from:from,to:to)))
                    }
                }
                let groupingLayout = composition.children.isEmpty ? (project.arrangements.first { $0.id == composition.selectedArrangementID }?.layout ?? Layout()) : composition.layout
                trees.append(seal(tree,layout:groupingLayout))
            }
            for pair in zip(ids, ids.dropFirst()) {
                let id="composition-flow:\(pair.0):\(pair.1)",from=CircleAddress.composition(pair.0),to=CircleAddress.composition(pair.1)
                edges.append(CircleSceneEdge(id:id,from:from,to:to,kind:.flow,connectionID:.init(edgeID:id,from:from,to:to)))
            }
            return trees
        }
        var root = Tree(node: node(.album, title: project.name, subtitle: "앨범", role: .album, context: project.global))
        root.children = try compositions(album.children, parentContext: project.global, layout: album.layout, depth: 0)
        root=sequence(root)
        var sound = Tree(node: node(.sound, title: "앨범 사운드", subtitle: "트랙 출력 · 버스 · 마스터", role: .sound, context: project.global))
        for signal in project.signal.nodes {
            let labels: [SignalKind:String] = [.source:"트랙 출력",.effect:"전역 이펙터",.bus:"버스",.master:"마스터"]
            sound.children.append(Tree(node: node(.signal(signal.id), title: signal.name, subtitle: labels[signal.kind] ?? "사운드", role: .music, context: project.global, signal: signal), position: project.signal.layout.positions[signal.id] ?? Point()))
        }
        sound = seal(sound,layout:project.signal.layout)
        let lowerEdge = root.children.map { $0.position.y+$0.node.outerRadius }.max() ?? 0
        sound.position = album.layout.positions["circlr:sound"] ?? Point(0, lowerEdge+sound.node.outerRadius+220)
        root.children.append(sound)
        for edge in project.signal.edges {
            let from=CircleAddress.signal(edge.from),to=CircleAddress.signal(edge.to)
            edges.append(CircleSceneEdge(id:"signal:\(edge.id)",from:from,to:to,kind:edge.sidechain ? .sidechain:.audio,gain:edge.gain,connectionID:.init(edgeID:edge.id,from:from,to:to)))
        }
        if project.usesOrbits {sound.position=album.layout.positions["circlr:sound"] ?? Point();root.children[root.children.count-1]=sound}
        root = seal(root,layout:album.layout)
        var flattened: [CircleSceneNode] = []
        func flatten(_ tree: Tree, center: Point, scale: Double, parent: CircleAddress?, depth: Int) throws {
            guard flattened.count < 100_000 else { throw CirclrError("한 화면의 서클 수가 너무 많습니다") }
            var item = tree.node; item.center = center; item.radius *= scale; item.scale = scale; item.parent = parent; item.depth = depth
            item.orbit?.radius *= scale
            flattened.append(item)
            for child in tree.children {
                let nextScale = scale * tree.childScale
                let point = Point(center.x + child.position.x * nextScale, center.y + child.position.y * nextScale)
                try flatten(child, center: point, scale: nextScale, parent: item.id, depth: depth + 1)
            }
        }
        try flatten(root, center: Point(), scale: 1, parent: nil, depth: 0)
        guard Set(flattened.map(\.id)).count == flattened.count else { throw CirclrError("캔버스의 서클 ID가 중복되었습니다") }
        let placements=Dictionary(uniqueKeysWithValues:(project.portLayout?.connections ?? []).map{($0.id,$0.placement)})
        let displayedEdges = edges.compactMap { edge -> CircleSceneEdge? in
            var copy = edge
            if let id=copy.connectionID,let placement=placements[id] {copy.placement=placement}
            while let owner = hiddenOwners[copy.from] { copy.from = owner }
            while let owner = hiddenOwners[copy.to] { copy.to = owner }
            if copy.from != edge.from, let alias=GroupPortEditing.presented(.init(node:edge.from,portID:edge.fromPortID),at:copy.from,in:project) {copy.explicitFromPortID=alias.portID}
            if copy.to != edge.to, let alias=GroupPortEditing.presented(.init(node:edge.to,portID:edge.toPortID),at:copy.to,in:project) {copy.explicitToPortID=alias.portID}
            return copy.from == copy.to ? nil : copy
        }
        return HierarchyScene(nodes: flattened, edges: displayedEdges)
    }
}

public struct HierarchyCamera: Codable, Equatable, Sendable {
    public var pan = Point()
    public var zoom: Double = 1
    public init(pan: Point = Point(), zoom: Double = 1) { self.pan = pan; self.zoom = zoom }
    public func screen(_ p: Point) -> Point { Point(p.x * zoom + pan.x, p.y * zoom + pan.y) }
    public func world(_ p: Point) -> Point { Point((p.x-pan.x)/zoom, (p.y-pan.y)/zoom) }
    public func zoomed(to value: Double, around anchor: Point) -> HierarchyCamera {
        guard value.isFinite, value > 0 else { return self }
        let z = min(1e12, max(1e-6, value)), point = world(anchor)
        return HierarchyCamera(pan: Point(anchor.x-point.x*z, anchor.y-point.y*z), zoom: z)
    }
    /// Keep the selected circle in the same screen position and size after a layout change.
    public func preserving(_ previous:CircleSceneNode,in next:CircleSceneNode)->HierarchyCamera {
        guard previous.id==next.id,previous.radius.isFinite,previous.radius>0,next.radius.isFinite,next.radius>0 else{return self}
        let anchor=screen(previous.center),scale=zoom*previous.radius/next.radius
        guard anchor.x.isFinite,anchor.y.isFinite,scale.isFinite,scale>0,next.center.x.isFinite,next.center.y.isFinite else{return self}
        let z=min(1e12,max(1e-6,scale))
        return HierarchyCamera(pan:Point(anchor.x-next.center.x*z,anchor.y-next.center.y*z),zoom:z)
    }
    public func focused(on node: CircleSceneNode, width: Double, height: Double, detail: Bool = false) -> HierarchyCamera {
        let desired = max(80, min(width - 120, height - 160)) * (detail ? 0.68 : 0.43)
        let z = min(1e12, max(1e-6, desired / max(detail ? node.radius : node.outerRadius, 1e-12)))
        return HierarchyCamera(pan: Point(width/2-node.center.x*z, height/2+10-node.center.y*z), zoom: z)
    }
    public func interpolated(to target: HierarchyCamera, progress: Double) -> HierarchyCamera {
        let p = min(1, max(0, progress)), t = p*p*(3-2*p)
        // Log interpolation keeps large changes of scale from spending most frames at the wrong depth.
        let z = exp(log(zoom) + (log(target.zoom)-log(zoom))*t)
        let ratio = abs(target.zoom-zoom) < 1e-12 ? t : (z-zoom)/(target.zoom-zoom)
        return HierarchyCamera(pan: Point(pan.x+(target.pan.x-pan.x)*ratio, pan.y+(target.pan.y-pan.y)*ratio), zoom: z)
    }
}

/// Saved with the document, independently of musical revision and undo history.
public struct HierarchyViewport: Codable, Equatable {
    public var camera: HierarchyCamera
    public var width: Double
    public var height: Double
    public var selection: CircleAddress
    public var settingsOpen: Bool
    public var midiStepMode:Bool?
    public init(camera: HierarchyCamera, width: Double, height: Double, selection: CircleAddress, settingsOpen: Bool = false, midiStepMode:Bool = false) {
        self.camera=camera;self.width=width;self.height=height;self.selection=selection;self.settingsOpen=settingsOpen;self.midiStepMode=midiStepMode
    }
    public func restored(width: Double, height: Double) -> HierarchyCamera? {
        guard camera.zoom.isFinite, (1e-6...1e12).contains(camera.zoom), camera.pan.x.isFinite, camera.pan.y.isFinite,
              self.width.isFinite,self.height.isFinite,self.width>0,self.height>0 else { return nil }
        return HierarchyCamera(pan:Point(camera.pan.x+(width-self.width)/2,camera.pan.y+(height-self.height)/2),zoom:camera.zoom)
    }
}
