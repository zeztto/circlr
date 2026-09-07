import XCTest
@testable import CirclrCore

final class HierarchyGeometryTests: XCTestCase {
    func scene() throws -> (Project, HierarchyScene) {
        var p = Project(); p.circleLayout = .freeform; _ = p.addTrack(name: "악기")
        _ = p.addSection(name: "벌스", at: Point(100, 50), bars: 4)
        p.enableAlbum()
        _ = try AlbumEditing.wrapContents(of: p.album!.children[0], name: "첫 악장", in: &p)
        p = try SectionGraphMigration.migrate(p)
        return (p, try HierarchySceneBuilder.build(p))
    }
    func testRealHierarchyContainsAlbumSongMovementSectionAndMusic() throws {
        let (_, scene) = try scene()
        let leaf = try XCTUnwrap(scene.nodes.first { if case .midi = $0.music?.content { return true }; return false })
        let path = scene.path(to: leaf.id)
        XCTAssertEqual(path.map(\.role), [.album, .song, .movement, .section, .music])
        for node in scene.nodes {
            if let parent = node.parent.flatMap(scene.node) {
                XCTAssertLessThanOrEqual(hypot(node.center.x-parent.center.x, node.center.y-parent.center.y) + node.outerRadius, parent.radius)
            }
        }
    }
    func testParentMoveTranslatesWholeSubtreeWithoutChangingExecution() throws {
        var (project, before) = try scene()
        let song = project.album!.children[0]
        let plan = try AlbumCompiler.executionPlan(project)
        project.album?.layout.positions[song] = Point(400, -200)
        let after = try HierarchySceneBuilder.build(project)
        for node in before.nodes where before.path(to:node.id).contains(where:{$0.id == .composition(song)}) {
            let moved = try XCTUnwrap(after.node(node.id))
            XCTAssertEqual(moved.center.x-node.center.x, 120, accuracy: 1e-8)
            XCTAssertEqual(moved.center.y-node.center.y, -60, accuracy: 1e-8)
        }
        XCTAssertEqual(try AlbumCompiler.executionPlan(project).duration, plan.duration)
    }
    func testDeepZoomKeepsCursorAndDetailFocusInsideCanvas() throws {
        let (_, scene) = try scene()
        let leaf = try XCTUnwrap(scene.nodes.first { $0.role == .music })
        let camera = HierarchyCamera(pan: Point(200, 100))
        let pointer = Point(350, 250)
        let zoomed = camera.zoomed(to: 1500, around: pointer)
        XCTAssertEqual(zoomed.world(pointer).x, camera.world(pointer).x, accuracy: 1e-9)
        XCTAssertEqual(zoomed.world(pointer).y, camera.world(pointer).y, accuracy: 1e-9)
        let focused = zoomed.focused(on: leaf, width: 1440, height: 850, detail: true)
        XCTAssertEqual(focused.screen(leaf.center).x, 720, accuracy: 1e-6)
        XCTAssertGreaterThan(focused.zoom * leaf.radius, 450)
        XCTAssertEqual(camera.interpolated(to: focused, progress: 0), camera)
        let end = camera.interpolated(to: focused, progress: 1)
        XCTAssertEqual(end.zoom, focused.zoom, accuracy: 1e-7)
        XCTAssertEqual(end.pan.x, focused.pan.x, accuracy: 1e-6)
        var repeated=leaf;repeated.repeatCount=256
        let detailed=focused.focused(on:repeated,width:1080,height:800,detail:true)
        XCTAssertGreaterThan(detailed.zoom*repeated.radius,325)
        XCTAssertGreaterThan(repeated.outerRadius,repeated.radius)
    }
}
