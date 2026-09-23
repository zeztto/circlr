import AppKit
import SwiftUI
import CirclrCore

struct CableToolsView: View {
    let title: String
    let compact: Bool
    let mode: CircleCableGesture.Mode
    let canReconnect: Bool
    let direction: CirclePortDirection
    let placement: CircleConnectionPlacement
    let chooseMode: (CircleCableGesture.Mode) -> Void
    let chooseEnd: (CirclePortDirection) -> Void
    let edit: () -> Void
    let disconnect: () -> Void
    let close: () -> Void

    @ViewBuilder private var modeButtons: some View {
        if canReconnect { Button("재연결") { chooseMode(.reconnect) }.foregroundStyle(mode == .reconnect ? StudioTheme.accent:StudioTheme.text) }
        Button("위치 이동") { chooseMode(.placement) }.foregroundStyle(mode == .placement ? StudioTheme.accent:StudioTheme.text)
    }

    @ViewBuilder private var endpointButtons: some View {
        Button("OUT · \(placement.from.label)") { chooseEnd(.output) }
            .foregroundStyle(direction == .output ? StudioTheme.accent : StudioTheme.text).accessibilityLabel("OUT 끝점 선택 · \(placement.from.label)")
        Button("IN · \(placement.to.label)") { chooseEnd(.input) }
            .foregroundStyle(direction == .input ? StudioTheme.accent : StudioTheme.text).accessibilityLabel("IN 끝점 선택 · \(placement.to.label)")
    }

    @ViewBuilder private var editButtons: some View {
        if canReconnect { Button("편집", action: edit).help("선택 케이블을 바로 편집 · Return") }
        if canReconnect { Button("해제",action:disconnect) }
    }

    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text(title).lineLimit(1).truncationMode(.middle); Spacer(); Button("닫기",action:close) }
            if compact {
                HStack(spacing:12) { modeButtons; Spacer(minLength:8); editButtons }
                HStack(spacing:12) { endpointButtons; Spacer(minLength:0) }
            } else {
                HStack(spacing:12) { modeButtons; endpointButtons; Spacer(); editButtons }
            }
            Text(canReconnect ? "Tab 끝점 · ← → 위치 · ↑ ↓ 케이블 · Return 편집" : "Tab 끝점 · ← → 위치 · ↑ ↓ 케이블")
                .foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
        }.font(.system(size:12)).buttonStyle(.plain).padding(12)
            .background(StudioTheme.surface).clipShape(RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(StudioTheme.accent.opacity(0.7)))
    }
}

