import AppKit
import SwiftUI
import CirclrCore

struct CableToolsView: View {
    let title: String
    let mode: CircleCableGesture.Mode
    let canReconnect: Bool
    let chooseMode: (CircleCableGesture.Mode) -> Void
    let disconnect: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text(title).lineLimit(1).truncationMode(.middle); Spacer(); Button("닫기",action:close) }
            HStack(spacing:14) {
                if canReconnect { Button("재연결") { chooseMode(.reconnect) }.foregroundStyle(mode == .reconnect ? StudioTheme.accent:StudioTheme.text) }
                Button("위치 이동") { chooseMode(.placement) }.foregroundStyle(mode == .placement ? StudioTheme.accent:StudioTheme.text)
                Text(mode == .reconnect ? "OUT 또는 IN 끝점을 끌어 연결" : "끝점을 원래 서클 둘레로 이동").foregroundStyle(StudioTheme.secondary)
                Spacer()
                if canReconnect { Button("해제",action:disconnect) }
            }
        }.font(.system(size:12)).buttonStyle(.plain).padding(12)
            .background(StudioTheme.surface).clipShape(RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(StudioTheme.accent.opacity(0.7)))
    }
}

extension AlbumCanvasView {
    func cableDiagnostics()->[String:Any] {
        ["selected":store.json(selectedCable),"mode":cableMode.rawValue,"dragging":cableDrag != nil,
         "toolsFrame":cableTools.map{[$0.frame.minX,$0.frame.minY,$0.frame.width,$0.frame.height]} ?? [],
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
        selectedCable=nil;cableDrag=nil;connectionToken=nil;cableTools?.removeFromSuperview();cableTools=nil;needsDisplay=true
    }
    func selectCable(_ edge: CircleSceneEdge) {
        guard let id=edge.connectionID else{return}
        selectedCable=id;selectedCableProjectID=store.project.id;cableMode = .reconnect
        if case .composition = id.from {cableMode = .placement}
        refreshCableTools();needsDisplay=true
    }
    func refreshCableTools() {
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
        let title=name(id.from,edge.fromPortID)+" → "+name(id.to,edge.toPortID)
        let canReconnect:Bool = {if case .composition = id.from {return false};return true}()
        let view=CableToolsView(title:title,mode:cableMode,canReconnect:canReconnect,chooseMode:{[weak self] mode in
            guard let self else{return};self.cableDrag=nil;self.connectionToken=nil;self.cableMode=mode;self.refreshCableTools();self.window?.makeFirstResponder(self);self.needsDisplay=true
        },disconnect:{[weak self] in self?.disconnectSelectedCable()},close:{[weak self] in self?.clearCableSelection()})
        if let cableTools {cableTools.rootView=view} else {let host=NSHostingView(rootView:view);addSubview(host);cableTools=host}
        let width=min(650,workspaceViewport.width-16),middle=(try? curve.point(at:0.5)) ?? curve.from
        let x=max(workspaceViewport.minX+8,min(workspaceViewport.maxX-width-8,middle.x-width/2))
        let positions=[middle.y+30,middle.y-100,workspaceViewport.minY+8,workspaceViewport.maxY-82].map{max(workspaceViewport.minY+8,min(workspaceViewport.maxY-82,$0))}
        let y=positions.first {y in
            let rect=NSRect(x:x,y:y,width:width,height:74).insetBy(dx:-16,dy:-16)
            return !rect.contains(NSPoint(x:curve.from.x,y:curve.from.y)) && !rect.contains(NSPoint(x:curve.to.x,y:curve.to.y)) && editor?.frame.intersects(rect) != true
        } ?? workspaceViewport.minY+8
        cableTools?.frame=NSRect(x:x,y:y,width:width,height:74)
        cableTools?.isHidden=cableDrag != nil
    }
    func cablePointAvailable(_ point:Point,labels:Bool=true)->Bool {
        let p=NSPoint(x:point.x,y:point.y)
        return workspaceViewport.contains(p) && editor?.frame.contains(p) != true && !(cableTools?.isHidden == false && cableTools?.frame.contains(p) == true) &&
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
        guard let edge=selectedSceneCable,let id=edge.connectionID,edge.from==id.from,edge.to==id.to,
              let curve=connectionCurve(edge),cableTools != nil else{return []}
        return [(CirclePortDirection.output,CirclePortHandle(endpoint:.init(node:id.from,portID:edge.fromPortID),octant:edge.placement.from,point:curve.from)),
                (.input,CirclePortHandle(endpoint:.init(node:id.to,portID:edge.toPortID),octant:edge.placement.to,point:curve.to))].filter {cablePointAvailable($0.1.point)}
    }
    func beginCableDrag(at point:NSPoint)->Bool {
        guard let hit=cableEndpointHandles().first(where:{hypot($0.1.point.x-point.x,$0.1.point.y-point.y)<=12}),let id=selectedCable else{return false}
        do {cableDrag=try CircleCableGesture(id:id,direction:hit.0,mode:cableMode,project:store.project);connectionToken=UUID();cableDragOriginal=store.editOriginal;connectionPoint=point;cableTools?.isHidden=true;needsDisplay=true}
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
            guard let node=scene?.node(gesture.moving.node) else{return}
            let center=screen(node),radius=node.outerRadius*camera.zoom,distance=hypot(point.x-center.x,point.y-center.y)
            guard abs(distance-radius)<=115,let octant=CirclePortGeometry.nearestOctant(to:Point(point.x,point.y),center:Point(center.x,center.y)) else {store.status="위치 이동은 원래 서클 둘레에 놓으세요";return}
            apply(gesture.moving,octant);return
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
            StudioTheme.accentNS.setStroke();let ring=NSBezierPath(ovalIn:NSRect(x:p.x-10,y:p.y-10,width:20,height:20));ring.lineWidth=2;ring.stroke()
            let descriptor=scene?.node(handle.endpoint.node)?.ports.first{$0.id==handle.endpoint.portID}
            let label=descriptor.map(shortPortLabel) ?? (direction == .output ? "OUT":"IN")
            let horizontal=abs(CirclePortGeometry.normal(handle.octant).x)>0.7
            drawText(label,x:p.x,y:p.y+(horizontal && direction == .output ? 14:-26),size:10,color:StudioTheme.accentNS,maxWidth:44)
        }
        guard let gesture=cableDrag,let edge=selectedSceneCable,let curve=connectionCurve(edge) else{return}
        let fixedPoint=gesture.direction == .output ? curve.to:curve.from
        var moving=Point(connectionPoint.x,connectionPoint.y),octant=gesture.direction == .output ? edge.placement.from:edge.placement.to
        if gesture.mode == .placement,let node=scene?.node(gesture.moving.node),let port=node.ports.first(where:{$0.id==gesture.moving.portID}) {
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
