import SwiftUI
import CirclrCore

/// Named workspace modes stay directly accessible as the canvas width changes.
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
        (store.project.takes ?? []).filter{summary($0) != nil}
    }
    func summary(_ take:RecordedTake)->RecordedTakeSummary? {
        guard let use=store.selectedUse,let laneID=store.selectedLaneID else{return nil}
        return RecordedTakeSummary.make(take,arrangementID:store.project.activeArrangementID,useID:use.id,laneID:laneID,in:store.project)
    }
    func takeTitle(_ take:RecordedTake)->String {
        guard let value=summary(take) else{return take.name}
        return "\(take.name) · 노트 \(value.noteCount)개 · 클립 \(value.clipCount)개" + (value.matchesCurrentContent ? " · 현재 내용과 일치":"")
    }
    func activate(_ take:RecordedTake,identity:NumberEditIdentity) {
        guard store.numberEditIdentity==identity,!store.trackBounceRecoveryLocked,
              store.midiImportDraft==nil,store.nameEditing.resolve() else{return}
        var current=store.numberEditIdentity;current.revision=identity.revision
        guard current==identity,let live=store.project.takes?.first(where:{$0.id==take.id}),summary(live) != nil else{return}
        store.activateTake(live)
    }
    var body:some View {
        InlineEditorHeaderLayout {
            VStack(alignment:.leading,spacing:0) {
            if showingTransition && !store.connectionsOpen {
                Text("섹션 전환").font(.system(size:17,weight:.semibold)).frame(minWidth:80,alignment:.leading)
            } else if store.hierarchySelection == .sound {
                Text(store.selectedCircle?.title ?? "앨범 사운드").font(.system(size:17,weight:.semibold)).frame(minWidth:80,alignment:.leading)
            } else {CommittedNameField(title:"서클 이름",value:Binding(get:{store.selectedMusic != nil ? store.musicEditingNode?.name ?? store.selectedCircle?.title ?? "" : store.selectedCircle?.title ?? ""},set:{store.renameHierarchy($0)}),focus:nameFocus,message:{store.status=$0})
                .disabled(store.midiImportDraft != nil || store.musicEditingIssue != nil).frame(minWidth:80)}
            }
            HStack(spacing:2) {
                if store.selectedMusic != nil || store.canEditCirclePorts {mode(contentName,page:.content,help:store.selectedMusic==nil ? "이 서클의 편집으로 돌아가기":"이 서클의 "+contentName+" 편집으로 돌아가기")}
                if store.canEditCirclePorts {mode("연결",page:.connections,help:"IN/OUT·대상·8방향 위치 편집 · L")}
                if store.recentTransitionID != nil {mode("전환",page:.transition,help:"최근 편집한 섹션 전환으로 돌아가기")}
                if store.selectedMusic != nil {
                    mode("오토메이션",page:.automation,help:"볼륨·팬 곡선 · ⌘5")
                    mode("설정",page:.settings,help:"템포·박자·스케일·반복 설정")
                }
            }.disabled(store.midiImportDraft != nil)
            HStack(spacing:8) {
            if !takes.isEmpty {
                let identity=store.numberEditIdentity
                Menu("테이크 \(takes.count)개") {ForEach(takes){take in
                    Button(takeTitle(take)){activate(take,identity:identity)}
                        .accessibilityIdentifier("recorded-take-"+take.id)
                }}
                    .id(TakeMenuIdentity(value:identity))
                    .help("이번 사용의 녹음 내용을 바꿉니다 · 공유 원본은 유지 · 내용 일치는 저장된 노트·클립 기준입니다")
                    .disabled(store.midiImportDraft != nil || store.trackBounceRecoveryLocked)
            }
            if store.selectedUse != nil {AudioRecordButton(store:store)}
            Button {store.hierarchySettingsOpen=false;store.hierarchyParent()} label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}
                .help("상위 서클로 축소 · Esc").accessibilityLabel("상위 서클로 축소")
            }.fixedSize(horizontal:true,vertical:false)
        }.frame(minHeight:30).padding(.horizontal,store.project.usesOrbits ? 16:0)
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

/// Keeps name and native buttons alive when only their positions change.
private struct InlineEditorHeaderLayout:SwiftUI.Layout {
    private let gap:CGFloat=8
    private let minimumName:CGFloat=160
    private func metrics(width:CGFloat,subviews:Subviews)->(name:CGSize,modes:CGSize,actions:CGSize,wrapped:Bool) {
        let modes=subviews[1].sizeThatFits(.unspecified)
        let actions=subviews[2].sizeThatFits(.unspecified)
        let wrapped=minimumName+modes.width+actions.width+gap*2>width
        let nameWidth=max(80,width-actions.width-gap-(wrapped ? 0:modes.width+gap))
        let name=subviews[0].sizeThatFits(ProposedViewSize(width:nameWidth,height:nil))
        return (CGSize(width:nameWidth,height:name.height),modes,actions,wrapped)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) -> CGSize {
        guard subviews.count==3 else{return .zero}
        let width=proposal.width ?? minimumName+subviews[1].sizeThatFits(.unspecified).width+subviews[2].sizeThatFits(.unspecified).width+gap*2
        let value=metrics(width:width,subviews:subviews)
        let firstHeight=max(30,value.name.height,value.actions.height)
        return CGSize(width:width,height:value.wrapped ? firstHeight+gap+value.modes.height:max(firstHeight,value.modes.height))
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        guard subviews.count==3 else{return}
        let value=metrics(width:bounds.width,subviews:subviews)
        let firstHeight=max(30,value.name.height,value.actions.height)
        subviews[0].place(at:bounds.origin,anchor:.topLeading,proposal:ProposedViewSize(width:value.name.width,height:firstHeight))
        subviews[2].place(at:CGPoint(x:bounds.maxX-value.actions.width,y:bounds.minY),anchor:.topLeading,
                          proposal:ProposedViewSize(width:value.actions.width,height:firstHeight))
        let modesOrigin=value.wrapped ? CGPoint(x:bounds.minX,y:bounds.minY+firstHeight+gap):CGPoint(x:bounds.minX+value.name.width+gap,y:bounds.minY)
        subviews[1].place(at:modesOrigin,anchor:.topLeading,proposal:ProposedViewSize(value.modes))
    }
}

/// Refresh cached native menu actions whenever their guarded editing context changes.
private struct TakeMenuIdentity:Hashable {
    let value:NumberEditIdentity
    static func == (lhs:Self,rhs:Self)->Bool {lhs.value==rhs.value}
    func hash(into hasher:inout Hasher) {
        hasher.combine(value.projectID)
        hasher.combine(value.generation)
        hasher.combine(value.revision)
    }
}
