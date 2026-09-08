import AppKit
import SwiftUI
import CirclrCore
import CirclrAudio

struct SectionEditor:View {
    @ObservedObject var store:AppStore
    @State private var topPitch=72
    private var identity:String {"\(store.editPatternID ?? store.selectedUse?.id ?? ""):\(store.selectedTrackID ?? "")"}
    private var clips:[AudioClip] {store.currentLane?.audio ?? []}
    private var chosenClip:AudioClip? {clips.first{$0.id==store.selectedClipID} ?? clips.first}
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            trackStrip
            trackControls
            HStack(spacing:12) {
                Text("MIDI · \(store.currentLane?.notes.count ?? 0)개 노트").font(.system(size:11,weight:.medium))
                if let id=store.selectedNoteID,let note=store.currentLane?.notes.first(where:{$0.id==id}) {
                    ValueField(title:"Velocity",value:Binding(get:{Double(store.currentLane?.notes.first{$0.id==id}?.velocity ?? note.velocity)},set:{v in guard var lane=store.currentLane,let i=lane.notes.firstIndex(where:{$0.id==id}) else{return};lane.notes[i].velocity=Int(v);store.setLane(lane)}),width:48,range:1...127,integerOnly:true)
                }
                Spacer()
                Button {topPitch=max(26,topPitch-12)} label:{Image(systemName:"minus")}.help("한 옥타브 아래")
                Text("\(Scale.roots[topPitch%12])\(topPitch/12-1)").font(.system(size:11)).monospacedDigit()
                Button {topPitch=min(127,topPitch+12)} label:{Image(systemName:"plus")}.help("한 옥타브 위")
                Button {store.startMIDIRecording()} label:{Label(store.midiRecording ? "녹음 정지":"MIDI 녹음",systemImage:"record.circle")}.disabled(store.editPatternID != nil || store.audioRecording)
                Button {store.startAudioRecording()} label:{Label(store.audioRecording ? "녹음 정지":"오디오 녹음",systemImage:"record.circle")}.disabled(store.editPatternID != nil || store.midiRecording)
                Button {store.importAudio()} label:{Label("오디오 가져오기",systemImage:"plus")}
            }.font(.system(size:11))
            GeometryReader {geometry in
                ScrollView(.horizontal) {
                    VStack(spacing:0) {
                        ScrollView(.vertical) {PianoRoll(store:store,topPitch:topPitch).frame(height:562)}.frame(height:180)
                        Rectangle().fill(StudioTheme.line).frame(height:1)
                        ScrollView(.vertical) {AudioLane(store:store).frame(height:max(62,Double(clips.count)*36+14))}.frame(height:clips.count>1 ? 82:62)
                    }.frame(width:max(geometry.size.width,store.editorBeats*48+64))
                }.defaultScrollAnchor(.topLeading).id(identity)
            }.frame(height:clips.count>1 ? 278:258).background(StudioTheme.canvas).overlay(Rectangle().strokeBorder(StudioTheme.line))
            if let clip=chosenClip {AudioClipFields(store:store,clip:clip)}
            HStack {
                Text("건반으로 미리 듣기 · 빈 칸에 노트 입력 · 드래그로 이동 · 끝으로 길이 조절")
                Spacer()
                let takes=(store.project.takes ?? []).filter{$0.useID==store.selectedUse?.id && $0.lane.trackID==store.selectedTrackID}
                if !takes.isEmpty {Menu("녹음 Take") {ForEach(takes){take in Button(take.name){store.activateTake(take)}}}.menuStyle(.borderlessButton).fixedSize()}
            }.font(.system(size:10)).foregroundStyle(StudioTheme.secondary)
        }.onAppear{topPitch=store.selectedTrack?.instrument.drums == true ? 48:72}
        .onChange(of:store.selectedTrackID){_,_ in topPitch=store.selectedTrack?.instrument.drums == true ? 48:72}
    }
    private var trackStrip:some View {
        HStack(spacing:12) {
            Text("트랙").font(.system(size:11,weight:.semibold))
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:6){ForEach(store.project.tracks.filter{store.editPatternID==nil || $0.id==store.selectedTrackID}){track in
                    let selected=store.selectedTrackID==track.id
                    Button {store.selectTrack(track.id)} label:{
                        HStack(spacing:6){Image(systemName:track.instrument.drums ? "circle.grid.3x3":"pianokeys");Text(track.name);let lane=store.lane(for:track.id);if !(lane?.notes.isEmpty ?? true) || !(lane?.audio.isEmpty ?? true){Circle().fill(StudioTheme.accent).frame(width:4,height:4)}}.font(.system(size:11,weight:selected ? .semibold:.regular))
                    }.foregroundStyle(selected ? StudioTheme.accent:StudioTheme.secondary).background(selected ? StudioTheme.raised:Color.clear,in:RoundedRectangle(cornerRadius:5))
                }}
            }
            Button {store.addTrack()} label:{Label("트랙 추가",systemImage:"plus")}.disabled(store.editPatternID != nil)
            Toggle("공유 원본 편집",isOn:$store.editOriginal).controlSize(.mini).fixedSize().disabled(store.editPatternID != nil)
        }.font(.system(size:11))
    }
    @ViewBuilder private var trackControls:some View {
        if let track=store.selectedTrack {
            HStack(spacing:16) {
                TextField("트랙 이름",text:Binding(get:{track.name},set:{v in store.updateTrack("트랙 이름"){$0.name=v}})).textFieldStyle(.plain).font(.system(size:12,weight:.medium)).frame(width:130)
                Menu {
                    Button("기본 Sound Bank"){store.updateTrack("악기"){$0.instrument.kind = .soundBank}}
                    ForEach(store.instruments){plugin in Button(plugin.name){store.updateTrack("악기"){$0.instrument.kind = .audioUnit;$0.instrument.plugin=plugin}}}
                } label:{Text(track.instrument.kind == .soundBank ? "Sound Bank":track.instrument.plugin?.name ?? "악기 선택").lineLimit(1)}.menuStyle(.borderlessButton).frame(maxWidth:220,alignment:.leading)
                if track.instrument.kind == .soundBank {
                    CountControl(title:"GM",value:Binding(get:{(store.project.tracks.first{$0.id==track.id}?.instrument.program ?? track.instrument.program)+1},set:{v in store.updateTrack("GM Program"){$0.instrument.program=v-1}}),range:1...128)
                    Toggle("드럼",isOn:Binding(get:{track.instrument.drums},set:{v in store.updateTrack("드럼"){$0.instrument.drums=v}})).controlSize(.mini).fixedSize()
                } else {Button("Plugin 열기"){store.showPluginEditor(effect:false)}.disabled(track.instrument.plugin==nil)}
                Spacer(minLength:0)
                ValueField(title:"트랙 볼륨",value:Binding(get:{store.project.tracks.first{$0.id==track.id}?.gain ?? track.gain},set:{v in store.updateTrack("트랙 볼륨"){$0.gain=v}}),width:52,range:0...4)
                Button {store.updateTrack("음소거"){$0.muted.toggle()}} label:{Image(systemName:track.muted ? "speaker.slash.fill":"speaker.wave.2").foregroundStyle(track.muted ? StudioTheme.accent:StudioTheme.secondary)}.help("트랙 음소거")
            }.font(.system(size:11))
        }
    }
}
struct AudioClipFields:View {
    @ObservedObject var store:AppStore
    let clip:AudioClip
    func edit(_ block:(inout AudioClip)->Void) {guard var lane=store.currentLane,let i=lane.audio.firstIndex(where:{$0.id==clip.id}) else{return};block(&lane.audio[i]);store.setLane(lane)}
    var body:some View {
        HStack(spacing:12) {
            CompactChoice(selection:Binding(get:{clip.id},set:{store.selectedClipID=$0}),options:(store.currentLane?.audio ?? []).map{c in(c.id,store.project.assets.first{$0.id==c.assetID}?.name ?? "미디어 없음")},label:"오디오 클립").frame(maxWidth:150,alignment:.leading)
            ValueField(title:"시작 박",value:Binding(get:{store.currentLane?.audio.first{$0.id==clip.id}?.beat ?? clip.beat},set:{v in edit{$0.beat=v}}),width:48,range:0...131072)
            ValueField(title:"원본 초",value:Binding(get:{store.currentLane?.audio.first{$0.id==clip.id}?.sourceStart ?? clip.sourceStart},set:{v in edit{$0.sourceStart=v}}),width:48,range:0...Double.greatestFiniteMagnitude)
            ValueField(title:"길이 초",value:Binding(get:{store.currentLane?.audio.first{$0.id==clip.id}?.duration ?? clip.duration},set:{v in edit{$0.duration=v}}),width:48,range:0.01...Double.greatestFiniteMagnitude)
            ValueField(title:"볼륨",value:Binding(get:{store.currentLane?.audio.first{$0.id==clip.id}?.gain ?? clip.gain},set:{v in edit{$0.gain=v}}),width:44,range:0...4)
            Toggle("템포 추종",isOn:Binding(get:{clip.followsTempo},set:{v in edit{$0.followsTempo=v}})).controlSize(.mini).fixedSize()
            ValueField(title:"원본 BPM",value:Binding(get:{store.currentLane?.audio.first{$0.id==clip.id}?.sourceBPM ?? clip.sourceBPM},set:{v in edit{$0.sourceBPM=v}}),width:48,range:1...999)
            Button {guard var lane=store.currentLane else{return};lane.audio.removeAll{$0.id==clip.id};store.setLane(lane);store.selectedClipID=nil} label:{Image(systemName:"trash")}.help("오디오 클립 제거")
        }.font(.system(size:10))
    }
}
struct CompactNumber:View {
    let title:String;@Binding var value:Double
    var range:ClosedRange<Double>
    init(_ title:String,value:Binding<Double>,range:ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude){self.title=title;_value=value;self.range=range}
    var body:some View {
        HStack(spacing:8){Text(title).font(.system(size:12));Spacer(minLength:2);CommittedNumberField(title:title,value:$value,range:range,width:80)}
    }
}
struct PianoRoll:NSViewRepresentable {
    @ObservedObject var store:AppStore;let topPitch:Int
    var focusTarget:MIDIEditorFocus?=nil
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context:Context)->PianoRollView{let view=PianoRollView(store:store);focusTarget?.view=view;return view}
    func updateNSView(_ view:PianoRollView,context:Context){
        let note=store.currentLane?.notes.first{$0.id==store.selectedNoteID}
        let changed=view.topPitch != topPitch || view.lastSelection != note || (note==nil && view.lastBeat != store.selectedBeat)
        if !enabled || view.topPitch != topPitch || (view.dragIdentity != nil && view.dragIdentity != store.numberEditIdentity) {view.cancelDrag()}
        if !enabled {view.releaseHeldNote()}
        view.store=store;view.topPitch=max(0,min(127,topPitch));view.allowsEditing=enabled
        view.lastSelection=note;view.lastBeat=store.selectedBeat;view.needsDisplay=true
        if changed {DispatchQueue.main.async{[weak view] in view?.revealSelection()}}
    }
}
@MainActor final class PianoRollView:NSView {
    var store:AppStore;var topPitch=72;let row=20.0,unit=48.0,left=60.0
    var original:Note?,preview:Note?,down=NSPoint.zero,resizing=false
    var heldPitch:Int?
    var lastSelection:Note?,lastBeat=0.0
    var allowsEditing=true
    var dragIdentity:NumberEditIdentity?
    var accessibilityNotes:[ID:PianoNoteAccessibility]=[:]
    var scrollObserver:NSObjectProtocol?
    override var isFlipped:Bool{true};override var acceptsFirstResponder:Bool{true}
    init(store:AppStore){self.store=store;super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("피아노 롤 · Tab 노트 선택 · 방향키 편집")}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();DispatchQueue.main.async{[weak self] in
        guard let self,let window=self.window else{return}
        if self.scrollObserver==nil,let clip=self.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications=true
            self.scrollObserver=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:clip,queue:.main){[weak self] _ in MainActor.assumeIsolated{self?.needsDisplay=true}}
        }
        guard self.allowsEditing,!(window.firstResponder is NSTextView) else{return}
        window.makeFirstResponder(self);self.revealSelection()
    }}
    override func viewWillMove(toWindow newWindow:NSWindow?){if newWindow==nil{releaseHeldNote();cancelDrag();if let scrollObserver{NotificationCenter.default.removeObserver(scrollObserver);self.scrollObserver=nil}};super.viewWillMove(toWindow:newWindow)}
    deinit{if let scrollObserver{NotificationCenter.default.removeObserver(scrollObserver)}}
    func cancelDrag(){original=nil;preview=nil;dragIdentity=nil}
    func releaseHeldNote(){if let pitch=heldPitch{store.midi(status:0x80,pitch:pitch,velocity:0,time:ProcessInfo.processInfo.systemUptime);heldPitch=nil}}
    func revealSelection(){
        // A click can select near a viewport edge; keep the pointer's drag origin stable.
        guard original==nil,window != nil else{return}
        let note=store.currentLane?.notes.first{$0.id==store.selectedNoteID}
        var target=note.map{rect($0)} ?? NSRect(x:left+store.selectedBeat*unit,y:visibleRect.minY,width:unit,height:row)
        target.size.width=min(target.width,max(unit,visibleRect.width-left-48))
        target.origin.x-=left+16;target.size.width+=left+32
        target.origin.y-=20+row;target.size.height+=20+2*row
        scrollToVisible(target);needsDisplay=true
    }
    func rect(_ n:Note)->NSRect{NSRect(x:left+n.beat*unit,y:20+Double(topPitch-n.pitch)*row+1,width:max(3,n.length*unit),height:row-2)}
    override func draw(_ dirtyRect:NSRect){
        StudioTheme.canvasNS.setFill();bounds.fill();let ctx=store.currentContext
        for i in 0..<min(27,topPitch+1) {let pitch=topPitch-i,y=20+Double(i)*row; (ctx.scale.contains(pitch) ? NSColor(white:0.10,alpha:1):NSColor(white:0.073,alpha:1)).setFill();NSRect(x:left,y:y,width:bounds.width-left,height:row).fill()
            NSColor(white:0.17,alpha:1).setStroke();let l=NSBezierPath();l.move(to:NSPoint(x:0,y:y));l.line(to:NSPoint(x:bounds.width,y:y));l.stroke()}
        let step=1/Double(max(1,ctx.beatGrid.subdivisions)),count=min(131072,Int(store.editorBeats/step))
        let first=max(0,Int((visibleRect.minX-left)/unit/step)-1),last=min(count,max(0,Int((visibleRect.maxX-left)/unit/step)+1))
        for i in first...max(first,last) {let q=Double(i)*step,x=left+q*unit;let line=NSBezierPath();line.move(to:NSPoint(x:x,y:20));line.line(to:NSPoint(x:x,y:bounds.height));(i%ctx.beatGrid.subdivisions==0 ? NSColor(white:0.32,alpha:1):NSColor(white:0.16,alpha:1)).setStroke();line.lineWidth=0.5;line.stroke()}
        let selectedIDs=store.selectedMIDIIDs
        let visible=(store.currentLane?.notes ?? []).map{preview?.id==$0.id ? preview!:$0}.filter{$0.pitch<=topPitch && $0.pitch>=max(0,topPitch-26)}
        for n in visible.filter({!selectedIDs.contains($0.id)})+visible.filter({selectedIDs.contains($0.id)}) {let r=rect(n);(selectedIDs.contains(n.id) ? StudioTheme.accentNS:StudioTheme.accentNS.withAlphaComponent(0.60)).setFill();NSBezierPath(roundedRect:r,xRadius:2,yRadius:2).fill()}
        StudioTheme.accentNS.withAlphaComponent(0.5).setStroke();let cursor=NSBezierPath();cursor.move(to:NSPoint(x:left+store.selectedBeat*unit,y:20));cursor.line(to:NSPoint(x:left+store.selectedBeat*unit,y:bounds.height));cursor.stroke()
        drawPinnedAxes()
        if let window {
            let ids=Set(visible.map(\.id));accessibilityNotes=accessibilityNotes.filter{ids.contains($0.key)}
            setAccessibilityChildren(MIDIOrbitViewport.ordered(visible).map{note -> NSAccessibilityElement in
                let child=accessibilityNotes[note.id] ?? PianoNoteAccessibility(parent:self,id:note.id);accessibilityNotes[note.id]=child
                child.setAccessibilityLabel("\(Scale.roots[note.pitch%12])\(note.pitch/12-1) · \(note.beat)박 · 길이 \(note.length)박 · 세기 \(note.velocity)")
                child.setAccessibilityValue(selectedIDs.contains(note.id) ? "선택됨":"")
                child.setAccessibilityFrame(window.convertToScreen(convert(rect(note),to:nil)));return child
            })
        }
    }
    func drawPinnedAxes() {
        let v=visibleRect
        StudioTheme.canvasNS.setFill();NSRect(x:v.minX,y:v.minY,width:left,height:v.height).fill()
        for i in 0..<min(27,topPitch+1) {
            let pitch=topPitch-i,y=20+Double(i)*row
            guard y+row>v.minY+20,y<v.maxY else{continue}
            let keyboard=NSRect(x:v.minX,y:y,width:left-2,height:row-1)
            (heldPitch==pitch ? StudioTheme.accentNS.withAlphaComponent(0.4):NSColor(white:[1,3,6,8,10].contains(pitch%12) ? 0.085:0.16,alpha:1)).setFill();keyboard.fill()
            (Scale.roots[pitch%12]+String(pitch/12-1) as NSString).draw(at:NSPoint(x:v.minX+8,y:y+3),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:StudioTheme.textNS])
        }
        StudioTheme.canvasNS.setFill();NSRect(x:v.minX,y:v.minY,width:v.width,height:20).fill()
        let start=max(0,Int(ceil(v.minX/unit))),end=min(Int(ceil(store.editorBeats)),max(start,Int((v.maxX-left)/unit)))
        for beat in start...max(start,end) {
            (String(beat+1) as NSString).draw(at:NSPoint(x:left+Double(beat)*unit+3,y:v.minY+3),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.regular),.foregroundColor:StudioTheme.secondaryNS])
        }
        ("음높이" as NSString).draw(at:NSPoint(x:v.minX+4,y:v.minY+3),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:StudioTheme.secondaryNS])
    }
    func snap(_ q:Double)->Double{let s=Double(max(1,store.currentContext.beatGrid.subdivisions));return (q*s).rounded()/s}
    override func mouseDown(with event:NSEvent){guard allowsEditing else{return};window?.makeFirstResponder(self);down=convert(event.locationInWindow,from:nil);guard down.y>=visibleRect.minY+20,down.y<20+Double(min(27,topPitch+1))*row else{return}
        if down.x<visibleRect.minX+left {
            let pitch=max(0,min(127,topPitch-Int((down.y-20)/row)));heldPitch=pitch;store.midi(status:0x90,pitch:pitch,velocity:100,time:ProcessInfo.processInfo.systemUptime);needsDisplay=true;return
        }
        store.selectedClipID=nil;let q=max(0,min(store.editorBeats-0.03125,snap((down.x-left)/unit)));store.selectedBeat=q
        if let n=store.currentLane?.notes.reversed().first(where:{rect($0).contains(down)}) {if event.modifierFlags.contains(.shift){store.toggleMIDISelection(n.id);cancelDrag();needsDisplay=true;return};store.selectedNoteID=n.id;original=n;preview=n;dragIdentity=store.numberEditIdentity;resizing=down.x>rect(n).maxX-7}
        else if !event.modifierFlags.contains(.shift) {store.addNote(beat:q,pitch:topPitch-Int((down.y-20)/row),length:1/Double(store.currentContext.beatGrid.subdivisions))};needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent){guard allowsEditing,dragIdentity==store.numberEditIdentity,var n=original else{return};let p=convert(event.locationInWindow,from:nil);if resizing{n.length=max(1/Double(store.currentContext.beatGrid.subdivisions),min(store.editorBeats-n.beat,snap(n.length+(p.x-down.x)/unit)))}else{n.beat=max(0,min(store.editorBeats-n.length,snap(n.beat+(p.x-down.x)/unit)));n.pitch=max(0,min(127,n.pitch-Int(((p.y-down.y)/row).rounded())))};preview=n;needsDisplay=true}
    override func mouseUp(with event:NSEvent){defer{cancelDrag();needsDisplay=true};releaseHeldNote();if allowsEditing,let n=preview,n != original,dragIdentity==store.numberEditIdentity,var lane=store.currentLane,let i=lane.notes.firstIndex(where:{$0.id==n.id}){lane.notes[i]=n;store.setLane(lane)}}
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        if allowsEditing,window?.firstResponder===self,event.modifierFlags.contains(.command),store.handleMIDIBatchKey(event){needsDisplay=true;return true}
        return super.performKeyEquivalent(with:event)
    }
    override func keyDown(with event:NSEvent){
        guard allowsEditing else{super.keyDown(with:event);return}
        if store.handleMIDIKey(event,topPitch:topPitch){needsDisplay=true;return}
        if event.keyCode==53{store.focusCanvas?();store.hierarchyParent()}else{super.keyDown(with:event)}
    }
}
@MainActor final class PianoNoteAccessibility:NSAccessibilityElement {
    weak var plot:PianoRollView?
    let noteID:ID
    init(parent:PianoRollView,id:ID){plot=parent;noteID=id;super.init();setAccessibilityParent(parent);setAccessibilityRole(.button);setAccessibilityEnabled(true)}
    override func accessibilityPerformPress()->Bool {
        guard let plot,plot.window != nil,plot.allowsEditing,let note=plot.store.currentLane?.notes.first(where:{$0.id==noteID}) else{return false}
        plot.window?.makeFirstResponder(plot);plot.store.selectedNoteID=noteID;plot.store.selectedBeat=note.beat;plot.revealSelection();plot.needsDisplay=true;return true
    }
}
