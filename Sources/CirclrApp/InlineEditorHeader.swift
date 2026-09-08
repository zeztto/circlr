import SwiftUI
import CirclrCore

/// Named workspace modes, kept in the same row when selection details change.
struct InlineEditorHeader:View {
    @ObservedObject var store:AppStore
    var nameFocus:FocusState<Bool>.Binding
    enum Page {case content,connections,automation,settings}
    var page:Page {store.connectionsOpen ? .connections:store.hierarchySettingsOpen && store.selectedMusic != nil ? .settings:store.automationVisible ? .automation:.content}
    var contentName:String {
        guard let node=store.selectedMusic else{return "편집"}
        switch node.content {
        case .midi,.rhythmMIDI:return "MIDI"
        case .audio,.rhythmAudio:return "오디오"
        case .instrument:return "음색"
        case .effect:return "이펙트"
        case .output:return "레벨"
        case .mix:return "믹스"
        case .router:return "라우터"
        }
    }
    var takes:[RecordedTake] {
        guard let use=store.selectedUse,let track=store.selectedTrackID,store.selectedMusic != nil else{return []}
        return (store.project.takes ?? []).filter{$0.useID==use.id && $0.lane.trackID==track && ($0.targetLaneID==nil || $0.targetLaneID==store.selectedLaneID)}
    }
    var body:some View {
        HStack(spacing:8) {
            TextField("서클 이름",text:Binding(get:{store.selectedCircle?.title ?? ""},set:{store.renameHierarchy($0)}))
                .textFieldStyle(.plain).font(.system(size:17,weight:.semibold)).focused(nameFocus)
                .disabled(store.midiImportDraft != nil).frame(minWidth:80)
            Spacer(minLength:8)
            HStack(spacing:2) {
                if store.selectedMusic != nil || store.canEditCirclePorts {mode(contentName,page:.content,help:store.selectedMusic==nil ? "이 서클의 편집으로 돌아가기":"이 서클의 "+contentName+" 편집으로 돌아가기")}
                if store.canEditCirclePorts {mode("연결",page:.connections,help:"IN/OUT·대상·8방향 위치 편집 · L")}
                if store.selectedMusic != nil {
                    mode("오토메이션",page:.automation,help:"볼륨·팬 곡선 · ⌘5")
                    mode("설정",page:.settings,help:"템포·박자·스케일·반복 설정")
                }
            }.disabled(store.midiImportDraft != nil)
            if !takes.isEmpty {
                Menu("테이크") {ForEach(takes){take in Button(take.name){store.activateTake(take)}}}
                    .help("이 트랙의 녹음 테이크 선택").disabled(store.midiImportDraft != nil)
            }
            if store.selectedUse != nil {AudioRecordButton(store:store)}
            Button {store.hierarchySettingsOpen=false;store.hierarchyParent()} label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}
                .help("상위 서클로 축소 · Esc")
        }.frame(minHeight:30)
    }
    func mode(_ title:String,page target:Page,help:String)->some View {
        Button{select(target)}label:{Text(title).lineLimit(1).fixedSize().foregroundStyle(page==target ? StudioTheme.accent:StudioTheme.secondary)}
            .background(page==target ? StudioTheme.raised:Color.clear,in:RoundedRectangle(cornerRadius:5))
            .accessibilityLabel("작업 전환 · "+title).accessibilityAddTraits(page==target ? .isSelected:[]).help(help)
    }
    func select(_ target:Page) {
        guard store.midiImportDraft==nil else{return}
        switch target {
        case .content:store.connectionsOpen=false;store.hierarchySettingsOpen=store.selectedMusic==nil;store.automationOpen=false;store.embeddedPlugin=nil
        case .connections:store.hierarchySettingsOpen=false;store.automationOpen=false;store.showConnections()
        case .automation:store.connectionsOpen=false;store.hierarchySettingsOpen=false;store.showAutomation()
        case .settings:store.connectionsOpen=false;store.automationOpen=false;store.embeddedPlugin=nil;store.hierarchySettingsOpen=true
        }
    }
}
