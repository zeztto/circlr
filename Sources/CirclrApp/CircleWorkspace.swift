import SwiftUI
import AppKit
import CirclrCore

/// Rectangular workspace shown only in the reusable music editor window.
struct CircleWorkspace:View {
    @ObservedObject var store:AppStore
    let focus:CanvasFocus
    var title:String {store.focusTitle(focus)}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:16) {
                VStack(alignment:.leading,spacing:5) {
                    if case .section = focus,let use=store.selectedUse {
                        TextField("서클 이름",text:Binding(get:{use.name},set:{v in store.updateUse("서클 이름"){$0.name=v}})).textFieldStyle(.plain).font(.system(size:23,weight:.semibold)).help("서클 이름 바로 편집")
                    } else {Text(title).font(.system(size:23,weight:.semibold)).lineLimit(1)}

                }
                Spacer(minLength:12)
                if case .section = focus {Button {store.play(onlySelection:true)} label:{Label("이 서클 듣기",systemImage:"play.fill")}}
                Button {store.closeFocus()} label:{Label("닫기",systemImage:"xmark")}.help("편집 창 닫기 · Esc")
            }.padding(.horizontal,26).padding(.top,12).padding(.bottom,12)
            VStack(alignment:.leading,spacing:0){content}.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            HStack(spacing:10) {
                if store.preparing {ProgressView(value:store.progress).frame(width:65)}
                Text(store.status).lineLimit(1)
                Spacer()
                Text(focus == .global ? "곡에 적용 버튼으로 반영":"편집 내용 자동 반영 · ⌘S 저장")
            }.font(.system(size:10)).foregroundStyle(StudioTheme.secondary).padding(.horizontal,26).frame(height:28)
                .background(StudioTheme.canvas)
        }
        .background(StudioTheme.surface).foregroundStyle(StudioTheme.text)
        .font(.system(size:12)).buttonStyle(CanvasButtonStyle()).controlSize(.regular).toggleStyle(.switch)
        .textFieldStyle(StudioFieldStyle()).tint(StudioTheme.accent).accentColor(StudioTheme.accent).preferredColorScheme(.dark)
        .numberEditing(in:store)
        .onExitCommand{store.closeFocus()}
        .alert("작업을 완료하지 못했습니다",isPresented:Binding(get:{store.errorMessage != nil},set:{if !$0 {store.errorMessage=nil}})) {Button("확인"){store.errorMessage=nil}} message:{Text(store.errorMessage ?? "")}
    }
    @ViewBuilder var content:some View {
        switch focus {
        case .section:
            ScrollView {
                if let use=store.selectedUse {
                    VStack(alignment:.leading,spacing:12){UnifiedSectionView(store:store,use:use);pluginEditor}.padding(.horizontal,24).padding(.bottom,16)
                }
            }
        case .pattern(let id):
            ScrollView {VStack(alignment:.leading,spacing:14){patternSettings(id);Divider();SectionEditor(store:store);pluginEditor}.padding(24)}
        case .global:scroller{GlobalCircleSettings(store:store)}
        case .signal:
            scroller { if let n=store.selectedSignal { InspectorView(store:store).signal(n); if let track=store.selectedTrack,n.kind == .source { Divider();TrackInspector(store:store,track:track) } } }
        case .edge(let id):
            scroller { if store.soundView {InspectorView(store:store).signalEdge(id)} else if let e=store.project.active.edges.first(where:{$0.id==id}){InspectorView(store:store).transition(e)} }
        case .track(let id):
            scroller { if let t=store.project.tracks.first(where:{$0.id==id}) { TextField("트랙 이름",text:Binding(get:{t.name},set:{v in store.updateTrack("트랙 이름"){$0.name=v}})).textFieldStyle(StudioFieldStyle());TrackInspector(store:store,track:t) } }
        case .group(let id):scroller{groupSettings(id)}
        }
    }
    func scroller<Content:View>(@ViewBuilder _ content:()->Content)->some View {
        ScrollView {VStack(alignment:.leading,spacing:22){content();pluginEditor}.frame(maxWidth:900,alignment:.leading).padding(26).frame(maxWidth:.infinity,alignment:.topLeading)}.scrollIndicators(.automatic)
    }
    @ViewBuilder var pluginEditor:some View {
        if let plugin=store.embeddedPlugin {
            Divider()
            HStack{Text("Audio Unit").font(.headline);Spacer();Button("Plugin 닫기"){store.embeddedPlugin=nil}}
            EmbeddedPlugin(controller:plugin).frame(height:400)
        }
    }
    @ViewBuilder func patternSettings(_ id:ID)->some View {
        if let pattern=store.project.patterns.first(where:{$0.id==id}) {
            TextField("리듬 이름",text:Binding(get:{pattern.name},set:{v in store.mutate("리듬 이름"){p in if let i=p.patterns.firstIndex(where:{$0.id==id}){p.patterns[i].name=v}}})).textFieldStyle(StudioFieldStyle())
            CompactNumber("길이 · 4분음표 박",value:Binding(get:{store.project.patterns.first{$0.id==id}?.length ?? pattern.length},set:{v in store.mutate("리듬 길이"){p in if let i=p.patterns.firstIndex(where:{$0.id==id}){p.patterns[i].length=max(0.25,min(16384,v))}}}),range:0.25...16384)
            Text("글로벌 또는 서클 음악 설정에서 이 리듬을 선택하면 곡과 함께 반복 재생합니다.").foregroundStyle(.secondary)
        }
    }
    @ViewBuilder func groupSettings(_ id:ID)->some View {
        if let group=store.layout.groups.first(where:{$0.id==id}) {
            TextField("그룹 이름",text:Binding(get:{group.name},set:{v in store.editLayout("그룹 이름"){l in if let i=l.groups.firstIndex(where:{$0.id==id}){l.groups[i].name=v}}})).textFieldStyle(StudioFieldStyle())
            Text("\(group.members.count)개 서클").foregroundStyle(.secondary)
            Button(group.collapsed ? "펼치기":"접기"){store.toggleGroup(id);store.closeFocus()}
            Button("그룹 해제"){store.ungroup(id);store.closeFocus()}
        }
    }
}
struct GlobalCircleSettings:View {
    @ObservedObject var store:AppStore
    @State private var context=MusicContext()
    @State private var name=""
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            TextField("곡 이름",text:$name).textFieldStyle(StudioFieldStyle())
            CompactNumber("템포 · BPM",value:$context.tempo,range:1...999)
            MeterEditor(meter:$context.meter);ScaleEditor(scale:$context.scale)
            Divider(); Text("박 분할과 강세").font(.system(size:12,weight:.semibold));BeatEditor(grid:$context.beatGrid)
            Divider();PatternPicker(project:store.project,assignment:$context.rhythm)
            Text("서클마다 템포·박자·스케일·리듬을 따로 정할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            Button("곡에 적용") {do{try ContextResolver.validate(context);store.mutate("글로벌 설정"){$0.global=context;$0.name=name.isEmpty ? "새 곡":name};store.closeFocus()}catch{store.fail(error)}}.foregroundStyle(Color.accentColor)
        }.onAppear{context=store.project.global;name=store.project.name}
    }
}
struct EmbeddedPlugin:NSViewControllerRepresentable {
    let controller:PluginEditorController
    func makeNSViewController(context:Context)->PluginEditorController {controller}
    func updateNSViewController(_ controller:PluginEditorController,context:Context) {}
}
