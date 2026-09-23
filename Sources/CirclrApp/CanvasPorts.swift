import AppKit
import CirclrCore

extension AlbumCanvasView {
    private static let portFallback = CirclePort.flowPorts + CirclePort.ports(for: .router(AudioRouter())) +
        CirclePort.ports(for: .effect(Effect(.compressor))) + CirclePort.ports(for: .instrument(trackID: ""))
    func visiblePortHandles() -> [CirclePortHandle] {
        if let drawingPortHandles { return drawingPortHandles }
        guard let scene else { return [] }
        var result: [CirclePortHandle] = []
        var connectedByPort: [CirclePortEndpoint: Set<PortOctant>] = [:]
        for edge in scene.edges {
            connectedByPort[.init(node:edge.from,portID:edge.fromPortID),default:[]].insert(edge.placement.from)
            connectedByPort[.init(node:edge.to,portID:edge.toPortID),default:[]].insert(edge.placement.to)
        }
        let fixed = cableDrag?.mode == .reconnect ? cableDrag?.fixed : connecting?.endpoint
        let fixedPort = fixed.flatMap { endpoint in (try? CirclePortCatalog.ports(at:endpoint.node,in:store.project))?.first { $0.id == endpoint.portID } }
        let time = store.selectedCircle.flatMap { visibleTimeHandle($0) }
        let pointer = !store.viewingMode && window?.isKeyWindow == true
            ? window.map { convert($0.mouseLocationOutsideOfEventStream,from:nil) } : nil
        for node in scene.nodes where isVisible(node) && !node.ports.isEmpty {
            let center = screen(node)
            let radius = node.radius*camera.zoom
            let labelClearance = radius <= 45 ? 10.0 : 9.0
            let tinyFocused = radius <= 45 && !store.viewingMode &&
                (store.hierarchySelections.contains(node.id) || node.id == store.hierarchySelection || node.id == hoverAddress)
            // Keep the tiny control reachable across the gap between the circle and
            // its visible anchor while the pointer leaves the circle's hit region.
            let approaching = radius <= 45 && pointer.map { pointer in
                node.ports.contains { port in
                    guard let choice = CirclePortPresentation.overviewAnchor(for:port,center:Point(center.x,center.y),radius:node.outerRadius*camera.zoom,available:{ point in
                        cablePointAvailable(point,labels:false) &&
                            !labelPlacements.contains(where: { $0.rect.insetBy(dx:-labelClearance,dy:-labelClearance).contains(NSPoint(x:point.x,y:point.y)) })
                    }) else { return false }
                    let normal = CirclePortGeometry.normal(choice.octant)
                    let x = Double(pointer.x-center.x), y = Double(pointer.y-center.y)
                    let along = x*normal.x+y*normal.y
                    return along >= max(0,node.outerRadius*camera.zoom-8) &&
                        along <= hypot(choice.point.x-center.x,choice.point.y-center.y)+CirclePortGeometry.hitRadius &&
                        abs(x*normal.y-y*normal.x) <= CirclePortGeometry.hitRadius
                }
            } == true
            guard radius > 45 || tinyFocused || selectedCanvasPort?.node == node.id || approaching else { continue }
            for port in node.ports {
                let endpoint = CirclePortEndpoint(node:node.id,portID:port.id)
                let selected = endpoint == selectedCanvasPort
                var engaged = tinyFocused || approaching ||
                    (radius > 45 && (node.id == store.hierarchySelection || node.id == hoverAddress))
                var expanded = selected
                if let fixed, let fixedPort {
                    if endpoint != fixed {
                        guard port.direction != fixedPort.direction, port.signal == fixedPort.signal,
                              (try? CirclePortCatalog.normalize(fixed,endpoint,in:store.project)) != nil else { continue }
                    }
                    engaged = true
                    expanded = endpoint != fixed && hypot(connectionPoint.x-center.x,connectionPoint.y-center.y) <= node.outerRadius*camera.zoom+115
                } else if let gesture = cableDrag, gesture.mode == .placement {
                    engaged = (try? GroupPortEditing.resolve(endpoint,in:store.project)) == gesture.moving; expanded = engaged
                }
                let directions = CirclePortPresentation.octants(for:port,radius:node.radius*camera.zoom,engaged:engaged,expanded:expanded,connected:connectedByPort[endpoint] ?? [],selected:selected)
                func available(_ point: Point) -> Bool {
                    cablePointAvailable(point, labels:false) &&
                        (selected || (time.map({ hypot($0.x-point.x,$0.y-point.y) > 23 }) ?? true)) &&
                        (selected || !labelPlacements.contains(where: { $0.rect.insetBy(dx:-labelClearance,dy:-labelClearance).contains(NSPoint(x:point.x,y:point.y)) }))
                }
                if radius <= 45 {
                    guard !directions.isEmpty,
                          let choice = CirclePortPresentation.overviewAnchor(for:port,center:Point(center.x,center.y),radius:node.outerRadius*camera.zoom,available:{ point in
                              available(point) && !result.contains(where: { $0.endpoint != endpoint && hypot($0.point.x-point.x,$0.point.y-point.y) <= CirclePortGeometry.hitRadius*2 })
                          }) else { continue }
                    result.append(.init(endpoint:endpoint,octant:choice.octant,point:choice.point))
                    continue
                }
                for direction in directions {
                    guard let point = try? CirclePortGeometry.anchor(center:Point(center.x,center.y),radius:node.outerRadius*camera.zoom,port:port,octant:direction),
                          available(point) else { continue }
                    result.append(.init(endpoint:endpoint,octant:direction,point:point))
                }
            }
        }
        if isDrawingFrame { drawingPortHandles=result }
        return result
    }
    func drawPortHandles() {
        let selected=cableEndpointHandles().map{$0.1}
        for handle in visiblePortHandles() {
            if selected.contains(where:{$0.endpoint==handle.endpoint && $0.octant==handle.octant}) {continue}
            guard let node=scene?.node(handle.endpoint.node),let descriptor=node.ports.first(where:{$0.id==handle.endpoint.portID}) else { continue }
            let p=NSPoint(x:handle.point.x,y:handle.point.y),isOut=descriptor.direction == .output
            port(at:p,color:color(node),filled:isOut)
        }
        if let handle=selectedPortHandle() {
            let ring=NSBezierPath(ovalIn:NSRect(x:handle.point.x-10,y:handle.point.y-10,width:20,height:20))
            StudioTheme.accentNS.setStroke();ring.lineWidth=3;ring.stroke()
        }
    }
    func shortPortLabel(_ port:CirclePort)->String {
        if port.bindingTarget != nil {return String(port.name.prefix(26))}
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
