import AppKit
import SwiftUI
import CirclrCore

struct AudioLane:NSViewRepresentable {
    @ObservedObject var store:AppStore
    func makeNSView(context:Context)->AudioLaneView {AudioLaneView(store:store)}
    func updateNSView(_ view:AudioLaneView,context:Context) {view.needsDisplay=true}
}
@MainActor final class AudioLaneView:NSView {
    let store:AppStore
    let left=60.0,unit=48.0
    var original:AudioClip?,preview:AudioClip?,down=NSPoint.zero
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    var clips:[AudioClip] {store.currentLane?.audio ?? []}
    init(store:AppStore) {
        self.store=store;super.init(frame:.zero)
        setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("오디오 시간축. 클립을 드래그해서 시작 박을 옮깁니다.")
    }
    required init?(coder:NSCoder){fatalError()}
    func rect(_ clip:AudioClip,index:Int)->NSRect {
        let length=store.currentClock.map{AudioClipGeometry.visibleBeats(clip,clock:$0)} ?? clip.duration*(clip.followsTempo ? clip.sourceBPM:store.currentContext.tempo)/60
        return NSRect(x:left+clip.beat*unit,y:9+Double(index)*36,width:max(5,length*unit),height:27)
    }
    override func draw(_ dirtyRect:NSRect) {
        StudioTheme.canvasNS.setFill();bounds.fill()
        ("오디오" as NSString).draw(at:NSPoint(x:7,y:17),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:StudioTheme.secondaryNS])
        let first=max(0,Int((visibleRect.minX-left)/unit)),last=min(131072,Int((visibleRect.maxX-left)/unit)+1)
        if first<=last {for beat in first...last {StudioTheme.lineNS.withAlphaComponent(0.5).setStroke();let p=NSBezierPath();p.move(to:NSPoint(x:left+Double(beat)*unit,y:0));p.line(to:NSPoint(x:left+Double(beat)*unit,y:bounds.height));p.lineWidth=0.5;p.stroke()}}
        if clips.isEmpty {
            ("오디오 가져오기 또는 녹음으로 이 시간축에 추가" as NSString).draw(at:NSPoint(x:left+12,y:18),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:StudioTheme.secondaryNS])
        }
        for (index,item) in clips.enumerated() {
            let clip=preview?.id==item.id ? preview!:item,r=rect(clip,index:index)
            StudioTheme.accentNS.withAlphaComponent(store.selectedClipID==clip.id ? 0.27:0.12).setFill()
            StudioTheme.accentNS.withAlphaComponent(0.7).setStroke()
            let path=NSBezierPath(roundedRect:r,xRadius:3,yRadius:3);path.fill();path.stroke()
            NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:r.insetBy(dx:3,dy:1)).addClip()
            let name=store.project.assets.first{$0.id==clip.assetID}?.name ?? "미디어 없음"
            (name as NSString).draw(at:NSPoint(x:r.minX+6,y:r.minY+7),withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.medium),.foregroundColor:StudioTheme.textNS])
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self);down=convert(event.locationInWindow,from:nil)
        guard down.x>=left else{return}
        store.selectedNoteID=nil
        if let match=clips.enumerated().reversed().first(where:{rect($0.element,index:$0.offset).contains(down)}) {
            original=match.element;preview=match.element;store.selectedClipID=match.element.id
        } else {store.selectedBeat=max(0,min(store.editorBeats,(down.x-left)/unit))}
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard var clip=original else{return};let p=convert(event.locationInWindow,from:nil)
        let subdivisions=Double(max(1,store.currentContext.beatGrid.subdivisions))
        clip.beat=max(0,min(store.editorBeats-1/subdivisions,((clip.beat+(p.x-down.x)/unit)*subdivisions).rounded()/subdivisions))
        preview=clip;needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        if let clip=preview,var lane=store.currentLane,let i=lane.audio.firstIndex(where:{$0.id==clip.id}) {lane.audio[i]=clip;store.setLane(lane)}
        original=nil;preview=nil;needsDisplay=true
    }
    override func keyDown(with event:NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control){super.keyDown(with:event);return}
        if store.handleAudioTrimKey(event,clipID:store.selectedClipID){needsDisplay=true;return}
        if event.keyCode==51 || event.keyCode==117,let id=store.selectedClipID,var lane=store.currentLane {lane.audio.removeAll{$0.id==id};store.setLane(lane);store.selectedClipID=nil}
        else if event.keyCode==53 {store.focusCanvas?();store.hierarchyParent()}
        else if event.keyCode==49 {store.play()}
        else {super.keyDown(with:event)}
    }
}
