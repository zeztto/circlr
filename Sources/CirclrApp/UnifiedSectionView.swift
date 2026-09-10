import SwiftUI
import CirclrCore

struct UnifiedSectionView:View {
    @ObservedObject var store:AppStore
    let use:SectionUse
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            structure
            Divider()
            UnifiedMusicSettings(store:store)
            Divider()
            SectionEditor(store:store)
            Divider()
            SectionEffectsRow(store:store,use:use)
        }
    }
    private var structure:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:18) {
                CountControl(title:"길이",value:Binding(get:{store.selectedUse?.barsOverride ?? store.project.sections.first{$0.id==use.sectionID}?.bars ?? 8},set:{v in store.updateUse("길이"){$0.barsOverride=v}}),range:1...4096,suffix:"마디")
                CountControl(title:"재생",value:Binding(get:{store.selectedUse?.repeatCount ?? use.repeatCount},set:{v in store.updateUse("반복"){$0.repeatCount=v}}),range:1...256,suffix:"회")
                    .help("테두리 원 하나가 한 번의 재생입니다")
                Divider().frame(height:22)
                Button {store.setStart()} label:{Label("곡 시작",systemImage:store.project.active.startID==use.id ? "checkmark.circle.fill":"circle")}.foregroundStyle(store.project.active.startID==use.id ? StudioTheme.accent:StudioTheme.secondary)
                Button {store.updateUse("곡 끝"){$0.isEnd.toggle()}} label:{Label("곡 끝",systemImage:use.isEnd ? "checkmark.circle.fill":"circle")}.foregroundStyle(use.isEnd ? StudioTheme.accent:StudioTheme.secondary)
                Spacer(minLength:0)
                Button {store.reuse()} label:{Label("다시 사용",systemImage:"plus.square.on.square")}
                Button {store.removeSelection()} label:{Image(systemName:"trash")}.help("이 서클 삭제")
            }
            HStack(spacing:12) {
                Text("다음 서클").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                let edges=store.project.active.edges.filter{$0.from==use.id}
                if edges.isEmpty {Text("오른쪽 연결점에서 다음 서클로 드래그").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)}
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8){ForEach(edges){edge in
                        HStack(spacing:2){
                            Button {store.mutate("분기 선택"){$0.arrangements[$0.activeIndex].chosenEdges[use.id]=edge.id}} label:{Label(store.project.active.uses.first{$0.id==edge.to}?.name ?? "없음",systemImage:edges.count==1 || store.project.active.chosenEdges[use.id]==edge.id ? "arrow.right.circle.fill":"arrow.right.circle")}.foregroundStyle(edges.count==1 || store.project.active.chosenEdges[use.id]==edge.id ? StudioTheme.accent:StudioTheme.secondary)
                            Button {store.openEdge(edge.id)} label:{Image(systemName:"slider.horizontal.3")}.help("이 연결의 전환 효과")
                        }
                    }}
                }.frame(maxWidth:360)
                Menu {ForEach(store.project.active.uses.filter{$0.id != use.id}){target in Button(target.name){store.connect(use.id,target.id)}}} label:{Label("연결",systemImage:"plus")}.menuStyle(.borderlessButton).fixedSize()
                Spacer(minLength:0)
                Button("원본 분리"){store.detach()}.help("이 서클을 독립적인 음악 원본으로 분리")
                Button("반복 펼치기"){store.unfold()}.disabled(use.repeatCount<2).help("반복 횟수만큼 개별 서클로 펼치기")
            }.font(.system(size:11))
        }
    }
}

