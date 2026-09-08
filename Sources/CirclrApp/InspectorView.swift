import SwiftUI
import CirclrCore

struct InspectorView:View {
    @ObservedObject var store:AppStore
    var body:some View { EmptyView() }
    @ViewBuilder func signal(_ n:SignalNode)->some View {
        let projectID=store.project.id
        if n.kind == .effect {EffectControls(effect:Binding(get:{store.selectedSignal?.effect ?? n.effect},set:{v in store.updateSignal("이펙트 편집"){$0.effect=v}}),allowsAU:true,isCurrent:{store.project.id==projectID && store.selectedSignal?.id==n.id});if n.effect.kind == .audioUnit {Picker("Audio Unit",selection:Binding(get:{n.effect.plugin?.id ?? ""},set:{id in store.updateSignal("Audio Unit"){$0.effect.plugin=store.effects.first{$0.id==id}}})){Text("선택").tag("");ForEach(store.effects){Text($0.name).tag($0.id)}};Button("Plugin 화면"){store.showPluginEditor(effect:true)}.disabled(n.effect.plugin==nil)}}
        Menu("출력 연결"){ForEach(store.project.signal.nodes.filter{$0.id != n.id && $0.kind != .source}){target in Button(target.name){store.connect(n.id,target.id)}}}.disabled(n.kind == .master)
        if n.kind == .effect || n.kind == .bus {Button("노드 삭제",role:.destructive){store.removeSelection()}}
    }
    @ViewBuilder func signalEdge(_ id:ID)->some View {if let e=store.project.signal.edges.first(where:{$0.id==id}) {Text("사운드 연결").font(.headline);CompactNumber("Gain",value:Binding(get:{e.gain},set:{v in store.mutate("연결 Gain"){p in if let i=p.signal.edges.firstIndex(where:{$0.id==id}){p.signal.edges[i].gain=max(0,min(4,v))}}}));Text(e.sidechain ? "Sidechain 입력":"Audio 입력");Button("연결 삭제",role:.destructive){store.removeSelection()}}}
    @ViewBuilder func transition(_ e:FlowEdge)->some View {
        let projectID=store.project.id
        StudioChoice("방식",selection:Binding(get:{e.transition.mode},set:{v in store.updateEdge{$0.transition.mode=v}}),options:[(.within,"끝부분 안에서"),(.insert,"사이에 삽입"),(.overlap,"겹치기")])
        StudioChoice("길이 기준",selection:Binding(get:{e.transition.anchor},set:{v in store.updateEdge{$0.transition.anchor=v}}),options:[(.sourceBars,"앞 서클 마디"),(.targetBars,"뒤 서클 마디"),(.seconds,"초")])
        CompactNumber("길이",value:Binding(get:{e.transition.length},set:{v in store.updateEdge{$0.transition.length=max(0,v)}}))
        EffectControls(effect:Binding(get:{store.project.active.edges.first{$0.id==e.id}?.transition.effect ?? e.transition.effect},set:{v in store.updateEdge{$0.transition.effect=v}}),isCurrent:{store.project.id==projectID && store.edgeSelection==e.id})
        StudioChoice("전환 리듬",selection:Binding(get:{e.transition.patternID ?? ""},set:{v in store.updateEdge{$0.transition.patternID=v.isEmpty ? nil:v}}),options:[("","없음")]+store.project.patterns.map{($0.id,$0.name)})
        StudioChoice("대체할 트랙",selection:Binding(get:{e.transition.replaceTrackID ?? ""},set:{v in store.updateEdge{$0.transition.replaceTrackID=v.isEmpty ? nil:v}}),options:[("","대체 없이 합치기")]+store.project.tracks.map{($0.id,$0.name)})
        Text("겹치기는 앞 서클 fade-out과 뒤 서클 fade-in으로 연결합니다.").font(.caption).foregroundStyle(.secondary)
        Button("연결 삭제",role:.destructive){store.removeSelection()}
    }
}
struct ContextInspector:View {
    @ObservedObject var store:AppStore;let use:SectionUse
    func setting<T>(_ key:WritableKeyPath<ContextSettings,Setting<T>>,_ fallback:T)->Binding<Setting<T>> {Binding(get:{use.settings[keyPath:key]},set:{v in store.updateUse("서클 음악 설정"){$0.settings[keyPath:key]=v}})}
    func value<T>(_ key:WritableKeyPath<ContextSettings,Setting<T>>,_ fallback:T)->Binding<T> {Binding(get:{use.settings[keyPath:key].value ?? fallback},set:{v in store.updateUse("서클 음악 설정"){$0.settings[keyPath:key] = .local(v)}})}
    var body:some View{VStack(alignment:.leading,spacing:20){
        SourcePicker(title:"템포",setting:setting(\.tempo,store.currentContext.tempo),fallback:store.currentContext.tempo)
        if use.settings.tempo.source == .local {CompactNumber("BPM",value:value(\.tempo,store.currentContext.tempo))}
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
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Toggle("음소거",isOn:Binding(get:{track.muted},set:{v in store.updateTrack("음소거"){$0.muted=v}}))
                Spacer()
                ValueField(title:"트랙 볼륨",value:Binding(get:{track.gain},set:{v in store.updateTrack("트랙 볼륨"){$0.gain=v}}),range:0...4)
            }
            StudioChoice("악기",selection:Binding(get:{track.instrument.kind},set:{v in
                if v == .sampler {store.chooseSampleInstrument()}
                else {store.updateTrack("악기 종류"){$0.instrument.kind=v;if v == .synthesizer && $0.instrument.synth == nil {$0.instrument.synth=SynthPatch()}}}
            }),options:[(.synthesizer,"내장 신스"),(.sampler,"샘플 악기"),(.soundBank,"기본 Sound Bank"),(.audioUnit,"Audio Unit")])
            if track.instrument.kind == .synthesizer {
                SynthInspector(store:store,patch:track.instrument.synth ?? SynthPatch())
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
                Toggle("드럼",isOn:Binding(get:{track.instrument.drums},set:{v in store.updateTrack("드럼"){$0.instrument.drums=v}}))
                StudioStepper("GM Program · 0–127",value:Binding(get:{track.instrument.program},set:{v in store.updateTrack("GM Program"){$0.instrument.program=v}}),in:0...127)
            } else if track.instrument.kind == .audioUnit {
                Picker("Audio Unit",selection:Binding(get:{track.instrument.plugin?.id ?? ""},set:{id in store.updateTrack("Audio Unit"){$0.instrument.plugin=store.instruments.first{$0.id==id}}})){Text("선택").tag("");ForEach(store.instruments){Text($0.name).tag($0.id)}}
                Button("Plugin 화면"){store.showPluginEditor(effect:false)}.disabled(track.instrument.plugin==nil)
            }
        }
    }
}
struct SynthInspector:View {
    @ObservedObject var store:AppStore
    let patch:SynthPatch
    func binding(_ key:WritableKeyPath<SynthPatch,Double>)->Binding<Double> {Binding(get:{patch[keyPath:key]},set:{v in store.updateTrack("신스 편집"){$0.instrument.synth?[keyPath:key]=v}})}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            StudioChoice("음색",selection:Binding(get:{patch.voice},set:{v in store.updateTrack("신스 음색"){$0.instrument.synth=SynthPatch(v)}}),options:SynthVoice.allCases.map{($0,$0.label)})
            LazyVGrid(columns:[GridItem(.flexible(minimum:240),spacing:28),GridItem(.flexible(minimum:240))],alignment:.leading,spacing:10) {
                parameter("필터 Hz",\.cutoff,40...20000)
                parameter("Detune cent",\.detune,0...60)
                parameter("Attack 초",\.attack,0.001...5)
                parameter("Decay 초",\.decay,0.001...10)
                parameter("Sustain",\.sustain,0...1)
                parameter("Release 초",\.release,0.005...10)
                if patch.engineVersion>=2 {
                    parameter("공명",\.resonance,0...0.9)
                    parameter("스테레오 폭",\.stereoWidth,0...1)
                    parameter("필터 엔벌로프 · 옥타브",\.filterEnvelope,-4...4)
                }
                if patch.engineVersion==3 {
                    parameter("배음",\.character,0...1)
                    parameter("움직임",\.motion,0...1)
                }
            }
            if patch.engineVersion<3 {Button("신스 엔진 3으로 전환"){store.updateTrack("신스 엔진 전환"){$0.instrument.synth?.engineVersion=3}}}
        }
    }
    func parameter(_ title:String,_ key:WritableKeyPath<SynthPatch,Double>,_ range:ClosedRange<Double>)->some View {
        HStack(spacing:10) {
            Text(title).foregroundStyle(StudioTheme.secondary).lineLimit(1)
            Spacer(minLength:8)
            ValueField(title:title,value:binding(key),showsLabel:false,range:range)
        }
    }

}
