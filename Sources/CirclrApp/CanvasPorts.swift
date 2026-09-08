import AppKit
import CirclrCore

extension AlbumCanvasView {
    private static let portFallback = CirclePort.flowPorts + CirclePort.ports(for: .router(AudioRouter())) +
        CirclePort.ports(for: .effect(Effect(.compressor))) + CirclePort.ports(for: .instrument(trackID: ""))
    func visiblePortHandles() -> [CirclePortHandle] {
        guard let scene else { return [] }
        var result: [CirclePortHandle] = []
        for node in scene.nodes where isVisible(node) && node.radius*camera.zoom > 45 && !node.ports.isEmpty {
            let center = screen(node), detailed = node.id == store.hierarchySelection || connecting != nil || cableDrag != nil
            for port in node.ports {
                var directions = Set<PortOctant>()
                if detailed { directions.formUnion(node.radius*camera.zoom >= 90 ? PortOctant.allCases : [port.defaultOctant]) }
                for edge in scene.edges {
                    if edge.from == node.id && edge.fromPortID == port.id { directions.insert(edge.placement.from) }
                    if edge.to == node.id && edge.toPortID == port.id { directions.insert(edge.placement.to) }
                }
                for direction in directions.sorted(by: { $0.rawValue < $1.rawValue }) {
                    guard let point = try? CirclePortGeometry.anchor(center:Point(center.x,center.y),radius:node.outerRadius*camera.zoom,port:port,octant:direction),
                          workspaceViewport.contains(CGPoint(x:point.x,y:point.y)),
                          editor?.frame.contains(NSPoint(x:point.x,y:point.y)) != true,
                          !(cableTools?.isHidden == false && cableTools?.frame.contains(NSPoint(x:point.x,y:point.y)) == true),
                          !labelPlacements.contains(where: { $0.rect.insetBy(dx:-9,dy:-9).contains(NSPoint(x:point.x,y:point.y)) }) else { continue }
                    result.append(.init(endpoint:.init(node:node.id,portID:port.id),octant:direction,point:point))
                }
            }
        }
        return result
    }
    func drawPortHandles() {
        let selected=cableEndpointHandles().map{$0.1}
        for handle in visiblePortHandles() {
            if selected.contains(where:{$0.endpoint==handle.endpoint && $0.octant==handle.octant}) {continue}
            guard let node=scene?.node(handle.endpoint.node),let descriptor=node.ports.first(where:{$0.id==handle.endpoint.portID}) else { continue }
            let p=NSPoint(x:handle.point.x,y:handle.point.y),isOut=descriptor.direction == .output
            port(at:p,color:color(node),filled:isOut)
            let label = shortPortLabel(descriptor)
            if node.radius*camera.zoom > 45 {
                let horizontal=abs(CirclePortGeometry.normal(handle.octant).x)>0.7
                drawText(label,x:p.x,y:p.y+(horizontal && isOut ? 10:-20),size:9,color:StudioTheme.textNS,maxWidth:42)
            }
        }
    }
    func shortPortLabel(_ port:CirclePort)->String {
        if let index=AudioRouter.inputs.firstIndex(of:port.id) {return "IN \(index+1)"}
        if let index=AudioRouter.outputs.firstIndex(of:port.id) {return "OUT \(index+1)"}
        return port.direction == .output ? "OUT":port.isSidechain ? "SC IN":"IN"
    }
    func finishPortConnection(_ first:CirclePortHandle,at point:NSPoint) {
        let projectID=connectionProjectID,revision=connectionRevision,layoutRevision=connectionLayoutRevision,original=store.editOriginal,token=connectionToken
        func apply(_ second:CirclePortHandle) {
            guard token != nil,token==connectionToken else {store.status="이전 연결 조작은 취소되었습니다";return}
            guard projectID==store.project.id,revision==store.project.musicRevision,layoutRevision==(store.project.portLayout?.revision ?? 0) else {store.status="연결 중 음악·배치가 변경되었습니다. 다시 연결하세요";return}
            store.mutate("포트 연결") { p in
                try CircleConnectionEditing.connect(first.endpoint,second.endpoint,firstOctant:first.octant,secondOctant:second.octant,original:original,in:&p)
            }
        }
        if let second=CirclePortGeometry.hit(Point(point.x,point.y),visibleHandles:visiblePortHandles()) { apply(second); return }
        guard let target=hit(point),target.id != first.endpoint.node else { return }
        let center=screen(target)
        let choices=target.ports.compactMap { port -> (CirclePort, CirclePortHandle)? in
            let endpoint=CirclePortEndpoint(node:target.id,portID:port.id)
            guard (try? CirclePortCatalog.normalize(first.endpoint,endpoint,in:store.project)) != nil else { return nil }
            let direction=CirclePortGeometry.dropOctant(to:Point(point.x,point.y),center:Point(center.x,center.y),radius:target.outerRadius*camera.zoom,fallback:port.defaultOctant) ?? port.defaultOctant
            return (port,.init(endpoint:endpoint,octant:direction,point:Point(point.x,point.y)))
        }
        if choices.count==1 { apply(choices[0].1) }
        else if choices.count>1 {
            let menu=NSMenu(title:"연결할 포트")
            for (port,handle) in choices {
                let item=NSMenuItem(title:port.name,action:#selector(runCircleMenu(_:)),keyEquivalent:"")
                item.target=self;item.representedObject=CircleMenuAction { apply(handle) };menu.addItem(item)
            }
            menu.popUp(positioning:nil,at:point,in:self)
        } else {store.status="호환되는 OUT과 IN을 선택하세요"}
    }
    func connectionCurve(_ edge: CircleSceneEdge) -> CirclePortCurve? {
        guard let scene, let a = scene.node(edge.from), let b = scene.node(edge.to) else { return nil }
        // Collapsing projects an endpoint to the group outline; it does not add a group port.
        guard let fromPort = (a.ports + Self.portFallback).first(where: { $0.id == edge.fromPortID }),
              let toPort = (b.ports + Self.portFallback).first(where: { $0.id == edge.toPortID }) else { return nil }
        let ac = screen(a), bc = screen(b)
        guard let from = try? CirclePortGeometry.anchor(center: Point(ac.x,ac.y), radius: a.outerRadius*camera.zoom, port: fromPort, octant: edge.placement.from),
              let to = try? CirclePortGeometry.anchor(center: Point(bc.x,bc.y), radius: b.outerRadius*camera.zoom, port: toPort, octant: edge.placement.to) else { return nil }
        return try? CirclePortGeometry.curve(from: .init(endpoint: .init(node:edge.from,portID:edge.fromPortID),octant:edge.placement.from,point:from),
                                            to: .init(endpoint: .init(node:edge.to,portID:edge.toPortID),octant:edge.placement.to,point:to))
    }
    func wire(_ curve: CirclePortCurve, color: NSColor, dashed: Bool = false) {
        let path = NSBezierPath(); path.move(to: NSPoint(x:curve.from.x,y:curve.from.y))
        path.curve(to:NSPoint(x:curve.to.x,y:curve.to.y),controlPoint1:NSPoint(x:curve.control1.x,y:curve.control1.y),controlPoint2:NSPoint(x:curve.control2.x,y:curve.control2.y))
        color.setStroke();path.lineWidth=1.5
        if dashed {path.setLineDash([4,4],count:2,phase:0)}
        path.stroke()
    }
}
