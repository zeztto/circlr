import XCTest
@testable import CirclrCore

final class RadialOrbitLayoutTests: XCTestCase {
    func testActualDemoDefaultProjectionHasGenerousVariableRadiusClearance() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let p = try JSONDecoder().decode(Project.self,from:Data(contentsOf:root.appendingPathComponent("Resources/Demos/f0r-h3r.circlr/manifest.json")))
        let scene = try HierarchySceneBuilder.build(p)
        let section = try XCTUnwrap(scene.nodes.first { $0.role == .section })
        let children = scene.children(of:section.id)
        XCTAssertGreaterThan(children.count,40)
        let radii = Set(children.map(\.radius))
        XCTAssertTrue(radii.contains(88)); XCTAssertTrue(radii.contains(72)); XCTAssertTrue(radii.contains(54)); XCTAssertTrue(radii.contains(42))
        for (index,node) in children.enumerated() {
            XCTAssertGreaterThanOrEqual(hypot(node.center.x-section.center.x,node.center.y-section.center.y)+1e-8,section.radius+node.outerRadius+OrbitSceneLayout.gap)
            for other in children.dropFirst(index+1) {
                XCTAssertGreaterThanOrEqual(hypot(node.center.x-other.center.x,node.center.y-other.center.y)+1e-8,node.outerRadius+other.outerRadius+OrbitSceneLayout.gap)
            }
        }
        for edge in scene.edges where edge.kind != .sidechain {
            guard let from=scene.node(edge.from),let to=scene.node(edge.to),from.parent==section.id,to.parent==section.id,to.orbit==nil else { continue }
            XCTAssertGreaterThan(hypot(to.center.x-section.center.x,to.center.y-section.center.y),hypot(from.center.x-section.center.x,from.center.y-section.center.y))
        }
        XCTAssertEqual(scene.node(.album)?.radius,340)
        XCTAssertEqual(scene.nodes.first { $0.role == .song }?.radius,280)
        XCTAssertEqual(section.radius,200)
    }

    func testSidechainDetectionDoesNotPullPrimaryBranchesOffTheirLayout() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let original = try JSONDecoder().decode(Project.self,from:Data(contentsOf:root.appendingPathComponent("Resources/Demos/f0r-h3r.circlr/manifest.json")))
        var withoutDetectors = original
        for index in withoutDetectors.sections.indices {
            withoutDetectors.sections[index].graph?.edges.removeAll { $0.sidechain }
        }
        let withSidechains = try HierarchySceneBuilder.build(original)
        let primaryOnly = try HierarchySceneBuilder.build(withoutDetectors)
        XCTAssertGreaterThan(withSidechains.edges.filter { $0.kind == .sidechain }.count,0)
        XCTAssertEqual(primaryOnly.edges.filter { $0.kind == .sidechain }.count,0)
        for node in withSidechains.nodes {
            XCTAssertEqual(primaryOnly.node(node.id)?.center,node.center)
            XCTAssertEqual(primaryOnly.node(node.id)?.orbit,node.orbit)
        }
        XCTAssertEqual(try ArrangementCompiler.compile(original).duration,try ArrangementCompiler.compile(withoutDetectors).duration)
    }

    func testVersionOneMissingProcessorOffsetMovesByRequestedDelta() throws {
        var p = try OrbitTests().fixture()
        let initial = try HierarchySceneBuilder.build(p)
        let processor = try XCTUnwrap(initial.nodes.first { $0.music?.content.input != nil })
        let scope = try HierarchyEditing.scope(of:processor.id,in:p)
        try HierarchyEditing.editLayout(scope,in:&p) { layout in
            layout.orbitLayoutVersion = 1; layout.orbitPositions = [:]
        }
        let before = try XCTUnwrap(HierarchySceneBuilder.build(p).node(processor.id))
        XCTAssertEqual(try HierarchyEditing.position(processor.id,in:p),Point())
        try HierarchyEditing.move(processor.id,to:Point(10,20),in:&p)
        let moved = try XCTUnwrap(HierarchySceneBuilder.build(p).node(processor.id))
        XCTAssertEqual(moved.center.x-before.center.x,10,accuracy:1e-8)
        XCTAssertEqual(moved.center.y-before.center.y,20,accuracy:1e-8)
    }

    func testManualOffsetDoesNotReflowOtherNodesOrChangeTime() throws {
        var p = try OrbitTests().fixture()
        let before=try HierarchySceneBuilder.build(p)
        let source=try XCTUnwrap(before.nodes.first { $0.role == .music && $0.orbit != nil })
        let original=try HierarchyEditing.position(source.id,in:p)
        try HierarchyEditing.move(source.id,to:Point(original.x+500,original.y-200),in:&p)
        let after=try HierarchySceneBuilder.build(p)
        for old in before.nodes where old.id != source.id && old.role != .group {
            XCTAssertEqual(after.node(old.id)?.center,old.center)
        }
        let moved=try XCTUnwrap(after.node(source.id))
        XCTAssertEqual(moved.center.x-source.center.x,500,accuracy:1e-8)
        XCTAssertEqual(moved.center.y-source.center.y,-200,accuracy:1e-8)
        XCTAssertEqual(moved.orbit,source.orbit)
        p.circleLayout = .freeform
        let freeform=try HierarchySceneBuilder.build(p)
        XCTAssertEqual(try XCTUnwrap(freeform.node(source.id)).radius,80*pow(0.3,3),accuracy:1e-8)
    }
}
