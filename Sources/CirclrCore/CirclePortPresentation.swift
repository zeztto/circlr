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
    public static func octants(for port: CirclePort, radius: Double, engaged: Bool, expanded: Bool,
                               connected: Set<PortOctant>) -> [PortOctant] {
        guard radius.isFinite, radius > 45 else { return [] }
        var result = connected
        if engaged || expanded { result.insert(port.defaultOctant) }
        if expanded, radius >= 90 { result.formUnion(PortOctant.allCases) }
        return result.sorted { $0.rawValue < $1.rawValue }
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
