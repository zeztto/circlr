import AppKit
import SwiftUI
import CirclrCore

struct OrbitAudioEditor:NSViewRepresentable {
    @ObservedObject var store:AppStore
    let clip:AudioClip
    let asset:Asset
    func makeNSView(context:Context)->OrbitAudioView {OrbitAudioView(store:store,clip:clip,asset:asset)}
    func updateNSView(_ view:OrbitAudioView,context:Context) {view.clip=clip;view.asset=asset;view.needsDisplay=true}
}
@MainActor final class OrbitAudioView:NSView {
    let store:AppStore
    var clip:AudioClip,asset:Asset
    var original:AudioClip?,preview:AudioClip?
    var editingEnd=false,previousPhase=0.0,travel=0.0,revision=0
    var laneID:ID?
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    var center:NSPoint {NSPoint(x:bounds.midX,y:bounds.midY)}
    var outer:Double {max(20,min(bounds.width,bounds.height)/2-20)}
    var waveRadius:Double {outer*0.72}
    init(store:AppStore,clip:AudioClip,asset:Asset) {
        self.store=store;self.clip=clip;self.asset=asset;super.init(frame:.zero)
        setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("오디오 궤도 편집기 · 안쪽 원본 파형의 시작과 끝을 드래그해 구간 편집")
    }
    required init?(coder:NSCoder){fatalError()}
    func phase(_ point:NSPoint)->Double {OrbitTimeline.phase(Point(point.x-center.x,point.y-center.y))}
    func handle(_ seconds:Double,end:Bool)->NSPoint {OrbitDrawing.point(center,radius:waveRadius+(end ? 5:-5),phase:seconds/max(0.001,asset.duration))}
    override func draw(_ dirtyRect:NSRect) {
        let value=preview ?? clip,duration=max(0.001,asset.duration),start=value.sourceStart,end=start+value.duration
        let ring=OrbitDrawing.arc(center,radius:outer,from:0,to:1)
        StudioTheme.lineNS.setStroke();ring.lineWidth=1;ring.stroke()
        if let clock=store.currentClock {
            let rate=value.followsTempo ? clock.bpm(at:value.beat)/value.sourceBPM:1
            let a=clock.seconds(at:value.beat)/clock.seconds,b=min(1,a+value.duration/max(1e-9,rate)/clock.seconds)
            if a<1 {let active=OrbitDrawing.arc(center,radius:outer,from:a,to:b);StudioTheme.accentNS.setStroke();active.lineWidth=4;active.stroke()}
            for tick in OrbitTimeline(clock:clock).ticks.prefix(64) {OrbitDrawing.dot(OrbitDrawing.point(center,radius:outer,phase:tick.seconds/clock.seconds),radius:1.5,color:StudioTheme.secondaryNS)}
        }
        if let waveform=store.waveforms[asset.id] {
            let displayGain=min(64,1/max(0.001,Double(waveform.peaks.max() ?? 0)))
            for i in 0..<720 {
                let t=Double(i)/720*duration,phase=Double(i)/720,amplitude=Double(waveform.peak(at:t))*displayGain*outer*0.15
                let path=NSBezierPath();path.move(to:OrbitDrawing.point(center,radius:waveRadius-amplitude,phase:phase));path.line(to:OrbitDrawing.point(center,radius:waveRadius+amplitude,phase:phase))
                StudioTheme.accentNS.withAlphaComponent(t>=start && t<=end ? 0.9:0.18).setStroke();path.lineWidth=1;path.stroke()
            }
            OrbitDrawing.text(String(format:"파형 표시 ×%.1f",displayGain),at:NSPoint(x:center.x,y:center.y+outer+12),size:9)
        }
        let selected=OrbitDrawing.arc(center,radius:waveRadius,from:start/duration,to:end/duration)
        StudioTheme.accentNS.setStroke();selected.lineWidth=2;selected.stroke()
        let a=handle(start,end:false),b=handle(end,end:true)
        OrbitDrawing.dot(a,radius:6);OrbitDrawing.dot(b,radius:6,color:StudioTheme.textNS)
        OrbitDrawing.text("시작",at:NSPoint(x:a.x,y:a.y-16),size:9,color:StudioTheme.accentNS)
        OrbitDrawing.text("끝",at:NSPoint(x:b.x,y:b.y+15),size:9,color:StudioTheme.textNS)
        OrbitDrawing.text("원본 파일 · 초",at:NSPoint(x:center.x,y:center.y-13),size:10)
        OrbitDrawing.text(String(format:"%.2f → %.2f",start,end),at:NSPoint(x:center.x,y:center.y+5),size:11,color:StudioTheme.textNS)
        OrbitDrawing.text("바깥 원 · 재생 시간",at:NSPoint(x:center.x,y:center.y+24),size:9)
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        let p=convert(event.locationInWindow,from:nil),a=handle(clip.sourceStart,end:false),b=handle(clip.sourceStart+clip.duration,end:true)
        let da=hypot(p.x-a.x,p.y-a.y),db=hypot(p.x-b.x,p.y-b.y)
        guard min(da,db)<14 else{return}
        original=clip;preview=clip;editingEnd=db<da;previousPhase=phase(p);travel=0;revision=store.project.musicRevision;laneID=store.currentLane?.id
    }
    override func mouseDragged(with event:NSEvent) {
        guard var value=original,store.project.musicRevision==revision else{return}
        let p=convert(event.locationInWindow,from:nil),next=phase(p)
        travel+=OrbitTimeline.phaseDelta(from:previousPhase,to:next);previousPhase=next
        let end=value.sourceStart+value.duration
        if editingEnd {value.duration=max(0.01,min(asset.duration-value.sourceStart,value.duration+travel*asset.duration))}
        else {value.sourceStart=max(0,min(end-0.01,value.sourceStart+travel*asset.duration));value.duration=end-value.sourceStart}
        preview=value;needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        defer{preview=nil;original=nil;needsDisplay=true}
        guard let value=preview,value != original,store.project.musicRevision==revision,var lane=store.currentLane,lane.id==laneID,let i=lane.audio.firstIndex(where:{$0.id==value.id}) else{return}
        lane.audio[i]=value;store.setLane(lane)
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode==53 {preview=nil;original=nil;store.hierarchyParent()}
        else if event.keyCode==49 {store.play()}
        else {super.keyDown(with:event)}
    }
}
