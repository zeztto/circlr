import AppKit
import SwiftUI
import CirclrCore

extension AppStore {
    var automationNode:MusicCircle? {
        guard editOriginal,let id=selectedMusic?.id,let use=selectedUse else{return selectedMusic}
        return project.sections.first{$0.id==use.sectionID}?.graph?.nodes.first{$0.id==id}
    }
    var availableAutomationParameters:[AutomationParameter] {
        guard let node=automationNode else{return [.gain,.pan]}
        return AutomationParameter.allCases.filter{$0.supports(node:node,in:project)}
    }
    var automationFallback:Double {
        guard let node=automationNode else{return automationParameter.neutral}
        return automationParameter.fallback(node:node,in:project)
    }
    var currentAutomation:AutomationLane? {automationNode?.automation?.first{$0.parameter==automationParameter}}
    var automationContext:MusicContext {
        guard let node=automationNode,let use=selectedUse,let (_,parent,_)=context(for:use) else{return currentContext}
        return (try? ContextResolver.inheriting(global:project.global,parent:parent,settings:node.settings)) ?? currentContext
    }
    var automationClock:MusicClock? {
        guard let node=automationNode,let parent=sectionClock else{return nil}
        return try? AutomationCompiler.editingClock(node,context:automationContext,parent:parent)
    }
    var automationBeats:Double {max(0.03125,min(1_048_576,automationNode?.lengthBeats ?? currentClock?.beats ?? 32))}
    var automationDisplayedBeats:Double {automationViewport.displayedBeats(base:automationBeats)}
    var selectedAutomationPoint:AutomationPoint? {currentAutomation?.points.first{$0.id==selectedAutomationPointID}}
    var automationEditorHasFocus:Bool {NSApp.keyWindow?.firstResponder is AutomationPlotView}
    var automationVisible:Bool {automationOpen && selectedMusic?.supportsAutomation==true && !hierarchySettingsOpen && embeddedPlugin==nil}
    func canOpenSynthAutomation(_ parameter:AutomationParameter,trackID:ID)->Bool {
        guard parameter == .synthCutoff || parameter == .synthResonance,
              case .music(let arrangementID,let useID,let nodeID)=hierarchySelection,
              arrangementID==project.activeArrangementID,selectedUse?.id==useID,
              selectedTrackID==trackID,
              let selected=selectedMusic,let editing=musicEditingNode,let automated=automationNode,
              selected.id==nodeID,editing.id==nodeID,automated.id==nodeID else{return false}
        for node in [selected,editing,automated] {
            guard case .instrument(let owner)=node.content,owner==trackID,
                  parameter.supports(node:node,in:project) else{return false}
        }
        return true
    }
    func openSynthAutomation(_ parameter:AutomationParameter,trackID:ID,identity:NumberEditIdentity) {
        guard identity==numberEditIdentity,canOpenSynthAutomation(parameter,trackID:trackID) else{return}
        var expected=identity
        guard resolveActiveNumericDraft(),nameEditing.resolve() else{return}
        expected.revision=project.musicRevision
        guard expected==numberEditIdentity,canOpenSynthAutomation(parameter,trackID:trackID),
              let address=hierarchySelection else{return}
        focusHierarchy(address,detail:true)
        connectionsOpen=false;hierarchySettingsOpen=false;embeddedPlugin=nil;pitchBendOpen=false
        automationParameter=parameter;automationOpen=true
        requestEditorNavigationFocus()
    }
    func showAutomation() {
        var identity=numberEditIdentity
        guard resolveActiveNumericDraft(),nameEditing.resolve() else{return}
        identity.revision=project.musicRevision
        guard identity==numberEditIdentity else{return}
        if selectedMusic?.supportsAutomation==false {openTrackComponent(1)}
        guard selectedMusic?.supportsAutomation==true,let address=hierarchySelection else{return}
        connectionsOpen=false;hierarchySettingsOpen=false;embeddedPlugin=nil;automationOpen=true;focusHierarchy(address,detail:true);requestEditorNavigationFocus()
    }
    func setAutomation(_ points:[AutomationPoint]?=nil,enabled:Bool?=nil) {
        guard let node=selectedMusic,let use=selectedUse else{return}
        let parameter=automationParameter,original=editOriginal
        mutate("오토메이션 편집"){try AutomationEditing.set(parameter:parameter,points:points,enabled:enabled,nodeID:node.id,useID:use.id,original:original,in:&$0)}
        if let id=selectedAutomationPointID,currentAutomation?.points.contains(where:{$0.id==id}) != true {selectedAutomationPointID=currentAutomation?.points.first?.id}
    }
    func editAutomationPoint(_ point:AutomationPoint) {
        var points=currentAutomation?.points ?? []
        if let i=points.firstIndex(where:{$0.id==point.id}){points[i]=point}else{points.append(point)}
        setAutomation(points);if currentAutomation?.points.contains(where:{$0.id==point.id})==true{selectedAutomationPointID=point.id}
    }
    func addAutomationPoint() {
        let points=currentAutomation?.points ?? [],step=1/Double(automationContext.beatGrid.subdivisions)
        let desired=selectedAutomationPoint.map{$0.beat+step} ?? 0
        let choices=[desired,automationBeats/2,automationBeats]+Array(stride(from:0.0,through:automationBeats,by:step).prefix(4097))
        // Choose the first free musical grid position without moving existing points.
        guard let free=choices.first(where:{q in q>=0 && q<=automationBeats && !points.contains{abs($0.beat-q)<1e-9}}) else {status="표시 구간에 빈 오토메이션 위치가 없습니다";return}
        editAutomationPoint(AutomationPoint(beat:free,value:currentAutomation?.value(at:free) ?? automationFallback))
    }
    func chooseAutomationPoint(_ delta:Int) {
        guard let points=currentAutomation?.points,!points.isEmpty else{return}
        let i=points.firstIndex{$0.id==selectedAutomationPointID} ?? (delta>0 ? -1:0)
        selectedAutomationPointID=points[(i+delta+points.count)%points.count].id
        revealAutomationPoint()
    }
    func chooseAutomationBoundary(last:Bool) {
        selectedAutomationPointID=last ? currentAutomation?.points.last?.id:currentAutomation?.points.first?.id
        revealAutomationPoint()
    }
    func revealAutomationPoint() {
        if let point=selectedAutomationPoint {automationViewport.reveal(base:automationBeats,beat:point.beat)}
    }
    func removeAutomationPoint() {guard let point=selectedAutomationPoint else{return};setAutomation(currentAutomation?.points.filter{$0.id != point.id} ?? [])}
    func duplicateAutomationPoint() {
        guard var point=selectedAutomationPoint else{return};point.id=newID();point.beat+=1/Double(automationContext.beatGrid.subdivisions)
        guard point.beat<=automationBeats else{return};editAutomationPoint(point)
    }
}

