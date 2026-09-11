import SwiftUI
import CirclrCore

struct InspectorView:View {
    @ObservedObject var store:AppStore
    var body:some View { EmptyView() }
    @ViewBuilder func signal(_ n:SignalNode)->some View {
        let projectID=store.project.id
        if n.kind == .effect {
            EffectControls(effect:Binding(get:{store.selectedSignal?.effect ?? n.effect},set:{v in store.updateSignal("이펙트 편집"){$0.effect=v}}),allowsAU:true,isCurrent:{store.project.id==projectID && store.selectedSignal?.id==n.id},chooseAudioUnit:{store.showSoundPicker(.signalEffect)})
            SoundPickerButton(title:"Audio Unit 이펙트 찾기",current:n.effect.kind == .audioUnit ? n.effect.plugin?.name ?? "Audio Unit 선택 필요":"설치된 Audio Unit 이펙트") {store.showSoundPicker(.signalEffect)}
            if n.effect.kind == .audioUnit {Button("플러그인 편집"){store.showPluginEditor(effect:true)}.disabled(n.effect.plugin==nil)}
        }
        Menu("출력 연결"){ForEach(store.project.signal.nodes.filter{$0.id != n.id && $0.kind != .source}){target in Button(target.name){store.connect(n.id,target.id)}}}.disabled(n.kind == .master)
        if n.kind == .effect || n.kind == .bus {Button("노드 삭제",role:.destructive){store.removeSelection()}}
    }
    @ViewBuilder func signalEdge(_ id:ID)->some View {if let e=store.project.signal.edges.first(where:{$0.id==id}) {Text("사운드 연결").font(.headline);CompactNumber("Gain",value:Binding(get:{store.project.signal.edges.first{$0.id==id}?.gain ?? e.gain},set:{v in store.mutate("연결 Gain"){p in if let i=p.signal.edges.firstIndex(where:{$0.id==id}){p.signal.edges[i].gain=max(0,min(4,v))}}}),range:0...4);Text(e.sidechain ? "Sidechain 입력":"Audio 입력");Button("연결 삭제",role:.destructive){store.removeSelection()}}}

}
struct ContextInspector:View {
    @ObservedObject var store:AppStore;let use:SectionUse
    func setting<T>(_ key:WritableKeyPath<ContextSettings,Setting<T>>,_ fallback:T)->Binding<Setting<T>> {Binding(get:{use.settings[keyPath:key]},set:{v in store.updateUse("서클 음악 설정"){$0.settings[keyPath:key]=v}})}
    func value<T>(_ key:WritableKeyPath<ContextSettings,Setting<T>>,_ fallback:T)->Binding<T> {Binding(get:{store.selectedUse?.settings[keyPath:key].value ?? fallback},set:{v in store.updateUse("서클 음악 설정"){$0.settings[keyPath:key] = .local(v)}})}
    var body:some View{VStack(alignment:.leading,spacing:20){
        if let tempo=use.tempoOverride {
            UseTempoControls(store:store,useID:use.id,arrangementID:store.project.activeArrangementID,tempo:tempo,identity:store.numberEditIdentity)
        } else {
        SourcePicker(title:"템포",setting:setting(\.tempo,store.currentContext.tempo),fallback:store.currentContext.tempo)
        if use.settings.tempo.source == .local {CompactNumber("BPM",value:value(\.tempo,store.currentContext.tempo),range:1...999)}
        }
        SourcePicker(title:"박자",setting:setting(\.meter,store.currentContext.meter),fallback:store.currentContext.meter)
        if use.settings.meter.source == .local {MeterEditor(meter:value(\.meter,store.currentContext.meter))}
        SourcePicker(title:"스케일",setting:setting(\.scale,store.currentContext.scale),fallback:store.currentContext.scale)
        if use.settings.scale.source == .local {ScaleEditor(scale:value(\.scale,store.currentContext.scale))}
        SourcePicker(title:"BeatGrid",setting:setting(\.beatGrid,store.currentContext.beatGrid),fallback:store.currentContext.beatGrid)
        if use.settings.beatGrid.source == .local {BeatEditor(grid:value(\.beatGrid,store.currentContext.beatGrid))}
        SourcePicker(title:"리듬 패턴",setting:setting(\.rhythm,store.currentContext.rhythm),fallback:store.currentContext.rhythm)
        if use.settings.rhythm.source == .local {PatternPicker(project:store.project,assignment:value(\.rhythm,store.currentContext.rhythm))}
        Text("적용: \(store.currentContext.tempo.formatted()) BPM · \(store.currentContext.meter.label)\n\(store.currentContext.scale.label)").font(.caption).foregroundStyle(.secondary)
    }}
}
struct SourcePicker<T:Codable & Equatable>:View {let title:String;@Binding var setting:Setting<T>;let fallback:T
    var body:some View{StudioChoice(title,selection:Binding(get:{setting.source},set:{s in if s == .local && setting.value==nil{setting.value=fallback};setting.source=s}),options:[(.inherit,"상속"),(.global,"글로벌"),(.local,"개별")])}
}
struct TrackInspector:View {
    @ObservedObject var store:AppStore
    let track:Track
    var showsTrackLevel=true
    var showsAutomationLinks=false
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            if showsTrackLevel {TrackLevelEditor(store:store,track:track)}
            SoundPickerButton(title:"음색·악기 찾기",current:store.instrumentName(track.instrument)) {store.showInstrumentPicker(trackID:track.id)}
            if track.instrument.kind != .sampler {Button("샘플 파일을 악기로 열기…"){store.chooseSampleInstrument()}}
            if track.instrument.kind == .synthesizer {
                SynthInspector(store:store,trackID:track.id,patch:track.instrument.synth ?? SynthPatch(),showsAutomationLinks:showsAutomationLinks)
            } else if track.instrument.kind == .sampler,let sample=track.instrument.sample {
                Text(store.project.assets.first{$0.id==sample.assetID}?.name ?? "샘플").lineLimit(1)
                Button("샘플 바꾸기"){store.chooseSampleInstrument()}
                if let zones=sample.zones,!zones.isEmpty {
                    ForEach(zones,id:\.pitch){zone in HStack{Text("\(zone.pitch)").monospacedDigit();Text(store.project.assets.first{$0.id==zone.assetID}?.name ?? "샘플").lineLimit(1)}}
                } else {
                    StudioStepper("기준음 · MIDI",value:Binding(get:{sample.rootPitch},set:{v in store.updateTrack("샘플 기준음"){$0.instrument.sample?.rootPitch=v}}),in:0...127)
                }
                Toggle("원샷 · 끝까지 재생",isOn:Binding(get:{sample.oneShot},set:{v in store.updateTrack("원샷"){$0.instrument.sample?.oneShot=v}}))
            } else if track.instrument.kind == .soundBank {
                Text("음색·악기 찾기에서 악기 이름·변형 음색·드럼 킷을 선택하세요.").font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
            } else if track.instrument.kind == .audioUnit {
                Button("Plugin 화면"){store.showPluginEditor(effect:false)}.disabled(track.instrument.plugin==nil)
            }
        }
    }
}
struct SynthInspector:View {
    @ObservedObject var store:AppStore
    let trackID:ID
    let patch:SynthPatch
    var showsAutomationLinks=false
    @Environment(\.numberEditing) private var numberEditing
    @State private var engineOneFocus=NumberFieldFocus(Array(Self.fieldOrder.prefix(6)),revealOnFocus:true)
    @State private var engineTwoFocus=NumberFieldFocus(Array(Self.fieldOrder.prefix(9)),revealOnFocus:true)
    @State private var engineThreeFocus=NumberFieldFocus(Self.fieldOrder,revealOnFocus:true)
    private static let fieldOrder=["필터 Hz","Detune cent","Attack 초","Decay 초","Sustain","Release 초",
                                   "공명","스테레오 폭","필터 엔벌로프 · 옥타브","배음","움직임"]
    private var editingContext:NumberEditingContext {
        // Preserve the host's draft identity, live target check and name registry.
        var context=numberEditing
        context.fieldFocus=patch.engineVersion==3 ? engineThreeFocus:patch.engineVersion>=2 ? engineTwoFocus:engineOneFocus
        return context
    }
    func binding(_ key:WritableKeyPath<SynthPatch,Double>)->Binding<Double> {Binding(get:{store.selectedTrack?.instrument.synth?[keyPath:key] ?? patch[keyPath:key]},set:{v in store.updateTrack("신스 편집"){$0.instrument.synth?[keyPath:key]=v}})}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            SynthParameterLayout {
                parameter("필터 Hz",\.cutoff,40...20000,automation:.synthCutoff)
                parameter("Detune cent",\.detune,0...60)
                parameter("Attack 초",\.attack,0.001...5)
                parameter("Decay 초",\.decay,0.001...10)
                parameter("Sustain",\.sustain,0...1)
                parameter("Release 초",\.release,0.005...10)
                if patch.engineVersion>=2 {
                    parameter("공명",\.resonance,0...0.9,automation:.synthResonance)
                    parameter("스테레오 폭",\.stereoWidth,0...1)
                    parameter("필터 엔벌로프 · 옥타브",\.filterEnvelope,-4...4)
                }
                if patch.engineVersion==3 {
                    parameter("배음",\.character,0...1)
                    parameter("움직임",\.motion,0...1)
                }
            }
            if patch.engineVersion<3 {Button("신스 엔진 3으로 전환"){store.updateTrack("신스 엔진 전환"){$0.instrument.synth?.engineVersion=3}}}
        }.environment(\.numberEditing,editingContext)
    }
    func parameter(_ title:String,_ key:WritableKeyPath<SynthPatch,Double>,_ range:ClosedRange<Double>,automation:AutomationParameter?=nil)->some View {
        let identity=store.numberEditIdentity
        return HStack(spacing:10) {
            Text(title).foregroundStyle(StudioTheme.secondary).lineLimit(1)
            if showsAutomationLinks,let automation,store.canOpenSynthAutomation(automation,trackID:trackID) {
                Button("오토메이션") {store.openSynthAutomation(automation,trackID:trackID,identity:identity)}
                    .buttonStyle(.plain).font(.system(size:12,weight:.medium)).foregroundStyle(StudioTheme.accent)
                    .fixedSize(horizontal:true,vertical:false)
                    .accessibilityLabel("\(title) 오토메이션 열기")
                    .help("신스 설정값은 트랙 전체에 적용됩니다. 곡선은 현재 선택한 원본·이번 사용 범위에서 편집합니다.")
            }
            Spacer(minLength:8)
            ValueField(title:title,value:binding(key),showsLabel:false,range:range)
        }
    }

}

