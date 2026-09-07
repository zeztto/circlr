import XCTest
@testable import CirclrCore

final class HierarchyEditingTests: XCTestCase {
    func fixture() throws -> Project {
        var p = Project(); p.circleLayout = .freeform; _ = p.addTrack(name: "피아노"); _ = p.addTrack(name: "드럼", drums: true)
        _ = p.addSection(name: "벌스", at: Point(), bars: 2)
        p.sections[0].lanes[0].notes = [Note(beat: 1, pitch: 60)]
        p.enableAlbum(); return try SectionGraphMigration.migrate(p)
    }
    func addresses(_ p: Project) -> Set<CircleAddress> {
        Set(p.sections[0].lanes.map { .music(arrangementID: p.activeArrangementID, useID: p.active.uses[0].id, nodeID: "midi:\($0.id)") })
    }
    func testGroupingPreservesWorldPositionsSignalsAndMusicTime() throws {
        var p = try fixture(); let ids = addresses(p), before = try HierarchySceneBuilder.build(p)
        let plan = try AlbumCompiler.executionPlan(p)
        let group = try HierarchyEditing.group(ids, name: "연주", in: &p)
        let after = try HierarchySceneBuilder.build(p)
        for id in ids {
            let old = try XCTUnwrap(before.node(id)), new = try XCTUnwrap(after.node(id))
            XCTAssertEqual(old.center.x, new.center.x, accuracy: 1e-10)
            XCTAssertEqual(old.center.y, new.center.y, accuracy: 1e-10)
            XCTAssertEqual(old.radius, new.radius, accuracy: 1e-10)
            XCTAssertEqual(new.parent, group)
        }
        XCTAssertEqual(try AlbumCompiler.executionPlan(p).duration, plan.duration)
        XCTAssertEqual(try AlbumCompiler.executionPlan(p).occurrences[0].signalPlan?.midi, plan.occurrences[0].signalPlan?.midi)
        try ProjectStore.validateStructure(p)
    }
    func testGroupMoveTranslatesMembersAndMemberMoveUsesStoredScopeCoordinates() throws {
        var p = try fixture(); let ids = addresses(p)
        let group = try HierarchyEditing.group(ids, name: "연주", in: &p)
        let before = try Dictionary(uniqueKeysWithValues: ids.map { ($0, try HierarchyEditing.position($0, in: p)) })
        let origin = try HierarchyEditing.position(group, in: p)
        try HierarchyEditing.move(group, to: Point(origin.x+64, origin.y+96), in: &p)
        for id in ids {
            let point = try HierarchyEditing.position(id, in: p)
            XCTAssertEqual(point.x, before[id]!.x+64); XCTAssertEqual(point.y, before[id]!.y+96)
        }
        let first = try XCTUnwrap(ids.first)
        try HierarchyEditing.move(first, to: Point(-600,280), in: &p)
        XCTAssertEqual(try HierarchyEditing.position(first, in: p), Point(-600,280))
    }
    func testCollapsedGroupHidesChildrenKeepsExternalWiresAndDoesNotChangeExecution() throws {
        var p = try fixture(); let ids=addresses(p)
        let group = try HierarchyEditing.group(ids, name: "연주", in: &p)
        let plan = try AlbumCompiler.executionPlan(p)
        guard case .group(let parent,let id)=group else { return XCTFail() }
        try HierarchyEditing.editLayout(parent,in:&p) { layout in let i=layout.groups.firstIndex{$0.id==id}!;layout.groups[i].collapsed=true }
        let scene=try HierarchySceneBuilder.build(p)
        XCTAssertNotNil(scene.node(group)); XCTAssertTrue(ids.allSatisfy { scene.node($0)==nil })
        XCTAssertEqual(scene.edges.filter{$0.from==group}.count,2)
        XCTAssertEqual(try AlbumCompiler.executionPlan(p).occurrences[0].signalPlan?.midi,plan.occurrences[0].signalPlan?.midi)
        try HierarchyEditing.editLayout(parent,in:&p) { $0.groups.removeAll{$0.id==id} }
        XCTAssertTrue(try ids.allSatisfy { try HierarchySceneBuilder.build(p).node($0) != nil })
    }
    func testAlignmentAndCrossScopeRejectionAreAtomic() throws {
        var p = try fixture();let ids=addresses(p)
        try HierarchyEditing.align(ids,mode:0,in:&p)
        XCTAssertEqual(Set(try ids.map{try HierarchyEditing.position($0,in:p).y}).count,1)
        let song=try XCTUnwrap(p.album?.children.first),before=p
        var mixed=ids;mixed.insert(.composition(song))
        XCTAssertThrowsError(try HierarchyEditing.group(mixed,name:"잘못된 그룹",in:&p));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try HierarchyEditing.align(mixed,mode:1,in:&p));XCTAssertEqual(p,before)
    }
}