struct UnifiedMusicSettings:View {
    @ObservedObject var store:AppStore
    func value<T>(_ setting:WritableKeyPath<ContextSettings,Setting<T>>,_ context:KeyPath<MusicContext,T>)->Binding<T> {
        Binding(get:{store.currentContext[keyPath:context]},set:{v in
            guard v != store.currentContext[keyPath:context] else{return}
            store.updateUse("서클 음악 설정"){$0.settings[keyPath:setting] = .local(v)}
        })
    }
    func source<T>(_ setting:WritableKeyPath<ContextSettings,Setting<T>>,_ context:KeyPath<MusicContext,T>)->Binding<SettingSource> {
        Binding(get:{store.selectedUse?.settings[keyPath:setting].source ?? .inherit},set:{source in
            let current=store.currentContext[keyPath:context]
            store.updateUse("설정 출처") {use in
                if source == .local,use.settings[keyPath:setting].value==nil {use.settings[keyPath:setting].value=current}
                use.settings[keyPath:setting].source=source
            }
        })
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(alignment:.top,spacing:24) {
                if let use=store.selectedUse,let tempo=use.tempoOverride {
                    UseTempoControls(store:store,useID:use.id,arrangementID:store.project.activeArrangementID,tempo:tempo,identity:store.numberEditIdentity)
                } else {
                field("템포",source:source(\.tempo,\.tempo)) {
                    HStack(spacing:8){ValueField(title:"",value:value(\.tempo,\.tempo),width:75,range:1...999);Text("BPM").foregroundStyle(StudioTheme.secondary)}
                }.frame(maxWidth:.infinity,alignment:.leading)
                }
                field("박자",source:source(\.meter,\.meter)) {
                    let meter=value(\.meter,\.meter)
                    HStack(spacing:10){CountControl(title:"",value:meter.numerator,range:1...64);Text("/").foregroundStyle(StudioTheme.secondary);CompactChoice(selection:meter.denominator,options:[1,2,4,8,16,32,64].map{($0,String($0))},label:"박자 분모")}
                }.frame(maxWidth:.infinity,alignment:.leading)
                field("스케일",source:source(\.scale,\.scale)) {
                    let scale=value(\.scale,\.scale)
                    HStack(spacing:16){CompactChoice(selection:scale.root,options:(0..<12).map{($0,Scale.roots[$0])},label:"스케일 Root");CompactChoice(selection:Binding(get:{scale.wrappedValue.name},set:{name in var s=scale.wrappedValue;s.name=name;s.intervals=Scale.modes.first{$0.0==name}?.1 ?? s.intervals;scale.wrappedValue=s}),options:Scale.modes.map{($0.0,$0.0)},label:"스케일 Mode")}
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack(alignment:.top,spacing:24) {
                field("리듬 기준",source:source(\.beatGrid,\.beatGrid)) {
                    let grid=value(\.beatGrid,\.beatGrid)
                    HStack(spacing:16){
                        CountControl(title:"분할",value:grid.subdivisions,range:1...32)
                        ValueField(title:"Swing",value:grid.swing,width:54,range:0...0.75)
                        AccentField(accents:grid.accents)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                field("반복 리듬",source:source(\.rhythm,\.rhythm)) {
                    let rhythm=value(\.rhythm,\.rhythm)
                    CompactChoice(selection:Binding(get:{rhythm.wrappedValue.patternID ?? ""},set:{rhythm.wrappedValue=RhythmAssignment($0.isEmpty ? nil:$0)}),options:[("","없음")]+store.project.patterns.map{($0.id,$0.name)},label:"반복 리듬")
                }.frame(width:240,alignment:.leading)
            }
        }
    }
    func field<Content:View>(_ title:String,source:Binding<SettingSource>,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:5) {
            HStack(spacing:10){Text(title).font(.system(size:11,weight:.semibold));SourceBadge(source:source)}
            content().frame(height:28,alignment:.leading)
        }
    }
}
struct SourceBadge:View {
    @Binding var source:SettingSource
    private func name(_ value:SettingSource)->String {switch value {case .inherit:return "상속";case .global:return "글로벌";case .local:return "개별"}}
    var body:some View {
        Menu {ForEach(SettingSource.allCases,id:\.self){value in Button(name(value)){source=value}}} label:{Text(name(source)).font(.system(size:10)).foregroundStyle(source == .local ? StudioTheme.accent:StudioTheme.secondary)}
            .menuStyle(.borderlessButton).fixedSize().help("값을 바꾸면 개별 설정이 됩니다. 여기서 상속 또는 글로벌로 되돌릴 수 있습니다.")
    }
}
struct CompactChoice<Value:Hashable>:View {
    @Binding var selection:Value
    let options:[(Value,String)]
    let label:String
    var body:some View {
        Menu {ForEach(options,id:\.0){value,name in Button((selection==value ? "✓ ":"")+name){selection=value}}} label:{Text(options.first{$0.0==selection}?.1 ?? "선택").lineLimit(1).font(.system(size:12,weight:.medium))}
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(label).accessibilityValue(options.first{$0.0==selection}?.1 ?? "선택")
    }
}
struct AccentField:View {
    @Binding var accents:[Int]
    @State private var text=""
    @FocusState private var focused:Bool
    var body:some View {
        HStack(spacing:6){Text("강세").foregroundStyle(StudioTheme.secondary);TextField("2+2+3",text:$text).textFieldStyle(.plain).padding(.horizontal,8).frame(width:86,height:27).background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:5)).focused($focused).onSubmit{commit()}}
            .font(.system(size:11)).onAppear{text=accents.map(String.init).joined(separator:"+")}
            .onChange(of:focused){_,f in if !f {commit()}}
            .onChange(of:accents){_,v in if !focused{text=v.map(String.init).joined(separator:"+")}}
    }
    private func commit() {
        let parts=text.split(separator:"+").map{Int($0.trimmingCharacters(in:.whitespaces))}
        if parts.allSatisfy({($0 ?? 0)>0}) {accents=parts.compactMap{$0}}
        text=accents.map(String.init).joined(separator:"+")
    }
}
struct SectionEffectsRow:View {
    @ObservedObject var store:AppStore
    let use:SectionUse
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:20){Text("서클 이펙트").font(.system(size:12,weight:.semibold));ValueField(title:"볼륨",value:Binding(get:{store.selectedUse?.gain ?? use.gain},set:{v in store.updateUse("서클 볼륨"){$0.gain=v}}),range:0...4)
                if use.effects.isEmpty {Text("이 서클의 모든 트랙에 적용").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)}
                Spacer()
                Menu {ForEach(EffectKind.allCases.filter{$0 != .audioUnit},id:\.self){kind in Button(AppStore.effectName(kind)){store.updateUse("Effect 추가"){$0.effects.append(Effect(kind,amount:kind == .gain ? 1:0.5))}}}} label:{Label("이펙트 추가",systemImage:"plus")}.menuStyle(.borderlessButton).fixedSize()
            }
            ForEach(Array(use.effects.enumerated()),id:\.offset){i,effect in
                let projectID=store.project.id
                HStack(alignment:.top,spacing:20) {
                    EffectControls(effect:Binding(get:{guard let effects=store.selectedUse?.effects,effects.indices.contains(i) else{return effect};return effects[i]},set:{v in store.updateUse("이펙트 편집"){$0.effects[i]=v}}),isCurrent:{store.project.id==projectID && store.selectedUse?.id==use.id && store.selectedUse?.effects==use.effects})
                    Spacer();Button {store.updateUse("Effect 제거"){$0.effects.remove(at:i)}} label:{Image(systemName:"xmark")}.help("이 이펙트 제거")
                }
            }
        }
    }
}
