import AppKit
import SwiftUI
import CirclrCore

struct PitchBendWorkspace:View {
    @ObservedObject var store:AppStore
    @State private var focus=MIDIEditorFocus()
    @State private var initialFields=NumberFieldFocus(["초기 채널","초기 벤드 값","초기 범위 반음","초기 범위 센트"],revealOnFocus:true)
    @State private var valueFields=NumberFieldFocus(["벤드 위치 박","벤드 값"],revealOnFocus:true)
    @State private var rangeFields=NumberFieldFocus(["벤드 위치 박","범위 반음","범위 센트"],revealOnFocus:true)
    private var sequence:MIDIPitchBendSequence? {store.currentLane?.pitchBend}
    private var fieldFocus:NumberFieldFocus {
        guard let event=store.selectedPitchBendEvent else{return initialFields}
        switch event.kind {case .value:return valueFields;case .range:return rangeFields}
    }
    private var scope:String {
        if let id=store.editPatternID,let pattern=store.project.patterns.first(where:{$0.id==id}) {return "공유 리듬 · "+pattern.name+" · 모든 사용에 적용"}
        return (store.editOriginal ? "공유 원본":"이번 사용")+" · "+(store.selectedUse?.name ?? "MIDI")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            MIDIWorkspaceToolbarLayout(gap:8) {
                MIDIEditorModeControls(store:store)
                Button("초기 상태"){store.selectPitchBend(nil);focus.focus()}.help("초기 채널·14-bit 값·RPN 범위 편집 · 보기만으로 표현을 만들지 않습니다")
                Button("값 추가"){store.addPitchBend();focus.focus()}
                Button("범위 추가"){store.addPitchBend(range:true);focus.focus()}
                Button("선택 삭제") {if let index=store.pitchBendState.selectedIndex{store.editPitchBend(.remove(index:index),identity:store.pitchBendIdentity)};focus.focus()}.disabled(store.selectedPitchBendEvent==nil)
                Button("전체 표현 제거"){store.editPitchBend(.clear,identity:store.pitchBendIdentity);focus.focus()}.disabled(sequence==nil)
            }
            Text(scope+" · 재생은 내장 신스 경로만 지원 · 데이터 편집·저장 가능").font(.system(size:11)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
            HStack(spacing:12) {
                Text("● 값 · ■ 범위").foregroundStyle(StudioTheme.secondary)
                Text(store.pitchBendSelectionReadout).monospacedDigit()
            }.font(.system(size:11)).lineLimit(1)
            PitchBendPlot(store:store,focus:focus,fields:fieldFocus).frame(minHeight:72,maxHeight:.infinity)
            ScrollView(.horizontal) {
                HStack(spacing:10) {
                    if let event=store.selectedPitchBendEvent {
                        Text("\((store.pitchBendState.selectedIndex ?? 0)+1)/\(sequence?.events.count ?? 0)").monospacedDigit().fixedSize()
                        eventField("벤드 위치 박",event:event,value:event.beat,range:0...131072,presentation:.beatPosition){$0.beat=$1}
                        switch event.kind {
                        case .value(let value):eventField("벤드 값",event:event,value:Double(value),range:0...16383,integer:true){$0.kind = .value(Int($1))}
                        case .range(let range):
                            eventField("범위 반음",event:event,value:Double(range.semitones),range:0...127,integer:true){event,value in if case .range(var range)=event.kind {range.semitones=Int(value);event.kind = .range(range)}}
                            eventField("범위 센트",event:event,value:Double(range.cents),range:0...127,integer:true){event,value in if case .range(var range)=event.kind {range.cents=Int(value);event.kind = .range(range)}}
                        }
                    } else {
                        initialField("초기 채널",value:Double((sequence?.channel ?? 0)+1),range:1...16){$0.channel=Int($1)-1}
                        initialField("초기 벤드 값",value:Double(sequence?.initialValue ?? 8192),range:0...16383){$0.initialValue=Int($1)}
                        initialField("초기 범위 반음",value:Double(sequence?.initialRange.semitones ?? 2),range:0...127){$0.initialRange.semitones=Int($1)}
                        initialField("초기 범위 센트",value:Double(sequence?.initialRange.cents ?? 0),range:0...127){$0.initialRange.cents=Int($1)}
                    }
                }.padding(.vertical,1)
            }.fixedSize(horizontal:false,vertical:true)
            HStack(spacing:10) {
                Text("8192 중심 · hold · [ ] 선택 · ↑↓ 값 · ←→ 박 · Tab 수치 · Return 값 추가").font(.system(size:11)).foregroundStyle(StudioTheme.secondary).lineLimit(1)
                Spacer(minLength:0)
                Button(store.pitchBendState.displayedBeats == nil ? "표현 구간 보기":"서클 길이 보기") {
                    store.pitchBendState.displayedBeats=store.pitchBendState.displayedBeats == nil ? max(0.03125,sequence?.events.last?.beat ?? store.editorBeats):nil
                    focus.focus()
                }.fixedSize()
            }
        }
        .environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focus.focus()},fieldFocus:fieldFocus))
    }
    private func eventField(_ title:String,event:MIDIPitchBendEvent,value:Double,range:ClosedRange<Double>,integer:Bool=false,presentation:NumberEditPresentation = .number,change:@escaping(inout MIDIPitchBendEvent,Double)->Void)->some View {
        let identity=store.pitchBendIdentity
        return HStack(spacing:5) {
            Text(title).font(.system(size:11)).fixedSize()
            CommittedNumberField(title:title,value:Binding(get:{value},set:{value in
                guard let index=identity.index else{return}
                var updated=event;change(&updated,value);store.editPitchBend(.update(index:index,event:updated),identity:identity)
            }),range:range,integerOnly:integer,width:86,presentation:presentation,validate:{_ in try store.validatePitchBendIdentity(identity)})
        }
    }
    private func initialField(_ title:String,value:Double,range:ClosedRange<Double>,change:@escaping(inout MIDIPitchBendSequence,Double)->Void)->some View {
        let identity=store.pitchBendIdentity
        return HStack(spacing:5) {
            Text(title).font(.system(size:11)).fixedSize()
            CommittedNumberField(title:title,value:Binding(get:{value},set:{value in
                var source=identity.sequence ?? .init();change(&source,value)
                store.editPitchBend(.setInitial(channel:source.channel,value:source.initialValue,range:source.initialRange),identity:identity)
            }),range:range,integerOnly:true,width:72,validate:{_ in try store.validatePitchBendIdentity(identity)})
        }
    }
}

