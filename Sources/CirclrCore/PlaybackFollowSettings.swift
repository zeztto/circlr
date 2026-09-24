import Foundation
import CoreGraphics

public enum PlaybackFollowTarget: String, Codable, CaseIterable, Sendable { case song, section, pinned }
public enum PlaybackFollowFraming: String, Codable, CaseIterable, Sendable { case fit, keepZoom }
public enum PlaybackFollowTransition: String, Codable, CaseIterable, Sendable { case off, subtle, emphasized }

/// Workspace preferences only. Runtime following/suspended/off remains PlaybackFollowMode.
public struct PlaybackFollowSettings: Codable, Equatable, Sendable {
    public var target: PlaybackFollowTarget
    public var framing: PlaybackFollowFraming
    public var transition: PlaybackFollowTransition
    public var pinned: CircleAddress?
    public init(target: PlaybackFollowTarget = .song, framing: PlaybackFollowFraming = .fit,
                transition: PlaybackFollowTransition = .subtle, pinned: CircleAddress? = nil) {
        self.target=target; self.framing=framing; self.transition=transition; self.pinned=pinned
    }
}

public enum PlaybackFollowResolution: Equatable {
    case target(CircleAddress)
    /// Valid pinned circle not participating now, or no current playback occurrence: retain camera.
    case inactive
    /// Caller must suspend and explain; never replace an invalid pin with the current selection.
    case missingPinnedTarget
}

public enum PlaybackFollowResolver {
    /// activeCircles must represent participation in the prepared plan, not nonzero meter levels.
    /// Include silent participating nodes; a group participates if one of its descendants does.
    public static func resolve(_ settings: PlaybackFollowSettings, currentSection: CircleAddress?,
                               activeCircles: Set<CircleAddress>, in scene: HierarchyScene) -> PlaybackFollowResolution {
        if settings.target == .pinned {
            guard let pin=settings.pinned, scene.node(pin) != nil else { return .missingPinnedTarget }
            let participating=activeCircles.contains(pin) || activeCircles.contains { address in
                scene.path(to:address).contains { $0.id == pin }
            }
            return participating ? .target(pin):.inactive
        }
        guard let currentSection, scene.node(currentSection) != nil else { return .inactive }
        if settings.target == .section { return .target(currentSection) }
        guard let song=scene.path(to:currentSection).last(where:{$0.role == .song}) else { return .inactive }
        return .target(song.id)
    }

    public static func camera(for target: CircleAddress, settings: PlaybackFollowSettings,
                              current: HierarchyCamera, scene: HierarchyScene, viewport: CGRect,
                              avoiding console:CGRect?=nil) -> HierarchyCamera? {
        guard let node=scene.node(target), let fitted=PlaybackFraming.camera(for:node,in:scene,viewport:viewport,avoiding:console) else { return nil }
        guard settings.framing == .keepZoom else { return fitted }
        guard current.zoom.isFinite, (1e-6...1e12).contains(current.zoom) else { return nil }
        if let console {
            // Keep the requested zoom where it fits. If the orbit disks cannot all
            // avoid the console at that scale, reduce only as far as visibility needs.
            let circles=CanvasWorkspaceGeometry.contextCircles(target,in:scene)
            return CanvasWorkspaceGeometry.fittingCamera(circles:circles,within:viewport,
                avoiding:console,marginX:min(56,viewport.width*0.12),
                marginY:min(40,viewport.height*0.12),maximumZoom:current.zoom)
        }
        // Preserve the actual fitted content anchor, not the container's center.
        guard let content=scene.contextBounds(of:target) else{return nil}
        let center=Point(content.midX,content.midY),anchor=fitted.screen(center)
        return HierarchyCamera(pan:Point(anchor.x-center.x*current.zoom,
                                          anchor.y-center.y*current.zoom),zoom:current.zoom)
    }
}

/// Pure elapsed-time curve shared by display and capture. Cancellation is owned by the caller:
/// discard this value and build the next transition from the currently displayed camera.
public struct PlaybackFollowCameraCurve {
    public let start: HierarchyCamera
    public let destination: HierarchyCamera
    public let duration: Double
    public let minimumZoom: Double
    private let viewport: CGRect
    private let excursion: Bool

    public init(start: HierarchyCamera, destination: HierarchyCamera, viewport: CGRect,
                transition: PlaybackFollowTransition, changesSection: Bool,
                remainingSectionSeconds: Double? = nil, reduceMotion: Bool = false) {
        self.start=start; self.destination=destination; self.viewport=viewport
        let same=start == destination
        let available=remainingSectionSeconds.map { $0.isFinite ? max(0,$0):0 }
        excursion = changesSection && transition != .off && !reduceMotion && !same && (available == nil || available! >= 0.5)
        let nominal = transition == .emphasized ? 0.7:0.55
        duration = same || reduceMotion ? 0 : min(nominal,available.map{max(0,$0*0.45)} ?? nominal)
        // Bound additional zoom-out even for extremely distant targets: never fit the entire path.
        minimumZoom=max(1e-6,min(start.zoom,destination.zoom)*(excursion ? (transition == .emphasized ? 0.8:0.9):1))
    }

    public func camera(at elapsedSeconds: Double) -> HierarchyCamera {
        guard duration > 0 else { return destination }
        let t=elapsedSeconds.isNaN ? 0:max(0,min(1,elapsedSeconds/duration))
        if t == 0 { return start }; if t == 1 { return destination }
        let smooth=t*t*(3-2*t)
        let a=Point((viewport.midX-start.pan.x)/start.zoom,(viewport.midY-start.pan.y)/start.zoom)
        let b=Point((viewport.midX-destination.pan.x)/destination.zoom,(viewport.midY-destination.pan.y)/destination.zoom)
        let center=Point(a.x+(b.x-a.x)*smooth,a.y+(b.y-a.y)*smooth)
        let zoom: Double
        if excursion {
            // Two smooth halves meet with zero velocity at the widest midpoint.
            let half=t<0.5 ? t*2:(t-0.5)*2
            let eased=half*half*(3-2*half)
            let from=t<0.5 ? start.zoom:minimumZoom, to=t<0.5 ? minimumZoom:destination.zoom
            zoom=exp(log(from)+(log(to)-log(from))*eased)
        } else { zoom=exp(log(start.zoom)+(log(destination.zoom)-log(start.zoom))*smooth) }
        return HierarchyCamera(pan:Point(viewport.midX-center.x*zoom,viewport.midY-center.y*zoom),zoom:zoom)
    }
}
