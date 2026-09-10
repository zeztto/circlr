import AppKit
import SwiftUI
import CirclrCore
import Combine

struct AlbumCanvas: NSViewRepresentable {
    @ObservedObject var store: AppStore
    func makeNSView(context: Context) -> AlbumCanvasView { AlbumCanvasView(store: store) }
    func updateNSView(_ view: AlbumCanvasView, context: Context) { view.update() }
}

@MainActor final class AlbumCanvasView: NSView {
    let store: AppStore
    var camera = HierarchyCamera()
    var scene: HierarchyScene?
    var renderedRevision = -1
    var renderedProjectID:ID?
    var renderedOrbits:Bool?
    var commandID: UUID?
    var initialized = false
    var previousSize = NSSize.zero
    var animation: Timer?
    var animationDestination: HierarchyCamera?
    var scrollMonitor: Any?
    private var paletteKeyMonitor:Any?
    private var paletteFocusObserver:NSObjectProtocol?
    private var pendingPaletteKeys:[(UUID,NSEvent)]=[]
    var editor: NSHostingView<InlineCircleEditor>?
    var editorAddress: CircleAddress?
    var labelPlacements:[CanvasLabelPlacement]=[]
    var fileDropPreview:CanvasFileDropPreview?
    var hoverAddress:CircleAddress?
    var colorTarget: (projectID: ID, address: CircleAddress)?
    var colorSubscription: AnyCancellable?
    var down = NSPoint.zero
    var dragNode: CircleSceneNode?
    var dragOrigin = Point()
    var dragPositions: [CircleAddress: Point] = [:]
    var dragPreview: Point?
    var panOrigin = Point()
    var panning = false
    var connecting: CirclePortHandle?
    var connectionRevision = 0
    var connectionLayoutRevision = 0
    var connectionProjectID: ID?
    var connectionToken: UUID?
    var connectionPoint = NSPoint.zero
    var selectedCable: CircleConnectionID?
    var selectedCableProjectID: ID?
    var selectedCanvasPort: CirclePortEndpoint?
    var selectedCableEnd = CirclePortDirection.output
    var portTools: NSHostingView<PortToolsView>?
    var circleAccessibility: [CircleAddress: CircleAccessibility] = [:]
    var portAccessibility: [CirclePortEndpoint: PortAccessibility] = [:]
    var cableAccessibility: [CircleConnectionID: CableAccessibility] = [:]
    var cableMode = CircleCableGesture.Mode.reconnect
    var cableDrag: CircleCableGesture?
    var cableDragOriginal = false
    var cableTools: NSHostingView<CableToolsView>?
    var tracking: NSTrackingArea?
    var meterSubscription:AnyCancellable?
    var albumPlan:AlbumExecutionPlan?
    var orbitDrag:CircleSceneNode?
    var orbitPhase=0.0,orbitTravel=0.0,orbitSeconds=0.0
    var orbitRevision=0
    var playbackAnimation: Timer?
    var playbackNotifications: [AnyCancellable] = []
    var interactionMonitor: Any?
    var visualFrame = PlaybackVisualFrame()
    var followedSection: CircleAddress?
    var playbackFollowViewport = CGRect.zero
    var playbackVisibilityFocus: CircleAddress?
    var visualSelection: CircleAddress?
    var lastFollowMode: PlaybackFollowMode = .off
    var lastVisualFrameTime = 0.0
    var frameCount = 0
    var maximumFrameGap = 0.0
    var accessibilityUpdateTime = 0.0
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(store: AppStore) {
        self.store = store; super.init(frame: .zero)
        store.captureHierarchyViewport = { [weak self] in
            guard let self,self.initialized,self.bounds.width>0 else{return nil}
            // A save may arrive before SwiftUI consumes the latest focus command.
            self.update()
            let savedCamera = self.animation?.isValid == true ? (self.animationDestination ?? self.camera) : self.camera
            return HierarchyViewport(camera:savedCamera,width:self.bounds.width,height:self.bounds.height,selection:self.store.hierarchySelection ?? .album,settingsOpen:self.store.hierarchySettingsOpen,midiStepMode:self.store.midiStepMode,workspace:self.store.capturedStudioWorkspace)
        }
        store.captureMovieFrame = { [weak self] in
            guard let self,self.bounds.width>=64,self.bounds.height>=64 else{return nil}
            self.updatePlaybackFrame();self.placeEditor()
            guard let bitmap=self.bitmapImageRepForCachingDisplay(in:self.bounds) else{return nil}
            self.cacheDisplay(in:self.bounds,to:bitmap)
            return bitmap.cgImage
        }
        store.canvasCommands = { [weak self] in self?.availableCommands() ?? [] }
        store.focusCanvas = { [weak self] in guard let self else{return};self.store.editorFocusRequest=nil;self.window?.makeFirstResponder(self) }
        installCircleColorObserver()
        registerForDraggedTypes([.fileURL])
        wantsLayer = true; clipsToBounds = true; layer?.masksToBounds = true; layer?.backgroundColor = StudioTheme.canvasNS.cgColor
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("앨범 서클 캔버스")
        store.capturePlaybackVisualization = { [weak self] in self?.playbackDiagnostics() ?? [:] }
        meterSubscription=store.meter.$playing.sink { [weak self] playing in
            DispatchQueue.main.async { [weak self] in self?.refreshPlaybackAnimation(playing: playing) }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor); self.scrollMonitor = nil }
        if let paletteKeyMonitor {NSEvent.removeMonitor(paletteKeyMonitor);self.paletteKeyMonitor=nil}
        if let paletteFocusObserver {NotificationCenter.default.removeObserver(paletteFocusObserver);self.paletteFocusObserver=nil}
        pendingPaletteKeys=[]
        if let interactionMonitor { NSEvent.removeMonitor(interactionMonitor); self.interactionMonitor = nil }
        playbackNotifications.removeAll()
        if window != nil {
            installPlaybackObservers()
            paletteKeyMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
                guard let self,event.window===self.window,let owner=self.store.commandPalette?.id else{return event}
                guard NSApp.isActive,self.window?.isKeyWindow==true else{self.pendingPaletteKeys=[];return nil}
                if let field=self.paletteSearch(owner) {
                    guard self.focusPaletteSearch(field) else{
                        self.pendingPaletteKeys=[];self.store.status="검색 입력을 시작하지 못했습니다. 검색창을 다시 여세요";return nil
                    }
                    let queued=self.pendingPaletteKeys.filter{$0.0==owner && ProcessInfo.processInfo.systemUptime-$0.1.timestamp<=2}.map{$0.1};self.pendingPaletteKeys=[]
                    for pending in queued {
                        guard self.store.commandPalette?.id==owner,NSApp.isActive,self.window?.isKeyWindow==true else{return nil}
                        NSApp.sendEvent(pending)
                    }
                    return self.store.commandPalette?.id==owner ? event:nil
                }
                self.pendingPaletteKeys.removeAll{$0.0 != owner || ProcessInfo.processInfo.systemUptime-$0.1.timestamp>2}
                guard self.pendingPaletteKeys.count<256 else{
                    self.pendingPaletteKeys=[];self.store.status="검색 입력 대기가 길어졌습니다. 검색창을 다시 여세요";return nil
                }
                self.pendingPaletteKeys.append((owner,event))
                return nil
            }
            paletteFocusObserver=NotificationCenter.default.addObserver(forName:CommandSearchField.SearchControl.attached,object:nil,queue:.main){[weak self] notification in
                guard let field=notification.object as? CommandSearchField.SearchControl,let owner=field.focusOwner else{return}
                DispatchQueue.main.async{[weak self,weak field] in
                    guard let self else{return}
                    guard let field,field.active,field.window===self.window,self.store.commandPalette?.id==owner,
                          NSApp.isActive,self.window?.isKeyWindow==true else{
                        self.pendingPaletteKeys.removeAll{$0.0==owner};return
                    }
                    let events=self.pendingPaletteKeys.filter{$0.0==owner && ProcessInfo.processInfo.systemUptime-$0.1.timestamp<=2}.map{$0.1}
                    self.pendingPaletteKeys=[]
                    for event in events {
                        guard self.store.commandPalette?.id==owner,field.active,field.window===self.window,
                              NSApp.isActive,self.window?.isKeyWindow==true else{break}
                        guard self.focusPaletteSearch(field) else{
                            self.store.status="검색 입력을 시작하지 못했습니다. 검색창을 다시 여세요";break
                        }
                        NSApp.sendEvent(event)
                    }
                }
            }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                if self.store.outputPreferencesOpen{return event}
                if self.store.consoleBounds.contains(self.convert(event.locationInWindow,from:nil)){return event}
                if let content=self.window?.contentView,let hit=content.hitTest(content.convert(event.locationInWindow,from:nil)) {
                    if hit !== self,!hit.isDescendant(of:self){return event}
                    var candidate:NSView?=hit
                    while let view=candidate,view !== self {
                        if view is OrbitAudioView || view is NSScrollView {return event}
                        candidate=view.superview
                    }
                }
                // Waveforms own source-time navigation and scroll views own their content.
                // On the remaining editor surface, Shift still keeps editor scroll available.
                if event.modifierFlags.contains(.shift), let editor = self.editor, editor.frame.contains(self.convert(event.locationInWindow, from: nil)) { return event }
                self.scrollWheel(with: event); return nil
            }
        } else { colorTarget = nil; animation?.invalidate(); animation = nil; playbackAnimation?.invalidate(); playbackAnimation = nil }
    }
    override func layout() {
        super.layout()
        if !initialized, bounds.width > 100, let root = scene?.node(.album) { camera = camera.focused(on: root, width: bounds.width, height: bounds.height); initialized = true }
        if previousSize.width > 0, previousSize != bounds.size {
            camera.pan.x += (bounds.width-previousSize.width)/2
            camera.pan.y += (bounds.height-previousSize.height)/2
            followedSection = nil
        }
        previousSize = bounds.size
        placeEditor(); needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {removeTrackingArea(tracking)}
        let area=NSTrackingArea(rect:.zero,options:[.mouseMoved,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);tracking=area
    }
    override func mouseMoved(with event:NSEvent) {
        let point=convert(event.locationInWindow,from:nil)
        let port=CirclePortGeometry.hit(Point(point.x,point.y),visibleHandles:visiblePortHandles())
        let node=port.flatMap{scene?.node($0.endpoint.node)} ?? hit(point)
        if hoverAddress != node?.id {hoverAddress=node?.id;needsDisplay=true}
        if let port,let descriptor=node?.ports.first(where:{$0.id==port.endpoint.portID}) {
            toolTip=(node?.title ?? "")+" · "+descriptor.name+" · 클릭으로 8방향 선택 · 끌어서 연결"
        } else {toolTip=node.map{$0.title+" · "+$0.subtitle+" · 두 번 클릭해 확대"}}
    }
    func update() {
        if visualSelection != store.hierarchySelection {
            visualSelection = store.hierarchySelection; playbackVisibilityFocus = nil
        }
        if renderedRevision != store.hierarchyRevision {
            let anchor=editorAddress ?? store.hierarchySelection ?? .album
            let previous=renderedProjectID==store.project.id && renderedOrbits != nil && renderedOrbits != store.project.usesOrbits ? scene?.node(anchor):nil
            scene = store.hierarchyScene; renderedRevision = store.hierarchyRevision
            renderedProjectID=store.project.id;renderedOrbits=store.project.usesOrbits
            followedSection = nil
            if let focus = playbackVisibilityFocus, scene?.node(focus) == nil { playbackVisibilityFocus = nil }
            albumPlan=try? AlbumCompiler.compile(store.project)
            if let selected = store.hierarchySelection, scene?.node(selected) == nil { removePrecisionEditor() }
            if let previous,let next=scene?.node(anchor) {
                connecting=nil;orbitDrag=nil;cableDrag=nil;dragNode=nil;dragPreview=nil;panning=false
                setCamera(camera.preserving(previous,in:next))
            }
        }
        if let command = store.hierarchyCommand, command.id != commandID {
            commandID = command.id
            switch command.action {
            case .focus(let address, let detail): focus(address, detail: detail)
            case .parent:
                let parent = store.selectedCircle?.parent ?? editorAddress.flatMap { scene?.node($0)?.parent } ?? .album
                store.rememberCircleWorkspace();store.selectHierarchy(parent); focus(parent)
            case .fit: store.rememberCircleWorkspace();store.selectHierarchy(.album); focus(.album)
            case .restore:
                removePrecisionEditor()
                connecting=nil;orbitDrag=nil;clearCableSelection()
                circleAccessibility=[:];portAccessibility=[:];cableAccessibility=[:]
                if let saved=store.project.hierarchyView,let restored=saved.restored(width:bounds.width,height:bounds.height) {
                    let selection=StudioWorkspace.restoredSelection(saved.selection,in:store.project)
                    store.selectHierarchy(selection);scene=store.hierarchyScene;store.midiStepMode=saved.midiStepMode ?? false
                    if selection==saved.selection {
                        store.restoreStudioWorkspace(saved.workspace ?? .init(page:saved.settingsOpen ? .settings:.content));setCamera(restored)
                    } else {
                        store.restoreStudioWorkspace(.init());focus(selection)
                    }
                } else {store.selectHierarchy(.album);store.hierarchySettingsOpen=false;focus(.album)}
            case .zoom(let factor): setCamera(camera.zoomed(to: camera.zoom*factor, around: Point(bounds.midX, bounds.midY)), animated: true)
            }
        }
        if lastFollowMode != store.playbackFollow {
            lastFollowMode = store.playbackFollow; followedSection = nil
            if store.playbackFollow != .following { animation?.invalidate(); animation = nil }
            if store.playback.playing { updatePlaybackFrame() }
        }
        placeEditor(); needsDisplay = true
    }
    func focus(_ address: CircleAddress, detail: Bool = false) {
        guard let scene=store.hierarchyScene,let node = scene.node(address), bounds.width > 100 else { return }
        if !detail,node.role == .section,
           let target=PlaybackFraming.camera(for:node,in:scene,viewport:workspaceViewport) {
            setCamera(target,animated:true);return
        }
        var target=camera.focused(on:node,width:workspaceViewport.width,height:workspaceViewport.height,detail:detail)
        if detail {
            let r=max(360,min(620,workspaceViewport.width*0.52))
            target.zoom=r/max(node.radius,1e-12)
        }
        target.pan=Point(workspaceViewport.midX-node.center.x*target.zoom,workspaceViewport.midY-node.center.y*target.zoom)
        setCamera(target,animated:true)
    }
    func setCamera(_ target: HierarchyCamera, animated: Bool = false, manual: Bool = true) {
        if manual { interruptPlaybackFollow() }
        animation?.invalidate(); animation = nil
        animationDestination = nil
        if animated {
            animationDestination = target
            let start = camera, time = ProcessInfo.processInfo.systemUptime
            animation = Timer(timeInterval: 1/60, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self else { timer.invalidate(); return }
                    let progress = min(1, (ProcessInfo.processInfo.systemUptime-time)/(manual ? 0.28 : 0.65))
                    self.camera = start.interpolated(to: target, progress: progress)
                    self.placeEditor(); self.needsDisplay = true
                    if progress >= 1 {
                        timer.invalidate(); self.animation = nil; self.store.hierarchyZoom = self.camera.zoom
                        self.finishConnectionEditorFocus()
                    }
                }
            }
            if let animation { RunLoop.main.add(animation, forMode: .common) }
        } else { camera = target; placeEditor(); needsDisplay = true; store.hierarchyZoom = camera.zoom; finishConnectionEditorFocus() }
    }
    func placeEditor() {
        defer { refreshCableTools() }
        if store.movieWriter != nil {removePrecisionEditor();return}
        if store.playback.playing, store.playbackFollow == .following {
            removePrecisionEditor(); return
        }
        guard let address = store.hierarchySelection, let node = scene?.node(address), (node.role == .music || store.hierarchySettingsOpen || store.midiImportDraft != nil || store.connectionsOpen),
              node.radius*camera.zoom >= 325, isVisible(node) else {
            removePrecisionEditor(); return
        }
        let center = camera.screen(node.center), radius = node.radius*camera.zoom
        let frame=CanvasWorkspaceGeometry.editor(center:CGPoint(x:center.x,y:center.y),radius:radius,within:workspaceViewport)
        guard frame.intersects(bounds) else { removePrecisionEditor(); return }
        if editorAddress != address || editor == nil {
            removePrecisionEditor()
            let host = NSHostingView(rootView: InlineCircleEditor(store: store))
            host.sizingOptions = []; host.wantsLayer = true; host.layer?.backgroundColor = NSColor.clear.cgColor
            addSubview(host); editor = host; editorAddress = address
        }
        editor?.frame = frame
        if let editor {store.consumeEditorNavigationFocus(in:editor)}
    }
    func removePrecisionEditor() {
        guard let current=editor else {editorAddress=nil;return}
        if let responder=window?.firstResponder as? NSView {
            let fieldOwner=(responder as? NSTextView)?.delegate as? NSView
            if responder === current || responder.isDescendant(of:current) || fieldOwner?.isDescendant(of:current) == true {
                window?.makeFirstResponder(self)
            }
        }
        current.removeFromSuperview();editor=nil;editorAddress=nil
    }
    func finishConnectionEditorFocus() {
        guard store.connectionsOpen, let editor else { return }
        func visit(_ view: NSView) {
            if let search = view as? PortSearchControl { search.navigation?.scheduleFocusRequest() }
            for child in view.subviews { visit(child) }
        }
        visit(editor)
    }
    func screen(_ node: CircleSceneNode) -> NSPoint {
        var point = node.center
        if let dragged = dragNode, let preview = dragPreview, let scene,
           scene.path(to: node.id).contains(where: { dragPositions[$0.id] != nil }) {
            point.x += (preview.x-dragOrigin.x)*dragged.scale; point.y += (preview.y-dragOrigin.y)*dragged.scale
        }
        let p = camera.screen(point); return NSPoint(x: p.x, y: p.y)
    }
    func color(_ node: CircleSceneNode) -> NSColor {
        let value = store.project.circleColors?[node.id] ?? node.baseColor
        let tint = value.nsColor
        // Desaturation survives callers replacing alpha for ticks and orbit rings.
        return node.music?.muted == true
            ? (tint.blended(withFraction: 0.6, of: StudioTheme.secondaryNS) ?? tint)
            : tint
    }
    func isVisible(_ node: CircleSceneNode) -> Bool {
        let context=labelContext
        let direct=node.parent==context?.id
        guard node.radius*camera.zoom > (direct ? 0.000001:(store.project.usesOrbits ? 1.2:20)) else { return false }
        // At editing depth, unrelated overlapping freeform branches must not cover the active circle.
        if let scene,let selected=context,
           !scene.path(to:node.id).contains(where:{$0.id==selected.id}),!scene.path(to:selected.id).contains(where:{$0.id==node.id}) { return false }
        guard let parent = node.parent.flatMap({ scene?.node($0) }) else { return true }
        return direct || parent.radius*camera.zoom >= 140
    }
    override func draw(_ dirtyRect: NSRect) {
        StudioTheme.canvasNS.setFill(); bounds.fill()
        guard let scene else { return }
        if store.project.album?.layout.grid != false { drawGrid() }
        for node in scene.nodes {
            let radius = node.radius*camera.zoom, center = screen(node)
            guard isVisible(node) else { continue }
            let rect = NSRect(x: center.x-radius, y: center.y-radius, width: 2*radius, height: 2*radius)
            guard rect.intersects(bounds), radius < 1e7 else { continue }
            let displayRect=radius<3 && node.parent==labelContext?.id ? NSRect(x:center.x-3,y:center.y-3,width:6,height:6):rect
            let path = NSBezierPath(ovalIn: displayRect)
            NSColor(white: node.role == .music ? 0.105 : 0.065+Double(min(4,node.depth))*0.008, alpha: 1).setFill(); path.fill()
            let selected = store.hierarchySelections.contains(node.id)
            let muted = node.music?.muted == true
            // A wider neutral under-stroke remains visible beside any custom color,
            // including black, without replacing it. Screen-space widths also retain
            // the selection outline on circles too small for a separate inner ring.
            StudioTheme.textNS.withAlphaComponent(selected ? 0.75 : (muted ? 0.22 : 0.35)).setStroke()
            path.lineWidth = selected ? 4.4 : 2.2; path.stroke()
            color(node).withAlphaComponent(selected ? 1 : (muted ? 0.3 : 0.55)).setStroke()
            path.lineWidth = selected ? 2.4 : 1; path.stroke()
            drawTicks(node, center: center, radius: radius)
            if node.repeatCount > 1, radius > 30 {
                let rings=SectionRings(repeats:node.repeatCount,baseRadius:node.radius/node.scale)
                color(node).withAlphaComponent(0.4).setStroke()
                for r in rings.radii.dropFirst() {
                    let delta=(r-rings.baseRadius)*node.scale*camera.zoom
                    let ring=NSBezierPath(ovalIn:rect.insetBy(dx:-delta,dy:-delta));ring.lineWidth=max(0.25,min(1.4,rings.lineWidth*node.scale*camera.zoom));ring.stroke()
                }
            }
        }
        if store.project.usesOrbits {for node in scene.nodes {drawOrbit(node)}}
        for edge in scene.edges { drawEdge(edge, scene: scene) }
        for node in scene.nodes {
            let radius = node.radius*camera.zoom, center = screen(node)
            guard isVisible(node), NSRect(x: center.x-radius, y: center.y-radius, width: 2*radius, height: 2*radius).intersects(bounds) else { continue }
            if radius<22 {continue}
            let isEditor = editorAddress == node.id
            if node.role == .music, !isEditor, radius > 65 { drawMusic(node, center: center, radius: radius) }
        }
        for node in scene.nodes where isVisible(node) { drawPlaybackCircle(node) }
        drawReadableLabels()
        drawPortHandles()
        drawCableEditing()
        drawPortLabels()
        drawPlaybackCaption()
        drawFileDropPreview()
        if let handle = connecting, let node = scene.node(handle.endpoint.node) {
            let target=CirclePortGeometry.hit(Point(connectionPoint.x,connectionPoint.y),visibleHandles:visiblePortHandles()) ??
                CirclePortHandle(endpoint:handle.endpoint,octant:PortOctant(rawValue:(handle.octant.rawValue+4)%8)!,point:Point(connectionPoint.x,connectionPoint.y))
            if let curve=try? CirclePortGeometry.curve(from:handle,to:target) {wire(curve,color:color(node),dashed:true)}
        }
        updateAccessibility()
    }
    func drawGrid() {
        let spacing = 32.0
        StudioTheme.lineNS.withAlphaComponent(0.45).setFill()
        let ox = camera.pan.x.truncatingRemainder(dividingBy: spacing), oy = camera.pan.y.truncatingRemainder(dividingBy: spacing)
        for x in stride(from: ox, through: bounds.width, by: spacing) { for y in stride(from: oy, through: bounds.height, by: spacing) { NSRect(x:x,y:y,width:1,height:1).fill() } }
    }
    func drawTicks(_ node: CircleSceneNode, center: NSPoint, radius: Double) {
        guard let timeline=node.timeline, timeline.duration>0, radius>30 else{return}
        color(node).withAlphaComponent(0.6).setStroke()
        let path = NSBezierPath(); path.lineWidth = 1
        for i in stride(from:0,to:timeline.ticks.count,by:max(1,timeline.ticks.count/256)) {
            let angle=timeline.angle(at:timeline.ticks[i].seconds)
            path.move(to: NSPoint(x:center.x+cos(angle)*(radius-7),y:center.y+sin(angle)*(radius-7)))
            path.line(to: NSPoint(x:center.x+cos(angle)*radius,y:center.y+sin(angle)*radius))
        }; path.stroke()
    }
    func timeHandle(_ node:CircleSceneNode)->NSPoint? {
        guard store.project.usesOrbits,let orbit=node.orbit,let owner=scene?.node(orbit.owner),node.radius*camera.zoom>1.2 else{return nil}
        let center=screen(owner),seconds=orbitDrag?.id==node.id ? orbitSeconds:orbit.anchor
        return OrbitDrawing.point(center,radius:(orbit.radius+node.outerRadius*1.22)*camera.zoom,phase:seconds/orbit.timeline.duration)
    }
    func drawOrbit(_ node:CircleSceneNode) {
        guard editorAddress == nil else{return}
        guard let orbit=node.orbit,let owner=scene?.node(orbit.owner),isVisible(node),owner.radius*camera.zoom>100 else{return}
        guard owner.radius*camera.zoom<max(bounds.width,bounds.height)*4 else{return}
        let center=screen(owner),radius=orbit.radius*camera.zoom
        guard radius<1e7 else{return}
        let ring=OrbitDrawing.arc(center,radius:radius,from:0,to:1)
        color(node).withAlphaComponent(0.13).setStroke();ring.lineWidth=0.7;ring.stroke()
        for interval in orbit.intervals {
            let arc=OrbitDrawing.arc(center,radius:radius,from:interval.start/orbit.timeline.duration,to:interval.end/orbit.timeline.duration)
            color(node).withAlphaComponent(store.hierarchySelection==node.id ? 0.7:0.3).setStroke();arc.lineWidth=2;arc.stroke()
            OrbitDrawing.dot(OrbitDrawing.point(center,radius:radius,phase:interval.start/orbit.timeline.duration),radius:2,color:color(node))
        }
        if store.hierarchySelection==node.id,let handle=visibleTimeHandle(node) {
            OrbitDrawing.dot(handle,radius:6,color:StudioTheme.textNS)
            OrbitDrawing.text(node.role == .music ? "시작 시간":"순서 이동",at:NSPoint(x:handle.x,y:handle.y-16),size:10)
        }
    }
    func drawPlayhead(_ node:CircleSceneNode) {
        guard let phase = visualFrame.phases[node.id], node.radius*camera.zoom > 30 else { return }
        let point=OrbitDrawing.point(screen(node),radius:node.radius*camera.zoom,phase:phase)
        OrbitDrawing.dot(point,radius:4,color:StudioTheme.textNS)
    }
    func drawEdge(_ edge: CircleSceneEdge, scene: HierarchyScene) {
        guard let a=scene.node(edge.from), let b=scene.node(edge.to), isVisible(a), isVisible(b) else { return }
        guard let curve = connectionCurve(edge) else { return }
        let tint: NSColor = edge.kind == .midi ? StudioTheme.accentNS : edge.kind == .flow ? StudioTheme.secondaryNS : NSColor(srgbRed:0.62,green:0.75,blue:0.94,alpha:1)
        wire(curve,color:tint.withAlphaComponent(0.55),dashed:edge.kind == .sidechain)
        if let before = try? curve.point(at: 0.48), let tip = try? curve.point(at: 0.52) {
            let angle = atan2(tip.y-before.y, tip.x-before.x), path = NSBezierPath()
            for offset in [-0.5, 0.5] { path.move(to: NSPoint(x: tip.x-7*cos(angle+offset), y: tip.y-7*sin(angle+offset))); path.line(to: NSPoint(x:tip.x,y:tip.y)) }
            tint.setStroke(); path.lineWidth=1.5; path.stroke()
        }
        drawPlaybackEdge(edge, curve: curve, tint: tint)
    }
    func wire(_ from:NSPoint,_ to:NSPoint,color:NSColor,dashed:Bool=false) {
        let width=max(30,abs(to.x-from.x)*0.45),path=NSBezierPath()
        path.move(to:from);path.curve(to:to,controlPoint1:NSPoint(x:from.x+width,y:from.y),controlPoint2:NSPoint(x:to.x-width,y:to.y))
        color.setStroke();path.lineWidth=1.5;if dashed {path.setLineDash([4,4],count:2,phase:0)};path.stroke()
    }
    func port(at point:NSPoint,color:NSColor,filled:Bool) {
        let circle=NSBezierPath(ovalIn:NSRect(x:point.x-5,y:point.y-5,width:10,height:10));StudioTheme.canvasNS.setFill();circle.fill();color.setStroke();circle.lineWidth=1.5;circle.stroke()
        if filled {color.setFill();NSBezierPath(ovalIn:NSRect(x:point.x-2,y:point.y-2,width:4,height:4)).fill()}
    }
    func drawText(_ text:String,x:Double,y:Double,size:Double,color:NSColor,maxWidth:Double) {
        let style=NSMutableParagraphStyle();style.alignment = .center;style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in:NSRect(x:x-maxWidth/2,y:y,width:maxWidth,height:size*1.6),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:color,.paragraphStyle:style])
    }
    func drawMusic(_ node: CircleSceneNode,center:NSPoint,radius:Double) {
        guard let music=node.music,case .music(let ai,let ui,_) = node.id,
              let arrangement=store.project.arrangements.first(where:{$0.id==ai}),let use=arrangement.uses.first(where:{$0.id==ui}),
              let section=store.project.sections.first(where:{$0.id==use.sectionID}),let lanes=try? ArrangementCompiler.effectiveLanes(section:section,use:use) else{return}
        let rect=NSRect(x:center.x-radius*0.52,y:center.y+28,width:radius*1.04,height:radius*0.26)
        if store.project.usesOrbits,let clock=node.clock {
            switch music.content {
            case .midi(let laneID):
                let notes=lanes.first{$0.id==laneID}?.notes ?? []
                for note in notes.prefix(4000) where note.beat<clock.beats {
                    let r=radius*(0.5+Double(max(0,min(60,note.pitch-36)))/200)
                    let arc=OrbitDrawing.arc(center,radius:r,from:clock.seconds(at:note.beat)/clock.seconds,to:clock.seconds(at:min(clock.beats,note.beat+note.length))/clock.seconds)
                    color(node).withAlphaComponent(0.65).setStroke();arc.lineWidth=2;arc.stroke()
                }
                if notes.isEmpty {drawText("확대해서 노트 입력",x:center.x,y:center.y+25,size:10,color:StudioTheme.secondaryNS,maxWidth:radius*1.4)}
            case .audio(let laneID,let clipID):
                if let clip=lanes.first(where:{$0.id==laneID})?.audio.first(where:{$0.id==clipID}),let asset=store.project.assets.first(where:{$0.id==clip.assetID}) {
                    if let waveform=store.waveforms[asset.id] {
                        let rate=clip.followsTempo ? clock.bpm(at:clip.beat)/clip.sourceBPM:1,start=clock.seconds(at:clip.beat)
                        let duration=min(clip.duration/max(1e-9,rate),max(0,clock.seconds-start))
                        let path=NSBezierPath();path.lineWidth=1;color(node).setStroke()
                        for i in 0..<360 {
                            let t=Double(i)/360*duration,phase=(start+t)/clock.seconds,peak=Double(waveform.peak(at:clip.sourceStart+t*rate))*radius*0.16
                            path.move(to:OrbitDrawing.point(center,radius:radius*0.7-peak,phase:phase));path.line(to:OrbitDrawing.point(center,radius:radius*0.7+peak,phase:phase))
                        };path.stroke()
                    } else {DispatchQueue.main.async{[weak store] in store?.requestWaveform(asset)}}
                }
            default:break
            }
            return
        }
        switch music.content {
        case .midi(let laneID):
            let notes=lanes.first{$0.id==laneID}?.notes ?? [];let beats=max(1,music.lengthBeats ?? node.parent.flatMap{scene?.node($0)?.clock?.beats} ?? 32)
            color(node).withAlphaComponent(0.75).setFill()
            for note in notes.prefix(1000) {NSBezierPath(roundedRect:NSRect(x:rect.minX+note.beat/beats*rect.width,y:rect.minY+Double(84-note.pitch)/60*rect.height,width:max(2,note.length/beats*rect.width),height:2),xRadius:1,yRadius:1).fill()}
            if notes.isEmpty {drawText("확대해서 노트 입력",x:center.x,y:rect.minY,size:9,color:StudioTheme.secondaryNS,maxWidth:rect.width)}
        case .audio(let laneID,let clipID):
            guard let clip=lanes.first(where:{$0.id==laneID})?.audio.first(where:{$0.id==clipID}),let asset=store.project.assets.first(where:{$0.id==clip.assetID}) else{return}
            if let waveform=store.waveforms[asset.id] {
                color(node).setStroke();let path=NSBezierPath();path.lineWidth=1
                for x in stride(from:0.0,through:rect.width,by:2) {let peak=Double(waveform.peak(at:clip.sourceStart+x/rect.width*clip.duration));path.move(to:NSPoint(x:rect.minX+x,y:rect.midY-peak*rect.height/2));path.line(to:NSPoint(x:rect.minX+x,y:rect.midY+peak*rect.height/2))};path.stroke()
            } else {DispatchQueue.main.async{[weak store] in store?.requestWaveform(asset)}}
        default: break
        }
    }
    func hit(_ point:NSPoint) -> CircleSceneNode? {
        guard let scene else{return nil}
        if let label=labelPlacements.reversed().first(where:{$0.rect.contains(point)}),let node=scene.node(label.id) {return node}
        // Rings remain selectable even when a child is under their centre.
        return scene.nodes.reversed().first { node in
            let p=screen(node),r=node.outerRadius*camera.zoom
            guard isVisible(node) else{return false}
            return hypot(point.x-p.x,point.y-p.y)<=r+7
        }
    }
    override func mouseDown(with event:NSEvent) {
        var identity=store.numberEditIdentity
        guard store.resolveActiveNumericDraft(),store.nameEditing.resolve() else{return}
        identity.revision=store.project.musicRevision
        guard identity==store.numberEditIdentity else{return}
        store.editorFocusRequest=nil
        interruptPlaybackFollow()
        window?.makeFirstResponder(self); animation?.invalidate(); animation=nil
        down=convert(event.locationInWindow,from:nil);panOrigin=camera.pan;dragNode=nil;dragPreview=nil
        orbitDrag=nil
        panning=store.panMode || event.buttonNumber==2
        if panning{return}
        let labelHit=labelPlacements.contains{$0.rect.contains(down)}
        if !labelHit,let node=store.hierarchySelection.flatMap({scene?.node($0)}),let handle=visibleTimeHandle(node),hypot(handle.x-down.x,handle.y-down.y)<13,let orbit=node.orbit,let owner=scene?.node(orbit.owner) {
            orbitDrag=node;orbitSeconds=orbit.anchor;orbitTravel=0;orbitRevision=store.project.musicRevision
            let center=screen(owner);orbitPhase=OrbitTimeline.phase(Point(down.x-center.x,down.y-center.y));return
        }
        if beginCableDrag(at:down) {return}
        if let handle=CirclePortGeometry.hit(Point(down.x,down.y),visibleHandles:visiblePortHandles()) {
            connecting=handle;connectionToken=UUID();connectionPoint=down;connectionRevision=store.project.musicRevision;connectionLayoutRevision=store.project.portLayout?.revision ?? 0;connectionProjectID=store.project.id;portTools?.isHidden=true;needsDisplay=true;return
        }
        if !labelHit,let cable=hitCable(down) {selectCable(cable);return}
        clearCableSelection()
        guard let node=hit(down) else{panning=true;return}
        if !event.modifierFlags.contains(.shift), store.hierarchySelections.contains(node.id), store.hierarchySelections.count > 1 { store.hierarchySelection=node.id }
        else if event.modifierFlags.contains(.shift) { store.selectHierarchy(node.id,additive:true) }
        else { guard store.selectUserWorkspace(node.id) else{return} }
        if event.clickCount==2 {
            if node.role == .group, store.selectedHierarchyGroup?.collapsed == true { store.updateHierarchyGroup { $0.collapsed=false }; update() }
            focus(node.id,detail:node.role == .music);return
        }
        if node.role != .album, !store.project.usesOrbits || (node.orbit == nil && node.role != .group) {dragNode=node;dragOrigin=store.hierarchyLocalPosition(node);dragPositions=Dictionary(uniqueKeysWithValues:store.hierarchySelections.compactMap{address in scene?.node(address).map{(address,store.hierarchyLocalPosition($0))}})}
        needsDisplay=true
    }
    override func otherMouseDown(with event:NSEvent){mouseDown(with:event)}
    override func mouseDragged(with event:NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        if let node=orbitDrag,let orbit=node.orbit,let owner=scene?.node(orbit.owner) {
            let center=screen(owner),next=OrbitTimeline.phase(Point(p.x-center.x,p.y-center.y))
            orbitTravel+=OrbitTimeline.phaseDelta(from:orbitPhase,to:next);orbitPhase=next
            orbitSeconds=max(0,min(orbit.timeline.duration,orbit.anchor+orbitTravel*orbit.timeline.duration));needsDisplay=true;return
        }
        if connecting != nil {connectionPoint=p;needsDisplay=true;return}
        if cableDrag != nil {connectionPoint=p;needsDisplay=true;return}
        if panning {setCamera(HierarchyCamera(pan:Point(panOrigin.x+p.x-down.x,panOrigin.y+p.y-down.y),zoom:camera.zoom));return}
        if let node=dragNode,hypot(p.x-down.x,p.y-down.y)>3 {dragPreview=Point(dragOrigin.x+(p.x-down.x)/camera.zoom/node.scale,dragOrigin.y+(p.y-down.y)/camera.zoom/node.scale);needsDisplay=true}
    }
    override func otherMouseDragged(with event:NSEvent){mouseDragged(with:event)}
    override func mouseUp(with event:NSEvent) {
        if let node=orbitDrag,let orbit=node.orbit,orbitRevision==store.project.musicRevision,abs(orbitSeconds-orbit.anchor)>1e-7 {
            if node.role == .music {let seconds=orbitSeconds,original=store.editOriginal;store.mutate("궤도 시작 이동"){try OrbitEditing.setStart(node.id,seconds:seconds,original:original,in:&$0)}}
            else if node.role == .section {
                let target=scene?.nodes.filter{$0.orbit?.owner==orbit.owner && $0.id != node.id && ($0.orbit?.anchor ?? 0)>orbitSeconds}.min{($0.orbit?.anchor ?? 0)<($1.orbit?.anchor ?? 0)}
                let before=target.flatMap{HierarchyEditing.memberID($0.id)}
                store.mutate("섹션 순서 이동"){try OrbitEditing.reorderSection(node.id,before:before,in:&$0)}
            } else if case .composition(let id)=node.id {
                let siblings=store.project.album?.parent(of:id).flatMap{store.project.album?.composition($0)?.children} ?? store.project.album?.children ?? []
                let before=scene?.nodes.filter{$0.orbit?.owner==orbit.owner && $0.id != node.id && ($0.orbit?.anchor ?? 0)>orbitSeconds}.min{($0.orbit?.anchor ?? 0)<($1.orbit?.anchor ?? 0)}.flatMap{HierarchyEditing.memberID($0.id)}
                let order=siblings.filter{$0 != id},index=before.flatMap{order.firstIndex(of:$0)} ?? order.count,parent=store.project.album?.parent(of:id)
                store.mutate("곡·악장 순서 이동"){try AlbumEditing.move(id,to:parent,index:index,in:&$0)}
            }
        }
        orbitDrag=nil
        if cableDrag != nil {finishCableDrag(at:convert(event.locationInWindow,from:nil));cableDrag=nil;refreshCableTools()}
        if let from=connecting {
            let point=convert(event.locationInWindow,from:nil)
            if hypot(point.x-down.x,point.y-down.y) < 3, connectionProjectID == store.project.id, connectionRevision == store.project.musicRevision {
                connecting=nil; selectCanvasPort(from.endpoint)
            } else { finishPortConnection(from,at:point) }
        }
        if dragNode != nil,var p=dragPreview {
            if store.project.album?.layout.snap != false {let spacing=store.project.album?.layout.spacing ?? 32;p=Point((p.x/spacing).rounded()*spacing,(p.y/spacing).rounded()*spacing)}
            store.moveHierarchySelection(dragPositions,delta:Point(p.x-dragOrigin.x,p.y-dragOrigin.y))
        }
        dragNode=nil;dragPreview=nil;dragPositions=[:];panning=false;connecting=nil;connectionToken=nil;refreshPortTools();needsDisplay=true
    }
    override func otherMouseUp(with event:NSEvent){mouseUp(with:event)}
    override func scrollWheel(with event:NSEvent) {
        let p=convert(event.locationInWindow,from:nil)
        if store.consoleBounds.contains(p){super.scrollWheel(with:event);return}
        if event.modifierFlags.contains(.shift) {setCamera(HierarchyCamera(pan:Point(camera.pan.x-event.scrollingDeltaX,camera.pan.y-event.scrollingDeltaY),zoom:camera.zoom));return}
        let direction=event.isDirectionInvertedFromDevice ? -1.0:1.0
        let delta=event.scrollingDeltaY*direction
        let exponent=max(-0.35,min(0.35,delta*(event.hasPreciseScrollingDeltas ? 0.009:0.07)))
        setCamera(camera.zoomed(to:camera.zoom*exp(exponent),around:Point(p.x,p.y)))
        if let leaf=hit(p),leaf.role == .music,leaf.radius*camera.zoom>=325,store.hierarchySelection != leaf.id {if store.selectUserWorkspace(leaf.id){placeEditor()}}
    }
    override func magnify(with event:NSEvent){let p=convert(event.locationInWindow,from:nil);setCamera(camera.zoomed(to:camera.zoom*exp(event.magnification),around:Point(p.x,p.y)))}
    private func focusPaletteSearch(_ field:CommandSearchField.SearchControl)->Bool {
        guard let window,field.active,field.window===window,NSApp.isActive,window.isKeyWindow else{return false}
        if let editor=field.currentEditor(),window.firstResponder===editor{return true}
        if window.firstResponder===field{return true}
        guard window.makeFirstResponder(field) else{return false}
        if let editor=field.currentEditor(),window.firstResponder===editor{return true}
        return window.firstResponder===field
    }
    private func paletteSearch(_ owner:UUID)->CommandSearchField.SearchControl? {
        func find(_ view:NSView)->CommandSearchField.SearchControl? {
            if let field=view as? CommandSearchField.SearchControl,field.active,field.focusOwner==owner{return field}
            for child in view.subviews {if let field=find(child){return field}}
            return nil
        }
        return window?.contentView.flatMap{find($0)}
    }
    override func keyDown(with event:NSEvent) {
        if store.outputPreferencesOpen || store.libraryOpen || store.soundPickerRequest != nil || store.arrangementPickerRequest != nil || store.commandPalette != nil || store.navigationOpen || store.keyboardHelp {return}
        if event.keyCode==53,event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,let draft=store.midiImportDraft {
            store.cancelMIDIImport(draft.id);return
        }
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {super.keyDown(with:event);return}
        if handleConnectionKey(event) { return }
        if event.modifierFlags.contains([.option,.shift]),[123,124,125,126].contains(event.keyCode),!store.project.usesOrbits {
            let spacing=store.project.album?.layout.spacing ?? 24
            let x=event.keyCode==123 ? -spacing:event.keyCode==124 ? spacing:0
            let y=event.keyCode==126 ? -spacing:event.keyCode==125 ? spacing:0
            let positions=Dictionary(uniqueKeysWithValues:(scene?.nodes ?? []).filter{store.hierarchySelections.contains($0.id)}.map{($0.id,store.hierarchyLocalPosition($0))})
            store.moveHierarchySelection(positions,delta:Point(x,y));needsDisplay=true;return
        }
        if event.modifierFlags.contains(.option),[123,124,125,126].contains(event.keyCode) {
            let delta=event.modifierFlags.contains(.shift) ? 120.0:40.0
            let x=event.keyCode==123 ? delta:event.keyCode==124 ? -delta:0
            let y=event.keyCode==126 ? delta:event.keyCode==125 ? -delta:0
            setCamera(HierarchyCamera(pan:Point(camera.pan.x+x,camera.pan.y+y),zoom:camera.zoom));return
        }
        switch event.keyCode {
        case 53:
            if cableDrag != nil {cableDrag=nil;connectionToken=nil;refreshCableTools();needsDisplay=true;return}
            if connecting != nil { connecting=nil;connectionToken=nil;needsDisplay=true;return }
            if selectedCable != nil {clearCableSelection();return}
            if store.connectionsOpen {store.connectionsOpen=false;return}
            store.hierarchySettingsOpen=false;store.hierarchyParent()
        case 49: store.play()
        case 51,117:
            if selectedCable != nil {disconnectSelectedCable()} else {store.removeHierarchy()}
        case 3: store.hierarchyCommand=HierarchyCommand(action:.fit)
        case 4: store.panMode=true
        case 9: store.panMode=false
        case 36,76:
            if event.modifierFlags.intersection([.shift,.option]).isEmpty,store.audioScopeRecoveryAvailable {
                _ = store.recoverAudioEditScope(identity:store.numberEditIdentity)
                return
            }
            enterSelectedCircle()
        case 48: selectNeighbor(forward:!event.modifierFlags.contains(.shift))
        case 123,126: selectNeighbor(forward:false,additive:event.modifierFlags.contains(.shift))
        case 124,125: selectNeighbor(forward:true,additive:event.modifierFlags.contains(.shift))
        case 0: creationMenu(at:NSPoint(x:bounds.midX,y:bounds.midY),selected:store.hierarchySelection).popUp(positioning:nil,at:NSPoint(x:bounds.midX,y:bounds.midY),in:self)
        case 8: circleMenu(at:NSPoint(x:bounds.midX,y:bounds.midY),selected:store.selectedCircle).popUp(positioning:nil,at:NSPoint(x:bounds.midX,y:bounds.midY),in:self)
        case 15: store.openCircleSettings()
        case 37: store.showConnections()
        case 24,69: store.hierarchyCommand=HierarchyCommand(action:.zoom(1.25))
        case 27,78: store.hierarchyCommand=HierarchyCommand(action:.zoom(0.8))
        default: super.keyDown(with:event)
        }
    }
    func updateAccessibility() {
        let now = ProcessInfo.processInfo.systemUptime
        if playbackAnimation != nil, now-accessibilityUpdateTime < 0.2 { return }
        accessibilityUpdateTime = now
        guard let scene,window != nil else{return}
        let labeled=Set(labelPlacements.map(\.id))
        let visible=scene.nodes.filter{node in let p=screen(node);return isVisible(node) && (labeled.contains(node.id) || cablePointAvailable(Point(p.x,p.y),labels:false))}
        let children=visible.map { node -> NSAccessibilityElement in
            let p=screen(node),r=min(100,node.radius*camera.zoom)
            let hitRect=labelPlacements.first{$0.id==node.id}?.rect ?? NSRect(x:p.x-r,y:p.y-r,width:max(12,r*2),height:max(12,r*2))
            let element=circleAccessibility[node.id] ?? CircleAccessibility(parent:self,address:node.id)
            circleAccessibility[node.id]=element
            element.setAccessibilityLabel(node.title+" · "+node.subtitle);element.setFrameInView(hitRect,view:self)
            element.setAccessibilitySelected(store.hierarchySelections.contains(node.id))
            return element
        }
        let ids=Set(visible.map(\.id));circleAccessibility=circleAccessibility.filter{ids.contains($0.key)}
        var accessible: [Any] = children + connectionAccessibilityChildren()
        if let editor { accessible.append(editor) }
        if let cableTools, !cableTools.isHidden { accessible.append(cableTools) }
        if let portTools, !portTools.isHidden { accessible.append(portTools) }
        setAccessibilityChildren(accessible)
    }
}
@MainActor final class CircleAccessibility:NSAccessibilityElement {
    weak var canvas:AlbumCanvasView?
    let address:CircleAddress
    init(parent:AlbumCanvasView,address:CircleAddress){self.canvas=parent;self.address=address;super.init();setAccessibilityParent(parent);setAccessibilityRole(.button);setAccessibilityEnabled(true)}
    override func accessibilityPerformPress()->Bool {canvas?.store.focusUserWorkspace(address,detail:true) ?? false}
}

