import XCTest
@testable import CirclrCore

final class CircleHistoryTests: XCTestCase {
    private func fixture() -> Project {
        var project = Project()
        _ = project.addTrack(name: "신스")
        _ = project.addSection(name: "벌스", at: Point(), bars: 4)
        project.enableAlbum()
        return project
    }

    func testUndoAndRedoKeepPreferencesChangedAfterEachMusicEdit() throws {
        let original = fixture()
        var edited = original
        edited.name = "새 곡 이름"; edited.musicRevision = 1
        var current = edited
        current.circleLayout = .freeform
        current.album?.layout.grid = false; current.album?.layout.snap = false
        let undone = try CircleHistory.restore(original, layoutOnly: false, current: current)
        var expected = original
        expected.circleLayout = .freeform
        expected.album?.layout.grid = false; expected.album?.layout.snap = false
        expected.musicRevision = 2
        XCTAssertEqual(undone, expected)

        var viewed = undone
        viewed.circleLayout = .orbit; viewed.album?.layout.snap = true
        let redone = try CircleHistory.restore(current, layoutOnly: false, current: viewed)
        expected.name = edited.name; expected.circleLayout = .orbit
        expected.album?.layout.snap = true; expected.musicRevision = 3
        XCTAssertEqual(redone, expected)
    }

    func testActualPositionsGroupsAndSpacingRemainUndoable() throws {
        let original = fixture()
        var moved = original
        let useID = moved.active.uses[0].id
        let songID = try XCTUnwrap(moved.album?.children.first)
        moved.album?.layout.positions[songID] = Point(800, 400)
        moved.album?.layout.groups = [CanvasGroup(name: "그룹", members: [songID])]
        moved.album?.layout.spacing = 48
        moved.arrangements[0].layout.positions[useID] = Point(400, 600)
        moved.arrangements[0].layout.grid = false
        moved.signal.layout.positions[moved.signal.nodes[0].id] = Point(700, 300)
        moved.circleLayout = .freeform; moved.album?.layout.grid = false
        let undone = try CircleHistory.restore(original, layoutOnly: false, current: moved)
        var expected = original
        expected.circleLayout = .freeform; expected.album?.layout.grid = false
        expected.musicRevision = 1
        XCTAssertEqual(undone, expected)
        var redoneExpected = moved; redoneExpected.musicRevision = 2
        XCTAssertEqual(try CircleHistory.restore(moved, layoutOnly: false, current: undone), redoneExpected)
    }

    func testDifferentAlbumIdentityDoesNotInheritAnotherAlbumsPreferences() throws {
        let saved = fixture()
        var current = saved
        current.album?.id = newID()
        current.album?.layout.grid = false; current.album?.layout.snap = false
        current.circleLayout = .freeform
        let result = try CircleHistory.restore(saved, layoutOnly: false, current: current)
        XCTAssertEqual(result.album, saved.album)
        XCTAssertEqual(result.circleLayout, .freeform)
    }

    func testAlbumCreationAndRemovalPreserveStructure() throws {
        var legacy = Project(); legacy.circleLayout = .freeform
        var created = legacy; created.enableAlbum()
        created.album?.layout.grid = false; created.album?.layout.snap = false
        let removed = try CircleHistory.restore(legacy, layoutOnly: false, current: created)
        XCTAssertNil(removed.album); XCTAssertEqual(removed.schemaVersion, 1)
        let restored = try CircleHistory.restore(created, layoutOnly: false, current: removed)
        XCTAssertEqual(restored.album, created.album); XCTAssertEqual(restored.schemaVersion, 2)
    }

    func testImplicitOrbitPreferenceStaysImplicit() throws {
        var saved = fixture(); saved.circleLayout = .freeform
        var current = saved; current.circleLayout = nil
        let result = try CircleHistory.restore(saved, layoutOnly: false, current: current)
        XCTAssertNil(result.circleLayout); XCTAssertTrue(result.usesOrbits)
    }

    func testPortOnlyUndoKeepsCurrentMusicAndAllViewingPreferences() throws {
        let saved = fixture()
        var current = saved
        current.name = "최근 음악"; current.musicRevision = 9
        current.circleLayout = .freeform
        current.album?.layout.grid = false; current.album?.layout.snap = false
        let cable = try XCTUnwrap(CirclePortCatalog.connections(in: current).first)
        try CirclePortLayoutEditing.apply([.init(id: cable.id, placement: .init(from: .north, to: .south))],
            projectID: current.id, expectedMusicRevision: 9, expectedLayoutRevision: 0, in: &current)
        var result = try CircleHistory.restore(saved, layoutOnly: true, current: current)
        XCTAssertEqual(result.portLayout?.revision, 2)
        XCTAssertEqual(result.portLayout?.connections, [])
        result.portLayout = current.portLayout
        XCTAssertEqual(result, current)
    }

    func testHistoryRejectsAnotherProjectBeforeRestoringAnything() {
        let saved = fixture(), current = fixture()
        for layoutOnly in [false, true] {
            XCTAssertThrowsError(try CircleHistory.restore(saved, layoutOnly: layoutOnly, current: current))
        }
    }
}
