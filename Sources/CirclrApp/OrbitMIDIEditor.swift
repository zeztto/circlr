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

struct OrbitMIDIEditor: NSViewRepresentable {
    @ObservedObject var store:AppStore
    let topPitch:Int
    func makeNSView(context:Context)->OrbitMIDIView {OrbitMIDIView(store:store)}
    func updateNSView(_ view:OrbitMIDIView,context:Context) {view.topPitch=topPitch;view.needsDisplay=true}
}
@MainActor final class OrbitMIDIView:NSView {
    let store:AppStore
    var topPitch=72
    var original:Note?,preview:Note?
    var previousPhase=0.0,travel=0.0,downRadius=0.0
    var resizing=false,revision=0
    var laneID:ID?
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    var center:NSPoint {NSPoint(x:bounds.midX,y:bounds.midY)}
    var outer:Double {max(30,min(bounds.width,bounds.height)/2-22)}
    var inner:Double {outer*0.34}
    var row:Double {(outer-inner)/24}
    var clock:MusicClock? {
        guard let base=store.currentClock else {return nil}
        if abs(base.beats-store.editorBeats)<1e-8 {return base}
        return try? MusicClock(beats:store.editorBeats,context:store.currentContext,tempoChanges:base.tempos)
    }
    init(store:AppStore) {self.store=store;super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("MIDI 궤도 편집기 · 각도는 시간, 반경은 음높이")}
    required init?(coder:NSCoder){fatalError()}
    func radius(_ pitch:Int)->Double {outer-(Double(topPitch-pitch)+0.5)*row}
    func phase(_ point:NSPoint)->Double {OrbitTimeline.phase(Point(point.x-center.x,point.y-center.y))}
    func snap(_ value:Double)->Double {let grid=Double(store.currentContext.beatGrid.subdivisions);return (value*grid).rounded()/grid}
    override func draw(_ dirtyRect:NSRect) {
        guard let clock else {return};let duration=clock.seconds
        for i in 0..<24 {
            let pitch=topPitch-i,r=radius(pitch),path=OrbitDrawing.arc(center,radius:r,from:0,to:1)
            (store.currentContext.scale.contains(pitch) ? NSColor(white:0.13,alpha:1):NSColor(white:0.085,alpha:1)).setStroke();path.lineWidth=max(1,row-0.7);path.stroke()
            if pitch%12==0 {OrbitDrawing.text(Scale.roots[pitch%12]+String(pitch/12-1),at:OrbitDrawing.point(center,radius:r,phase:0.75),size:8)}
        }
        let grid=Double(store.currentContext.beatGrid.subdivisions),count=min(512,Int(clock.beats*grid))
        let tickStep=max(1,Int(ceil(clock.beats*grid/Double(max(1,count)))))
        let lines=NSBezierPath();lines.lineWidth=0.5;StudioTheme.lineNS.setStroke()
        for i in stride(from:0,through:max(0,Int(clock.beats*grid)),by:tickStep) {
            let phase=clock.seconds(at:Double(i)/grid)/duration
            lines.move(to:OrbitDrawing.point(center,radius:inner,phase:phase));lines.line(to:OrbitDrawing.point(center,radius:outer,phase:phase))
        };lines.stroke()
        for (i,beat) in clock.barStarts.dropLast().enumerated() where i%max(1,clock.meters.count/24)==0 {
            OrbitDrawing.text(String(i+1),at:OrbitDrawing.point(center,radius:outer+12,phase:clock.seconds(at:beat)/duration),size:9)
        }
        for note in store.currentLane?.notes ?? [] {
            let n=preview?.id==note.id ? preview!:note
            guard n.pitch<=topPitch,n.pitch>topPitch-24,n.beat<clock.beats else {continue}
            let start=clock.seconds(at:n.beat)/duration,end=clock.seconds(at:min(clock.beats,n.beat+n.length))/duration
            let arc=OrbitDrawing.arc(center,radius:radius(n.pitch),from:start,to:end)
            let selected=store.selectedNoteID==n.id
            StudioTheme.accentNS.withAlphaComponent(selected ? 1:0.35+Double(n.velocity)/220).setStroke();arc.lineWidth=max(2,row-1.5);arc.stroke()
            if selected {OrbitDrawing.dot(OrbitDrawing.point(center,radius:radius(n.pitch),phase:end),radius:4,color:StudioTheme.textNS)}
        }
        OrbitDrawing.text("12시 → 시계 방향",at:NSPoint(x:center.x,y:center.y-10),size:10)
        OrbitDrawing.text("\(clock.meters.count)마디 · \(store.currentContext.scale.label)",at:NSPoint(x:center.x,y:center.y+10),size:9)
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        guard let clock else {return};let p=convert(event.locationInWindow,from:nil),r=hypot(p.x-center.x,p.y-center.y)
        guard r>=inner-3,r<=outer+3 else{return}
        previousPhase=phase(p);travel=0;downRadius=r;revision=store.project.musicRevision;laneID=store.currentLane?.id
        let beat=clock.beat(atSeconds:previousPhase*clock.seconds)
        let pitch=max(0,min(127,topPitch-Int((outer-r)/row)))
        store.selectedClipID=nil
        if let n=store.currentLane?.notes.reversed().first(where:{n in
            guard abs(radius(n.pitch)-r)<max(4,row/2),n.pitch<=topPitch,n.pitch>topPitch-24 else{return false}
            let endpoint=OrbitDrawing.point(center,radius:radius(n.pitch),phase:clock.seconds(at:min(clock.beats,n.beat+n.length))/clock.seconds)
            return (beat>=n.beat && beat<=n.beat+n.length) || hypot(p.x-endpoint.x,p.y-endpoint.y)<7
        }) {
            original=n;preview=n;store.selectedNoteID=n.id
            let end=OrbitDrawing.point(center,radius:radius(n.pitch),phase:clock.seconds(at:min(clock.beats,n.beat+n.length))/clock.seconds)
            resizing=hypot(p.x-end.x,p.y-end.y)<8
        } else {store.addNote(beat:max(0,min(clock.beats-1/grid, snap(beat))),pitch:pitch,length:1/grid)}
        needsDisplay=true
    }
    var grid:Double {Double(max(1,store.currentContext.beatGrid.subdivisions))}
    override func mouseDragged(with event:NSEvent) {
        guard var n=original,let clock,store.project.musicRevision==revision else{return}
        let p=convert(event.locationInWindow,from:nil),next=phase(p)
        travel+=OrbitTimeline.phaseDelta(from:previousPhase,to:next);previousPhase=next
        let originalBeat=resizing ? n.beat+n.length:n.beat
        let q=snap(clock.beat(atSeconds:clock.seconds(at:originalBeat)+travel*clock.seconds))
        if resizing {n.length=max(1/grid,min(clock.beats-n.beat,q-n.beat))}
        else {n.beat=max(0,min(clock.beats-n.length,q));n.pitch=max(0,min(127,n.pitch+Int(((hypot(p.x-center.x,p.y-center.y)-downRadius)/row).rounded())))}
        preview=n;needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        defer{original=nil;preview=nil;needsDisplay=true}
        guard let n=preview,n != original,store.project.musicRevision==revision,var lane=store.currentLane,lane.id==laneID,let i=lane.notes.firstIndex(where:{$0.id==n.id}) else{return}
        lane.notes[i]=n;store.setLane(lane)
    }
    override func keyDown(with event:NSEvent) {
        if store.handleMIDIKey(event,topPitch:topPitch){needsDisplay=true;return}
        if event.keyCode==53 {original=nil;preview=nil;store.focusCanvas?();store.hierarchyParent()}
        else {super.keyDown(with:event)}
    }
}
