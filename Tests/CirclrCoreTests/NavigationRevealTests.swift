import XCTest
@testable import CirclrCore

final class NavigationRevealTests: XCTestCase {
    private func fixture() throws -> (Project, CircleAddress, CircleAddress, CircleAddress) {
        var project = try HierarchyEditingTests().fixture()
        var graph = try XCTUnwrap(project.sections[0].graph)
        let routes = try StudioNavigation.build(project)[0].tracks
        let targets = try routes.map { try XCTUnwrap($0.destinations.first { $0.role == "MIDI" }) }
        for route in routes {
            let members = route.destinations.filter { ["MIDI", "악기"].contains($0.role) }.compactMap { HierarchyEditing.memberID($0.id) }
            var group = CanvasGroup(name: route.name + " 그룹", members: members)
            group.collapsed = true; graph.layout.groups.append(group)
        }
        project.sections[0].graph = graph
        let scope = CircleAddress.section(arrangementID: project.active.id, useID: project.active.uses[0].id)
        return (project, targets[0].id, targets[1].id, .group(parent: scope, id: graph.layout.groups[0].id))
    }

    func testRevealIsUseScopedAndDoesNotMaterializeDocumentOverrides() throws {
        var (project, first, second, group) = try fixture()
        _ = try ProjectEditing.reuse(project.active.uses[0].id, in: &project, at: Point(400, 0))
        let original = project
        let scene = try StudioNavigation.scene(revealing: first, in: project)
        XCTAssertNotNil(scene.node(first)); XCTAssertNil(scene.node(second))
        XCTAssertFalse(try XCTUnwrap(scene.node(group)).subtitle.contains("접힘"))
        let reused = CircleAddress.music(arrangementID: project.active.id, useID: project.active.uses[1].id,
            nodeID: try XCTUnwrap(HierarchyEditing.memberID(first)))
        XCTAssertNil(scene.node(reused))
        XCTAssertTrue(try HierarchySceneBuilder.build(project).node(group)!.subtitle.contains("접힘"))
        XCTAssertEqual(project, original)
    }

    func testParentAndOtherPathReturnToStoredCollapseInBothLayouts() throws {
        var (project, first, second, group) = try fixture()
        for mode in [CircleLayout.orbit, .freeform] {
            project.circleLayout = mode
            let inside = try StudioNavigation.scene(revealing: first, in: project)
            XCTAssertEqual(inside.node(first)?.parent, group)
            let parent = try StudioNavigation.scene(revealing: group, in: project)
            XCTAssertNil(parent.node(first)); XCTAssertTrue(parent.node(group)!.subtitle.contains("접힘"))
            let elsewhere = try StudioNavigation.scene(revealing: second, in: project)
            XCTAssertNotNil(elsewhere.node(second)); XCTAssertNil(elsewhere.node(first))
            XCTAssertNil(try StudioNavigation.scene(revealing: .album, in: project).node(second))
        }
    }

    func testAllContainingScopesRevealWithoutOpeningUnrelatedGroups() throws {
        var (project, first, second, _) = try fixture()
        let song = try XCTUnwrap(project.album?.children.first)
        var songGroup = CanvasGroup(name: "접힌 곡", members: [song]); songGroup.collapsed = true
        project.album?.layout.groups.append(songGroup)
        var sectionGroup = CanvasGroup(name: "접힌 섹션", members: [project.active.uses[0].id]); sectionGroup.collapsed = true
        project.arrangements[0].layout.groups.append(sectionGroup)
        let original = project
        XCTAssertNil(try HierarchySceneBuilder.build(project).node(first))
        let scene = try StudioNavigation.scene(revealing: first, in: project)
        XCTAssertNotNil(scene.node(first)); XCTAssertNil(scene.node(second))
        XCTAssertEqual(try StudioNavigation.containingGroups(of: first, in: project).count, 3)
        XCTAssertEqual(scene.path(to: first).filter { $0.role == .group }.count, 3)
        XCTAssertEqual(project, original)
    }

    func testMusicalHistoryAndExplicitGroupEditKeepTheirSeparateMeaning() throws {
        let (saved, first, _, group) = try fixture()
        var edited = saved; edited.name = "편집한 곡"; edited.musicRevision = 1
        let undone = try CircleHistory.restore(saved, layoutOnly: false, current: edited)
        XCTAssertNotNil(try StudioNavigation.scene(revealing: first, in: undone).node(first))
        let redone = try CircleHistory.restore(edited, layoutOnly: false, current: undone)
        XCTAssertEqual(redone.name, edited.name)
        XCTAssertNotNil(try StudioNavigation.scene(revealing: first, in: redone).node(first))
        var explicitlyOpened = saved
        guard case .group(let scope, let id) = group else { return XCTFail() }
        try HierarchyEditing.editLayout(scope, in: &explicitlyOpened) { layout in
            layout.groups[layout.groups.firstIndex { $0.id == id }!].collapsed = false
        }
        XCTAssertNotNil(try StudioNavigation.scene(revealing: .album, in: explicitlyOpened).node(first))
        let closed = try CircleHistory.restore(saved, layoutOnly: false, current: explicitlyOpened)
        XCTAssertNil(try StudioNavigation.scene(revealing: .album, in: closed).node(first))
        XCTAssertNotNil(try StudioNavigation.scene(revealing: first, in: closed).node(first))
    }

    func testSavedSelectionCanBeRevealedWithoutChangingStoredGroups() throws {
        var (project, first, _, _) = try fixture()
        project.hierarchyView = HierarchyViewport(camera: HierarchyCamera(pan: Point(), zoom: 1),
            width: 1024, height: 768, selection: first)
        let data = try JSONEncoder().encode(project)
        let loaded = try JSONDecoder().decode(Project.self, from: data)
        let selection = try XCTUnwrap(loaded.hierarchyView?.selection)
        XCTAssertNotNil(try StudioNavigation.scene(revealing: selection, in: loaded).node(first))
        XCTAssertEqual(loaded, project)
        XCTAssertEqual(try StudioNavigation.containingGroups(of: nil, in: loaded), [])
    }

    func testMissingAndUnselectedArrangementTargetsAreRejectedWithoutMutation() throws {
        var (project, first, _, _) = try fixture()
        let original = project
        XCTAssertThrowsError(try StudioNavigation.scene(revealing: .music(arrangementID: project.active.id,
            useID: project.active.uses[0].id, nodeID: "missing"), in: project))
        XCTAssertEqual(project, original)
        var alternative = project.active; alternative.id = newID()
        project.arrangements.append(alternative)
        project.album?.compositions[0].arrangementIDs.append(alternative.id)
        let before = project
        XCTAssertThrowsError(try StudioNavigation.scene(revealing: .music(arrangementID: alternative.id,
            useID: alternative.uses[0].id, nodeID: HierarchyEditing.memberID(first)!), in: project))
        XCTAssertEqual(project, before)
    }
}
