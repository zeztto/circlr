import Foundation

/// Camera math is independent of UI events, layout persistence, and musical time.
public struct CanvasCamera: Equatable {
    public var pan: Point
    public var zoom: Double
    public init(pan: Point = Point(), zoom: Double = 1) { self.pan = pan; self.zoom = zoom }
    public func world(_ screen: Point) -> Point { Point((screen.x-pan.x)/zoom, (screen.y-pan.y)/zoom) }
    public func screen(_ world: Point) -> Point { Point(world.x*zoom+pan.x, world.y*zoom+pan.y) }
    public func zoomed(to value: Double, around anchor: Point) -> CanvasCamera {
        let z = max(0.25, min(2.5, value)), w = world(anchor)
        return CanvasCamera(pan: Point(anchor.x-w.x*z, anchor.y-w.y*z), zoom: z)
    }
    /// Coarse mouse wheels use physical up/down even when macOS reverses scrolling.
    /// Continuous devices retain their logical direction and get a smaller per-point gain.
    public func wheelZoom(deltaY:Double, precise:Bool, inverted:Bool, around anchor:Point)->CanvasCamera {
        guard deltaY.isFinite else{return self}
        let direction = !precise && inverted ? -deltaY:deltaY
        let limit = precise ? 60.0:4.0
        let delta = max(-limit,min(limit,direction))
        return zoomed(to:zoom*exp(delta*(precise ? 0.006:0.065)),around:anchor)
    }
    public static func fitting(points: [Point], width: Double, height: Double, margin: Double = 110) -> CanvasCamera? {
        guard let first = points.first, width > 0, height > 0 else { return nil }
        let minX = points.map(\.x).min() ?? first.x, maxX = points.map(\.x).max() ?? first.x
        let minY = points.map(\.y).min() ?? first.y, maxY = points.map(\.y).max() ?? first.y
        let z = max(0.25, min(1.25, min(width/(maxX-minX+margin*2), height/(maxY-minY+margin*2))))
        return CanvasCamera(pan: Point(width/2-(minX+maxX)/2*z, height/2-(minY+maxY)/2*z), zoom: z)
    }
    public func interpolated(to target: CanvasCamera, progress: Double) -> CanvasCamera {
        let p = max(0, min(1, progress)), t = p*p*(3-2*p)
        return CanvasCamera(pan: Point(pan.x+(target.pan.x-pan.x)*t, pan.y+(target.pan.y-pan.y)*t), zoom: zoom+(target.zoom-zoom)*t)
    }
    /// Snap a shared translation, never each member separately: group spacing survives a drop.
    public static func droppedDelta(_ delta: Point, anchor: Point, spacing: Double, snap: Bool) -> Point {
        guard snap, spacing > 0, spacing.isFinite else { return delta }
        return Point(((anchor.x+delta.x)/spacing).rounded()*spacing-anchor.x,
                     ((anchor.y+delta.y)/spacing).rounded()*spacing-anchor.y)
    }
}
