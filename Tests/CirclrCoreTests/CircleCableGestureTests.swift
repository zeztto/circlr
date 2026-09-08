import XCTest
@testable import CirclrCore

extension CircleConnectionEditingTests {
    private func cableFixture() throws -> (Project, CircleConnectionID, CirclePortEndpoint) {
        var p = try fixture(); let ns = try nodes(p)
        let router = ns.first { if case .router = $0.content { return true }; return false }!
        let output = ns.first { if case .output = $0.content { return true }; return false }!
        let source = endpoint(p,node:router.id,port:AudioRouter.output1)
        let id = try CircleConnectionEditing.connect(source,endpoint(p,node:output.id,port:CirclePort.audioInput),firstOctant:.north,secondOctant:.south,in:&p)
        return (p,id,endpoint(p,node:router.id,port:AudioRouter.output2))
    }
    func testCableGestureReconnectsBothEndsAndKeepsFixedPlacement() throws {
        var (p,id,alternate) = try cableFixture()
        let before = p
        let drag = try CircleCableGesture(id:id,direction:.output,mode:.reconnect,project:p)
        XCTAssertEqual(p,before) // Constructing a preview does not disconnect anything.
        let nextID = try drag.apply(to:alternate,octant:.northwest,in:&p)
        XCTAssertEqual(nextID.edgeID,id.edgeID)
        XCTAssertEqual(p.portLayout?.placement(for:nextID),.init(from:.northwest,to:.south))
        let mix = try nodes(p).first { if case .mix = $0.content { return true }; return false }!
        let inputDrag = try CircleCableGesture(id:nextID,direction:.input,mode:.reconnect,project:p)
        let moved = try inputDrag.apply(to:endpoint(p,node:mix.id,port:CirclePort.audioInput),octant:.east,in:&p)
        XCTAssertEqual(moved.edgeID,id.edgeID)
        XCTAssertEqual(p.portLayout?.placement(for:moved),.init(from:.northwest,to:.east))
    }
    func testCablePlacementDoesNotChangeMusicAndRejectsOtherPort() throws {
        var (p,id,alternate) = try cableFixture(); let before = p
        let drag = try CircleCableGesture(id:id,direction:.output,mode:.placement,project:p)
        XCTAssertThrowsError(try drag.apply(to:alternate,octant:.west,in:&p)); XCTAssertEqual(p,before)
        for octant in PortOctant.allCases {
            let gesture = try CircleCableGesture(id:id,direction:.output,mode:.placement,project:p)
            try gesture.apply(to:gesture.moving,octant:octant,in:&p)
            XCTAssertEqual(p.musicRevision,before.musicRevision); XCTAssertEqual(p.sections,before.sections)
            XCTAssertEqual(p.arrangements,before.arrangements); XCTAssertEqual(p.portLayout?.placement(for:id).from,octant)
        }
    }
    func testCableGestureRejectsMusicLayoutProjectAndDeletedCableChanges() throws {
        let (baseline,id,alternate) = try cableFixture()
        let gesture = try CircleCableGesture(id:id,direction:.output,mode:.reconnect,project:baseline)
        for change in 0..<4 {
            var p = baseline
            if change == 0 { p.musicRevision += 1 }
            if change == 1 { try CirclePortLayoutEditing.apply([.init(id:id,placement:.init(from:.west,to:.east))],projectID:p.id,expectedMusicRevision:p.musicRevision,expectedLayoutRevision:p.portLayout?.revision ?? 0,in:&p) }
            if change == 2 { p.id = newID() }
            if change == 3 { try CircleConnectionEditing.disconnect(id,in:&p) }
            let before = p
            XCTAssertThrowsError(try gesture.apply(to:alternate,octant:.south,in:&p)); XCTAssertEqual(p,before)
        }
    }
    func testCableCurveHitDistanceFollowsBendAndRejectsInvalidGeometry() throws {
        let curve = CirclePortCurve(from:Point(0,0),control1:Point(0,-100),control2:Point(100,-100),to:Point(100,0))
        XCTAssertLessThan(try XCTUnwrap(curve.distance(to:Point(50,-75))),0.01)
        XCTAssertGreaterThan(try XCTUnwrap(curve.distance(to:Point(50,0))),40)
        XCTAssertNil(curve.distance(to:Point(.nan,0)))
        let dot = CirclePortCurve(from:Point(3,4),control1:Point(3,4),control2:Point(3,4),to:Point(3,4))
        XCTAssertEqual(dot.distance(to:Point(0,0)),5)
        XCTAssertEqual(CirclePortGeometry.dropOctant(to:Point(0.2,0.3),center:Point(),radius:80,fallback:.west),.west)
        XCTAssertEqual(CirclePortGeometry.dropOctant(to:Point(0,-80),center:Point(),radius:80,fallback:.west),.north)
        XCTAssertNil(CirclePortGeometry.dropOctant(to:Point(),center:Point(),radius:.infinity,fallback:.west))
    }
}
