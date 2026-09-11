import XCTest
@testable import CirclrCore

final class OrbitLayoutMigrationTests: XCTestCase {
    func testLegacyProjectionKeepsFreeformAndPersistsOnlyOnVisualEdit() throws {
        var layout = Layout()
        layout.positions = ["timed":Point(14400,8800),"processor":Point(890,5460)]
        let bytes = try JSONEncoder().encode(layout)
        let projected = OrbitLayoutOffsets.positions(in:layout,timed:["timed"])
        XCTAssertEqual(projected["timed"],Point())
        XCTAssertEqual(projected["processor"]!.y,400,accuracy:1e-9)
        XCTAssertEqual(try JSONEncoder().encode(layout).count,bytes.count)
        let original = layout.positions
        OrbitLayoutOffsets.materialize(&layout,timed:["timed"])
        layout.orbitPositions?["timed"] = Point(83,-47)
        let restored = try JSONDecoder().decode(Layout.self,from:JSONEncoder().encode(layout))
        XCTAssertEqual(restored.positions,original)
        XCTAssertEqual(OrbitLayoutOffsets.positions(in:restored,timed:["timed"])["timed"],Point(83,-47))
        XCTAssertEqual(restored.orbitLayoutVersion,1)
        layout.orbitPositions?["bad"] = Point(.infinity,0)
        XCTAssertThrowsError(try AlbumEditing.validateLayout(layout))
        layout.orbitPositions = nil; layout.orbitLayoutVersion = 2
        XCTAssertThrowsError(try AlbumEditing.validateLayout(layout))
    }

    func testExistingDemoSongFitKeepsSectionsReadableWithoutRewritingLayout() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let p = try JSONDecoder().decode(Project.self,from:Data(contentsOf:root.appendingPathComponent("Resources/Demos/f0r-h3r.circlr/manifest.json")))
        let original = p
        let scene = try HierarchySceneBuilder.build(p)
        let song = try XCTUnwrap(scene.nodes.first { $0.role == .song })
        let camera = try XCTUnwrap(PlaybackFraming.camera(for:song,in:scene,viewport:CGRect(x:0,y:0,width:1024,height:700)))
        for child in scene.children(of:song.id) {
            XCTAssertGreaterThan(child.radius*camera.zoom,35)
            XCTAssertGreaterThanOrEqual(hypot(child.center.x-song.center.x,child.center.y-song.center.y),song.radius+child.outerRadius+70)
        }
        XCTAssertEqual(p,original)
        var moved=p
        let section=try XCTUnwrap(scene.children(of:song.id).first)
        let freeform=try HierarchyEditing.layout(for:song.id,in:moved).positions
        try HierarchyEditing.move(section.id,to:Point(50,20),in:&moved)
        XCTAssertEqual(try HierarchyEditing.layout(for:song.id,in:moved).positions,freeform)
        XCTAssertEqual(try HierarchySceneBuilder.build(moved).node(section.id)?.orbit,section.orbit)
    }

    func testDuplicateArrangementRemapsOrbitOffsetsWithoutChangingOriginal() throws {
        var p = try OrbitTests().fixture()
        let ai = p.activeIndex
        p.arrangements[ai].layout.orbitLayoutVersion = 1
        p.arrangements[ai].layout.orbitPositions = Dictionary(uniqueKeysWithValues:p.active.uses.enumerated().map { ($0.element.id,Point(Double($0.offset)*83,47)) })
        let original = p.active
        ProjectEditing.duplicateArrangement(in:&p,name:"복제")
        XCTAssertEqual(p.arrangements.first { $0.id == original.id },original)
        XCTAssertEqual(p.active.layout.orbitLayoutVersion,1)
        for (old, copied) in zip(original.uses,p.active.uses) {
            XCTAssertNotEqual(old.id,copied.id)
            XCTAssertEqual(p.active.layout.orbitPositions?[copied.id],original.layout.orbitPositions?[old.id])
            XCTAssertNil(p.active.layout.orbitPositions?[old.id])
        }
    }

    func testEditingScheduledCircleDoesNotRelocateLegacyOffPathCircle() throws {
        var p = try OrbitTests().fixture()
        let unreachable = p.addSection(name:"경로 밖",at:Point(800,1200),bars:2)
        let before = try HierarchySceneBuilder.build(p)
        let offAddress = CircleAddress.section(arrangementID:p.active.id,useID:unreachable)
        let off = try XCTUnwrap(before.node(offAddress))
        XCTAssertNil(off.orbit)
        let scheduled = try XCTUnwrap(before.nodes.first { $0.role == .section && $0.orbit != nil })
        try HierarchyEditing.move(scheduled.id,to:Point(50,20),in:&p)
        let after = try XCTUnwrap(HierarchySceneBuilder.build(p).node(offAddress))
        XCTAssertEqual(after.center,off.center)
        XCTAssertNil(after.orbit)
    }

    func testOrbitAlignmentUsesVisualCentersAndKeepsMusicTime() throws {
        var p = try OrbitTests().fixture()
        let before = try HierarchySceneBuilder.build(p)
        let sections = Set(before.nodes.filter { $0.role == .section }.map(\.id))
        try HierarchyEditing.align(sections,mode:0,in:&p)
        let after = try HierarchySceneBuilder.build(p)
        let centers = sections.compactMap { after.node($0)?.center.y }
        XCTAssertEqual(centers.max()!,centers.min()!,accuracy:1e-9)
        for id in sections { XCTAssertEqual(after.node(id)?.orbit,before.node(id)?.orbit) }
    }
}
