import AppKit
import SwiftUI
import CirclrCore

enum OrbitDrawing {
    static func point(_ center: NSPoint, radius: Double, phase: Double) -> NSPoint {
        let angle=phase*2*Double.pi-Double.pi/2
        return NSPoint(x:center.x+cos(angle)*radius,y:center.y+sin(angle)*radius)
    }
    static func arc(_ center: NSPoint, radius: Double, from: Double, to: Double) -> NSBezierPath {
        let path=NSBezierPath(),count=max(2,min(4096,Int(abs(to-from)*max(20,radius)*2)))
        for i in 0...count {let point=point(center,radius:radius,phase:from+(to-from)*Double(i)/Double(count));if i==0 {path.move(to:point)}else{path.line(to:point)}}
        path.lineCapStyle = .round;return path
    }
    static func text(_ text: String, at p: NSPoint, size: Double = 10, color: NSColor = StudioTheme.secondaryNS) {
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:size),.foregroundColor:color]
        let width=(text as NSString).size(withAttributes:attributes).width
        (text as NSString).draw(at:NSPoint(x:p.x-width/2,y:p.y-size/2),withAttributes:attributes)
    }
    static func dot(_ p:NSPoint, radius:Double=4, color:NSColor=StudioTheme.accentNS) {
        color.setFill();NSBezierPath(ovalIn:NSRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2)).fill()
    }
}

