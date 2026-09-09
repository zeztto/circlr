import AppKit
import SwiftUI
import CirclrCore

struct OrbitAudioEditor:NSViewRepresentable {
    @ObservedObject var store:AppStore
    let clip:AudioClip
    let asset:Asset
    @Binding var viewport:AudioSourceViewport
    let focusTarget:AudioEditorFocus
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context:Context)->OrbitAudioView {
        let view=OrbitAudioView(store:store,clip:clip,asset:asset);focusTarget.view=view;return view
    }
    func updateNSView(_ view:OrbitAudioView,context:Context) {
        if !enabled || view.clip.id != clip.id || view.asset.id != asset.id || view.viewport != viewport || (view.dragIdentity != nil && !view.dragIsCurrent) {view.cancelDrag()}
        view.clip=clip;view.asset=asset;view.viewport=viewport;view.allowsEditing=enabled;view.needsDisplay=true
        let identity=store.numberEditIdentity
        view.editIdentity=identity
        view.viewportChanged={value in guard store.numberEditIdentity==identity else{return};viewport=value}
        let range=viewport.range(assetDuration:asset.duration)
        view.setAccessibilityLabel(store.project.usesOrbits ? "오디오 궤도 편집기":"오디오 파형 편집기")
        view.setAccessibilityValueDescription(String(format:"원본 표시 %.3f부터 %.3f초 · 선택 %.3f부터 %.3f초 · 분할 %.3f초",range.lowerBound,range.upperBound,clip.sourceStart,clip.sourceStart+clip.duration,store.audioCutOffset))
    }
}
@MainActor final class OrbitAudioView:NSView {
    let store:AppStore
    var clip:AudioClip,asset:Asset
    var viewport=AudioSourceViewport()
    var editIdentity:NumberEditIdentity?
    var viewportChanged:(AudioSourceViewport)->Void={_ in}
    var original:AudioClip?,preview:AudioClip?
    var editingEnd=false,previousPhase=0.0,travel=0.0,allowsEditing=true
    var dragIdentity:NumberEditIdentity?,dragViewport:AudioSourceViewport?,dragOrbital:Bool?,dragBounds:NSRect?
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    var center:NSPoint {NSPoint(x:bounds.midX,y:bounds.midY)}
    var outer:Double {max(20,min(bounds.width,bounds.height)/2-24)}
    var waveRadius:Double {outer*0.72}
    var sourceRange:ClosedRange<Double> {viewport.range(assetDuration:asset.duration)}
    var span:Double {sourceRange.upperBound-sourceRange.lowerBound}
    var plot:NSRect {bounds.insetBy(dx:12,dy:22)}
    var orbital:Bool {store.project.usesOrbits}
    var isCurrent:Bool {allowsEditing && window != nil && editIdentity==store.numberEditIdentity && store.currentAudioClip?.id==clip.id && store.currentAudioClip?.assetID==asset.id}
    var dragIsCurrent:Bool {isCurrent && dragIdentity==store.numberEditIdentity && dragViewport==viewport && dragOrbital==orbital && dragBounds==bounds}
    init(store:AppStore,clip:AudioClip,asset:Asset) {
        self.store=store;self.clip=clip;self.asset=asset;super.init(frame:.zero)
        setAccessibilityElement(true);setAccessibilityRole(.group)
        toolTip="휠: 확대·축소 · 가로 휠/⇧휠: 시간 이동 · −/+: 확대·축소 · Page Up/Down: 이동 · Home/End: 파일 처음/끝 · 0: 전체 · F: 선택 · C: 커서 보기 · 파형 클릭: 분할 위치 · ← →: 시작 trim · ⌥← →: 끝 trim · ⇧: 0.1초 · ⌘T: 분할 · ⌘D: 복제"
        setAccessibilityHelp(toolTip)
    }
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window==nil{cancelDrag();return}
        DispatchQueue.main.async{[weak self] in guard let self,self.isCurrent,let window=self.window,!(window.firstResponder is NSTextView) else{return};window.makeFirstResponder(self)}
    }
    func cancelDrag(){original=nil;preview=nil;dragIdentity=nil;dragViewport=nil;dragOrbital=nil;dragBounds=nil}
    func phase(_ point:NSPoint)->Double {orbital ? OrbitTimeline.phase(Point(point.x-center.x,point.y-center.y)):max(0,min(1,(point.x-plot.minX)/max(1,plot.width)))}
    func visible(_ seconds:Double)->Bool {viewport.contains(seconds,assetDuration:asset.duration)}
    func handle(_ seconds:Double,end:Bool)->NSPoint {
        let phase=viewport.phase(at:seconds,assetDuration:asset.duration)
        return orbital ? OrbitDrawing.point(center,radius:waveRadius+(end ? 5:-5),phase:phase):NSPoint(x:plot.minX+phase*plot.width,y:bounds.midY)
    }
    override func draw(_ dirtyRect:NSRect) {
        guard bounds.width>24,bounds.height>44 else{return}
        let value=preview ?? clip,start=value.sourceStart,end=start+value.duration
        if !orbital {drawLinear(value);return}
        let ring=OrbitDrawing.arc(center,radius:outer,from:0,to:1)
        StudioTheme.lineNS.setStroke();ring.lineWidth=1;ring.stroke()
        if let clock=store.sectionClock,let node=store.selectedMusic {
            let timing=AudioClipTiming(node:node,context:store.currentContext,clock:clock)
            let a=timing.time(value.beat)/clock.seconds,b=min(1,a+value.duration/max(1e-9,timing.rate(value))/clock.seconds)
            if a<1 {let active=OrbitDrawing.arc(center,radius:outer,from:max(0,a),to:b);StudioTheme.accentNS.setStroke();active.lineWidth=4;active.stroke()}
            for tick in OrbitTimeline(clock:clock).ticks.prefix(64) {OrbitDrawing.dot(OrbitDrawing.point(center,radius:outer,phase:tick.seconds/clock.seconds),radius:1.5,color:StudioTheme.secondaryNS)}
        }
        if let waveform=store.waveforms[asset.id] {
            let displayGain=min(64,1/max(0.001,Double(waveform.peaks.max() ?? 0)))
            for i in 0..<720 {
                let phase=Double(i)/720,t=viewport.source(at:phase,assetDuration:asset.duration)
                let amplitude=Double(waveform.peak(at:t))*displayGain*outer*0.15*envelopeGain(value,t)
                let path=NSBezierPath();path.move(to:OrbitDrawing.point(center,radius:waveRadius-amplitude,phase:phase));path.line(to:OrbitDrawing.point(center,radius:waveRadius+amplitude,phase:phase))
                StudioTheme.accentNS.withAlphaComponent(t>=start && t<=end ? 0.9:0.18).setStroke();path.lineWidth=1;path.stroke()
            }
        }
        let from=max(0,viewport.phase(at:start,assetDuration:asset.duration)),to=min(1,viewport.phase(at:end,assetDuration:asset.duration))
        if from<to {let selected=OrbitDrawing.arc(center,radius:waveRadius,from:from,to:to);StudioTheme.accentNS.setStroke();selected.lineWidth=2;selected.stroke()}
        for (source,isEnd,label) in [(start,false,"시작"),(end,true,"끝")] where visible(source) {
            let p=handle(source,end:isEnd),color=isEnd ? StudioTheme.textNS:StudioTheme.accentNS
            OrbitDrawing.dot(p,radius:6,color:color)
            OrbitDrawing.text(label,at:NSPoint(x:p.x,y:p.y+(isEnd ? 16:-16)),size:10,color:color)
        }
        let cut=clip.sourceStart+store.audioCutOffset
        if visible(cut) {let cursor=OrbitDrawing.point(center,radius:waveRadius,phase:viewport.phase(at:cut,assetDuration:asset.duration));OrbitDrawing.dot(cursor,radius:4,color:StudioTheme.textNS)}
        if outer>55 {
            OrbitDrawing.text("원본 초",at:NSPoint(x:center.x,y:center.y-10),size:11)
            OrbitDrawing.text(String(format:span<1 ? "%.3f–%.3f":"%.2f–%.2f",sourceRange.lowerBound,sourceRange.upperBound),at:NSPoint(x:center.x,y:center.y+8),size:11,color:StudioTheme.textNS)
        }
        OrbitDrawing.text("바깥 궤도 · 섹션 내 첫 재생",at:NSPoint(x:center.x,y:bounds.maxY-10),size:10)
    }
    func envelopeGain(_ value:AudioClip,_ source:Double)->Double {
        guard source>=value.sourceStart,source<=value.sourceStart+value.duration else{return 1}
        return (value.renderWindow?.envelopes ?? []).reduce(value.explicitEnvelope?.gain(at:source) ?? 1){$0*$1.gain(at:source)}
    }
    func drawLinear(_ value:AudioClip) {
        StudioTheme.canvasNS.setFill();bounds.fill()
        let start=value.sourceStart,end=start+value.duration
        let ticks=plot.width>320 ? 4:2
        for i in 0...ticks {
            let phase=Double(i)/Double(ticks),x=plot.minX+phase*plot.width
            let line=NSBezierPath();line.move(to:NSPoint(x:x,y:plot.minY));line.line(to:NSPoint(x:x,y:plot.maxY));StudioTheme.lineNS.setStroke();line.stroke()
            let label=String(format:span<1 ? "%.3f":"%.2f",viewport.source(at:phase,assetDuration:asset.duration))
            let half=(label as NSString).size(withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.regular)]).width/2+2
            OrbitDrawing.text(label,at:NSPoint(x:min(bounds.maxX-half,max(half,x)),y:10),size:10)
        }
        if let wave=store.waveforms[asset.id] {
            let scale=min(64,1/max(0.001,Double(wave.peaks.max() ?? 0)))
            for x in stride(from:plot.minX,to:plot.maxX,by:1.5) {
                let time=viewport.source(at:(x-plot.minX)/plot.width,assetDuration:asset.duration)
                let a=Double(wave.peak(at:time))*scale*plot.height*0.4*envelopeGain(value,time)
                let path=NSBezierPath();path.move(to:NSPoint(x:x,y:bounds.midY-a));path.line(to:NSPoint(x:x,y:bounds.midY+a))
                StudioTheme.accentNS.withAlphaComponent(time>=start && time<=end ? 0.8:0.18).setStroke();path.stroke()
            }
        }
        for (source,isEnd,label) in [(start,false,"시작"),(end,true,"끝")] where visible(source) {
            let p=handle(source,end:isEnd),path=NSBezierPath();path.move(to:NSPoint(x:p.x,y:plot.minY));path.line(to:NSPoint(x:p.x,y:plot.maxY))
            (isEnd ? StudioTheme.textNS:StudioTheme.accentNS).setStroke();path.lineWidth=2;path.stroke();OrbitDrawing.dot(p,radius:5,color:isEnd ? StudioTheme.textNS:StudioTheme.accentNS)
            OrbitDrawing.text(label,at:NSPoint(x:min(bounds.width-16,max(16,p.x)),y:bounds.maxY-10),size:10)
        }
        let cut=clip.sourceStart+store.audioCutOffset
        if visible(cut) {
            let x=handle(cut,end:false).x,line=NSBezierPath();line.move(to:NSPoint(x:x,y:plot.minY));line.line(to:NSPoint(x:x,y:plot.maxY));StudioTheme.textNS.setStroke();line.setLineDash([3,3],count:2,phase:0);line.stroke()
        }
    }
    override func mouseDown(with event:NSEvent) {
        guard isCurrent else{return};window?.makeFirstResponder(self);cancelDrag()
        let p=convert(event.locationInWindow,from:nil),a=handle(clip.sourceStart,end:false),b=handle(clip.sourceStart+clip.duration,end:true)
        if !orbital && !plot.contains(p){return}
        let da=visible(clip.sourceStart) ? (orbital ? hypot(p.x-a.x,p.y-a.y):abs(p.x-a.x)):Double.infinity
        let db=visible(clip.sourceStart+clip.duration) ? (orbital ? hypot(p.x-b.x,p.y-b.y):abs(p.x-b.x)):Double.infinity
        guard min(da,db)<14 else {
            if orbital && abs(hypot(p.x-center.x,p.y-center.y)-waveRadius)>max(16,outer*0.2){return}
            let source=viewport.source(at:phase(p),assetDuration:asset.duration);store.audioSplitOffset=max(0,min(clip.duration,source-clip.sourceStart));needsDisplay=true;return
        }
        original=clip;preview=clip;editingEnd=db<da;previousPhase=phase(p);travel=0
        dragIdentity=store.numberEditIdentity;dragViewport=viewport;dragOrbital=orbital;dragBounds=bounds
    }
    override func mouseDragged(with event:NSEvent) {
        guard let value=original,dragIsCurrent else{cancelDrag();needsDisplay=true;return}
        let next=phase(convert(event.locationInWindow,from:nil))
        travel+=orbital ? OrbitTimeline.phaseDelta(from:previousPhase,to:next):next-previousPhase;previousPhase=next
        preview=AudioTrimBounds(clip:value,asset:asset).trimming(value,to:value.sourceStart+(editingEnd ? value.duration:0)+travel*span,editingEnd:editingEnd)
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        defer{cancelDrag();needsDisplay=true}
        guard let value=preview,value != original,dragIsCurrent else{return}
        store.editAudioClip(clip){$0=value}
    }
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        if isCurrent,window?.firstResponder===self,event.modifierFlags.contains(.command),store.handleAudioEditKey(event){needsDisplay=true;return true}
        return super.performKeyEquivalent(with:event)
    }
    func changeViewport(_ edit:(inout AudioSourceViewport)->Void) {
        guard isCurrent else{return}
        cancelDrag();edit(&viewport);viewportChanged(viewport);needsDisplay=true
    }
    func zoom(_ factor:Double) {
        let cursor=clip.sourceStart+store.audioCutOffset,anchor=visible(cursor) ? cursor:(sourceRange.lowerBound+sourceRange.upperBound)/2
        changeViewport{$0.zoom(by:factor,around:anchor,assetDuration:asset.duration)}
    }
    override func scrollWheel(with event:NSEvent) {
        guard isCurrent else{return}
        guard !event.modifierFlags.contains(.command),!event.modifierFlags.contains(.control),!event.modifierFlags.contains(.option) else {super.scrollWheel(with:event);return}
        if !(window?.firstResponder is NSTextView){window?.makeFirstResponder(self)}
        let horizontal=abs(event.scrollingDeltaX)>abs(event.scrollingDeltaY),shift=event.modifierFlags.contains(.shift)
        if horizontal || shift {
            let delta=horizontal ? event.scrollingDeltaX:event.scrollingDeltaY
            let seconds = -delta*span*(event.hasPreciseScrollingDeltas ? 0.002:0.05)
            changeViewport{$0.pan(by:seconds,assetDuration:asset.duration)}
        } else {
            let power=max(-1,min(1,event.scrollingDeltaY*(event.hasPreciseScrollingDeltas ? 0.01:0.15)))
            let anchor=viewport.source(at:phase(convert(event.locationInWindow,from:nil)),assetDuration:asset.duration)
            changeViewport{$0.zoom(by:pow(2,power),around:anchor,assetDuration:asset.duration)}
        }
    }
    func handleViewportKey(_ event:NSEvent)->Bool {
        guard !event.modifierFlags.contains(.option) else{return false}
        let halfSpan=span/2
        switch event.keyCode {
        case 27,78:zoom(0.5)
        case 24,69:zoom(2)
        case 116:changeViewport{$0.pan(by:-halfSpan,assetDuration:asset.duration)}
        case 121:changeViewport{$0.pan(by:halfSpan,assetDuration:asset.duration)}
        case 115:changeViewport{$0.pan(by:-asset.duration,assetDuration:asset.duration)}
        case 119:changeViewport{$0.pan(by:asset.duration,assetDuration:asset.duration)}
        case 29,82:changeViewport{$0.showAll()}
        case 3:changeViewport{$0.fit(clip,assetDuration:asset.duration)}
        case 8:changeViewport{$0.reveal(clip.sourceStart+store.audioCutOffset,assetDuration:asset.duration)}
        default:return false
        }
        return true
    }
    override func keyDown(with event:NSEvent) {
        guard isCurrent else{return}
        if store.handleAudioEditKey(event){needsDisplay=true;return}
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {super.keyDown(with:event);return}
        if handleViewportKey(event){return}
        if store.handleAudioTrimKey(event,clipID:clip.id){needsDisplay=true;return}
        if event.keyCode==53 {cancelDrag();store.focusCanvas?();store.hierarchyParent()}
        else if event.keyCode==49 {store.play()}
        else {super.keyDown(with:event)}
    }
}