private struct AutomationControlsHeight:PreferenceKey {
    static let defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat){value=max(value,nextValue())}
}
private struct AutomationLinearLayout:SwiftUI.Layout {
    let controlsHeight:CGFloat
    private let gap:CGFloat=12
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        .init(width:proposal.width ?? 800,height:proposal.height ?? (80+gap+controlsHeight))
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        guard subviews.count==2 else{return}
        if bounds.width>=600 && bounds.width<800 && bounds.height<240 {
            let width=(bounds.width-gap)/2
            subviews[0].place(at:bounds.origin,anchor:.topLeading,proposal:.init(width:width,height:max(80,bounds.height)))
            subviews[1].place(at:.init(x:bounds.minX+width+gap,y:bounds.minY),anchor:.topLeading,proposal:.init(width:width,height:bounds.height))
        } else {
            let controls=min(controlsHeight,max(0,bounds.height-80-gap)),plot=max(80,bounds.height-controls-gap)
            subviews[0].place(at:bounds.origin,anchor:.topLeading,proposal:.init(width:bounds.width,height:plot))
            subviews[1].place(at:.init(x:bounds.minX,y:bounds.minY+plot+gap),anchor:.topLeading,proposal:.init(width:bounds.width,height:controls))
        }
    }
}
struct AutomationEditor:View {
    @ObservedObject var store:AppStore
    @State private var focusTarget=AutomationFocusTarget()
    @State private var linearControlsHeight:CGFloat=88
    @State private var gainFields=NumberFieldFocus(["오토메이션 위치 박","오토메이션 볼륨 dB"],revealOnFocus:true)
    @State private var panFields=NumberFieldFocus(["오토메이션 위치 박","오토메이션 팬 %"],revealOnFocus:true)
    @State private var cutoffFields=NumberFieldFocus(["오토메이션 위치 박","오토메이션 필터 cutoff Hz"],revealOnFocus:true)
    @State private var resonanceFields=NumberFieldFocus(["오토메이션 위치 박","오토메이션 필터 공명 %"],revealOnFocus:true)
    private var fieldFocus:NumberFieldFocus {
        switch store.automationParameter {case .gain:return gainFields;case .pan:return panFields;case .synthCutoff:return cutoffFields;case .synthResonance:return resonanceFields}
    }
    private var valueTitle:String {
        switch store.automationParameter {case .gain:return "오토메이션 볼륨 dB";case .pan:return "오토메이션 팬 %";case .synthCutoff:return "오토메이션 필터 cutoff Hz";case .synthResonance:return "오토메이션 필터 공명 %"}
    }
    private var valuePresentation:NumberEditPresentation {
        switch store.automationParameter {case .gain:return .gainDecibels;case .pan:return .panPercent;case .synthCutoff:return .number;case .synthResonance:return .resonancePercent}
    }
    private var valueUnit:String {
        switch store.automationParameter {case .gain:return "dB";case .pan:return "%";case .synthCutoff:return "Hz";case .synthResonance:return "%"}
    }
    var lane:AutomationLane? {store.currentAutomation}
    var hidden:Int {lane?.points.filter{$0.beat>store.automationDisplayedBeats}.count ?? 0}
    var available:Bool {store.automationNode != nil}
    var body:some View {
        Group {if store.project.usesOrbits {orbital}else{linear}}
            .onChange(of:store.availableAutomationParameters){_,parameters in
                // An instrument can change kind without changing its circle address.
                if !parameters.contains(store.automationParameter) {store.automationParameter = .gain}
            }
            .onChange(of:store.automationParameter){_,_ in if let view=focusTarget.view {store.fulfillEditorFocusWhenMounted(view)}}
            .onChange(of:store.editOriginal){_,_ in if let view=focusTarget.view {store.fulfillEditorFocusWhenMounted(view)}}
            .environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focusTarget.focus()},fieldFocus:fieldFocus))
    }
    var plot:some View {AutomationPlot(store:store,displayBeats:store.automationDisplayedBeats,focusTarget:focusTarget,fieldFocus:fieldFocus).disabled(!available)}
    var linear:some View {
        VStack(alignment:.leading,spacing:8) {
            MIDIWorkspaceToolbarLayout(gap:12) {
                parameterItems
                originalToggle
                pointActions.fixedSize(horizontal:true,vertical:false)
            }
            GeometryReader { geometry in
                AutomationLinearLayout(controlsHeight:linearControlsHeight) {
                    plot
                    ScrollView {
                        VStack(alignment:.leading,spacing:8) {
                            MIDIWorkspaceToolbarLayout(gap:12) {
                                navigation.fixedSize(horizontal:true,vertical:false)
                                if let point=store.selectedAutomationPoint {
                                    timeControl(point).fixedSize(horizontal:true,vertical:false)
                                    valueControl(point).fixedSize(horizontal:true,vertical:false)
                                    shapeControl(point).fixedSize(horizontal:true,vertical:false)
                                }else{emptyHint}
                            }
                            MIDIWorkspaceToolbarLayout(gap:12) {
                                Text(compactScopeDescription).fixedSize(horizontal:true,vertical:false)
                                    .help(scopeDescription+" · "+scopeHelp).accessibilityLabel(scopeDescription+" · "+scopeHelp)
                                rangeButton.fixedSize(horizontal:true,vertical:false)
                                if store.selectedAutomationPoint != nil {positionText.fixedSize(horizontal:true,vertical:false)}
                                Text(shortValueHint).fixedSize(horizontal:true,vertical:false)
                                    .help(valueHintDescription).accessibilityLabel(valueHintDescription)
                            }.font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                            .fixedSize(horizontal:false,vertical:true)
                            .background(GeometryReader { size in
                                Color.clear.preference(key:AutomationControlsHeight.self,value:size.size.height)
                            })
                    }
                }.frame(width:geometry.size.width,height:geometry.size.height)
            }.onPreferenceChange(AutomationControlsHeight.self) {if $0>0 {linearControlsHeight=$0}}

        }
    }
    var orbital:some View {
        GeometryReader { geometry in
        let compact=geometry.size.width<700
        HStack(alignment:.top,spacing:compact ? 12:20) {
            ScrollView {
            VStack(alignment:.leading,spacing:12) {
                parameterControls
                pointActions
                originalToggle
                scopeText.font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                rangeButton
                Text("각도는 시간 · 반경은 "+store.automationParameter.label).font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,6)
            }.frame(width:compact ? 170:225,alignment:.leading)
            plot.frame(minWidth:100,maxWidth:.infinity,maxHeight:.infinity)
            ScrollView {
            VStack(alignment:.leading,spacing:12) {
                navigation
                if let point=store.selectedAutomationPoint {
                    Button("수치 입력"){_ = fieldFocus.enter(in:focusTarget.view?.window)}
                        .help("곡선에서 Tab 첫 수치 · ⇧Tab 마지막 수치 · Return/Esc 곡선 복귀")
                    timeControl(point);positionText;valueControl(point);shapeControl(point)
                }else{emptyHint}
                valueHint.font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,6)
            }.frame(width:compact ? 210:250,alignment:.leading)
        }
        }
    }
    private func selectParameter(_ parameter:AutomationParameter) {
        var identity=store.numberEditIdentity
        guard store.resolveActiveNumericDraft(),store.nameEditing.resolve() else{return}
        identity.revision=store.project.musicRevision
        guard identity==store.numberEditIdentity,store.availableAutomationParameters.contains(parameter) else{return}
        store.automationParameter=parameter;store.requestEditorNavigationFocus()
    }
    var parameterControls:some View {
        MIDIWorkspaceToolbarLayout {parameterItems}
    }
    @ViewBuilder var parameterItems:some View {
        Group {
            if store.availableAutomationParameters.contains(.synthCutoff) {
                ForEach(store.availableAutomationParameters,id:\.self) { parameter in
                    StudioModeButton(title:parameter.label,label:"오토메이션 대상 · "+parameter.label,
                        selected:store.automationParameter==parameter,help:parameter.label+" 오토메이션 편집") {
                        selectParameter(parameter)
                    }
                    .frame(width:max(48,(parameter.label as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.semibold)]).width+24),height:28)
                }
            } else {
                Picker("오토메이션 대상",selection:Binding(get:{store.automationParameter},set:{selectParameter($0)})){ForEach(store.availableAutomationParameters,id:\.self){Text($0.label).tag($0)}}
                    .pickerStyle(.segmented).labelsHidden().frame(width:112)
            }
            HStack(spacing:10) {
            Toggle("적용",isOn:Binding(get:{lane?.enabled ?? false},set:{store.setAutomation(enabled:$0)})).disabled(lane==nil).fixedSize()
            Text("\(lane?.points.count ?? 0)개 점").foregroundStyle(StudioTheme.secondary).fixedSize()
            }.fixedSize()
        }
    }
    var originalToggle:some View {Toggle("공유 원본 편집",isOn:$store.editOriginal).fixedSize()}
    var pointActions:some View {
        MIDIWorkspaceToolbarLayout {
            Button("점 추가"){act{store.addAutomationPoint()}}.fixedSize().disabled(!available)
            Button("점 삭제"){act{store.removeAutomationPoint()}}.fixedSize().disabled(store.selectedAutomationPoint==nil)
            Menu("곡선") {
                Button("선택 점 복제"){act{store.duplicateAutomationPoint()}}.disabled(store.selectedAutomationPoint==nil)
                Button("곡선 지우기"){act{store.setAutomation([])}}.disabled(lane==nil)
            }.fixedSize()
        }
    }
    var navigation:some View {
        let count="\(lane?.points.firstIndex(where:{$0.id==store.selectedAutomationPointID}).map{$0+1} ?? 0)/\(lane?.points.count ?? 0)"
        return HStack(spacing:8) {
            Button {act{store.chooseAutomationPoint(-1)}} label:{Image(systemName:"chevron.left")}.help("이전 점 · [").accessibilityLabel("이전 오토메이션 점").disabled(lane==nil)
            Text(count)
                .monospacedDigit().foregroundStyle(StudioTheme.secondary).fixedSize().accessibilityLabel("선택 점 "+count)
                .help("Home 첫 점 · End 마지막 점 · 범위 밖의 점을 선택하면 표시 범위를 펼칩니다")
            Button {act{store.chooseAutomationPoint(1)}} label:{Image(systemName:"chevron.right")}.help("다음 점 · ]").accessibilityLabel("다음 오토메이션 점").disabled(lane==nil)
            if let point=store.selectedAutomationPoint,point.beat>store.automationDisplayedBeats {
                Button{act{store.revealAutomationPoint()}}label:{Image(systemName:"scope")}.accessibilityLabel("선택 오토메이션 점 보기").help("선택한 점까지 표시 범위를 펼칩니다")
            }
        }
    }
    var positionText:some View {
        let point=store.selectedAutomationPoint,clock=store.automationClock
        let position=point.flatMap{AutomationRuler.text(at:$0.beat,clock:clock)} ?? ""
        let seconds=point.flatMap{p in clock.map{String(format:"%.2f초",$0.seconds(at:p.beat))}} ?? ""
        let description=[position,seconds].filter{!$0.isEmpty}.joined(separator:" · ")
        return Text(description)
            .font(.system(size:11)).foregroundStyle(StudioTheme.secondary).accessibilityLabel("선택 점 위치 · "+description)
            .help("마디 안의 박은 현재 박자 분모 기준입니다. 위치 입력은 서클 시작부터의 4분음표 박입니다. 서클 길이 밖은 마지막 박자를 이어 표시합니다.")
    }
    func timeControl(_ point:AutomationPoint)->some View {
        HStack(spacing:10) {
            Text("위치").foregroundStyle(StudioTheme.secondary)
            CommittedNumberField(title:"오토메이션 위치 박",value:pointValue(point,\.beat),range:0...1_048_576,width:80,presentation:.beatPosition)
            Text("박").foregroundStyle(StudioTheme.secondary)
        }
    }
    func valueControl(_ point:AutomationPoint)->some View {
        HStack(spacing:10) {
            Text(store.automationParameter.label).foregroundStyle(StudioTheme.secondary)
            CommittedNumberField(title:valueTitle,value:pointValue(point,\.value),range:store.automationParameter.range,width:84,presentation:valuePresentation)
            Text(valueUnit).foregroundStyle(StudioTheme.secondary)
        }
    }
    func shapeControl(_ point:AutomationPoint)->some View {
        let identity=store.numberEditIdentity
        return MIDIWorkspaceToolbarLayout {
            Text("다음 점까지").fixedSize().foregroundStyle(StudioTheme.secondary)
            Picker("다음 점까지",selection:Binding(get:{store.selectedAutomationPoint?.shape ?? point.shape},set:{v in
                guard store.numberEditIdentity==identity,var current=store.selectedAutomationPoint,current.id==point.id else{return}
                current.shape=v;store.editAutomationPoint(current)
            })){Text("선형").tag(AutomationShape.linear);Text("유지").tag(AutomationShape.hold)}.pickerStyle(.segmented).labelsHidden().frame(width:112)
                .help("선형은 저장된 배율·팬·Hz·공명 값을 연결합니다. cutoff의 표시 축만 로그이며 보간은 Hz 선형입니다. 유지는 다음 점까지 값을 유지합니다.")
        }
    }
    var emptyHint:some View {Text(available ? "빈 곳 클릭 또는 점 추가 · Return":"이번 사용에 추가된 서클입니다. 공유 원본 편집을 끄고 조절하세요.").foregroundStyle(StudioTheme.secondary)}
    var valueHint:Text {Text(valueHintDescription)}
    private var valueHintDescription:String {
        switch store.automationParameter {
        case .gain:return "0 dB 원래 레벨 · −∞ 무음"
        case .pan:return "−100 왼쪽 · 0 중앙 · +100 오른쪽"
        case .synthResonance:return "0–90% · 선형 눈금과 보간\n곡선이 없거나 꺼지면 신스 설정값 사용 · ↑↓ 1% · ⌥ 0.1% · ⇧ 10%"
        case .synthCutoff:return "40–20,000 Hz · 로그 눈금 · Hz 선형 보간\n곡선이 없거나 꺼지면 신스 설정값 사용 · ↑↓ 100 Hz · ⌥ 1 Hz · ⇧ 1,000 Hz"
        }
    }
    private var shortValueHint:String {
        switch store.automationParameter {
        case .gain,.pan:return valueHintDescription
        case .synthCutoff:return "40–20k Hz · ↑↓100 · ⌥1 · ⇧1000"
        case .synthResonance:return "0–90% · ↑↓1 · ⌥0.1 · ⇧10%"
        }
    }
    private var scopeHelp:String {"위치는 서클 시작부터의 4분음표 박입니다. 개별 길이가 없는 오디오의 자동 반복에서도 곡선은 연속 진행합니다."}
    private var scopeDescription:String {
        let scope=store.editOriginal ? "공유 원본":"이번 사용"
        let timing=store.automationNode?.lengthBeats.map{String(format:"%.2f박 · %d회 반복",$0,store.automationNode?.repeatCount ?? 1)} ?? "서클 시작부터 연속 진행"
        return scope+" · "+timing
    }
    private var compactScopeDescription:String {
        let scope=store.editOriginal ? "공유 원본":"이번 사용"
        let timing=store.automationNode?.lengthBeats.map{String(format:"%.10g박 ×%d",$0,store.automationNode?.repeatCount ?? 1)} ?? "연속"
        return scope+" · "+timing
    }
    var scopeText:some View {Text(scopeDescription).help(scopeHelp)}
    @ViewBuilder var rangeButton:some View {
        if hidden>0 || store.automationViewport.fittedBeats != nil {
            Button(hidden>0 ? "전체 점 보기 (\(hidden))":"서클 길이 보기") {
                act {if hidden>0 {store.automationViewport.fit(base:store.automationBeats,points:lane?.points ?? [])}else{store.automationViewport.reset()}}
            }.help("전체 점에 맞춘 범위는 편집 중 유지됩니다. 새 점이 범위 밖에 있으면 다시 맞출 수 있습니다.")
        }
    }
    func act(_ action:()->Void){action();focusTarget.focus()}
    func pointValue(_ point:AutomationPoint,_ key:WritableKeyPath<AutomationPoint,Double>)->Binding<Double> {
        let address=store.hierarchySelection,original=store.editOriginal,parameter=store.automationParameter,projectID=store.project.id,generation=store.mediaImportGeneration
        return Binding(get:{store.currentAutomation?.points.first{$0.id==point.id}?[keyPath:key] ?? point[keyPath:key]},set:{v in
            guard store.project.id==projectID,store.mediaImportGeneration==generation,store.hierarchySelection==address,store.editOriginal==original,store.automationParameter==parameter,
                  var p=store.currentAutomation?.points.first(where:{$0.id==point.id}) else{return}
            p[keyPath:key]=v;store.editAutomationPoint(p)
        })
    }
}
@MainActor final class AutomationFocusTarget {
    weak var view:AutomationPlotView?
    func focus(){guard let view,view.allowsEditing else{return};view.window?.makeFirstResponder(view)}
}
struct AutomationPlot:NSViewRepresentable {
    @ObservedObject var store:AppStore
    let displayBeats:Double
    let focusTarget:AutomationFocusTarget
    let fieldFocus:NumberFieldFocus
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context:Context)->AutomationPlotView {let view=AutomationPlotView(store:store);focusTarget.view=view;return view}
    func updateNSView(_ view:AutomationPlotView,context:Context){
        view.fieldFocus=fieldFocus
        view.displayBeats=displayBeats;view.plotClock=store.automationClock;view.allowsEditing=enabled
        if !enabled || (view.dragIdentity != nil && (view.dragIdentity != store.numberEditIdentity || view.dragExtent != displayBeats)) {view.preview=nil;view.origin=nil;view.dragIdentity=nil;view.dragExtent=nil}
        view.needsDisplay=true
    }
}
@MainActor final class AutomationPlotView:NSView {
    let store:AppStore
    var preview:AutomationPoint?,origin:AutomationPoint?
    var dragIdentity:NumberEditIdentity?
    var dragExtent:Double?
    var dragFrame:NSRect?
    var allowsEditing=true
    var fieldFocus:NumberFieldFocus?
    var displayBeats=32.0
    var plotClock:MusicClock?
    var accessibilityPoints:[ID:AutomationPointAccessibility]=[:]
    var accessibilityIdentity:NumberEditIdentity?
    var accessibilityExtent:Double?
    var accessibilityClock:MusicClock?
    var accessibilityOrbital:Bool?
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    init(store:AppStore){self.store=store;super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("오토메이션 곡선 · Tab 첫 수치 · Shift Tab 마지막 수치 · Return 점 추가 · 대괄호 점 선택 · Home·End 첫·끝 점 · 방향키 시간과 값 · Delete 삭제 · 겹친 점 Option 클릭")}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();store.fulfillEditorFocusWhenMounted(self)}
    override func layout() {
        super.layout()
        if let dragFrame,dragFrame != convert(bounds,to:nil) {
            preview=nil;origin=nil;dragIdentity=nil;dragExtent=nil;self.dragFrame=nil;needsDisplay=true
        }
    }
    var rect:NSRect {bounds.insetBy(dx:42,dy:24)}
    var center:NSPoint {NSPoint(x:bounds.midX,y:bounds.midY)}
    var radius:Double {max(20,min(rect.width,rect.height)/2)}
    var orbital:Bool {store.project.usesOrbits}
    var displaySeconds:Double {plotClock?.seconds(at:displayBeats) ?? displayBeats}
    func phase(_ beat:Double)->Double {(plotClock?.seconds(at:beat) ?? beat)/max(1e-9,displaySeconds)}
    func beat(_ phase:Double)->Double {plotClock?.beat(atSeconds:phase*displaySeconds) ?? phase*displayBeats}
    var points:[AutomationPoint] {
        var points=store.currentAutomation?.points ?? []
        if let preview,let i=points.firstIndex(where:{$0.id==preview.id}){points[i]=preview}
        return points.sorted{$0.beat<$1.beat}
    }
    func normalized(_ v:Double)->Double {AutomationDisplay.normalized(v,parameter:store.automationParameter)}
    func value(_ n:Double)->Double {AutomationDisplay.value(atNormalized:n,parameter:store.automationParameter)}
    func position(_ p:AutomationPoint)->NSPoint {
        position(beat:p.beat,value:p.value)
    }
    func position(beat:Double,value:Double)->NSPoint {
        let n=normalized(value),x=orbital ? phase(beat):beat/displayBeats
        return orbital ? OrbitDrawing.point(center,radius:radius*(0.3+0.7*n),phase:x):NSPoint(x:rect.minX+x*rect.width,y:rect.maxY-n*rect.height)
    }
    func coordinate(_ p:NSPoint)->(Double,Double) {
        let phase=orbital ? OrbitTimeline.phase(Point(p.x-center.x,p.y-center.y)):max(0,min(1,(p.x-rect.minX)/max(1,rect.width)))
        let n=orbital ? max(0,min(1,(hypot(p.x-center.x,p.y-center.y)/radius-0.3)/0.7)):max(0,min(1,(rect.maxY-p.y)/max(1,rect.height)))
        return (orbital ? beat(phase):phase*displayBeats,value(n))
    }
    override func draw(_ dirtyRect:NSRect) {
        let parameter=store.automationParameter,points=points,lane=AutomationLane(parameter:parameter,points:points)
        var occupied:[NSRect]=[]
        let levels:[Double]
        switch parameter {case .gain:levels=[0,1,4];case .pan:levels=[-1,0,1];case .synthCutoff:levels=[40,400,4000,20000];case .synthResonance:levels=[0,0.3,0.6,0.9]}
        for (index,v) in levels.enumerated() {
            let n=normalized(v),path=NSBezierPath()
            if orbital {path.append(OrbitDrawing.arc(center,radius:radius*(0.3+0.7*n),from:0,to:1))}
            else {path.move(to:NSPoint(x:rect.minX,y:rect.maxY-n*rect.height));path.line(to:NSPoint(x:rect.maxX,y:rect.maxY-n*rect.height))}
            StudioTheme.lineNS.setStroke();path.lineWidth=1;path.stroke()
            let label:String
            switch parameter {
            case .gain:label=GainScale.text(v)
            case .pan:label=v<0 ? "L":v>0 ? "R":"C"
            case .synthResonance:label=String(format:"%.0f%%",v*100)
            case .synthCutoff:label=v>=1000 ? String(format:"%.0fk",v/1000):String(format:"%.0f",v)
            }
            let text=label+(orbital && parameter == .gain ? " dB":parameter == .synthCutoff ? " Hz":""),at=orbital ? NSPoint(x:48,y:rect.minY+Double(index)*20):NSPoint(x:parameter == .synthCutoff || parameter == .synthResonance ? 23:18,y:rect.maxY-n*rect.height)
            occupied.append(labelRect(text,at:at,size:11))
            OrbitDrawing.text(text,at:at,size:11,color:StudioTheme.secondaryNS)
        }
        if !orbital {
            let end=BeatPosition.text(displayBeats)+"박",at=NSPoint(x:rect.maxX-12,y:bounds.height-12)
            occupied.append(labelRect(end,at:at,size:11));OrbitDrawing.text(end,at:at,size:11)
        }
        let barLabels=drawBarRuler(avoiding:occupied)
        let curve=NSBezierPath()
        // Evaluate in stored units before mapping to the display axis. In particular,
        // Hz-linear cutoff sweeps are curved on the logarithmic frequency axis.
        let samples=(0...720).map {orbital ? beat(Double($0)/720):Double($0)/720*displayBeats}
        let sampleBeats=Set(samples+points.filter{$0.beat>=0 && $0.beat<=displayBeats}.map(\.beat)).sorted()
        var holdEnds:[Double:Double]=[:]
        for (left,right) in zip(points,points.dropFirst()) where left.shape == .hold {holdEnds[right.beat]=left.value}
        for (index,beat) in sampleBeats.enumerated() {
            if index>0,let held=holdEnds[beat] {curve.line(to:position(beat:beat,value:held))}
            let p=position(beat:beat,value:points.isEmpty ? store.automationFallback:lane.value(at:beat))
            if index==0 {curve.move(to:p)}else{curve.line(to:p)}
        }
        (store.currentAutomation?.enabled == false ? StudioTheme.secondaryNS:StudioTheme.accentNS).setStroke();curve.lineWidth=2;curve.stroke()
        let visiblePoints=points.filter{$0.beat<=displayBeats}
        for p in visiblePoints.filter({$0.id != store.selectedAutomationPointID})+visiblePoints.filter({$0.id == store.selectedAutomationPointID}) {
            let selected=p.id==store.selectedAutomationPointID
            OrbitDrawing.dot(position(p),radius:selected ? 6:4,color:selected ? StudioTheme.textNS:StudioTheme.accentNS)
        }
        if orbital {
            if radius>70 {OrbitDrawing.text(String(format:"길이 %.2f박",displayBeats),at:center,size:12,color:StudioTheme.textNS)}
        } else {
            if plotClock==nil {OrbitDrawing.text("1",at:NSPoint(x:rect.minX,y:bounds.height-9),size:11)}
        }
        let help="표시 위치 1–"+BeatPosition.text(displayBeats)+"박"+" · 마디 눈금 "+barLabels.joined(separator:", ")+" · 길이 밖은 마지막 박자 기준 · 겹친 점은 Option 클릭으로 순환 선택"
        setAccessibilityHelp(help);if toolTip != help {toolTip=help}
        setAccessibilityValue(store.selectedAutomationPoint.map{pointDescription($0)} ?? "선택한 점 없음")
        if window != nil {
            let identity=store.numberEditIdentity
            if identity != accessibilityIdentity || displayBeats != accessibilityExtent || plotClock != accessibilityClock || orbital != accessibilityOrbital {
                accessibilityPoints=[:];accessibilityIdentity=identity;accessibilityExtent=displayBeats;accessibilityClock=plotClock;accessibilityOrbital=orbital
            }
            let visible=points.filter{$0.beat<=displayBeats};let ids=Set(visible.map(\.id))
            accessibilityPoints=accessibilityPoints.filter{ids.contains($0.key)}
            let children=visible.enumerated().map { i,p -> NSAccessibilityElement in
                let child=accessibilityPoints[p.id] ?? AutomationPointAccessibility(parent:self,id:p.id);accessibilityPoints[p.id]=child
                child.setAccessibilityLabel("\(i+1)번 점 · "+pointDescription(p))
                child.setAccessibilityValue(p.id==store.selectedAutomationPointID ? "선택됨":"")
                let pt=position(p);child.setFrameInView(NSRect(x:pt.x-7,y:pt.y-7,width:14,height:14),view:self)
                return child
            };setAccessibilityChildren(children)
        }
    }
    func pointDescription(_ point:AutomationPoint)->String {
        [AutomationRuler.text(at:point.beat,clock:plotClock),AutomationDisplay.time(point.beat,clock:plotClock),AutomationDisplay.value(point.value,parameter:store.automationParameter)].compactMap{$0}.joined(separator:" · ")
    }
    func labelRect(_ text:String,at point:NSPoint,size:Double)->NSRect {
        let measured=(text as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:size)])
        return NSRect(x:point.x-measured.width/2,y:point.y-size/2,width:measured.width,height:measured.height)
    }
    func drawBarRuler(avoiding reserved:[NSRect])->[String] {
        var occupied=reserved,labels:[String]=[]
        let capacity=Int(max(1,orbital ? 2*Double.pi*radius/70:rect.width/80))
        for tick in AutomationRuler.ticks(clock:plotClock,end:displayBeats,capacity:capacity) {
            let text=orbital ? String(tick.bar):"\(tick.bar)마디",size=orbital ? 10.0:11.0
            let gridX=rect.minX+tick.beat/displayBeats*rect.width
            var point=orbital ? OrbitDrawing.point(center,radius:radius+16,phase:phase(tick.beat)):NSPoint(x:gridX,y:bounds.height-12)
            if !orbital,tick.bar==1 {point.x+=labelRect(text,at:point,size:size).width/2+2}
            let frame=labelRect(text,at:point,size:size)
            guard bounds.contains(frame),!occupied.contains(where:{$0.insetBy(dx:-5,dy:-2).intersects(frame)}) else{continue}
            occupied.append(frame);labels.append(String(tick.bar))
            if orbital {OrbitDrawing.dot(OrbitDrawing.point(center,radius:radius+8,phase:phase(tick.beat)),radius:1.5,color:StudioTheme.secondaryNS)}
            else {
                let line=NSBezierPath();line.move(to:NSPoint(x:gridX,y:rect.minY));line.line(to:NSPoint(x:gridX,y:rect.maxY))
                StudioTheme.lineNS.withAlphaComponent(0.6).setStroke();line.lineWidth=1;line.stroke()
            }
            OrbitDrawing.text(text,at:point,size:size)
        }
        return labels
    }
    override func mouseDown(with event:NSEvent) {
        guard allowsEditing else{return}
        window?.makeFirstResponder(self);let p=convert(event.locationInWindow,from:nil)
        let hits=points.filter{$0.beat<=displayBeats && hypot(position($0).x-p.x,position($0).y-p.y)<12}
        let hitID=AutomationDisplay.hit(in:hits.map(\.id),selected:store.selectedAutomationPointID,cycle:event.modifierFlags.contains(.option))
        if let hit=hits.first(where:{$0.id==hitID}) {
            store.selectedAutomationPointID=hit.id;origin=hit;preview=hit;dragIdentity=store.numberEditIdentity;dragExtent=displayBeats;dragFrame=convert(bounds,to:nil)
        } else {
            let (q,v)=coordinate(p),grid=Double(store.automationContext.beatGrid.subdivisions),beat=min(displayBeats,max(0,(q*grid).rounded()/grid))
            if let existing=points.first(where:{abs($0.beat-beat)<1e-9}){store.selectedAutomationPointID=existing.id}
            else{store.editAutomationPoint(AutomationPoint(beat:beat,value:v))}
        };needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard allowsEditing,var point=origin,dragIdentity==store.numberEditIdentity,dragExtent==displayBeats,dragFrame==convert(bounds,to:nil) else{return}
        let (q,v)=coordinate(convert(event.locationInWindow,from:nil)),grid=Double(store.automationContext.beatGrid.subdivisions)
        point.beat=min(displayBeats,max(0,event.modifierFlags.contains(.shift) ? q:(q*grid).rounded()/grid));point.value=v
        let others=points.filter{$0.id != point.id};guard !others.contains(where:{abs($0.beat-point.beat)<1e-9}) else{return}
        preview=point;needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        defer{origin=nil;preview=nil;dragIdentity=nil;dragExtent=nil;dragFrame=nil;needsDisplay=true}
        guard allowsEditing,let preview,preview != origin,dragIdentity==store.numberEditIdentity,dragExtent==displayBeats,dragFrame==convert(bounds,to:nil) else{return}
        store.editAutomationPoint(preview)
    }
    override func keyDown(with event:NSEvent) {
        if !allowsEditing || event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control){super.keyDown(with:event);return}
        switch event.keyCode {
        case 33:store.chooseAutomationPoint(-1)
        case 30:store.chooseAutomationPoint(1)
        case 115:store.chooseAutomationBoundary(last:false)
        case 119:store.chooseAutomationBoundary(last:true)
        case 48:
            if !event.modifierFlags.contains(.option) {
                if store.selectedAutomationPoint != nil,
                   fieldFocus?.enter(last:event.modifierFlags.contains(.shift),in:window)==true {return}
                // An empty lane has no numeric fields. Traverse controls explicitly instead
                // of bubbling Tab to the parent canvas, where it selects another circle.
                if event.modifierFlags.contains(.shift) {window?.selectPreviousKeyView(self)} else {window?.selectNextKeyView(self)}
                return
            }
            super.keyDown(with:event)
        case 36,76:store.addAutomationPoint()
        case 51,117:store.removeAutomationPoint()
        case 53:preview=nil;origin=nil;dragIdentity=nil;dragExtent=nil;store.automationOpen=false
        case 123,124,125,126:
            guard var p=store.selectedAutomationPoint else{return}
            if event.keyCode==123 || event.keyCode==124 {p.beat=max(0,min(max(displayBeats,p.beat),p.beat+(event.keyCode==123 ? -1:1)/Double(store.automationContext.beatGrid.subdivisions)))}
            else {p.value=AutomationDisplay.nudge(p.value,parameter:store.automationParameter,direction:event.keyCode==125 ? -1:1,fine:event.modifierFlags.contains(.option),coarse:event.modifierFlags.contains(.shift))}
            store.editAutomationPoint(p)
        default:super.keyDown(with:event)
        };needsDisplay=true
    }
}
@MainActor final class AutomationPointAccessibility:NSAccessibilityElement {
    weak var plot:AutomationPlotView?
    let pointID:ID
    let identity:NumberEditIdentity,extent:Double,clock:MusicClock?,orbital:Bool
    init(parent:AutomationPlotView,id:ID){plot=parent;pointID=id;identity=parent.store.numberEditIdentity;extent=parent.displayBeats;clock=parent.plotClock;orbital=parent.orbital;super.init();setAccessibilityParent(parent);setAccessibilityRole(.button);setAccessibilityEnabled(parent.allowsEditing)}
    override func accessibilityPerformPress()->Bool {
        guard let plot,plot.window != nil,plot.allowsEditing,plot.store.numberEditIdentity==identity,
              plot.displayBeats==extent,plot.plotClock==clock,plot.orbital==orbital,
              plot.points.contains(where:{$0.id==pointID && $0.beat<=plot.displayBeats}) else{return false}
        plot.window?.makeFirstResponder(plot);plot.store.selectedAutomationPointID=pointID;plot.needsDisplay=true;return true
    }
}
