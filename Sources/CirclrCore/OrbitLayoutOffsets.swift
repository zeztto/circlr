import Foundation

/// Version 1 separates outward canvas offsets from the legacy freeform coordinates.
/// Projection is read-only until the first visual edit; music and freeform layout stay intact.
public enum OrbitLayoutOffsets {
    public static func isValid(_ layout: Layout) -> Bool {
        guard layout.orbitLayoutVersion == nil || layout.orbitLayoutVersion == 1 else { return false }
        return (layout.orbitPositions ?? [:]).values.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x)<1e7 && abs($0.y)<1e7 }
    }
    public static func positions(in layout: Layout, timed: Set<ID>) -> [ID: Point] {
        if layout.orbitLayoutVersion == 1 { return layout.orbitPositions ?? [:] }
        let untimed = layout.positions.filter { !timed.contains($0.key) }
        let extent = untimed.values.map { max(abs($0.x), abs($0.y)) }.max() ?? 0
        let scale = min(1, 400 / max(1, extent))
        return Dictionary(uniqueKeysWithValues: layout.positions.map { id, point in
            (id, timed.contains(id) ? Point() : Point(point.x*scale, point.y*scale))
        })
    }
    public static func materialize(_ layout: inout Layout, timed: Set<ID>) {
        let offsets = positions(in: layout, timed: timed)
        layout.orbitPositions = offsets
        layout.orbitLayoutVersion = 1
    }
}
