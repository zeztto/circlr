import AppKit
import SwiftUI
import CirclrCore

/// The full performance stays visible while the orbit edits a 12/24-semitone window.
struct MIDIPitchNavigator:NSViewRepresentable {
    @Binding var viewport:MIDIOrbitViewport
    let notes:[Note]
    let selected:Note?
    let identity:NumberEditIdentity
    let focusTarget:MIDIEditorFocus
    func makeNSView(context:Context)->MIDIPitchNavigatorView {MIDIPitchNavigatorView()}
    func updateNSView(_ view:MIDIPitchNavigatorView,context:Context) {
        if view.identity != identity || view.viewport.rows != viewport.rows {view.grabOffset=nil}
        view.identity=identity;view.viewport=viewport;view.pitches=Set(notes.map(\.pitch).filter{(0...127).contains($0)})
        view.selectedPitch=selected?.pitch;view.change={viewport=$0};view.returnFocus={focusTarget.focus()}
        view.setAccessibilityMinValue(0);view.setAccessibilityMaxValue(128-viewport.rows)
        view.setAccessibilityValueDescription("\(view.name(viewport.lowest))–\(view.name(viewport.highest)) · \(viewport.rows)개 반음 · 전체 연주 \(view.pitches.count)개 음높이")
        view.needsDisplay=true
    }
}

@MainActor final class MIDIPitchNavigatorView:NSView {
    var viewport=MIDIOrbitViewport()
    var pitches=Set<Int>(),selectedPitch:Int?
    var identity:NumberEditIdentity?
    var grabOffset:Int?
    var change:(MIDIOrbitViewport)->Void={_ in}
    var returnFocus:()->Void={}
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    var track:NSRect {NSRect(x:7,y:3,width:max(1,bounds.width-14),height:17)}
    var windowRect:NSRect {NSRect(x:track.minX+Double(viewport.lowest)/128*track.width,y:track.minY,width:Double(viewport.rows)/128*track.width,height:track.height)}
    override init(frame:NSRect) {
        super.init(frame:frame);setAccessibilityElement(true);setAccessibilityRole(.slider)
        setAccessibilityLabel("MIDI 전체 음역 탐색")
        let help="표시 범위 드래그 · 클릭해 이동 · 좌우 반음 · Shift 좌우 옥타브 · Home/End 양 끝 · Return/Esc 궤도로 복귀"
        setAccessibilityHelp(help);toolTip=help
    }
    required init?(coder:NSCoder){fatalError()}
    override func becomeFirstResponder()->Bool {needsDisplay=true;return super.becomeFirstResponder()}
    override func resignFirstResponder()->Bool {needsDisplay=true;return super.resignFirstResponder()}
    func name(_ pitch:Int)->String {Scale.roots[pitch%12]+String(pitch/12-1)}
    func apply(_ edit:(inout MIDIOrbitViewport)->Void) {
        var next=viewport;edit(&next)
        guard next != viewport else{return};viewport=next;change(next);needsDisplay=true
        NSAccessibility.post(element:self,notification:.valueChanged)
    }
    override func draw(_ dirtyRect:NSRect) {
        StudioTheme.raisedNS.setFill();NSBezierPath(roundedRect:track,xRadius:3,yRadius:3).fill()
        StudioTheme.accentNS.withAlphaComponent(0.18).setFill();NSBezierPath(rect:windowRect).fill()
        for pitch in pitches.sorted() {
            let x=track.minX+(Double(pitch)+0.5)/128*track.width
            let path=NSBezierPath();path.move(to:NSPoint(x:x,y:track.minY+4));path.line(to:NSPoint(x:x,y:track.maxY-4))
            (pitch==selectedPitch ? StudioTheme.textNS:StudioTheme.accentNS).setStroke();path.lineWidth=1.5;path.stroke()
        }
        StudioTheme.accentNS.setStroke();let border=NSBezierPath(rect:windowRect.insetBy(dx:0.5,dy:0.5));border.lineWidth=window?.firstResponder===self ? 2:1;border.stroke()
        for pitch in stride(from:0,through:120,by:24) {
            let x=track.minX+(Double(pitch)+0.5)/128*track.width
            OrbitDrawing.text(name(pitch),at:NSPoint(x:max(10,min(bounds.width-10,x)),y:29),size:9)
        }
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        let p=convert(event.locationInWindow,from:nil)
        guard track.insetBy(dx:0,dy:-3).contains(p),let pitch=MIDIOrbitViewport.pitch(at:(p.x-track.minX)/track.width) else{grabOffset=nil;return}
        if !windowRect.contains(p) {apply{$0.centerPitch(pitch)}}
        grabOffset=pitch-viewport.lowest
    }
    override func mouseDragged(with event:NSEvent) {
        guard let grabOffset else{return};let p=convert(event.locationInWindow,from:nil)
        guard let pitch=MIDIOrbitViewport.pitch(at:(p.x-track.minX)/track.width) else{return}
        apply{$0.setLowestPitch(pitch-grabOffset)}
    }
    override func mouseUp(with event:NSEvent){grabOffset=nil}
    override func keyDown(with event:NSEvent) {
        switch event.keyCode {
        case 123:apply{$0.movePitches(event.modifierFlags.contains(.shift) ? -12:-1)}
        case 124:apply{$0.movePitches(event.modifierFlags.contains(.shift) ? 12:1)}
        case 115:apply{$0.setLowestPitch(0)}
        case 119:apply{$0.setLowestPitch(127)}
        case 36,76,53:grabOffset=nil;returnFocus()
        default:super.keyDown(with:event)
        }
    }
    override func accessibilityValue()->Any? {viewport.lowest}
    override func setAccessibilityValue(_ value:Any?) {
        guard let number=value as? NSNumber,number.doubleValue.isFinite else{return}
        apply{$0.setLowestPitch(Int(max(0,min(127,number.doubleValue))))}
    }
    override func accessibilityPerformIncrement()->Bool {apply{$0.movePitches(1)};return true}
    override func accessibilityPerformDecrement()->Bool {apply{$0.movePitches(-1)};return true}
}
