import AppKit
import SwiftUI
import CirclrCore

struct SustainWorkspace:View {
    @ObservedObject var store:AppStore
    @State private var focus=MIDIEditorFocus()
    @State private var initialFields=NumberFieldFocus(["페달 초기 채널","페달 초기 raw"],revealOnFocus:true)
    @State private var eventFields=NumberFieldFocus(["페달 위치 박","페달 raw"],revealOnFocus:true)
    private var sequence:MIDISustainSequence? {store.currentLane?.sustain}
    private var fields:NumberFieldFocus {store.selectedSustainEvent == nil ? initialFields:eventFields}
    private var scope:String {
        if store.editPatternID != nil {return "공유 패턴 · 모든 사용에 반영"}
        return store.editOriginal ? "공유 원본":"이번 사용"
    }
    var body:some View {
        GeometryReader { geometry in
        // A tall console can leave less room than the plot and controls' minimum
        // height. Keep the complete form scrollable instead of clipping its last
        // row; NumberFieldFocus can then reveal the active field and error badge.
        ScrollView(.vertical) {
        VStack(alignment:.leading,spacing:8) {
            MIDIWorkspaceToolbarLayout(gap:8) {MIDIWorkspaceFileActions(store:store)}
            MIDIWorkspaceToolbarLayout(gap:8) {
                Button("초기 상태"){act{store.selectSustain(nil)}}
                Button("점 추가"){act{store.addSustain()}}
                Button("선택 삭제"){act{if let index=store.sustainState.selectedIndex {store.editSustain(.remove(index:index),identity:store.sustainIdentity)}}}.disabled(store.selectedSustainEvent==nil)
                Button("전체 제거"){act{store.editSustain(.clear,identity:store.sustainIdentity)}}.disabled(sequence==nil)
                Button(store.sustainState.displayedBeats == nil ? "전체 점 보기":"서클 길이 보기") {
                    act{store.sustainState.displayedBeats=store.sustainState.displayedBeats == nil ? max(0.03125,sequence?.events.last?.beat ?? store.editorBeats):nil}
                }.fixedSize()
            }
            Text(scope+" · "+store.sustainSelectionReadout).font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                .fixedSize(horizontal:false,vertical:true)
                .help("CC64 raw 0–127을 보존합니다. 64 이상은 눌림, 63 이하는 해제입니다. 같은 위치의 이벤트는 원본 순서대로 실행합니다. [ ] 선택 · Tab 수치")
            SustainPlot(store:store,focus:focus,fields:fields).frame(minHeight:72,maxHeight:.infinity)
            // Keep one scroll ancestor so native focus reveal reaches the vertical
            // viewport. Reflow these same controls without replacing their drafts.
            MIDIWorkspaceToolbarLayout(gap:12) {
                    if let event=store.selectedSustainEvent {
                        eventField("페달 위치 박",event:event,value:event.beat,range:0...131072,presentation:.beatPosition){$0.beat=$1}
                        eventField("페달 raw",event:event,value:Double(event.rawValue),range:0...127,integer:true){$0.rawValue=Int($1)}
                    } else {
                        initialField("페달 초기 채널",value:Double((sequence?.channel ?? store.currentLane?.pitchBend?.channel ?? 0)+1),range:1...16){$0.channel=Int($1)-1}
                        initialField("페달 초기 raw",value:Double(sequence?.initialValue ?? 0),range:0...127){$0.initialValue=Int($1)}
                    }
            }.padding(.vertical,6)
        }.frame(minHeight:max(0,geometry.size.height),alignment:.topLeading)
        }
        }.environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focus.focus()},fieldFocus:fields,names:store.nameEditing))
    }
    private func act(_ action:()->Void) {
        var identity=store.numberEditIdentity
        guard store.resolveActiveNumericDraft(),store.nameEditing.resolve() else{return}
        identity.revision=store.project.musicRevision
        guard identity==store.numberEditIdentity else{return}
        action();focus.focus()
    }
    private func eventField(_ title:String,event:MIDISustainEvent,value:Double,range:ClosedRange<Double>,integer:Bool=false,presentation:NumberEditPresentation = .number,change:@escaping(inout MIDISustainEvent,Double)->Void)->some View {
        let identity=store.sustainIdentity
        return HStack(spacing:5) {
            Text(title).font(.system(size:11)).fixedSize()
            CommittedNumberField(title:title,value:Binding(get:{value},set:{value in
                guard let index=identity.index else{return}
                var updated=event;change(&updated,value)
                store.editSustain(.update(index:index,event:updated),identity:identity)
            }),range:range,integerOnly:integer,width:86,presentation:presentation,validate:{_ in try store.validateSustainIdentity(identity)})
        }
    }
    private func initialField(_ title:String,value:Double,range:ClosedRange<Double>,change:@escaping(inout MIDISustainSequence,Double)->Void)->some View {
        let identity=store.sustainIdentity,channel=store.currentLane?.pitchBend?.channel ?? 0
        func candidate(_ value:Double)->MIDISustainSequence {var sequence=identity.sequence ?? .init(channel:channel);change(&sequence,value);return sequence}
        return HStack(spacing:5) {
            Text(title).font(.system(size:11)).fixedSize()
            CommittedNumberField(title:title,value:Binding(get:{value},set:{value in
                let source=candidate(value)
                store.editSustain(.setInitial(channel:source.channel,value:source.initialValue),identity:identity)
            }),range:range,integerOnly:true,width:72,validate:{value in
                try store.validateSustainIdentity(identity)
                try MIDISustainStorage.validate(sustain:candidate(value),pitchBend:store.currentLane?.pitchBend)
            })
        }
    }
}