struct PitchBendPlot:NSViewRepresentable {
    @ObservedObject var store:AppStore
    let focus:MIDIEditorFocus
    let fields:NumberFieldFocus
    func makeNSView(context:Context)->PitchBendPlotView {let view=PitchBendPlotView(store:store);focus.view=view;return view}
    func updateNSView(_ view:PitchBendPlotView,context:Context){view.fields=fields;view.refresh();view.needsDisplay=true}
}
@MainActor final class PitchBendPlotView:NSView {
    let store:AppStore
    var fields:NumberFieldFocus?
    private var cacheIdentity:NumberEditIdentity?
    private var cacheSequence:MIDIPitchBendSequence?
    private var cacheIndex:Int?
    private var cacheBeats=0.0
    private var trace:[(Double,Double)]=[]
    private var markers:[(Int,Double,Double,Bool)]=[]
    private var selectedMarker:(Int,Double,Double,Bool)?
    private var selectedSemitones=0.0
    var area:NSRect {bounds.insetBy(dx:44,dy:16)}
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    init(store:AppStore) {self.store=store;super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("피치 벤드 곡선 · Return 값 추가 · 대괄호 이전 다음 · Home End 처음 끝 · Tab 수치 입력")}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async{[weak self] in guard let self,let window=self.window,!(window.firstResponder is NSTextView) else{return};window.makeFirstResponder(self)}
    }
    func refresh() {
        let identity=store.numberEditIdentity,index=store.pitchBendState.selectedIndex,beats=store.pitchBendDisplayBeats
        let source=store.currentLane?.pitchBend
        guard cacheIdentity != identity || cacheIndex != index || cacheBeats != beats || cacheSequence != source else{return}
        cacheIdentity=identity;cacheIndex=index;cacheBeats=beats;cacheSequence=source
        trace=[];markers=[];selectedMarker=nil
        let sequence=source ?? .init(),events=sequence.events
        let stride=max(1,(events.count+999)/1000)
        var raw=sequence.initialValue,range=sequence.initialRange,cursor=0
        // Keep exact event boundaries when visible density allows; dense sources use
        // bounded markers while the selected event remains an exact source index.
        var sampleBeats=(0...720).map{Double($0)/720*beats}
        if !events.isEmpty {
            for index in Swift.stride(from:0,to:events.count,by:stride) where events[index].beat<=beats {sampleBeats.append(events[index].beat)}
        }
        if let index,events.indices.contains(index),events[index].beat<=beats {sampleBeats.append(events[index].beat)}
        for beat in Set(sampleBeats).sorted() {
            while cursor<events.count,events[cursor].beat<=beat {
                let event=events[cursor]
                switch event.kind {case .value(let value):raw=value;case .range(let next):range=next}
                let isRange:Bool
                switch event.kind {case .range:isRange=true;case .value:isRange=false}
                if cursor % stride == 0 {markers.append((cursor,event.beat,Double(raw),isRange))}
                if cursor==index {selectedMarker=(cursor,event.beat,Double(raw),isRange);selectedSemitones=Double(raw-8192)/8192*range.totalSemitones}
                cursor+=1
            }
            trace.append((beat,Double(raw)))
        }
        if let index,selectedMarker==nil,events.indices.contains(index) {
            while cursor<=index {
                switch events[cursor].kind {case .value(let value):raw=value;case .range(let next):range=next}
                cursor+=1
            }
            let isRange:Bool
            switch events[index].kind {case .range:isRange=true;case .value:isRange=false}
            selectedMarker=(index,events[index].beat,Double(raw),isRange);selectedSemitones=Double(raw-8192)/8192*range.totalSemitones
        }
        let selection=selectedMarker.map{"\($0.0+1)번 이벤트 · \(BeatPosition.text($0.1))박 · raw \(Int($0.2)) · \(String(format:"%.3f",selectedSemitones))반음"} ?? "초기 상태 · 이벤트 \(events.count)개"
        setAccessibilityValue(selection)
        setAccessibilityHelp("14-bit raw 값의 hold 곡선 · 많은 이벤트는 그림을 간소화합니다. 대괄호와 Home·End는 전체 원본 이벤트를 선택합니다. ↑↓ 128 · Option 1 · Shift 1024")
    }
    func point(_ beat:Double,_ value:Double)->NSPoint {NSPoint(x:area.minX+beat/max(0.03125,cacheBeats)*area.width,y:area.maxY-value/16383*area.height)}
    override func draw(_ dirtyRect:NSRect) {
        StudioTheme.canvasNS.setFill();bounds.fill();refresh()
        for value in [0.0,8192,16383] {
            let p=point(0,value),line=NSBezierPath();line.move(to:p);line.line(to:NSPoint(x:area.maxX,y:p.y));StudioTheme.lineNS.setStroke();line.stroke()
            OrbitDrawing.text(String(Int(value)),at:NSPoint(x:22,y:p.y),size:10,color:StudioTheme.secondaryNS)
        }
        let path=NSBezierPath()
        for (index,sample) in trace.enumerated() {
            let p=point(sample.0,sample.1)
            if index==0 {path.move(to:p)}else{path.line(to:point(sample.0,trace[index-1].1));path.line(to:p)}
        }
        StudioTheme.accentNS.setStroke();path.lineWidth=1.5;path.stroke()
        for marker in markers {drawMarker(marker,selected:false)}
        if let selectedMarker,selectedMarker.1<=cacheBeats {drawMarker(selectedMarker,selected:true)}
        OrbitDrawing.text(BeatPosition.text(cacheBeats)+"박",at:NSPoint(x:area.maxX-20,y:bounds.maxY-5),size:10,color:StudioTheme.secondaryNS)
    }
    private func drawMarker(_ marker:(Int,Double,Double,Bool),selected:Bool) {
        let p=point(marker.1,marker.2),radius=selected ? 5.0:3.0,color=selected ? StudioTheme.textNS:StudioTheme.accentNS
        if marker.3 {
            color.setFill();NSRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2).fill()
        } else {OrbitDrawing.dot(p,radius:radius,color:color)}
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        let p=convert(event.locationInWindow,from:nil)
        let candidates=selectedMarker.map{markers+[$0]} ?? markers
        if let hit=candidates.min(by:{hypot(point($0.1,$0.2).x-p.x,point($0.1,$0.2).y-p.y)<hypot(point($1.1,$1.2).x-p.x,point($1.1,$1.2).y-p.y)}),hypot(point(hit.1,hit.2).x-p.x,point(hit.1,hit.2).y-p.y)<14 {
            store.selectPitchBend(hit.0)
        }
        refresh();needsDisplay=true
    }
    override func keyDown(with event:NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {super.keyDown(with:event);return}
        switch event.keyCode {
        case 33:store.choosePitchBend(-1)
        case 30:store.choosePitchBend(1)
        case 115:store.selectPitchBend((store.currentLane?.pitchBend?.events.isEmpty == false) ? 0:nil)
        case 119:store.selectPitchBend(store.currentLane?.pitchBend?.events.indices.last)
        case 36,76:store.addPitchBend()
        case 51,117:if let index=store.pitchBendState.selectedIndex{store.editPitchBend(.remove(index:index),identity:store.pitchBendIdentity)}
        case 48:
            if fields?.enter(last:event.modifierFlags.contains(.shift),in:window) != true {
                if event.modifierFlags.contains(.shift){window?.selectPreviousKeyView(self)}else{window?.selectNextKeyView(self)}
            }
        case 53:store.pitchBendOpen=false
        case 123,124,125,126:
            guard let index=store.pitchBendState.selectedIndex,var source=store.selectedPitchBendEvent else{return}
            if event.keyCode==123 || event.keyCode==124 {
                let amount=1/Double(store.currentContext.beatGrid.subdivisions)
                source.beat=max(0,min(131072,source.beat+(event.keyCode==123 ? -amount:amount)))
            } else {
                let direction=event.keyCode==125 ? -1:1,step=event.modifierFlags.contains(.option) ? 1:event.modifierFlags.contains(.shift) ? 1024:128
                switch source.kind {
                case .value(let value):source.kind = .value(max(0,min(16383,value+direction*step)))
                case .range(var range):range.semitones=max(0,min(127,range.semitones+direction));source.kind = .range(range)
                }
            }
            store.editPitchBend(.update(index:index,event:source),identity:store.pitchBendIdentity)
        default:super.keyDown(with:event)
        }
        refresh();needsDisplay=true
    }
}