@MainActor final class CircleMenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run=run }
}
extension AlbumCanvasView {
    @objc func runCircleMenu(_ sender: NSMenuItem) { (sender.representedObject as? CircleMenuAction)?.run() }
    override func rightMouseDown(with event: NSEvent) {
        let point=convert(event.locationInWindow,from:nil)
        window?.makeFirstResponder(self)
        NSMenu.popUpContextMenu(circleMenu(at:point),with:event,for:self)
    }
    func circleMenu(at point:NSPoint, selected:CircleSceneNode? = nil)->NSMenu {
        let create=creationMenu(at:point,selected:selected?.id)
        guard let node=selected ?? hit(point) else{return create}
        let menu=NSMenu()
        let createItem=NSMenuItem(title:"서클 만들기",action:nil,keyEquivalent:"")
        createItem.submenu=create;menu.addItem(createItem);menu.addItem(.separator())
        func action(_ title:String,in target:NSMenu?=nil,_ block:@escaping()->Void) {
            let item=NSMenuItem(title:title,action:#selector(runCircleMenu(_:)),keyEquivalent:"")
            item.target=self;item.representedObject=CircleMenuAction(block);(target ?? menu).addItem(item)
        }
        func submenu(_ title:String)->NSMenu {let item=NSMenuItem(title:title,action:nil,keyEquivalent:"");let child=NSMenu();item.submenu=child;menu.addItem(item);return child}
        action("확대해서 편집"){[weak self] in _ = self?.store.focusUserWorkspace(node.id,detail:node.role == .music)}
        action(store.hierarchySelections.contains(node.id) ? "선택에서 제외":"선택에 추가"){[weak self] in self?.store.selectHierarchy(node.id,additive:true)}
        let colors = submenu("서클 색상")
        let colorProjectID = store.project.id
        let current = store.project.circleColors?[node.id]
        action("종류별 기본 색상", in: colors) { [weak self] in
            guard let self, self.store.project.id == colorProjectID else { return }
            self.colorTarget = nil
            self.setCircleColor(nil, for: node.id)
        }
        colors.items.last?.state = current == nil ? .on : .off
        for preset in CircleColor.Preset.allCases {
            action(preset.title, in: colors) { [weak self] in
                guard let self, self.store.project.id == colorProjectID else { return }
                self.colorTarget = nil
                self.setCircleColor(preset.color, for: node.id)
            }
            colors.items.last?.state = current == preset.color ? .on : .off
            colors.items.last?.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                preset.color.nsColor.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill(); return true
            }
        }
        colors.addItem(.separator())
        action("사용자 지정…", in: colors) { [weak self] in
            guard let self, self.store.project.id == colorProjectID else { return }
            self.chooseCircleColor(node)
        }
        action("이름·음악 설정"){[weak self] in self?.store.hierarchyTransitionID=nil;self?.store.focusHierarchy(node.id,detail:true);self?.store.hierarchySettingsOpen=true}
        switch node.id {
        case .music(let arrangement,let use,let id):
            if let a=store.project.arrangements.first(where:{$0.id==arrangement}),let u=a.uses.first(where:{$0.id==use}),let section=store.project.sections.first(where:{$0.id==u.sectionID}),let graph=try? SectionGraphEditing.effective(section:section,use:u),let source=graph.nodes.first(where:{$0.id==id}) {
                let targets=graph.nodes.filter{$0.id != id && $0.content.input != nil && $0.content.input==source.content.output}
                if !targets.isEmpty {let child=submenu("출력 연결");for target in targets {action(target.name,in:child){[weak self] in self?.store.connectHierarchy(node.id,.music(arrangementID:arrangement,useID:use,nodeID:target.id))}}}
                if source.content.output == .audio {
                    let compressors=targets.filter{if case .effect(let effect)=$0.content{return effect.kind == .compressor};return false}
                    if !compressors.isEmpty {let child=submenu("사이드체인 연결");for target in compressors {action(target.name,in:child){[weak self] in self?.store.connectHierarchy(node.id,.music(arrangementID:arrangement,useID:use,nodeID:target.id),sidechain:true)}}}
                }
                let outgoing=graph.edges.filter{$0.from==id}
                if !outgoing.isEmpty {let child=submenu("연결 해제");for edge in outgoing {action(graph.nodes.first{$0.id==edge.to}?.name ?? edge.to,in:child){[weak self] in self?.store.disconnectHierarchy(node.id,edgeID:edge.id)}}}
            }
        case .section(let arrangement,let use):
            if let a=store.project.arrangements.first(where:{$0.id==arrangement}) {
                let child=submenu("다음 섹션 연결")
                for target in a.uses where target.id != use {action(target.name,in:child){[weak self] in self?.store.connectHierarchy(node.id,.section(arrangementID:arrangement,useID:target.id))}}
                let outgoing=a.edges.filter{$0.from==use}
                if !outgoing.isEmpty {
                    let isEnd=a.uses.first{$0.id==use}?.isEnd == true
                    let choose=submenu(isEnd ? "끝 해제 후 재생할 연결":"재생할 연결"),transition=submenu("전환 편집"),remove=submenu("연결 해제")
                    for edge in outgoing {
                        let name=a.uses.first{$0.id==edge.to}?.name ?? "다음 섹션"
                        let connection=CircleConnectionID(edgeID:edge.id,from:node.id,to:.section(arrangementID:arrangement,useID:edge.to))
                        action(name,in:choose){[weak self] in self?.store.chooseHierarchyEdge(node.id,edgeID:edge.id)}
                        choose.items.last?.state=SectionFlowSelection.isSelected(connection,in:store.project) ? .on:.off
                        choose.items.last?.toolTip=isEnd ? "끝 섹션 지정을 해제하고 이 연결로 재생을 이어갑니다":"이 연결로 다음 섹션을 재생합니다"
                        action(name,in:transition){[weak self] in self?.store.openHierarchyTransition(node.id,edgeID:edge.id)}
                        action(name,in:remove){[weak self] in self?.store.disconnectHierarchy(node.id,edgeID:edge.id)}
                    }
                }
                action("시작 섹션으로 지정"){[weak self] in self?.store.selectHierarchy(node.id);self?.store.setStart()}
            }
        case .composition(let id):
            if let album=store.project.album {
                let siblings=album.parent(of:id).flatMap{album.composition($0)?.children} ?? album.children
                let child=submenu("다음 순서로 연결")
                for sibling in siblings where sibling != id {action(album.composition(sibling)?.name ?? "곡",in:child){[weak self] in self?.store.connectHierarchy(node.id,.composition(sibling))}}
            }
        case .group:
            action("그룹 접기·펼치기"){[weak self] in self?.store.selectHierarchy(node.id);self?.store.updateHierarchyGroup{$0.collapsed.toggle()}}
            action("그룹 해제"){[weak self] in self?.store.selectHierarchy(node.id);self?.store.ungroupHierarchy()}
        case .signal(let id):
            if let source=store.project.signal.nodes.first(where:{$0.id==id}) {
                if source.kind != .master {let child=submenu("출력 연결");for target in store.project.signal.nodes where target.id != id && target.kind != .source {action(target.name,in:child){[weak self] in self?.store.connectHierarchy(node.id,.signal(target.id))}}}
                if source.kind != .master {
                    let compressors=store.project.signal.nodes.filter{$0.id != id && $0.kind == .effect && $0.effect.kind == .compressor}
                    if !compressors.isEmpty {let child=submenu("사이드체인 연결");for target in compressors {action(target.name,in:child){[weak self] in self?.store.connectHierarchy(node.id,.signal(target.id),sidechain:true)}}}
                }
                let outgoing=store.project.signal.edges.filter{$0.from==id}
                if !outgoing.isEmpty {let child=submenu("연결 해제");for edge in outgoing {action(store.project.signal.nodes.first{$0.id==edge.to}?.name ?? edge.to,in:child){[weak self] in self?.store.disconnectHierarchy(node.id,edgeID:edge.id)}}}
            }
        case .album, .sound: break
        }
        if node.role != .album,node.role != .group,node.role != .sound,node.signal?.kind != .source,node.signal?.kind != .master {
            menu.addItem(.separator());action("서클 삭제"){[weak self] in self?.store.selectHierarchy(node.id);self?.store.removeHierarchy()}
        }
        return menu
    }
}
