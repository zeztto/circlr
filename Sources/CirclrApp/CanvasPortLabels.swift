import AppKit
import CirclrCore

extension AlbumCanvasView {
    func visibleTimeHandle(_ node: CircleSceneNode) -> NSPoint? {
        guard !store.viewingMode,editorAddress == nil, isVisible(node), let orbit = node.orbit, let owner = scene?.node(orbit.owner),
              owner.radius*camera.zoom > 100, owner.radius*camera.zoom < max(bounds.width,bounds.height)*4,
              let point = timeHandle(node), cablePointAvailable(Point(point.x,point.y), labels: false) else { return nil }
        return point
    }

    func portLabelPlacements() -> [PortLabelPlacement] {
        guard !store.viewingMode else{return []}
        guard let scene else { return [] }
        let endpoints = cableEndpointHandles().map(\.1), handles = visiblePortHandles()
        let all = endpoints + handles
        let near = (connecting != nil || cableDrag != nil) ? CirclePortGeometry.hit(Point(connectionPoint.x,connectionPoint.y),visibleHandles:handles) : nil
        var chosen: [CirclePortEndpoint: CirclePortHandle] = [:], order: [CirclePortEndpoint] = []
        for handle in all {
            guard let port = scene.node(handle.endpoint.node)?.ports.first(where: { $0.id == handle.endpoint.portID }) else { continue }
            if chosen[handle.endpoint] == nil { chosen[handle.endpoint] = handle; order.append(handle.endpoint) }
            if endpoints.contains(where: { $0.endpoint == handle.endpoint }) { continue }
            if handle == near || (chosen[handle.endpoint] != near && handle.octant == port.defaultOctant) { chosen[handle.endpoint] = handle }
        }
        let font = NSFont.systemFont(ofSize: StudioTheme.portLabelSize, weight: .semibold)
        let requests = order.compactMap { endpoint -> PortLabelRequest? in
            guard let handle = chosen[endpoint], let port = scene.node(endpoint.node)?.ports.first(where: { $0.id == endpoint.portID }) else { return nil }
            let width = ceil((shortPortLabel(port) as NSString).size(withAttributes: [.font: font]).width)+12
            let active = endpoints.contains { $0.endpoint == endpoint } || endpoint == selectedCanvasPort || endpoint == near?.endpoint
            return .init(endpoint: endpoint, anchor: CGPoint(x:handle.point.x,y:handle.point.y), size:CGSize(width:width,height:23), octant:handle.octant, priority:active ? 10:0)
        }
        var obstacles = labelPlacements.map { $0.rect.insetBy(dx:-4,dy:-4) }
        if let console=consoleObstruction {obstacles.append(console.insetBy(dx:-14,dy:-14))}
        obstacles += all.map { CGRect(x:$0.point.x-10,y:$0.point.y-10,width:20,height:20) }
        if let editor { obstacles.append(editor.frame) }
        if let cableTools, !cableTools.isHidden { obstacles.append(cableTools.frame) }
        if let portTools, !portTools.isHidden { obstacles.append(portTools.frame) }
        if let node = store.selectedCircle, let point = visibleTimeHandle(node) { obstacles.append(CGRect(x:point.x-14,y:point.y-14,width:28,height:28)) }
        return CirclePortPresentation.labels(requests, within:canvasViewport, avoiding:obstacles)
    }

    func drawPortLabels() {
        for placement in portLabelPlacements() {
            guard let port = scene?.node(placement.endpoint.node)?.ports.first(where: { $0.id == placement.endpoint.portID }) else { continue }
            let badge = NSBezierPath(roundedRect:placement.rect,xRadius:4,yRadius:4)
            StudioTheme.surfaceNS.setFill(); badge.fill()
            // A neutral edge keeps labels visible even beside a black custom circle.
            StudioTheme.lineNS.setStroke(); badge.lineWidth=1; badge.stroke()
            let textRect = placement.rect.insetBy(dx:6,dy:3)
            (shortPortLabel(port) as NSString).draw(in:textRect,withAttributes:[.font:NSFont.systemFont(ofSize:StudioTheme.portLabelSize,weight:.semibold),.foregroundColor:StudioTheme.textNS])
        }
    }
}
