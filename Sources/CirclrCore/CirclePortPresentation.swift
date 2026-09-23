import CoreGraphics
import Foundation

public struct PortLabelRequest {
    public var endpoint: CirclePortEndpoint
    public var anchor: CGPoint
    public var size: CGSize
    public var octant: PortOctant
    public var priority: Int
    public init(endpoint: CirclePortEndpoint, anchor: CGPoint, size: CGSize, octant: PortOctant, priority: Int = 0) {
        self.endpoint = endpoint; self.anchor = anchor; self.size = size; self.octant = octant; self.priority = priority
    }
}
public struct PortLabelPlacement {
    public var endpoint: CirclePortEndpoint
    public var rect: CGRect
}

/// Presentation only: every persisted connection keeps its original geometric anchor.
public enum CirclePortPresentation {
    /// Choose one overview control on the port's own side of the circle. A label
    /// may cover the default anchor, but must keep its existing click priority.
    public static func overviewAnchor(for port: CirclePort, center: Point, radius: Double,
                                      available: (Point) -> Bool) -> (octant: PortOctant, point: Point)? {
        let candidates: [PortOctant] = port.direction == .input
            ? [.west, .northwest, .southwest] : [.east, .northeast, .southeast]
        for octant in candidates {
            if let point = try? CirclePortGeometry.anchor(center: center, radius: radius, port: port, octant: octant),
               available(point) { return (octant, point) }
        }
        return nil
    }

    public static func octants(for port: CirclePort, radius: Double, engaged: Bool, expanded: Bool,
                               connected: Set<PortOctant>, selected: Bool = false) -> [PortOctant] {
        guard radius.isFinite, radius > 0 else { return [] }
        // Overview exposes only the default control of each focused logical port.
        // Eight octants would overlap here; saved edge anchors are not changed.
        if radius <= 45 { return engaged || selected ? [port.defaultOctant] : [] }
        var result = connected
        if engaged || expanded { result.insert(port.defaultOctant) }
        if expanded, radius >= 90 { result.formUnion(PortOctant.allCases) }
        return result.sorted { $0.rawValue < $1.rawValue }
    }

    /// Preserve overview scale unless a selected endpoint is too small or outside the
    /// available canvas. The anchor uses screen-space offsets, as the renderer does.
    public static func cameraRevealingSelected(_ port: CirclePort, on node: CircleSceneNode,
                                               current: HierarchyCamera, within viewport: CGRect,
                                               minimumRadius: Double = 62) -> HierarchyCamera? {
        guard current.zoom.isFinite, current.zoom > 0, node.radius.isFinite, node.radius > 0,
              node.outerRadius.isFinite, node.outerRadius > 0,
              node.center.x.isFinite, node.center.y.isFinite,
              viewport.minX.isFinite, viewport.minY.isFinite,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 40, viewport.height > 40,
              minimumRadius.isFinite, minimumRadius > 45 else { return nil }
        let radius = node.radius * current.zoom
        guard radius.isFinite else { return nil }
        let zoom = radius <= 45 ? min(1e12, max(current.zoom, minimumRadius / node.radius)) : current.zoom
        let original = current.screen(node.center)
        var pan = current.pan
        if radius <= 45 || !viewport.contains(CGPoint(x: original.x, y: original.y)) {
            pan = Point(viewport.midX - node.center.x * zoom, viewport.midY - node.center.y * zoom)
        }
        var candidate = HierarchyCamera(pan: pan, zoom: zoom)
        func anchor(_ camera: HierarchyCamera) -> Point? {
            let center = camera.screen(node.center)
            return try? CirclePortGeometry.anchor(center: center, radius: node.outerRadius * camera.zoom,
                                                  port: port, octant: port.defaultOctant)
        }
        guard let point = anchor(candidate), point.x.isFinite, point.y.isFinite else { return nil }
        let interior = viewport.insetBy(dx: 12, dy: 12)
        let x = min(max(point.x, interior.minX), interior.maxX)
        let y = min(max(point.y, interior.minY), interior.maxY)
        candidate.pan.x += x - point.x
        candidate.pan.y += y - point.y
        return candidate == current ? nil : candidate
    }

    /// One label per logical port, with the active endpoint placed before background ports.
    public static func labels(_ requests: [PortLabelRequest], within viewport: CGRect,
                              avoiding obstacles: [CGRect]) -> [PortLabelPlacement] {
        var occupied = obstacles, result: [PortLabelPlacement] = [], used = Set<CirclePortEndpoint>()
        let ordered = requests.enumerated().sorted {
            $0.element.priority == $1.element.priority ? $0.offset < $1.offset : $0.element.priority > $1.element.priority
        }
        for (_, request) in ordered {
            let p = request.anchor, w = request.size.width, h = request.size.height
            guard p.x.isFinite, p.y.isFinite, w.isFinite, h.isFinite, w > 0, h > 0,
                  !used.contains(request.endpoint) else { continue }
            let n = CirclePortGeometry.normal(request.octant)
            let reach = 13 + abs(n.x)*w/2 + abs(n.y)*h/2
            let centers = [CGPoint(x: p.x+n.x*reach, y: p.y+n.y*reach),
                CGPoint(x: p.x, y: p.y-h/2-13), CGPoint(x: p.x, y: p.y+h/2+13),
                CGPoint(x: p.x+w/2+13, y: p.y), CGPoint(x: p.x-w/2-13, y: p.y),
                CGPoint(x: p.x+w/2+13, y: p.y-h/2-13), CGPoint(x: p.x-w/2-13, y: p.y+h/2+13),
                CGPoint(x: p.x-w/2-13, y: p.y-h/2-13), CGPoint(x: p.x+w/2+13, y: p.y+h/2+13)]
            if let rect = centers.map({ CGRect(x: $0.x-w/2, y: $0.y-h/2, width: w, height: h) }).first(where: {
                viewport.contains($0) && !occupied.contains(where: $0.intersects)
            }) {
                result.append(.init(endpoint: request.endpoint, rect: rect)); used.insert(request.endpoint)
                occupied.append(rect.insetBy(dx: -4, dy: -3))
            }
        }
        return result
    }
}
