import AppKit
import SwiftUI
import Combine
import CirclrCore

/// Transport responds to Space only when it is a key command, not text input or a modified shortcut.
enum PlaybackSpaceShortcut {
    static func accepts(keyCode:UInt16,modifiers:NSEvent.ModifierFlags,textInputActive:Bool)->Bool {
        keyCode==49 && !textInputActive && modifiers.intersection([.command,.control,.option,.shift,.function]).isEmpty
    }
    static func accepts(_ event:NSEvent,in window:NSWindow?)->Bool {
        let responder=window?.firstResponder
        return accepts(keyCode:event.keyCode,modifiers:event.modifierFlags,
                       textInputActive:responder is NSTextView || responder is NSTextField)
    }
}

struct SongCanvas:NSViewRepresentable {
    @ObservedObject var store:AppStore
    func makeNSView(context:Context)->CircleCanvas { CircleCanvas(store:store) }
    func updateNSView(_ view:CircleCanvas,context:Context) { view.synchronize() }
}
@MainActor final class CircleCanvas:NSView {
    let store:AppStore
    let radius=80.0
    let accent=StudioTheme.accentNS
    var camera=CanvasCamera(), persistedCamera=CanvasCamera()
    var graphKey=""
    var animation:(start:Double,from:CanvasCamera,to:CanvasCamera)?
    var frameTimer:Timer?, cameraCommit:DispatchWorkItem?, playingSubscription:AnyCancellable?
    var lastCommand:UUID?
    var previousSize=NSSize.zero
    var dragged=Set<ID>(), originals:[ID:Point]=[:], preview:[ID:Point]=[:], dragAnchor:ID?
    var down=NSPoint.zero, screenDown=NSPoint.zero, last=NSPoint.zero, panStart=CanvasCamera()
    var selectionRect:NSRect?, linking:ID?, panning=false
    var edges:[(ID,NSPoint,NSPoint)]=[], groupRects:[ID:NSRect]=[:]
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    override var isOpaque:Bool {true}
    init(store:AppStore) {
        self.store=store
        super.init(frame:.zero)
        setAccessibilityElement(true);setAccessibilityRole(.group)
        setAccessibilityLabel("송폼 캔버스. 서클 두 번 클릭으로 별도 편집 창 열기. 휠 위는 확대, 아래는 축소. 이동 도구나 Shift 스크롤로 이동합니다.")
        playingSubscription=store.meter.$playing.sink{[weak self] _ in DispatchQueue.main.async {self?.startFrames();self?.needsDisplay=true}}
    }
    required init?(coder:NSCoder) {fatalError()}
    var nodeIDs:[ID] {store.soundView ? store.project.signal.nodes.map(\.id):store.project.active.uses.map(\.id)}
    var orderedNodes:[ID] {nodeIDs.filter{!store.selection.contains($0)}+nodeIDs.filter{store.selection.contains($0)}}
    func rings(_ id:ID)->SectionRings {SectionRings(repeats:store.soundView ? 1:(store.project.active.uses.first{$0.id==id}?.repeatCount ?? 1))}
    func nodeBounds(_ id:ID)->NSRect {
        let p=position(id),r=rings(id).outerRadius
        return NSRect(x:p.x-r-24,y:p.y-r-30,width:(r+24)*2,height:r*2+70)
    }
    func position(_ id:ID)->NSPoint {let p=preview[id] ?? store.layout.positions[id] ?? Point();return NSPoint(x:p.x,y:p.y)}
    func world(_ p:NSPoint)->NSPoint {let w=camera.world(Point(p.x,p.y));return NSPoint(x:w.x,y:w.y)}
    func screen(_ p:NSPoint)->NSPoint {let s=camera.screen(Point(p.x,p.y));return NSPoint(x:s.x,y:s.y)}
    func hidden(_ id:ID)->Bool {store.layout.groups.contains{$0.collapsed && $0.members.contains(id)}}
    func endpoint(_ id:ID,out:Bool)->NSPoint {
        if let g=store.layout.groups.first(where:{$0.collapsed && $0.members.contains(id)}),let r=groupRects[g.id] {return NSPoint(x:out ? r.maxX:r.minX,y:r.midY)}
        let p=position(id);return NSPoint(x:p.x+(out ? rings(id).portRadius : -rings(id).portRadius),y:p.y)
    }
    func synchronize() {
        let key="\(store.project.id):\(store.soundView ? "sound":store.project.activeArrangementID)"
        let saved=CanvasCamera(pan:store.layout.pan,zoom:store.layout.zoom)
        if key != graphKey {
            graphKey=key; camera=saved;persistedCamera=saved;animation=nil;cameraCommit?.cancel();cameraCommit=nil
        } else if saved != persistedCamera {
            persistedCamera=saved
            if animation==nil && !panning && cameraCommit==nil {camera=saved}
        }
        if let command=store.canvasCommand,command.id != lastCommand {
            lastCommand=command.id
            do {
                var target=camera
                switch command.action {
                case .fit:
                    let margin=(nodeIDs.map{rings($0).outerRadius}.max() ?? radius)+34
                    target=CanvasCamera.fitting(points:nodeIDs.compactMap{store.layout.positions[$0]},width:bounds.width-40,height:bounds.height-140,margin:margin) ?? camera
                    target.pan.x+=20;target.pan.y+=70
                case .zoomIn:target=camera.zoomed(to:camera.zoom*1.2,around:Point(bounds.midX,bounds.midY))
                case .zoomOut:target=camera.zoomed(to:camera.zoom/1.2,around:Point(bounds.midX,bounds.midY))
                }
                animate(to:target)
            }
        }
        window?.invalidateCursorRects(for:self)
        needsDisplay=true
    }
    func animate(to target:CanvasCamera) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            camera=target;animation=nil;commitCamera();needsDisplay=true
        } else {
            animation=(ProcessInfo.processInfo.systemUptime,camera,target);startFrames()
        }
    }
    func startFrames() {
        guard frameTimer==nil else {return}
        let timer=Timer(timeInterval:1/60,repeats:true){[weak self] _ in MainActor.assumeIsolated{self?.frameStep()}}
        frameTimer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    func frameStep() {
        if let a=animation {
            let t=min(1,(ProcessInfo.processInfo.systemUptime-a.start)/0.18)
            camera=a.from.interpolated(to:a.to,progress:t)
            if t>=1 {animation=nil;commitCamera()}
        }
        needsDisplay=true
        if animation==nil && !store.isPlaying {frameTimer?.invalidate();frameTimer=nil}
    }
    override func layout() {super.layout();needsDisplay=true}
    func commitCamera() {
        cameraCommit?.cancel();cameraCommit=nil
        persistedCamera=camera
        store.editViewport{$0.pan=camera.pan;$0.zoom=camera.zoom}
    }
    func deferCameraCommit() {
        cameraCommit?.cancel()
        let work=DispatchWorkItem{[weak self] in self?.commitCamera()};cameraCommit=work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.2,execute:work)
    }
    func label(_ s:String,_ rect:NSRect,size:CGFloat = 12,color:NSColor = StudioTheme.textNS,bold:Bool = false,center:Bool = false) {
        let style = NSMutableParagraphStyle(); style.alignment = center ? .center:.left; style.lineBreakMode = .byTruncatingTail
        (s as NSString).draw(in:rect,withAttributes:[.font:bold ? NSFont.systemFont(ofSize:size,weight:.semibold):NSFont.systemFont(ofSize:size),.foregroundColor:color,.paragraphStyle:style])
    }
    override func draw(_ dirtyRect:NSRect) {
        StudioTheme.canvasNS.setFill(); bounds.fill()
        guard camera.zoom.isFinite,camera.zoom>0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = AffineTransform(translationByX:camera.pan.x,byY:camera.pan.y); var t=transform; t.scale(camera.zoom); (t as NSAffineTransform).concat()
        let visible = NSRect(origin:world(.zero),size:NSSize(width:bounds.width/camera.zoom,height:bounds.height/camera.zoom))
        if store.layout.grid {
            let spacing=max(12,store.layout.spacing)*(camera.zoom<0.5 ? 2:1)
            NSColor(white:0.18,alpha:1).setFill();let dots=NSBezierPath()
            var x=floor(visible.minX/spacing)*spacing
            while x<visible.maxX {var y=floor(visible.minY/spacing)*spacing;while y<visible.maxY {dots.appendOval(in:NSRect(x:x,y:y,width:1.25/camera.zoom,height:1.25/camera.zoom));y+=spacing};x+=spacing};dots.fill()
        }
        groupRects = [:]
        for g in store.layout.groups {
            let members=g.members.filter{nodeIDs.contains($0)};guard let first=members.first else{continue}
            var r=nodeBounds(first)
            for id in members.dropFirst() {r=r.union(nodeBounds(id))}
            if g.collapsed { r.size=NSSize(width:210,height:46) }
            groupRects[g.id]=r
            NSColor(white:0.08,alpha:1).setFill(); StudioTheme.lineNS.setStroke(); let path=NSBezierPath(roundedRect:r,xRadius:8,yRadius:8);path.lineWidth=1;path.fill();path.stroke()
            label("\(g.collapsed ? "▸":"▾")  \(g.name) · \(g.members.count)",NSRect(x:r.minX+12,y:r.minY+10,width:r.width-20,height:20),bold:true)
        }
        edges=[]
        let connections:[(ID,ID,ID,String,Bool)] = store.soundView ? store.project.signal.edges.map{($0.id,$0.from,$0.to,$0.sidechain ? "Sidechain":"",$0.sidechain)} : store.project.active.edges.map{($0.id,$0.from,$0.to,$0.transition.length>0 ? "\($0.transition.mode.rawValue) \($0.transition.length.formatted())":"",false)}
        for (id,from,to,title,sidechain) in connections {
            if let g=store.layout.groups.first(where:{$0.collapsed && $0.members.contains(from)}),g.members.contains(to) {continue}
            let a=endpoint(from,out:true), b=endpoint(to,out:false); edges.append((id,a,b))
            drawEdge(a,b,selected:store.edgeSelection==id,dashed:sidechain)
            if !title.isEmpty { label(title,NSRect(x:(a.x+b.x)/2-75,y:(a.y+b.y)/2-25,width:150,height:20),size:11,color:accent,center:true) }
        }
        let active = store.isPlaying ? (store.prepared?.plan.occurrences.filter{store.transportSeconds >= $0.start && store.transportSeconds < $0.end} ?? []) : []
        for id in orderedNodes where !hidden(id) {drawNode(id,active:active)}
        if let linking { drawEdge(endpoint(linking,out:true),last,selected:true,dashed:true) }
        if let r=selectionRect { accent.withAlphaComponent(0.08).setFill();r.fill();accent.setStroke();NSBezierPath(rect:r).stroke() }
        NSGraphicsContext.restoreGraphicsState()
        if nodeIDs.isEmpty {
            let cx=bounds.midX,cy=bounds.midY-30
            accent.withAlphaComponent(0.20).setStroke();let circle=NSBezierPath(ovalIn:NSRect(x:cx-44,y:cy-94,width:88,height:88));circle.lineWidth=1.2;circle.stroke()
            label("첫 서클에서 시작하세요",NSRect(x:cx-240,y:cy+24,width:480,height:30),size:22,bold:true,center:true)
            label("빈 곳을 두 번 클릭해 곡의 한 부분을 만드세요",NSRect(x:cx-240,y:cy+66,width:480,height:22),size:13,color:StudioTheme.secondaryNS,center:true)
        }
    }
    func drawNode(_ id:ID,active:[Occurrence]) {
            let p=position(id), selected=store.selection.contains(id), playing=active.first(where:{$0.use.id==id})
            let r=NSRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2)
            StudioTheme.surfaceNS.setFill();NSBezierPath(ovalIn:r).fill()
            let ring=rings(id)
            for (index,rr) in ring.radii.enumerated() {
                let outline=NSBezierPath(ovalIn:NSRect(x:p.x-rr,y:p.y-rr,width:rr*2,height:rr*2))
                let current=playing?.iteration==index
                let boundary=index==0 || index==ring.count-1
                let density=boundary ? 1:min(1,max(0.08,ring.spacing*camera.zoom/1.5))
                let color=current ? accent:(selected ? accent.withAlphaComponent(index==0 ? 1:0.65):NSColor(white:index==0 ? 0.38:0.32,alpha:1))
                color.withAlphaComponent(color.alphaComponent*(current ? 1:density)).setStroke()
                outline.lineWidth=current ? max(1.8,ring.lineWidth):(boundary ? 1.4:ring.lineWidth);outline.stroke()
            }
            var name="", info="", footer=""
            if !store.soundView,let use=store.project.active.uses.first(where:{$0.id==id}) {
                name=use.name
                if let (_,ctx,clock)=store.context(for:use) {
                    info="\(ctx.tempo.formatted()) · \(ctx.meter.label)"; footer="\(clock.meters.count)마디 · \(use.repeatCount)회"
                    let ticks=NSBezierPath(), barTicks=NSBezierPath()
                    for bar in stride(from:0,to:clock.meters.count,by:max(1,clock.meters.count/180)) {
                        let start=clock.barStarts[bar], m=clock.meters[bar]
                        let count=clock.beats>256 ? 1:m.numerator
                        for beat in 0..<count {
                            let q=start+Double(beat)*4/Double(m.denominator), angle=q/clock.beats*2*Double.pi-Double.pi/2
                            let path=beat==0 ? barTicks:ticks, inner=radius-(beat==0 ? 10:5)
                            path.move(to:NSPoint(x:p.x+cos(angle)*inner,y:p.y+sin(angle)*inner));path.line(to:NSPoint(x:p.x+cos(angle)*radius,y:p.y+sin(angle)*radius))
                        }
                    }
                    NSColor(white:0.29,alpha:1).setStroke();ticks.lineWidth=1;ticks.stroke();(selected ? accent:NSColor(white:0.54,alpha:1)).setStroke();barTicks.lineWidth=1.6;barTicks.stroke()
                    for bar in stride(from:0,to:clock.meters.count,by:max(1,clock.meters.count/180)) where ctx.beatGrid.accents.reduce(0,+)==clock.meters[bar].numerator {
                        var offset=0
                        for length in ctx.beatGrid.accents {
                            let q=clock.barStarts[bar]+Double(offset)*4/Double(clock.meters[bar].denominator),a=q/clock.beats*2*Double.pi-Double.pi/2
                            let mark=NSBezierPath(ovalIn:NSRect(x:p.x+cos(a)*(radius-15)-1.8,y:p.y+sin(a)*(radius-15)-1.8,width:3.6,height:3.6));accent.setFill();mark.fill();offset+=length
                        }
                    }
                    if let occurrence=playing {
                        let q=occurrence.clock.beat(atSeconds:store.transportSeconds-occurrence.start), a=q/occurrence.clock.beats*2*Double.pi-Double.pi/2
                        let indicator=NSBezierPath();indicator.move(to:NSPoint(x:p.x+cos(a)*(radius-22),y:p.y+sin(a)*(radius-22)));indicator.line(to:NSPoint(x:p.x+cos(a)*radius,y:p.y+sin(a)*radius));indicator.lineWidth=2;indicator.stroke()
                        footer="\(occurrence.iteration+1)/\(use.repeatCount)회 재생"
                    }
                    do {label(ctx.scale.label,NSRect(x:p.x-58,y:p.y+14,width:116,height:16),size:10,color:StudioTheme.secondaryNS,center:true)}
                }
                let start=store.project.active.startID==id
                let badge = start ? (use.isVariant ? "시작 · 변형":"시작") : (use.isVariant ? "변형":"")
                if !badge.isEmpty { label(badge,NSRect(x:p.x-52,y:p.y-47,width:104,height:16),size:10,color:accent,center:true) }

            } else if let n=store.project.signal.nodes.first(where:{$0.id==id}) { name=n.name;info=n.kind == .effect ? AppStore.effectName(n.effect.kind):n.kind.rawValue;footer=n.kind == .effect ? n.effect.amount.formatted(.number.precision(.fractionLength(2))):"" }
            do {
            label(name,NSRect(x:p.x-58,y:p.y-22,width:116,height:22),size:17,bold:true,center:true)
            label(info,NSRect(x:p.x-58,y:p.y,width:116,height:17),size:11,center:true)
            label(footer,NSRect(x:p.x-82,y:p.y+ring.outerRadius+12,width:164,height:20),size:11,color:StudioTheme.secondaryNS,center:true)
            }
            for out in [false,true] { let port=endpoint(id,out:out); let rr=NSRect(x:port.x-5,y:port.y-5,width:10,height:10);accent.setFill();NSBezierPath(ovalIn:rr).fill() }
    }
    func drawEdge(_ a:NSPoint,_ b:NSPoint,selected:Bool,dashed:Bool) {
        let path=NSBezierPath();let bend=max(55,abs(b.x-a.x)*0.45);path.move(to:a);path.curve(to:b,controlPoint1:NSPoint(x:a.x+bend,y:a.y),controlPoint2:NSPoint(x:b.x-bend,y:b.y));path.lineWidth=selected ? 3:1.6
        if dashed {path.setLineDash([5,4],count:2,phase:0)}
        (selected ? accent:NSColor(white:0.34,alpha:1)).setStroke();path.stroke()
        let arrow=NSBezierPath();arrow.move(to:NSPoint(x:b.x-10,y:b.y-5));arrow.line(to:b);arrow.line(to:NSPoint(x:b.x-10,y:b.y+5));arrow.stroke()
    }
    func hitNode(_ p:NSPoint) -> ID? { orderedNodes.reversed().first{!hidden($0) && hypot(position($0).x-p.x,position($0).y-p.y)<rings($0).outerRadius+7} }
    func hitEdge(_ p:NSPoint) -> ID? {
        for (id,a,b) in edges.reversed() {
            let bend=max(55,abs(b.x-a.x)*0.45)
            for step in 0...80 {let t=Double(step)/80,u=1-t;let x=u*u*u*a.x+3*u*u*t*(a.x+bend)+3*u*t*t*(b.x-bend)+t*t*t*b.x;let y=u*u*u*a.y+3*u*u*t*a.y+3*u*t*t*b.y+t*t*t*b.y;if hypot(p.x-x,p.y-y)<10/camera.zoom {return id}}
        };return nil
    }
    override func mouseDown(with event:NSEvent) {
        animation=nil
        window?.makeFirstResponder(self)
        screenDown=convert(event.locationInWindow,from:nil);down=world(screenDown);last=down;panStart=camera
        panning=store.panMode || event.buttonNumber==2
        if panning {NSCursor.closedHand.push();return}
        for g in store.layout.groups.reversed() {
            if let r=groupRects[g.id],NSRect(x:r.minX,y:r.minY,width:r.width,height:32).contains(down) {
                if event.clickCount==2 {store.toggleGroup(g.id);return}
                dragged=Set(g.members);originals=store.layout.positions;dragAnchor=g.members.sorted().first;return
            }
        }
        if let id=orderedNodes.reversed().first(where:{!hidden($0) && hypot(endpoint($0,out:true).x-down.x,endpoint($0,out:true).y-down.y)<12}) {linking=id;return}
        if let id=hitNode(down) {
            if event.modifierFlags.contains(.shift) {store.select(id,add:true)} else if !store.selection.contains(id) {store.select(id)}
            if event.clickCount==2 {store.openCircle(id);return}
            let p=position(id),d=hypot(p.x-down.x,p.y-down.y)
            if !store.soundView,d>58,let clock=store.currentClock {var angle=atan2(down.y-p.y,down.x-p.x)+Double.pi/2;if angle<0 {angle+=2*Double.pi};store.selectedBeat=angle/(2*Double.pi)*clock.beats}
            dragged=store.selection;originals=store.layout.positions;dragAnchor=id
        } else if let e=hitEdge(down) {
            store.selectNodes([]);store.edgeSelection=e
            if event.clickCount==2 {store.openEdge(e)}
        } else if event.clickCount==2,!store.soundView {store.addSection(at:Point(down.x,down.y))}
        else {if !event.modifierFlags.contains(.shift) {store.selectNodes([])};store.edgeSelection=nil;selectionRect=NSRect(origin:down,size:.zero)}
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard animation==nil else {return}
        let screenPoint=convert(event.locationInWindow,from:nil),p=world(screenPoint);last=p
        if panning {
            camera.pan=Point(panStart.pan.x+screenPoint.x-screenDown.x,panStart.pan.y+screenPoint.y-screenDown.y)
            needsDisplay=true;return
        }
        if linking != nil {needsDisplay=true;return}
        if !dragged.isEmpty {
            let dx=p.x-down.x,dy=p.y-down.y
            for id in dragged {let o=originals[id] ?? Point();preview[id]=Point(o.x+dx,o.y+dy)}
        } else if selectionRect != nil {selectionRect=NSRect(x:min(down.x,p.x),y:min(down.y,p.y),width:abs(p.x-down.x),height:abs(p.y-down.y))}
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        let p=world(convert(event.locationInWindow,from:nil))
        if let from=linking,let to=hitNode(p),to != from {store.connect(from,to,sidechain:event.modifierFlags.contains(.option))}
        if !preview.isEmpty,let id=dragAnchor,let origin=originals[id],let target=preview[id] {
            let delta=CanvasCamera.droppedDelta(Point(target.x-origin.x,target.y-origin.y),anchor:origin,spacing:store.layout.spacing,snap:store.layout.snap)
            var positions:[ID:Point]=[:]
            for id in dragged {let o=originals[id] ?? Point();positions[id]=Point(o.x+delta.x,o.y+delta.y)}
            store.editLayout("서클 이동") {for (id,p) in positions {$0.positions[id]=p}}
            if store.insertMode,dragged.count==1,let edge=hitEdge(p) {store.insert(id,on:edge)}
        }
        if let r=selectionRect {store.selectNodes(store.selection.union(nodeIDs.filter{!hidden($0) && r.contains(position($0))}))}
        if panning {NSCursor.pop();commitCamera()}
        linking=nil;dragged=[];preview=[:];selectionRect=nil;panning=false;dragAnchor=nil;needsDisplay=true
    }
    override func otherMouseDown(with event:NSEvent) {mouseDown(with:event)}
    override func otherMouseDragged(with event:NSEvent) {mouseDragged(with:event)}
    override func otherMouseUp(with event:NSEvent) {mouseUp(with:event)}
    override func scrollWheel(with event:NSEvent) {
        guard dragged.isEmpty,linking==nil,!panning else{return}
        animation=nil
        if event.modifierFlags.contains(.shift) {
            camera.pan.x+=event.scrollingDeltaX;camera.pan.y+=event.scrollingDeltaY
        } else {
            let p=convert(event.locationInWindow,from:nil)
            camera=camera.wheelZoom(deltaY:event.scrollingDeltaY,precise:event.hasPreciseScrollingDeltas,inverted:event.isDirectionInvertedFromDevice,around:Point(p.x,p.y))
        }
        needsDisplay=true;deferCameraCommit()
    }
    override func magnify(with event:NSEvent) {
        guard dragged.isEmpty,linking==nil,!panning else{return}
        animation=nil
        let p=convert(event.locationInWindow,from:nil)
        camera=camera.zoomed(to:camera.zoom*(1+event.magnification),around:Point(p.x,p.y))
        needsDisplay=true;deferCameraCommit()
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode==53,event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,let draft=store.midiImportDraft {
            store.cancelMIDIImport(draft.id);return
        }
        let plain=event.modifierFlags.intersection([.command,.control,.option]).isEmpty
        if plain && event.keyCode==4 {store.panMode=true;window?.invalidateCursorRects(for:self)}
        else if plain && event.keyCode==9 {store.panMode=false;window?.invalidateCursorRects(for:self)}
        else if plain && event.keyCode==3 {store.fitCanvas()}
        else if event.keyCode==53 {store.closeFocus();store.panMode=false}
        else if event.keyCode==36 {if let id=store.selection.first {store.openCircle(id)} else if let id=store.edgeSelection {store.openEdge(id)}}
        else if event.keyCode==51 || event.keyCode==117 {store.removeSelection()}
        else if PlaybackSpaceShortcut.accepts(event,in:window) {store.play()}
        else {super.keyDown(with:event)}
    }
    override func menu(for event:NSEvent)->NSMenu? {
        let p=world(convert(event.locationInWindow,from:nil)),menu=NSMenu()
        if let id=hitNode(p) {store.select(id);menu.addItem(withTitle:"서클 편집",action:#selector(openSelected),keyEquivalent:"").target=self
            if !store.soundView {menu.addItem(withTitle:"다시 사용",action:#selector(reuseSelected),keyEquivalent:"").target=self}
            menu.addItem(withTitle:"삭제",action:#selector(deleteSelected),keyEquivalent:"").target=self
        } else if let id=hitEdge(p) {store.selectNodes([]);store.edgeSelection=id;menu.addItem(withTitle:"연결 편집",action:#selector(openSelected),keyEquivalent:"").target=self;menu.addItem(withTitle:"연결 삭제",action:#selector(deleteSelected),keyEquivalent:"").target=self}
        return menu.items.isEmpty ? nil:menu
    }
    override func resetCursorRects() {if store.panMode {addCursorRect(bounds,cursor:.openHand)}}
    @objc func openSelected() {if let id=store.selection.first {store.openCircle(id)} else if let id=store.edgeSelection {store.openEdge(id)}}
    @objc func reuseSelected() {store.reuse()}
    @objc func deleteSelected() {store.removeSelection()}
}
