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
    var lane:AutomationLane? {store.currentAutomation}
    var body:some View {
        GeometryReader { geometry in
            HStack(alignment:.top,spacing:24) {
                AutomationPlot(store:store).frame(width:min(430,geometry.size.width*0.43),height:geometry.size.height)
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        HStack(spacing:12) {
                            Picker("오토메이션 대상",selection:$store.automationParameter){ForEach(AutomationParameter.allCases,id:\.self){Text($0.label).tag($0)}}.pickerStyle(.segmented).labelsHidden().frame(width:130)
                            Toggle("적용",isOn:Binding(get:{lane?.enabled ?? false},set:{store.setAutomation(enabled:$0)})).disabled(lane==nil).fixedSize()
                            Text("\(lane?.points.count ?? 0)개 점").foregroundStyle(StudioTheme.secondary).fixedSize()
                        }
                        HStack(spacing:12) {
                            Button("점 추가"){store.addAutomationPoint()}
                            Button("점 삭제"){store.removeAutomationPoint()}.disabled(store.selectedAutomationPoint==nil)
                            Button("곡선 지우기"){store.setAutomation([])}.disabled(lane==nil)
                        }
                        Text(store.automationNode?.lengthBeats.map{String(format:"개별 %.2f박 · %d회 반복",$0,store.automationNode?.repeatCount ?? 1)} ?? "서클 시작부터 연속 진행\n자동 오디오 반복에도 곡선 유지")
                            .font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                        HStack(spacing:12) {
                            Button("이전 점"){store.chooseAutomationPoint(-1)}.disabled(lane==nil)
                            Button("다음 점"){store.chooseAutomationPoint(1)}.disabled(lane==nil)
                        }
                        if let p=store.selectedAutomationPoint {
                            HStack(spacing:14) {
                                ValueField(title:"위치 박",value:pointValue(p,\.beat),range:0...1_048_576)
                                ValueField(title:store.automationParameter == .gain ? "볼륨 배율":"팬 L/R",value:pointValue(p,\.value),range:store.automationParameter.range)
                            }
                            HStack(spacing:14) {
                                Text("다음 점까지").foregroundStyle(StudioTheme.secondary)
                                Picker("다음 점까지",selection:Binding(get:{p.shape},set:{v in var q=p;q.shape=v;store.editAutomationPoint(q)})){Text("선형").tag(AutomationShape.linear);Text("유지").tag(AutomationShape.hold)}.labelsHidden().frame(width:100)
                            }
                        } else {Text("빈 곳 클릭 또는 점 추가").foregroundStyle(StudioTheme.secondary)}
                        Text(store.automationParameter == .gain ? "×1 = 원래 볼륨 · ×0 = 무음":"-1 왼쪽 · 0 중앙 · +1 오른쪽").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                        let hidden=lane?.points.filter{$0.beat>store.automationBeats}.count ?? 0
                        Text(hidden>0 ? "표시 범위 밖 \(hidden)개 점 · 이전/다음 점으로 선택":"드래그로 이동 · 방향키 시간·값\n[ ] 점 선택 · Delete 삭제 · ⌥ 클릭 끝점 선택")
                            .font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,8)
                }.frame(maxWidth:.infinity)
            }
        }.onChange(of:store.automationParameter){_,_ in store.selectedAutomationPointID=lane?.points.first?.id}
    }
    func pointValue(_ point:AutomationPoint,_ key:WritableKeyPath<AutomationPoint,Double>)->Binding<Double> {
        Binding(get:{point[keyPath:key]},set:{v in var p=point;p[keyPath:key]=v;store.editAutomationPoint(p)})
    }
}
struct AutomationPlot:NSViewRepresentable {
    @ObservedObject var store:AppStore
    func makeNSView(context:Context)->AutomationPlotView {AutomationPlotView(store:store)}
    func updateNSView(_ view:AutomationPlotView,context:Context){view.displayBeats=store.automationBeats;view.plotClock=store.automationClock;view.needsDisplay=true}
}
@MainActor final class AutomationPlotView:NSView {
    let store:AppStore
    var preview:AutomationPoint?,origin:AutomationPoint?,revision=0
    var address:CircleAddress?,parameter:AutomationParameter = .gain
    var displayBeats=32.0
    var plotClock:MusicClock?
    var accessibilityPoints:[ID:AutomationPointAccessibility]=[:]
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    init(store:AppStore){self.store=store;super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityRole(.group);setAccessibilityLabel("오토메이션 곡선 · Return 점 추가 · 대괄호 점 선택 · 방향키 시간과 값 · Delete 삭제")}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();DispatchQueue.main.async{[weak self] in guard let self,let window=self.window,!(window.firstResponder is NSTextView) else{return};window.makeFirstResponder(self)}}
    var rect:NSRect {bounds.insetBy(dx:28,dy:24)}
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
        for v in parameter == .gain ? [0.0,1,4]:[-1.0,0,1] {
            let n=normalized(v),path=NSBezierPath()
            if orbital {path.append(OrbitDrawing.arc(center,radius:radius*(0.3+0.7*n),from:0,to:1))}
            else {path.move(to:NSPoint(x:rect.minX,y:rect.maxY-n*rect.height));path.line(to:NSPoint(x:rect.maxX,y:rect.maxY-n*rect.height))}
            StudioTheme.lineNS.setStroke();path.lineWidth=1;path.stroke()
            let label=parameter == .gain ? String(format:"×%.0f",v):(v<0 ? "L":v>0 ? "R":"C")
            OrbitDrawing.text(label,at:orbital ? NSPoint(x:center.x+radius*(0.3+0.7*n),y:center.y+12):NSPoint(x:12,y:rect.maxY-n*rect.height),size:10)
        }
        let curve=NSBezierPath()
        for i in 0...720 {
            let beat=orbital ? beat(Double(i)/720):Double(i)/720*displayBeats,p=position(beat:beat,value:lane.value(at:beat))
            if i==0 {curve.move(to:p)}else{curve.line(to:p)}
        }
        (store.currentAutomation?.enabled == false ? StudioTheme.secondaryNS:StudioTheme.accentNS).setStroke();curve.lineWidth=2;curve.stroke()
        for p in points where p.beat<=displayBeats {
            let selected=p.id==store.selectedAutomationPointID
            OrbitDrawing.dot(position(p),radius:selected ? 6:4,color:selected ? StudioTheme.textNS:StudioTheme.accentNS)
        }
        if orbital {
            if radius>70 {OrbitDrawing.text(String(format:"%.2f박",displayBeats),at:center,size:12,color:StudioTheme.textNS)}
            let ticks=plotClock?.barStarts.filter{$0<displayBeats} ?? [0]
            let stride=max(1,Int(ceil(Double(ticks.count)/16)))
            for i in ticks.indices where i%stride==0 {
                let p=OrbitDrawing.point(center,radius:radius+12,phase:phase(ticks[i]))
                OrbitDrawing.dot(p,radius:1.5,color:StudioTheme.secondaryNS)
                OrbitDrawing.text("\(i+1)",at:OrbitDrawing.point(center,radius:radius+23,phase:phase(ticks[i])),size:10)
            }
        } else {
            OrbitDrawing.text("0",at:NSPoint(x:rect.minX,y:bounds.height-9),size:10)
            OrbitDrawing.text(String(format:"%.2f박",displayBeats),at:NSPoint(x:rect.maxX-12,y:bounds.height-9),size:10)
        }
        setAccessibilityValue(store.selectedAutomationPoint.map{String(format:"%.3f박 · %.3f",$0.beat,$0.value)} ?? "선택한 점 없음")
        if let window {
            let visible=points.filter{$0.beat<=displayBeats};let ids=Set(visible.map(\.id))
            accessibilityPoints=accessibilityPoints.filter{ids.contains($0.key)}
            let children=visible.enumerated().map { i,p -> NSAccessibilityElement in
                let child=accessibilityPoints[p.id] ?? AutomationPointAccessibility(parent:self,id:p.id);accessibilityPoints[p.id]=child
                child.setAccessibilityLabel(String(format:"%d번 점 · %.3f박 · %.3f",i+1,p.beat,p.value))
                child.setAccessibilityValue(p.id==store.selectedAutomationPointID ? "선택됨":"")
                let pt=position(p);child.setAccessibilityFrame(window.convertToScreen(convert(NSRect(x:pt.x-7,y:pt.y-7,width:14,height:14),to:nil)))
                return child
            };setAccessibilityChildren(children)
        }
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self);let p=convert(event.locationInWindow,from:nil)
        let hits=points.filter{$0.beat<=store.automationBeats && hypot(position($0).x-p.x,position($0).y-p.y)<12}
        if let hit=event.modifierFlags.contains(.option) ? hits.last:hits.first {
            store.selectedAutomationPointID=hit.id;origin=hit;preview=hit;revision=store.project.musicRevision;address=store.hierarchySelection;parameter=store.automationParameter
        } else {
            let (q,v)=coordinate(p),grid=Double(store.automationContext.beatGrid.subdivisions),beat=min(store.automationBeats,max(0,(q*grid).rounded()/grid))
            if let existing=points.first(where:{abs($0.beat-beat)<1e-9}){store.selectedAutomationPointID=existing.id}
            else{store.editAutomationPoint(AutomationPoint(beat:beat,value:v))}
        };needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard var point=origin,store.project.musicRevision==revision,store.hierarchySelection==address,store.automationParameter==parameter else{return}
        let (q,v)=coordinate(convert(event.locationInWindow,from:nil)),grid=Double(store.automationContext.beatGrid.subdivisions)
        point.beat=min(store.automationBeats,max(0,event.modifierFlags.contains(.shift) ? q:(q*grid).rounded()/grid));point.value=v
        let others=points.filter{$0.id != point.id};guard !others.contains(where:{abs($0.beat-point.beat)<1e-9}) else{return}
        preview=point;needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        defer{origin=nil;preview=nil;needsDisplay=true}
        guard let preview,preview != origin,store.project.musicRevision==revision,store.hierarchySelection==address,store.automationParameter==parameter else{return}
        store.editAutomationPoint(preview)
    }
    override func keyDown(with event:NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control){super.keyDown(with:event);return}
        switch event.keyCode {
        case 33:store.chooseAutomationPoint(-1)
        case 30:store.chooseAutomationPoint(1)
        case 36,76:store.addAutomationPoint()
        case 51,117:store.removeAutomationPoint()
        case 53:preview=nil;origin=nil;store.automationOpen=false
        case 123,124,125,126:
            guard var p=store.selectedAutomationPoint else{return}
            if event.keyCode==123 || event.keyCode==124 {p.beat=max(0,min(store.automationBeats,p.beat+(event.keyCode==123 ? -1:1)/Double(store.automationContext.beatGrid.subdivisions)))}
            else {p.value=max(store.automationParameter.range.lowerBound,min(store.automationParameter.range.upperBound,p.value+(event.keyCode==125 ? -1:1)*(event.modifierFlags.contains(.shift) ? 0.25:0.05)))}
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
        guard let plot,plot.points.contains(where:{$0.id==pointID}) else{return false}
        plot.window?.makeFirstResponder(plot);plot.store.selectedAutomationPointID=pointID;plot.needsDisplay=true;return true
    }
}