struct SustainPlot:NSViewRepresentable {
    @ObservedObject var store:AppStore
    let focus:MIDIEditorFocus
    let fields:NumberFieldFocus
    func makeNSView(context:Context)->SustainPlotView {let view=SustainPlotView(store:store);focus.view=view;return view}
    func updateNSView(_ view:SustainPlotView,context:Context){view.fields=fields;view.refresh();view.needsDisplay=true;store.fulfillEditorFocusWhenMounted(view)}
}
@MainActor final class SustainPlotView:NSView {
    let store:AppStore
    var fields:NumberFieldFocus?
    private var identity:SustainEditIdentity?
    private var beats=0.0
    private var trace:[(Double,Double)]=[]
    private var markers:[(Int,Double,Double)]=[]
    private var selectedMarker:(Int,Double,Double)?
    var area:NSRect {bounds.insetBy(dx:36,dy:16)}
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    init(store:AppStore){self.store=store;super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("페달 CC64 곡선 · Return 점 추가 · 대괄호 이전 다음 · Home End 처음 끝 · Tab 수치 입력")}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();store.fulfillEditorFocusWhenMounted(self)}
    func refresh() {
        let current=store.sustainIdentity,length=store.sustainDisplayBeats
        guard identity != current || beats != length else{return}
        identity=current;beats=length;trace=[];markers=[];selectedMarker=nil
        let source=current.sequence ?? .init(),events=source.events,stride=max(1,(source.events.count+999)/1000)
        var raw=source.initialValue,cursor=0
        var samples=(0...720).map{Double($0)/720*beats}
        for index in Swift.stride(from:0,to:events.count,by:stride) where events[index].beat<=beats {samples.append(events[index].beat)}
        if let index=current.index,events.indices.contains(index) {samples.append(min(beats,events[index].beat));selectedMarker=(index,events[index].beat,Double(events[index].rawValue))}
        for beat in Set(samples).sorted() {
            while cursor<events.count,events[cursor].beat<=beat {
                raw=events[cursor].rawValue
                if cursor%stride==0 {markers.append((cursor,events[cursor].beat,Double(raw)))}
                cursor+=1
            }
            trace.append((beat,Double(raw)))
        }
        setAccessibilityValue(store.sustainSelectionReadout+" · 이벤트 \(events.count)개")
        setAccessibilityHelp("raw 값 hold 곡선 · 많은 이벤트의 그림은 간소화하지만 대괄호·Home·End로 모든 원본 이벤트를 선택합니다. ↑↓ 1 · Shift 10 · ←→ 격자 박")
    }
    private func point(_ beat:Double,_ value:Double)->NSPoint {.init(x:area.minX+beat/max(0.03125,beats)*area.width,y:area.maxY-value/127*area.height)}
    override func draw(_ dirtyRect:NSRect) {
        StudioTheme.canvasNS.setFill();bounds.fill();refresh()
        for raw in [0.0,64,127] {let p=point(0,raw),line=NSBezierPath();line.move(to:p);line.line(to:.init(x:area.maxX,y:p.y));StudioTheme.lineNS.setStroke();line.stroke();OrbitDrawing.text(String(Int(raw)),at:.init(x:16,y:p.y),size:10,color:StudioTheme.secondaryNS)}
        let path=NSBezierPath()
        for (index,sample) in trace.enumerated() {let p=point(sample.0,sample.1);if index==0 {path.move(to:p)}else{path.line(to:point(sample.0,trace[index-1].1));path.line(to:p)}}
        StudioTheme.accentNS.setStroke();path.lineWidth=1.5;path.stroke()
        for marker in markers {OrbitDrawing.dot(point(marker.1,marker.2),radius:3,color:StudioTheme.accentNS)}
        if let marker=selectedMarker,marker.1<=beats {OrbitDrawing.dot(point(marker.1,marker.2),radius:5,color:StudioTheme.textNS)}
        OrbitDrawing.text(BeatPosition.text(beats)+"박",at:.init(x:area.maxX-20,y:bounds.maxY-5),size:10,color:StudioTheme.secondaryNS)
    }
    private func resolve()->Bool {
        var expected=store.numberEditIdentity
        guard store.resolveActiveNumericDraft(),store.nameEditing.resolve() else{return false}
        expected.revision=store.project.musicRevision
        return expected==store.numberEditIdentity && store.sustainOpen
    }
    override func mouseDown(with event:NSEvent) {
        guard resolve() else{return};window?.makeFirstResponder(self);refresh()
        let p=convert(event.locationInWindow,from:nil),candidates=selectedMarker.map{markers+[$0]} ?? markers
        if let hit=candidates.min(by:{hypot(point($0.1,$0.2).x-p.x,point($0.1,$0.2).y-p.y)<hypot(point($1.1,$1.2).x-p.x,point($1.1,$1.2).y-p.y)}),hypot(point(hit.1,hit.2).x-p.x,point(hit.1,hit.2).y-p.y)<14 {store.selectSustain(hit.0)}
        refresh();needsDisplay=true
    }
    override func keyDown(with event:NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {super.keyDown(with:event);return}
        guard resolve() else{return}
        switch event.keyCode {
        case 33:store.chooseSustain(-1)
        case 30:store.chooseSustain(1)
        case 115:store.selectSustain(store.currentLane?.sustain?.events.isEmpty == false ? 0:nil)
        case 119:store.selectSustain(store.currentLane?.sustain?.events.indices.last)
        case 36,76:store.addSustain()
        case 51,117:if let index=store.sustainState.selectedIndex {store.editSustain(.remove(index:index),identity:store.sustainIdentity)}
        case 48:_ = fields?.enter(last:event.modifierFlags.contains(.shift),in:window)
        case 53:store.sustainOpen=false;store.requestEditorNavigationFocus()
        case 123,124,125,126:
            guard let index=store.sustainState.selectedIndex,var eventValue=store.selectedSustainEvent else{return}
            if event.keyCode==123 || event.keyCode==124 {let step=1/Double(store.currentContext.beatGrid.subdivisions);eventValue.beat=max(0,min(131072,eventValue.beat+(event.keyCode==123 ? -step:step)))}
            else {let step=event.modifierFlags.contains(.shift) ? 10:1;eventValue.rawValue=max(0,min(127,eventValue.rawValue+(event.keyCode==125 ? -step:step)))}
            store.editSustain(.update(index:index,event:eventValue),identity:store.sustainIdentity)
        default:super.keyDown(with:event)
        }
        refresh();needsDisplay=true
    }
}