/// Keep offscreen fields alive for ordered Tab navigation without replacing them on resize.
private struct SynthParameterLayout:SwiftUI.Layout {
    private let horizontalGap:CGFloat=28
    private let verticalGap:CGFloat=10
    private func metrics(width:CGFloat,subviews:Subviews)->(cell:CGFloat,heights:[CGFloat]) {
        let cell=max(0,(width-horizontalGap)/2)
        var heights:[CGFloat]=[]
        for index in subviews.indices {
            let row=index/2
            if row==heights.count {heights.append(0)}
            heights[row]=max(heights[row],subviews[index].sizeThatFits(.init(width:cell,height:nil)).height)
        }
        return (cell,heights)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let width=proposal.width ?? 508
        let layout=metrics(width:width,subviews:subviews)
        return .init(width:width,height:layout.heights.reduce(0,+)+CGFloat(max(0,layout.heights.count-1))*verticalGap)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let layout=metrics(width:bounds.width,subviews:subviews)
        var y=bounds.minY
        for index in subviews.indices {
            let row=index/2,column=index%2
            if index>0 && column==0 {y+=layout.heights[row-1]+verticalGap}
            subviews[index].place(at:.init(x:bounds.minX+CGFloat(column)*(layout.cell+horizontalGap),y:y),anchor:.topLeading,
                                 proposal:.init(width:layout.cell,height:layout.heights[row]))
        }
    }
}
