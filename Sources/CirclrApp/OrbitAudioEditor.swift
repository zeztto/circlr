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
    var orbital:Bool {store.project.usesOrbits}
    func phase(_ point:NSPoint)->Double {orbital ? OrbitTimeline.phase(Point(point.x-center.x,point.y-center.y)):max(0,min(1,point.x/max(1,bounds.width)))}
    func handle(_ seconds:Double,end:Bool)->NSPoint {orbital ? OrbitDrawing.point(center,radius:waveRadius+(end ? 5:-5),phase:seconds/max(0.001,asset.duration)):NSPoint(x:seconds/max(0.001,asset.duration)*bounds.width,y:bounds.midY)}
    override func draw(_ dirtyRect:NSRect) {
        let value=preview ?? clip,duration=max(0.001,asset.duration),start=value.sourceStart,end=start+value.duration
        if !orbital {drawLinear(value);return}
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
                let t=Double(i)/720*duration,phase=Double(i)/720,amplitude=Double(waveform.peak(at:t))*displayGain*outer*0.15*envelopeGain(value,t)
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
        let cursor=OrbitDrawing.point(center,radius:waveRadius,phase:(clip.sourceStart+store.audioCutOffset)/duration)
        OrbitDrawing.dot(cursor,radius:4,color:StudioTheme.textNS)
        if outer>65 {
            OrbitDrawing.text("원본 파일 · 초",at:NSPoint(x:center.x,y:center.y-13),size:10)
            OrbitDrawing.text(String(format:"%.2f → %.2f",start,end),at:NSPoint(x:center.x,y:center.y+5),size:11,color:StudioTheme.textNS)
        }
    }
    func envelopeGain(_ value:AudioClip,_ source:Double)->Double {
        guard source>=value.sourceStart,source<=value.sourceStart+value.duration else{return 1}
        return (value.renderWindow?.envelopes ?? []).reduce(value.explicitEnvelope?.gain(at:source) ?? 1){$0*$1.gain(at:source)}
    }
    func drawLinear(_ value:AudioClip) {
        StudioTheme.canvasNS.setFill();bounds.fill()
        let duration=max(0.001,asset.duration),start=value.sourceStart/duration*bounds.width,end=(value.sourceStart+value.duration)/duration*bounds.width
        if let wave=store.waveforms[asset.id] {
            let scale=min(64,1/max(0.001,Double(wave.peaks.max() ?? 0)))
            for x in stride(from:0.0,to:bounds.width,by:1.5) {
                let time=x/max(1,bounds.width)*duration,a=Double(wave.peak(at:time))*scale*bounds.height*0.4*envelopeGain(value,time)
                let path=NSBezierPath();path.move(to:NSPoint(x:x,y:bounds.midY-a));path.line(to:NSPoint(x:x,y:bounds.midY+a))
                StudioTheme.accentNS.withAlphaComponent(x>=start && x<=end ? 0.8:0.18).setStroke();path.stroke()
            }
        }
        for (x,label) in [(start,"시작"),(end,"끝")] {let path=NSBezierPath();path.move(to:NSPoint(x:x,y:0));path.line(to:NSPoint(x:x,y:bounds.height));StudioTheme.accentNS.setStroke();path.stroke();OrbitDrawing.text(label,at:NSPoint(x:min(bounds.width-16,max(16,x)),y:10),size:10)}
        let x=(clip.sourceStart+store.audioCutOffset)/duration*bounds.width,line=NSBezierPath();line.move(to:NSPoint(x:x,y:0));line.line(to:NSPoint(x:x,y:bounds.height));StudioTheme.textNS.setStroke();line.setLineDash([3,3],count:2,phase:0);line.stroke()
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        let p=convert(event.locationInWindow,from:nil),a=handle(clip.sourceStart,end:false),b=handle(clip.sourceStart+clip.duration,end:true)
        let da=orbital ? hypot(p.x-a.x,p.y-a.y):abs(p.x-a.x),db=orbital ? hypot(p.x-b.x,p.y-b.y):abs(p.x-b.x)
        guard min(da,db)<14 else {let source=phase(p)*asset.duration;store.audioSplitOffset=max(0,min(clip.duration,source-clip.sourceStart));needsDisplay=true;return}
        original=clip;preview=clip;editingEnd=db<da;previousPhase=phase(p);travel=0;revision=store.project.musicRevision;laneID=store.currentLane?.id
    }
    override func mouseDragged(with event:NSEvent) {
        guard var value=original,store.project.musicRevision==revision else{return}
        let p=convert(event.locationInWindow,from:nil),next=phase(p)
        travel+=orbital ? OrbitTimeline.phaseDelta(from:previousPhase,to:next):next-previousPhase;previousPhase=next
        let end=value.sourceStart+value.duration
        let lower=value.renderWindow?.sourceStart ?? 0,upper=value.renderWindow.map{$0.sourceStart+$0.duration} ?? asset.duration
        if editingEnd {value.duration=max(0.01,min(upper-value.sourceStart,value.duration+travel*asset.duration))}
        else {value.sourceStart=max(lower,min(end-0.01,value.sourceStart+travel*asset.duration));value.duration=end-value.sourceStart}
        preview=value;needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        defer{preview=nil;original=nil;needsDisplay=true}
        guard let value=preview,value != original,store.project.musicRevision==revision,let lane=store.currentLane,lane.id==laneID,let i=lane.audio.firstIndex(where:{$0.id==value.id}) else{return}
        store.editAudioClip(lane.audio[i]){$0=value}
    }
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        if window?.firstResponder===self,event.modifierFlags.contains(.command),store.handleAudioEditKey(event){needsDisplay=true;return true}
        return super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event:NSEvent) {
        if store.handleAudioEditKey(event){needsDisplay=true;return}
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {super.keyDown(with:event);return}
        if store.handleAudioTrimKey(event,clipID:clip.id){needsDisplay=true;return}
        if event.keyCode==53 {preview=nil;original=nil;store.focusCanvas?();store.hierarchyParent()}
        else if event.keyCode==49 {store.play()}
        else {super.keyDown(with:event)}
    }
}