struct OrbitMIDIEditor:NSViewRepresentable {
    @ObservedObject var store:AppStore
    let viewport:MIDIOrbitViewport
    let focusTarget:MIDIEditorFocus
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context:Context)->OrbitMIDIView {let view=OrbitMIDIView(store:store);focusTarget.view=view;return view}
    func updateNSView(_ view:OrbitMIDIView,context:Context) {
        if !enabled || view.viewport != viewport || (view.dragIdentity != nil && view.dragIdentity != store.numberEditIdentity) {view.cancelDrag()}
        view.viewport=viewport;view.allowsEditing=enabled;view.needsDisplay=true
    }
}
@MainActor final class OrbitMIDIView:NSView {
    let store:AppStore
    var viewport=MIDIOrbitViewport()
    var original:Note?,preview:Note?
    var previousPhase=0.0,travel=0.0,downRadius=0.0
    var resizing=false,allowsEditing=true
    var dragIdentity:NumberEditIdentity?
    var accessibilityNotes:[ID:OrbitNoteAccessibility]=[:]
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    var center:NSPoint {NSPoint(x:bounds.midX,y:bounds.midY)}
    var outer:Double {max(30,min(bounds.width,bounds.height)/2-22)}
    var inner:Double {outer*0.34}
    var row:Double {(outer-inner)/Double(viewport.rows)}
    var clock:MusicClock? {store.orbitMIDIClock}
    var grid:Double {Double(max(1,store.currentContext.beatGrid.subdivisions))}
    init(store:AppStore) {self.store=store;super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("MIDI 궤도 편집기 · Tab 노트 선택 · 방향키 이동 · Shift 좌우 길이 · Option 상하 세기")}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();DispatchQueue.main.async{[weak self] in guard let self,self.allowsEditing,let window=self.window,!(window.firstResponder is NSTextView) else{return};window.makeFirstResponder(self)}}
    func cancelDrag(){original=nil;preview=nil;dragIdentity=nil}
    func radius(_ pitch:Int)->Double {outer-(Double(viewport.highest-pitch)+0.5)*row}
    func phase(_ point:NSPoint)->Double {OrbitTimeline.phase(Point(point.x-center.x,point.y-center.y))}
    func snap(_ value:Double)->Double {(value*grid).rounded()/grid}
    func pitchName(_ pitch:Int)->String {Scale.roots[pitch%12]+String(pitch/12-1)}
    func arc(_ note:Note,clock:MusicClock)->NSBezierPath {
        let r=viewport.beats(clock)
        return OrbitDrawing.arc(center,radius:radius(note.pitch),from:viewport.phase(max(r.lowerBound,note.beat),clock:clock),to:viewport.phase(min(r.upperBound,note.beat+note.length),clock:clock))
    }
    func endpoint(_ note:Note,clock:MusicClock)->NSPoint {OrbitDrawing.point(center,radius:radius(note.pitch),phase:viewport.phase(note.beat+note.length,clock:clock))}
    override func draw(_ dirtyRect:NSRect) {
        guard let clock else{return};let range=viewport.beats(clock),bars=viewport.bars(clock)
        for i in 0..<viewport.rows {
            let pitch=viewport.highest-i,r=radius(pitch),path=OrbitDrawing.arc(center,radius:r,from:0,to:1)
            (store.currentContext.scale.contains(pitch) ? NSColor(white:0.145,alpha:1):NSColor(white:0.075,alpha:1)).setStroke();path.lineWidth=max(1,row-0.8);path.stroke()
            if pitch%6==0 {OrbitDrawing.text(pitchName(pitch),at:OrbitDrawing.point(center,radius:r,phase:0.75),size:9)}
        }
        // Density limits only drawing; the musical snap grid stays unchanged.
        let first=Int(ceil(range.lowerBound*grid)),last=Int(floor(range.upperBound*grid))
        let strideSize=max(1,Int(ceil(Double(max(1,last-first))/max(1,2*Double.pi*inner/8))))
        let lines=NSBezierPath();lines.lineWidth=0.5;StudioTheme.lineNS.setStroke()
        for i in stride(from:first,through:max(first,last),by:strideSize) {
            let phase=viewport.phase(Double(i)/grid,clock:clock)
            lines.move(to:OrbitDrawing.point(center,radius:inner,phase:phase));lines.line(to:OrbitDrawing.point(center,radius:outer,phase:phase))
        };lines.stroke()
        let labelStride=max(1,Int(ceil(Double(bars.count)/max(1,2*Double.pi*outer/36))))
        for bar in bars where (bar-bars.lowerBound)%labelStride==0 {
            let phase=viewport.phase(clock.barStarts[bar],clock:clock),line=NSBezierPath()
            line.move(to:OrbitDrawing.point(center,radius:inner,phase:phase));line.line(to:OrbitDrawing.point(center,radius:outer+3,phase:phase));StudioTheme.secondaryNS.withAlphaComponent(0.5).setStroke();line.stroke()
            OrbitDrawing.text(String(bar+1),at:OrbitDrawing.point(center,radius:outer+13,phase:phase),size:11)
        }
        let selectedIDs=store.selectedMIDIIDs
        let visible=(store.currentLane?.notes ?? []).map{preview?.id==$0.id ? preview!:$0}.filter{viewport.visible($0,clock:clock)}
        for note in visible.filter({!selectedIDs.contains($0.id)})+visible.filter({selectedIDs.contains($0.id)}) {
            let selected=selectedIDs.contains(note.id),path=arc(note,clock:clock)
            StudioTheme.accentNS.withAlphaComponent(selected ? 1:0.55+Double(note.velocity)/360).setStroke();path.lineWidth=max(3,row-1.2);path.stroke()
            if selected,viewport.showsEnd(note,clock:clock) {OrbitDrawing.dot(endpoint(note,clock:clock),radius:4,color:StudioTheme.textNS)}
            for beat in [note.beat<range.lowerBound ? range.lowerBound:nil,note.beat+note.length>range.upperBound ? range.upperBound:nil].compactMap({$0}) {
                let point=OrbitDrawing.point(center,radius:radius(note.pitch),phase:viewport.phase(beat,clock:clock))
                let marker=NSBezierPath(ovalIn:NSRect(x:point.x-3,y:point.y-3,width:6,height:6));StudioTheme.textNS.setStroke();marker.lineWidth=1;marker.stroke()
            }
        }
        OrbitDrawing.text("\(bars.lowerBound+1)–\(bars.upperBound)마디",at:NSPoint(x:center.x,y:center.y-8),size:11,color:StudioTheme.textNS)
        OrbitDrawing.text("시계 방향",at:NSPoint(x:center.x,y:center.y+9),size:10)
        setAccessibilityValue("\(bars.lowerBound+1)–\(bars.upperBound)마디 · \(pitchName(viewport.lowest))–\(pitchName(viewport.highest)) · \(visible.count)개 노트 표시")
        if let window {
            let ids=Set(visible.map(\.id));accessibilityNotes=accessibilityNotes.filter{ids.contains($0.key)}
            setAccessibilityChildren(MIDIOrbitViewport.ordered(visible).map{note -> NSAccessibilityElement in
                let child=accessibilityNotes[note.id] ?? OrbitNoteAccessibility(parent:self,id:note.id);accessibilityNotes[note.id]=child
                child.setAccessibilityLabel("\(pitchName(note.pitch)) · \(note.beat)박 · 길이 \(note.length)박 · 세기 \(note.velocity)"+(note.beat<range.lowerBound ? " · 앞에서 이어짐":"")+(!viewport.showsEnd(note,clock:clock) ? " · 다음 범위로 이어짐":""))
                child.setAccessibilityValue(selectedIDs.contains(note.id) ? "선택됨":"")
                child.setAccessibilityFrame(window.convertToScreen(convert(arc(note,clock:clock).bounds.insetBy(dx:-6,dy:-6),to:nil)))
                return child
            })
        }
    }
    override func mouseDown(with event:NSEvent) {
        guard allowsEditing else{return};window?.makeFirstResponder(self)
        guard let clock else{return};let p=convert(event.locationInWindow,from:nil),r=hypot(p.x-center.x,p.y-center.y)
        guard r>=inner-3,r<=outer+3 else{return}
        previousPhase=phase(p);travel=0;downRadius=r
        let beat=viewport.beat(previousPhase,clock:clock),range=viewport.beats(clock)
        let pitch=max(0,min(127,viewport.highest-Int((outer-r)/row)))
        store.selectedClipID=nil
        let hits=(store.currentLane?.notes ?? []).filter{n in
            guard viewport.visible(n,clock:clock),abs(radius(n.pitch)-r)<max(4,row/2) else{return false}
            return (beat>=n.beat && beat<=n.beat+n.length) || (viewport.showsEnd(n,clock:clock) && hypot(p.x-endpoint(n,clock:clock).x,p.y-endpoint(n,clock:clock).y)<7)
        }.sorted{abs(radius($0.pitch)-r)<abs(radius($1.pitch)-r)}
        if let n=hits.first {
            if event.modifierFlags.contains(.shift) {store.toggleMIDISelection(n.id);cancelDrag();needsDisplay=true;return}
            original=n;preview=n;store.selectedNoteID=n.id;store.selectedBeat=n.beat;dragIdentity=store.numberEditIdentity
            let end=endpoint(n,clock:clock)
            resizing=viewport.showsEnd(n,clock:clock) && hypot(p.x-end.x,p.y-end.y)<8
        } else if !event.modifierFlags.contains(.shift) {store.addNote(beat:max(range.lowerBound,min(range.upperBound-1/grid,snap(beat))),pitch:pitch,length:1/grid)}
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard allowsEditing,var n=original,let clock,dragIdentity==store.numberEditIdentity else{return}
        let p=convert(event.locationInWindow,from:nil),next=phase(p),range=viewport.beats(clock)
        travel+=OrbitTimeline.phaseDelta(from:previousPhase,to:next);previousPhase=next
        let originalBeat=resizing ? n.beat+n.length:n.beat
        let q=snap(clock.beat(atSeconds:clock.seconds(at:originalBeat)+travel*(clock.seconds(at:range.upperBound)-clock.seconds(at:range.lowerBound))))
        if resizing {n.length=max(1/grid,min(clock.beats-n.beat,q-n.beat))}
        else {n.beat=max(0,min(clock.beats-n.length,q));n.pitch=max(0,min(127,n.pitch+Int(((hypot(p.x-center.x,p.y-center.y)-downRadius)/row).rounded())))}
        preview=n;needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        defer{cancelDrag();needsDisplay=true}
        guard allowsEditing,let n=preview,n != original,dragIdentity==store.numberEditIdentity,var lane=store.currentLane,let i=lane.notes.firstIndex(where:{$0.id==n.id}) else{return}
        lane.notes[i]=n;store.setLane(lane)
    }
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        if allowsEditing,window?.firstResponder===self,event.modifierFlags.contains(.command),store.handleMIDIBatchKey(event){needsDisplay=true;return true}
        return super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event:NSEvent) {
        guard allowsEditing else{super.keyDown(with:event);return}
        if [36,76].contains(event.keyCode),store.selectedNoteID==nil,let clock,!viewport.beats(clock).contains(store.selectedBeat){store.selectedBeat=viewport.beats(clock).lowerBound}
        if store.handleMIDIKey(event,topPitch:viewport.highest+6){needsDisplay=true;return}
        if event.keyCode==53 {cancelDrag();store.focusCanvas?();store.hierarchyParent()}
        else {super.keyDown(with:event)}
    }
}
@MainActor final class OrbitNoteAccessibility:NSAccessibilityElement {
    weak var plot:OrbitMIDIView?
    let noteID:ID
    init(parent:OrbitMIDIView,id:ID){plot=parent;noteID=id;super.init();setAccessibilityParent(parent);setAccessibilityRole(.button);setAccessibilityEnabled(true)}
    override func accessibilityPerformPress()->Bool {
        guard let plot,plot.allowsEditing,let note=plot.store.currentLane?.notes.first(where:{$0.id==noteID}) else{return false}
        plot.window?.makeFirstResponder(plot);plot.store.selectedNoteID=noteID;plot.store.selectedBeat=note.beat;plot.needsDisplay=true;return true
    }
}
