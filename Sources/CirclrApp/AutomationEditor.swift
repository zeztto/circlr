import AppKit
import SwiftUI
import CirclrCore

extension AppStore {
    var automationNode:MusicCircle? {
        guard editOriginal,let id=selectedMusic?.id,let use=selectedUse else{return selectedMusic}
        return project.sections.first{$0.id==use.sectionID}?.graph?.nodes.first{$0.id==id}
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
    func showAutomation() {
        if selectedMusic?.supportsAutomation==false {openTrackComponent(1)}
        guard selectedMusic?.supportsAutomation==true,let address=hierarchySelection else{return}
        hierarchySettingsOpen=false;embeddedPlugin=nil;automationOpen=true;focusHierarchy(address,detail:true)
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
        editAutomationPoint(AutomationPoint(beat:free,value:currentAutomation?.value(at:free) ?? automationParameter.neutral))
    }
    func chooseAutomationPoint(_ delta:Int) {
        guard let points=currentAutomation?.points,!points.isEmpty else{return}
        let i=points.firstIndex{$0.id==selectedAutomationPointID} ?? (delta>0 ? -1:0)
        selectedAutomationPointID=points[(i+delta+points.count)%points.count].id
    }
    func removeAutomationPoint() {guard let point=selectedAutomationPoint else{return};setAutomation(currentAutomation?.points.filter{$0.id != point.id} ?? [])}
    func duplicateAutomationPoint() {
        guard var point=selectedAutomationPoint else{return};point.id=newID();point.beat+=1/Double(automationContext.beatGrid.subdivisions)
        guard point.beat<=automationBeats else{return};editAutomationPoint(point)
    }
}

struct AutomationEditor:View {
    @ObservedObject var store:AppStore
    @State private var focusTarget=AutomationFocusTarget()
    var lane:AutomationLane? {store.currentAutomation}
    var hidden:Int {lane?.points.filter{$0.beat>store.automationDisplayedBeats}.count ?? 0}
    var available:Bool {store.automationNode != nil}
    var body:some View {
        Group {if store.project.usesOrbits {orbital}else{linear}}
            .onChange(of:store.automationParameter){_,_ in store.selectedAutomationPointID=lane?.points.first?.id;focusTarget.focus()}
            .onChange(of:store.editOriginal){_,_ in store.selectedAutomationPointID=lane?.points.first?.id;focusTarget.focus()}
            .environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focusTarget.focus()}))
    }
    var plot:some View {AutomationPlot(store:store,displayBeats:store.automationDisplayedBeats,focusTarget:focusTarget).disabled(!available).help("겹친 점은 Option 클릭으로 순환 선택합니다. 일반 클릭은 현재 선택을 유지합니다.")}
    var linear:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:12){parameterControls;Spacer(minLength:8);originalToggle;pointActions}
            plot.frame(minHeight:80,maxHeight:.infinity)
            HStack(spacing:12) {
                navigation
                if let point=store.selectedAutomationPoint {
                    timeControl(point);valueControl(point);Spacer(minLength:8);shapeControl(point)
                }else{emptyHint;Spacer(minLength:0)}
            }.frame(height:32)
            HStack(spacing:12){scopeText.lineLimit(1);rangeButton;Spacer(minLength:4);valueHint.lineLimit(1)}
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
        }
    }
    var orbital:some View {
        HStack(alignment:.top,spacing:20) {
            VStack(alignment:.leading,spacing:12) {
                parameterControls
                pointActions
                originalToggle
                scopeText.font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                rangeButton
                Text("각도는 시간 · 반경은 "+store.automationParameter.label).font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                Spacer(minLength:0)
            }.frame(width:225,alignment:.leading)
            plot.frame(minWidth:100,maxWidth:.infinity,maxHeight:.infinity)
            VStack(alignment:.leading,spacing:12) {
                navigation
                if let point=store.selectedAutomationPoint {timeControl(point);valueControl(point);shapeControl(point)}else{emptyHint}
                valueHint.font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                Spacer(minLength:0)
            }.frame(width:250,alignment:.leading)
        }
    }
    var parameterControls:some View {
        HStack(spacing:10) {
            Picker("오토메이션 대상",selection:$store.automationParameter){ForEach(AutomationParameter.allCases,id:\.self){Text($0.label).tag($0)}}
                .pickerStyle(.segmented).labelsHidden().frame(width:112)
            Toggle("적용",isOn:Binding(get:{lane?.enabled ?? false},set:{store.setAutomation(enabled:$0)})).disabled(lane==nil).fixedSize()
            Text("\(lane?.points.count ?? 0)개 점").foregroundStyle(StudioTheme.secondary).fixedSize()
        }
    }
    var originalToggle:some View {Toggle("공유 원본 편집",isOn:$store.editOriginal).fixedSize()}
    var pointActions:some View {
        HStack(spacing:12) {
            Button("점 추가"){act{store.addAutomationPoint()}}.disabled(!available)
            Button("점 삭제"){act{store.removeAutomationPoint()}}.disabled(store.selectedAutomationPoint==nil)
            Menu("곡선") {
                Button("선택 점 복제"){act{store.duplicateAutomationPoint()}}.disabled(store.selectedAutomationPoint==nil)
                Button("곡선 지우기"){act{store.setAutomation([])}}.disabled(lane==nil)
            }.fixedSize()
        }
    }
    var navigation:some View {
        HStack(spacing:12) {
            Button {act{store.chooseAutomationPoint(-1)}} label:{Image(systemName:"chevron.left")}.help("이전 점 · [").accessibilityLabel("이전 오토메이션 점").disabled(lane==nil)
            Button {act{store.chooseAutomationPoint(1)}} label:{Image(systemName:"chevron.right")}.help("다음 점 · ]").accessibilityLabel("다음 오토메이션 점").disabled(lane==nil)
        }
    }
    func timeControl(_ point:AutomationPoint)->some View {
        HStack(spacing:10) {
            Text("위치").foregroundStyle(StudioTheme.secondary)
            CommittedNumberField(title:"오토메이션 위치 박",value:pointValue(point,\.beat),range:0...1_048_576,width:80)
            Text("박").foregroundStyle(StudioTheme.secondary)
        }
    }
    func valueControl(_ point:AutomationPoint)->some View {
        HStack(spacing:10) {
            Text(store.automationParameter.label).foregroundStyle(StudioTheme.secondary)
            CommittedNumberField(title:store.automationParameter == .gain ? "오토메이션 볼륨 dB":"오토메이션 팬 %",value:pointValue(point,\.value),range:store.automationParameter.range,width:84,
                presentation:store.automationParameter == .gain ? .gainDecibels:.panPercent)
            Text(store.automationParameter == .gain ? "dB":"%").foregroundStyle(StudioTheme.secondary)
        }
    }
    func shapeControl(_ point:AutomationPoint)->some View {
        let identity=store.numberEditIdentity
        return HStack(spacing:10) {
            Text("다음 점까지").foregroundStyle(StudioTheme.secondary)
            Picker("다음 점까지",selection:Binding(get:{store.selectedAutomationPoint?.shape ?? point.shape},set:{v in
                guard store.numberEditIdentity==identity,var current=store.selectedAutomationPoint,current.id==point.id else{return}
                current.shape=v;store.editAutomationPoint(current)
            })){Text("선형").tag(AutomationShape.linear);Text("유지").tag(AutomationShape.hold)}.pickerStyle(.segmented).labelsHidden().frame(width:112)
                .help("선형은 저장된 신호 배율 또는 팬 값을 연결합니다. 유지는 다음 점까지 값을 유지합니다.")
        }
    }
    var emptyHint:some View {Text(available ? "빈 곳 클릭 또는 점 추가 · Return":"이번 사용에 추가된 서클입니다. 공유 원본 편집을 끄고 조절하세요.").foregroundStyle(StudioTheme.secondary)}
    var valueHint:Text {Text(store.automationParameter == .gain ? "0 dB 원래 레벨 · −∞ 무음":"−100 왼쪽 · 0 중앙 · +100 오른쪽")}
    var scopeText:some View {
        let scope=store.editOriginal ? "공유 원본":"이번 사용"
        let timing=store.automationNode?.lengthBeats.map{String(format:"%.2f박 · %d회 반복",$0,store.automationNode?.repeatCount ?? 1)} ?? "서클 시작부터 연속 진행"
        return Text(scope+" · "+timing).help("위치는 서클 시작부터의 4분음표 박입니다. 개별 길이가 없는 오디오의 자동 반복에서도 곡선은 연속 진행합니다.")
    }
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
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context:Context)->AutomationPlotView {let view=AutomationPlotView(store:store);focusTarget.view=view;return view}
    func updateNSView(_ view:AutomationPlotView,context:Context){
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
    var allowsEditing=true
    var displayBeats=32.0
    var plotClock:MusicClock?
    var accessibilityPoints:[ID:AutomationPointAccessibility]=[:]
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    init(store:AppStore){self.store=store;super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("오토메이션 곡선 · Return 점 추가 · 대괄호 점 선택 · 방향키 시간과 값 · Delete 삭제 · 겹친 점 Option 클릭")}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();DispatchQueue.main.async{[weak self] in guard let self,let window=self.window,!(window.firstResponder is NSTextView) else{return};window.makeFirstResponder(self)}}
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
    func normalized(_ v:Double)->Double {store.automationParameter == .gain ? sqrt(max(0,min(4,v))/4):max(0,min(1,(v+1)/2))}
    func value(_ n:Double)->Double {store.automationParameter == .gain ? 4*n*n:2*n-1}
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
        let levels:[Double]=parameter == .gain ? [0,1,4]:[-1,0,1]
        for (index,v) in levels.enumerated() {
            let n=normalized(v),path=NSBezierPath()
            if orbital {path.append(OrbitDrawing.arc(center,radius:radius*(0.3+0.7*n),from:0,to:1))}
            else {path.move(to:NSPoint(x:rect.minX,y:rect.maxY-n*rect.height));path.line(to:NSPoint(x:rect.maxX,y:rect.maxY-n*rect.height))}
            StudioTheme.lineNS.setStroke();path.lineWidth=1;path.stroke()
            let label=parameter == .gain ? GainScale.text(v):(v<0 ? "L":v>0 ? "R":"C")
            OrbitDrawing.text(label+(orbital && parameter == .gain ? " dB":""),at:orbital ? NSPoint(x:48,y:rect.minY+Double(index)*20):NSPoint(x:18,y:rect.maxY-n*rect.height),size:11,color:StudioTheme.secondaryNS)
        }
        if !orbital,let clock=plotClock {
            let ticks=clock.barStarts.filter{$0<displayBeats}
            let stride=max(1,Int(ceil(Double(ticks.count)/max(1,rect.width/80))))
            for i in ticks.indices where i%stride==0 {
                let x=rect.minX+ticks[i]/displayBeats*rect.width
                let grid=NSBezierPath();grid.move(to:NSPoint(x:x,y:rect.minY));grid.line(to:NSPoint(x:x,y:rect.maxY))
                StudioTheme.lineNS.withAlphaComponent(0.6).setStroke();grid.lineWidth=1;grid.stroke()
                OrbitDrawing.text("\(i+1)마디",at:NSPoint(x:x,y:bounds.height-9),size:11)
            }
        }
        let curve=NSBezierPath()
        for i in 0...720 {
            let beat=orbital ? beat(Double(i)/720):Double(i)/720*displayBeats,p=position(beat:beat,value:lane.value(at:beat))
            if i==0 {curve.move(to:p)}else{curve.line(to:p)}
        }
        (store.currentAutomation?.enabled == false ? StudioTheme.secondaryNS:StudioTheme.accentNS).setStroke();curve.lineWidth=2;curve.stroke()
        let visiblePoints=points.filter{$0.beat<=displayBeats}
        for p in visiblePoints.filter({$0.id != store.selectedAutomationPointID})+visiblePoints.filter({$0.id == store.selectedAutomationPointID}) {
            let selected=p.id==store.selectedAutomationPointID
            OrbitDrawing.dot(position(p),radius:selected ? 6:4,color:selected ? StudioTheme.textNS:StudioTheme.accentNS)
        }
        if orbital {
            if radius>70 {OrbitDrawing.text(String(format:"%.2f박",displayBeats),at:center,size:12,color:StudioTheme.textNS)}
            let ticks=plotClock?.barStarts.filter{$0<displayBeats} ?? [0]
            let stride=max(1,Int(ceil(Double(ticks.count)/max(3,2*Double.pi*radius/70))))
            for i in ticks.indices where i%stride==0 {
                let p=OrbitDrawing.point(center,radius:radius+12,phase:phase(ticks[i]))
                OrbitDrawing.dot(p,radius:1.5,color:StudioTheme.secondaryNS)
                OrbitDrawing.text("\(i+1)",at:OrbitDrawing.point(center,radius:radius+23,phase:phase(ticks[i])),size:10)
            }
        } else {
            if plotClock==nil {OrbitDrawing.text("0",at:NSPoint(x:rect.minX,y:bounds.height-9),size:11)}
            OrbitDrawing.text(String(format:"%.2f박",displayBeats),at:NSPoint(x:rect.maxX-12,y:bounds.height-9),size:11)
        }
        setAccessibilityValue(store.selectedAutomationPoint.map{AutomationDisplay.time($0.beat,clock:plotClock)+" · "+AutomationDisplay.value($0.value,parameter:parameter)} ?? "선택한 점 없음")
        if let window {
            let visible=points.filter{$0.beat<=displayBeats};let ids=Set(visible.map(\.id))
            accessibilityPoints=accessibilityPoints.filter{ids.contains($0.key)}
            let children=visible.enumerated().map { i,p -> NSAccessibilityElement in
                let child=accessibilityPoints[p.id] ?? AutomationPointAccessibility(parent:self,id:p.id);accessibilityPoints[p.id]=child
                child.setAccessibilityLabel("\(i+1)번 점 · "+AutomationDisplay.time(p.beat,clock:plotClock)+" · "+AutomationDisplay.value(p.value,parameter:parameter))
                child.setAccessibilityValue(p.id==store.selectedAutomationPointID ? "선택됨":"")
                let pt=position(p);child.setAccessibilityFrame(window.convertToScreen(convert(NSRect(x:pt.x-7,y:pt.y-7,width:14,height:14),to:nil)))
                return child
            };setAccessibilityChildren(children)
        }
    }
    override func mouseDown(with event:NSEvent) {
        guard allowsEditing else{return}
        window?.makeFirstResponder(self);let p=convert(event.locationInWindow,from:nil)
        let hits=points.filter{$0.beat<=displayBeats && hypot(position($0).x-p.x,position($0).y-p.y)<12}
        let hitID=AutomationDisplay.hit(in:hits.map(\.id),selected:store.selectedAutomationPointID,cycle:event.modifierFlags.contains(.option))
        if let hit=hits.first(where:{$0.id==hitID}) {
            store.selectedAutomationPointID=hit.id;origin=hit;preview=hit;dragIdentity=store.numberEditIdentity;dragExtent=displayBeats
        } else {
            let (q,v)=coordinate(p),grid=Double(store.automationContext.beatGrid.subdivisions),beat=min(displayBeats,max(0,(q*grid).rounded()/grid))
            if let existing=points.first(where:{abs($0.beat-beat)<1e-9}){store.selectedAutomationPointID=existing.id}
            else{store.editAutomationPoint(AutomationPoint(beat:beat,value:v))}
        };needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard allowsEditing,var point=origin,dragIdentity==store.numberEditIdentity,dragExtent==displayBeats else{return}
        let (q,v)=coordinate(convert(event.locationInWindow,from:nil)),grid=Double(store.automationContext.beatGrid.subdivisions)
        point.beat=min(displayBeats,max(0,event.modifierFlags.contains(.shift) ? q:(q*grid).rounded()/grid));point.value=v
        let others=points.filter{$0.id != point.id};guard !others.contains(where:{abs($0.beat-point.beat)<1e-9}) else{return}
        preview=point;needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        defer{origin=nil;preview=nil;dragIdentity=nil;dragExtent=nil;needsDisplay=true}
        guard allowsEditing,let preview,preview != origin,dragIdentity==store.numberEditIdentity,dragExtent==displayBeats else{return}
        store.editAutomationPoint(preview)
    }
    override func keyDown(with event:NSEvent) {
        if !allowsEditing || event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control){super.keyDown(with:event);return}
        switch event.keyCode {
        case 33:store.chooseAutomationPoint(-1)
        case 30:store.chooseAutomationPoint(1)
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
    init(parent:AutomationPlotView,id:ID){plot=parent;pointID=id;super.init();setAccessibilityParent(parent);setAccessibilityRole(.button);setAccessibilityEnabled(true)}
    override func accessibilityPerformPress()->Bool {
        guard let plot,plot.allowsEditing,plot.points.contains(where:{$0.id==pointID}) else{return false}
        plot.window?.makeFirstResponder(plot);plot.store.selectedAutomationPointID=pointID;plot.needsDisplay=true;return true
    }
}
