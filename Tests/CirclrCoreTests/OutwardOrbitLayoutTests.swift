import XCTest
@testable import CirclrCore

final class OutwardOrbitLayoutTests: XCTestCase {
    private func project() throws -> Project {
        var p = Project()
        _ = p.addTrack(name: "피아노")
        _ = p.addTrack(name: "패드")
        _ = p.addSection(name: "첫 구간", at: Point(), bars: 4)
        p.enableAlbum()
        return try SectionGraphMigration.migrate(p)
    }

    func testRingIsNotAnEnclosureAndTimeAttachmentsRemainExact() throws {
        let p = try project(), scene = try HierarchySceneBuilder.build(p)
        XCTAssertTrue(scene.isOrbit)
        XCTAssertTrue(scene.nodes.allSatisfy { $0.scale == 1 })
        for node in scene.nodes where node.orbit != nil {
            let orbit = try XCTUnwrap(node.orbit)
            let owner = try XCTUnwrap(scene.node(orbit.owner))
            let anchor = try XCTUnwrap(scene.orbitAnchor(for: node.id))
            XCTAssertEqual(orbit.radius, owner.radius, accuracy: 1e-9)
            XCTAssertEqual(hypot(anchor.x-owner.center.x, anchor.y-owner.center.y), owner.radius, accuracy: 1e-9)
            let expected = orbit.timeline.point(at: orbit.anchor, radius: owner.radius)
            XCTAssertEqual(anchor.x-owner.center.x, expected.x, accuracy: 1e-9)
            XCTAssertEqual(anchor.y-owner.center.y, expected.y, accuracy: 1e-9)
        }
        let section = try XCTUnwrap(scene.nodes.first { $0.role == .section })
        let children = scene.children(of: section.id)
        XCTAssertTrue(children.contains { hypot($0.center.x-section.center.x, $0.center.y-section.center.y)+$0.radius > section.radius })
        let content = try XCTUnwrap(scene.contextBounds(of: section.id))
        for node in [section]+children {
            XCTAssertTrue(content.contains(CGPoint(x:node.center.x-node.outerRadius,y:node.center.y)))
            XCTAssertTrue(content.contains(CGPoint(x:node.center.x,y:node.center.y-node.outerRadius)))
        }
        let sources = children.filter { $0.orbit != nil }
        for (index, node) in sources.enumerated() {
            for other in sources.dropFirst(index+1) {
                XCTAssertGreaterThan(hypot(node.center.x-other.center.x,node.center.y-other.center.y),node.outerRadius+other.outerRadius)
            }
        }
    }

    func testVisualSourceMovePreservesCompilerTimeAndRing() throws {
        var p = try project()
        let before = try HierarchySceneBuilder.build(p)
        let source = try XCTUnwrap(before.nodes.first { $0.music != nil && $0.orbit != nil })
        let plan = try ArrangementCompiler.compile(p)
        let original = try HierarchyEditing.position(source.id, in:p)
        try HierarchyEditing.move(source.id, to:Point(original.x+83,original.y-47), in:&p)
        let after = try HierarchySceneBuilder.build(p)
        let moved = try XCTUnwrap(after.node(source.id))
        XCTAssertEqual(moved.center.x-source.center.x,83,accuracy:1e-9)
        XCTAssertEqual(moved.center.y-source.center.y,-47,accuracy:1e-9)
        XCTAssertEqual(moved.orbit,source.orbit)
        XCTAssertEqual(after.orbitAnchor(for:source.id),before.orbitAnchor(for:source.id))
        XCTAssertEqual(moved.music?.startBeat,source.music?.startBeat)
        XCTAssertEqual(try ArrangementCompiler.compile(p).duration,plan.duration)
        for node in before.nodes where node.role != .group {
            XCTAssertEqual(after.node(node.id)?.radius,node.radius)
        }
    }

    func testFourteenSimultaneousSourcesUseBalancedCompactShells() throws {
        var p = Project()
        for index in 0..<14 { _ = p.addTrack(name:"악기 \(index+1)") }
        _ = p.addSection(name:"동시 시작",at:Point(),bars:4)
        p.enableAlbum(); p = try SectionGraphMigration.migrate(p)
        let plan = try ArrangementCompiler.compile(p)
        let scene = try HierarchySceneBuilder.build(p)
        let section = try XCTUnwrap(scene.nodes.first { $0.role == .section })
        let sources = scene.children(of:section.id).filter { $0.orbit != nil }
        XCTAssertEqual(sources.count,14)
        var bounds = CGRect.null
        for (index, source) in sources.enumerated() {
            bounds = bounds.union(CGRect(x:source.center.x-source.radius,y:source.center.y-source.radius,width:source.radius*2,height:source.radius*2))
            XCTAssertEqual(source.orbit?.anchor,0)
            XCTAssertEqual(scene.orbitAnchor(for:source.id),scene.orbitAnchor(for:sources[0].id))
            for other in sources.dropFirst(index+1) {
                XCTAssertGreaterThan(hypot(source.center.x-other.center.x,source.center.y-other.center.y),source.outerRadius+other.outerRadius)
            }
        }
        XCTAssertGreaterThan(bounds.width/bounds.height,0.6)
        XCTAssertLessThan(bounds.width/bounds.height,1.7)
        XCTAssertLessThan(max(bounds.width,bounds.height),2000)
        XCTAssertEqual(try ArrangementCompiler.compile(p).duration,plan.duration)
        let camera = try XCTUnwrap(PlaybackFraming.camera(for:section,in:scene,viewport:CGRect(x:0,y:0,width:1440,height:850)))
        XCTAssertGreaterThan(sources[0].radius*camera.zoom,18)
    }

    func testContextFramingDoesNotExpandToAllDescendants() throws {
        let scene = try HierarchySceneBuilder.build(project())
        let album = try XCTUnwrap(scene.node(.album))
        XCTAssertEqual(scene.childScale(of:.album),1)
        let viewport = CGRect(x:0,y:0,width:900,height:1400)
        let camera = try XCTUnwrap(PlaybackFraming.camera(for:album,in:scene,viewport:viewport))
        XCTAssertGreaterThan(camera.zoom*album.radius,40)
        XCTAssertTrue(camera.pan.x.isFinite)
    }
}
