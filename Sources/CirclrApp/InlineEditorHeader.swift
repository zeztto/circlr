import SwiftUI
import CirclrCore

/// Named workspace modes, kept in the same row when selection details change.
struct InlineEditorHeader:View {
    @ObservedObject var store:AppStore
    var nameFocus:Binding<Bool>
    let connectionKeyboard:PortKeyboardFocus
    enum Page {case content,connections,transition,automation,settings}
    var showingTransition:Bool {store.hierarchyTransitionID != nil && store.hierarchyTransitionID==store.recentTransitionID}
    var page:Page {store.connectionsOpen ? .connections:showingTransition ? .transition:store.hierarchySettingsOpen && store.selectedMusic != nil ? .settings:store.automationVisible ? .automation:.content}
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
            if showingTransition && !store.connectionsOpen {
                Text("섹션 전환").font(.system(size:17,weight:.semibold)).frame(minWidth:80,alignment:.leading)
            } else if store.hierarchySelection == .sound {
                Text(store.selectedCircle?.title ?? "앨범 사운드").font(.system(size:17,weight:.semibold)).frame(minWidth:80,alignment:.leading)
            } else {CommittedNameField(title:"서클 이름",value:Binding(get:{store.selectedMusic != nil ? store.musicEditingNode?.name ?? store.selectedCircle?.title ?? "" : store.selectedCircle?.title ?? ""},set:{store.renameHierarchy($0)}),focus:nameFocus,message:{store.status=$0})
                .disabled(store.midiImportDraft != nil || store.musicEditingIssue != nil).frame(minWidth:80)}
            Spacer(minLength:8)
            HStack(spacing:2) {
                if store.selectedMusic != nil || store.canEditCirclePorts {mode(contentName,page:.content,help:store.selectedMusic==nil ? "이 서클의 편집으로 돌아가기":"이 서클의 "+contentName+" 편집으로 돌아가기")}
                if store.canEditCirclePorts {mode("연결",page:.connections,help:"IN/OUT·대상·8방향 위치 편집 · L")}
                if store.recentTransitionID != nil {mode("전환",page:.transition,help:"최근 편집한 섹션 전환으로 돌아가기")}
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
        StudioModeButton(title:title,label:"작업 전환 · "+title,selected:page==target,help:help,keyboard:store.connectionsOpen ? connectionKeyboard:nil,order:order(target)){select(target)}
            .frame(width:CGFloat(title.count)*13+18,height:30)
    }
    private func order(_ target:Page)->Int {
        switch target {case .content:return -30;case .connections:return -20;case .transition:return -10;case .automation:return -9;case .settings:return -8}
    }
    func select(_ target:Page) {
        guard store.midiImportDraft==nil,store.nameEditing.resolve() else{return}
        switch target {
        case .content:
            store.connectionsOpen=false;store.hierarchySettingsOpen=store.selectedMusic==nil;store.automationOpen=false;store.embeddedPlugin=nil
            store.hierarchyTransitionID=nil;store.edgeSelection=nil
        case .connections:store.hierarchySettingsOpen=false;store.automationOpen=false;store.showConnections()
        case .transition:
            if let address=store.hierarchySelection,let id=store.recentTransitionID {store.openHierarchyTransition(address,edgeID:id)}
        case .automation:store.connectionsOpen=false;store.hierarchySettingsOpen=false;store.showAutomation()
        case .settings:store.connectionsOpen=false;store.automationOpen=false;store.embeddedPlugin=nil;store.hierarchySettingsOpen=true
        }
    }
}