extension AlbumCanvasView {
    func cableDiagnostics()->[String:Any] {
        ["selected":store.json(selectedCable),"selectedPort":store.json(selectedCanvasPort),"keyboardEnd":selectedCableEnd.rawValue,
         "editorIntent":store.json(store.connectionEditorIntent),"mode":cableMode.rawValue,"dragging":cableDrag != nil,
         "toolsFrame":cableTools.map{[$0.frame.minX,$0.frame.minY,$0.frame.width,$0.frame.height]} ?? [],
         "portToolsFrame":portTools.map{[$0.frame.minX,$0.frame.minY,$0.frame.width,$0.frame.height]} ?? [],
         "portLabels":portLabelPlacements().map{["endpoint":store.json($0.endpoint),"rect":[$0.rect.minX,$0.rect.minY,$0.rect.width,$0.rect.height]]},
         "timeHandle":store.selectedCircle.flatMap{visibleTimeHandle($0)}.map{[$0.x,$0.y]} ?? [],
         "handles":visiblePortHandles().map{["endpoint":store.json($0.endpoint),"octant":$0.octant.rawValue,"point":[$0.point.x,$0.point.y]]},
         "endpoints":cableEndpointHandles().map{["direction":$0.0.rawValue,"point":[$0.1.point.x,$0.1.point.y]]},
         "cables":(scene?.edges ?? []).compactMap{edge -> [String:Any]? in
             guard let a=scene?.node(edge.from),let b=scene?.node(edge.to),isVisible(a),isVisible(b),let curve=connectionCurve(edge) else{return nil}
             return ["id":store.json(edge.connectionID),"from":[curve.from.x,curve.from.y],"control1":[curve.control1.x,curve.control1.y],
                     "control2":[curve.control2.x,curve.control2.y],"to":[curve.to.x,curve.to.y]]
         }]
    }
    var selectedSceneCable: CircleSceneEdge? { guard let selectedCable else{return nil};return scene?.edges.first { $0.connectionID == selectedCable } }
    func clearCableSelection() {
        selectedCable=nil;selectedCanvasPort=nil;selectedCableEnd = .output;cableDrag=nil;connectionToken=nil
        cableTools?.removeFromSuperview();cableTools=nil;portTools?.removeFromSuperview();portTools=nil;needsDisplay=true
    }
    func selectCable(_ edge: CircleSceneEdge) {
        guard let id=edge.connectionID else{return}
        clearCableSelection()
        selectedCable=id;selectedCableProjectID=store.project.id;cableMode = .reconnect
        selectedCableEnd = .output
        if case .composition = id.from {cableMode = .placement}
        interruptPlaybackFollow();refreshCableTools();window?.makeFirstResponder(self);needsDisplay=true
    }
    func refreshCableTools() {
        defer { refreshPortTools() }
        guard selectedCableProjectID==store.project.id,let id=selectedCable,let edge=selectedSceneCable,
              let a=scene?.node(edge.from),let b=scene?.node(edge.to),isVisible(a),isVisible(b),let curve=connectionCurve(edge),store.movieWriter==nil,
              !(store.playback.playing && store.playbackFollow == .following),workspaceViewport.width>320 else {
            if selectedCableProjectID != store.project.id || selectedSceneCable==nil {selectedCable=nil}
            cableTools?.removeFromSuperview();cableTools=nil;return
        }
        func name(_ address:CircleAddress,_ portID:String)->String {
            let port=(try? CirclePortCatalog.ports(at:address,in:store.project))?.first{$0.id==portID}?.name ?? portID
            return (scene?.node(address)?.title ?? "접힌 그룹 내부")+" · "+port
        }
        let title=name(edge.from,edge.fromPortID)+" → "+name(edge.to,edge.toPortID)
        let canReconnect:Bool = {if case .composition = id.from {return false};return true}()
        let width=min(650,workspaceViewport.width-16),compact=workspaceViewport.width<900
        let view=CableToolsView(title:title,compact:compact,mode:cableMode,canReconnect:canReconnect,direction:selectedCableEnd,placement:edge.placement,chooseMode:{[weak self] mode in
            guard let self else{return};self.cableDrag=nil;self.connectionToken=nil;self.cableMode=mode;self.refreshCableTools();self.window?.makeFirstResponder(self);self.needsDisplay=true
        },chooseEnd:{[weak self] in self?.chooseCableEnd($0)},edit:{[weak self] in self?.editConnectionSelection()},
            disconnect:{[weak self] in self?.disconnectSelectedCable()},close:{[weak self] in self?.clearCableSelection()})
        if let cableTools {cableTools.rootView=view} else {let host=NSHostingView(rootView:view);addSubview(host);cableTools=host}
        let height=compact ? 136.0:102.0,middle=(try? curve.point(at:0.5)) ?? curve.from
        let x=max(workspaceViewport.minX+8,min(workspaceViewport.maxX-width-8,middle.x-width/2))
        let positions=[middle.y+30,middle.y-height-24,workspaceViewport.minY+8,workspaceViewport.maxY-height-8].map{max(workspaceViewport.minY+8,min(workspaceViewport.maxY-height-8,$0))}
        let y=positions.first {y in
            let rect=NSRect(x:x,y:y,width:width,height:height).insetBy(dx:-16,dy:-16)
            return !rect.contains(NSPoint(x:curve.from.x,y:curve.from.y)) && !rect.contains(NSPoint(x:curve.to.x,y:curve.to.y)) && editor?.frame.intersects(rect) != true
        } ?? workspaceViewport.minY+8
        cableTools?.frame=NSRect(x:x,y:y,width:width,height:height)
        cableTools?.isHidden=cableDrag != nil
    }
    func cablePointAvailable(_ point:Point,labels:Bool=true)->Bool {
        let p=NSPoint(x:point.x,y:point.y)
        return workspaceViewport.contains(p) && editor?.frame.contains(p) != true && !(cableTools?.isHidden == false && cableTools?.frame.contains(p) == true) &&
            !(portTools?.isHidden == false && portTools?.frame.contains(p) == true) &&
            (!labels || !labelPlacements.contains{$0.rect.insetBy(dx:-3,dy:-3).contains(p)})
    }
    func hitCable(_ point:NSPoint)->CircleSceneEdge? {
        guard cablePointAvailable(Point(point.x,point.y)) else{return nil}
        return scene?.edges.compactMap { edge -> (CircleSceneEdge,Double)? in
            guard edge.connectionID != nil,let a=scene?.node(edge.from),let b=scene?.node(edge.to),isVisible(a),isVisible(b),
                  let distance=connectionCurve(edge)?.distance(to:Point(point.x,point.y)),distance<=6 else{return nil}
            return (edge,distance)
        }.min{$0.1<$1.1}?.0
    }
    func cableEndpointHandles()->[(CirclePortDirection,CirclePortHandle)] {
        guard let edge=selectedSceneCable,
              let curve=connectionCurve(edge),cableTools != nil else{return []}
        let time = store.selectedCircle.flatMap { visibleTimeHandle($0) }
        return [(CirclePortDirection.output,CirclePortHandle(endpoint:.init(node:edge.from,portID:edge.fromPortID),octant:edge.placement.from,point:curve.from)),
                (.input,CirclePortHandle(endpoint:.init(node:edge.to,portID:edge.toPortID),octant:edge.placement.to,point:curve.to))].filter {
                    let endpoint=$0.1.endpoint,p=$0.1.point
                    return scene?.node(endpoint.node)?.ports.contains(where:{$0.id==endpoint.portID}) == true &&
                        cablePointAvailable(p) && (time.map{hypot($0.x-p.x,$0.y-p.y)>23} ?? true)
                }
    }
    func displayedMovingPort(_ gesture:CircleCableGesture)->CirclePortEndpoint {
        guard let edge=selectedSceneCable else {return gesture.moving}
        return .init(node:gesture.direction == .output ? edge.from:edge.to,portID:gesture.direction == .output ? edge.fromPortID:edge.toPortID)
    }
    func beginCableDrag(at point:NSPoint)->Bool {
        guard let hit=cableEndpointHandles().first(where:{hypot($0.1.point.x-point.x,$0.1.point.y-point.y)<=12}),let id=selectedCable else{return false}
        do {cableDrag=try CircleCableGesture(id:id,direction:hit.0,mode:cableMode,project:store.project);selectedCableEnd=hit.0;connectionToken=UUID();cableDragOriginal=store.editOriginal;connectionPoint=point;cableTools?.isHidden=true;needsDisplay=true}
        catch {store.status=error.localizedDescription}
        return true
    }
    func disconnectSelectedCable() {
        guard let id=selectedCable else{return};let original=store.editOriginal
        store.mutate("케이블 해제") {try CircleConnectionEditing.disconnect(id,original:original,in:&$0)}
        if (try? CirclePortCatalog.connections(in:store.project).contains{$0.id==id}) == false {clearCableSelection()}
    }
    func finishCableDrag(at point:NSPoint) {
        guard let gesture=cableDrag else{return}
        let original=cableDragOriginal,token=connectionToken
        func apply(_ endpoint:CirclePortEndpoint,_ octant:PortOctant) {
            guard token != nil,token==connectionToken else {store.status="이전 연결 조작은 취소되었습니다";return}
            var next:CircleConnectionID?
            store.mutate(gesture.mode == .placement ? "연결 위치 이동":"케이블 재연결",musical:gesture.mode != .placement,portLayoutOnly:gesture.mode == .placement) {p in
                next=try gesture.apply(to:endpoint,octant:octant,original:original,in:&p)
            }
            if let next {selectedCable=next}
        }
        guard cablePointAvailable(Point(point.x,point.y),labels:false) else{return}
        if gesture.mode == .placement {
            let endpoint=displayedMovingPort(gesture)
            guard let node=scene?.node(endpoint.node) else{return}
            let center=screen(node),radius=node.outerRadius*camera.zoom,distance=hypot(point.x-center.x,point.y-center.y)
            guard abs(distance-radius)<=115,let octant=CirclePortGeometry.nearestOctant(to:Point(point.x,point.y),center:Point(center.x,center.y)) else {store.status="위치 이동은 원래 서클 둘레에 놓으세요";return}
            apply(endpoint,octant);return
        }
        if let handle=CirclePortGeometry.hit(Point(point.x,point.y),visibleHandles:visiblePortHandles()) {apply(handle.endpoint,handle.octant);return}
        guard let target=hit(point) else{return}
        let center=screen(target)
        let fallback=target.id==gesture.moving.node ? (gesture.direction == .output ? gesture.placement.from:gesture.placement.to) : (gesture.direction == .output ? PortOctant.east:.west)
        let octant=CirclePortGeometry.dropOctant(to:Point(point.x,point.y),center:Point(center.x,center.y),radius:target.outerRadius*camera.zoom,fallback:fallback) ?? fallback
        let choices=target.ports.filter {port in
            port.direction==gesture.direction && (try? CirclePortCatalog.normalize(.init(node:target.id,portID:port.id),gesture.fixed,in:store.project)) != nil
        }
        if choices.count==1 {apply(.init(node:target.id,portID:choices[0].id),octant)}
        else if choices.count>1 {
            let menu=NSMenu(title:"재연결할 포트")
            for port in choices {
                let item=NSMenuItem(title:port.name,action:#selector(runCircleMenu(_:)),keyEquivalent:"")
                item.target=self;item.representedObject=CircleMenuAction{apply(.init(node:target.id,portID:port.id),octant)};menu.addItem(item)
            }
            menu.popUp(positioning:nil,at:point,in:self)
        } else {store.status="호환되는 포트를 선택하세요. 기존 연결은 유지됩니다"}
    }
    func drawCableEditing() {
        if cableTools != nil,let edge=selectedSceneCable,let curve=connectionCurve(edge) {wire(curve,color:StudioTheme.accentNS)}
        for (direction,handle) in cableEndpointHandles() {
            let p=NSPoint(x:handle.point.x,y:handle.point.y)
            StudioTheme.canvasNS.setFill();NSBezierPath(ovalIn:NSRect(x:p.x-10,y:p.y-10,width:20,height:20)).fill()
            StudioTheme.accentNS.setStroke();let ring=NSBezierPath(ovalIn:NSRect(x:p.x-10,y:p.y-10,width:20,height:20));ring.lineWidth=direction == selectedCableEnd ? 3.5:1.5;ring.stroke()
        }
        guard let gesture=cableDrag,let edge=selectedSceneCable,let curve=connectionCurve(edge) else{return}
        let fixedPoint=gesture.direction == .output ? curve.to:curve.from
        var moving=Point(connectionPoint.x,connectionPoint.y),octant=gesture.direction == .output ? edge.placement.from:edge.placement.to
        let displayed=displayedMovingPort(gesture)
        if gesture.mode == .placement,let node=scene?.node(displayed.node),let port=node.ports.first(where:{$0.id==displayed.portID}) {
            let center=screen(node)
            octant=CirclePortGeometry.nearestOctant(to:moving,center:Point(center.x,center.y)) ?? octant
            moving=(try? CirclePortGeometry.anchor(center:Point(center.x,center.y),radius:node.outerRadius*camera.zoom,port:port,octant:octant)) ?? moving
        } else if let handle=CirclePortGeometry.hit(moving,visibleHandles:visiblePortHandles()) {moving=handle.point;octant=handle.octant}
        let movingHandle=CirclePortHandle(endpoint:gesture.moving,octant:octant,point:moving)
        let fixedHandle=CirclePortHandle(endpoint:gesture.fixed,octant:gesture.fixedOctant,point:fixedPoint)
        if let preview=try? CirclePortGeometry.curve(from:gesture.direction == .output ? movingHandle:fixedHandle,to:gesture.direction == .output ? fixedHandle:movingHandle) {
            wire(preview,color:StudioTheme.textNS,dashed:true)
        }
    }
}
