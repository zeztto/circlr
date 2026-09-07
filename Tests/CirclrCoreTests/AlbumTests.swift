import XCTest
@testable import CirclrCore

final class AlbumTests: XCTestCase {
    func legacySong() throws -> Project {
        var p = Project(); p.name = "원래 곡"
        let track = p.addTrack(name: "피아노")
        let id = p.addSection(name: "벌스", at: Point(12, 48), bars: 2)
        var lane = p.sections[0].lanes[0]
        lane.notes = [Note(beat: 1, length: 2, pitch: 67, velocity: 91)]
        try ProjectEditing.setLane(lane, for: id, original: false, in: &p)
        p.arrangements[0].uses[0].effects = [Effect(.drive, amount: 0.4)]
        XCTAssertEqual(lane.trackID, track)
        return p
    }

    func testMigrationPreservesOriginalsVariantsAlternativesAndExecution() throws {
        var p = try legacySong()
        ProjectEditing.duplicateArrangement(in: &p, name: "두 번째 안")
        let before = p, plan = try ArrangementCompiler.compile(p)
        p.enableAlbum()
        let album = try XCTUnwrap(p.album), song = try XCTUnwrap(album.compositions.first)
        XCTAssertEqual(p.schemaVersion, 2)
        XCTAssertEqual(song.name, before.name)
        XCTAssertEqual(song.arrangementIDs, before.arrangements.map(\.id))
        XCTAssertEqual(song.selectedArrangementID, before.activeArrangementID)
        XCTAssertEqual(p.sections, before.sections)
        XCTAssertEqual(p.arrangements, before.arrangements)
        XCTAssertEqual(p.tracks, before.tracks)
        XCTAssertEqual(p.signal, before.signal)
        XCTAssertEqual(p.assets, before.assets)
        XCTAssertEqual(p.takes, before.takes)
        XCTAssertEqual(try ArrangementCompiler.compile(p).duration, plan.duration)
        let migrated = p; p.enableAlbum(); XCTAssertEqual(p, migrated)
        try ProjectStore.validateStructure(p)
    }

    func testAlbumSongsMovementsAndRepeatedSectionsUseOneAbsoluteTime() throws {
        var p = try legacySong(); p.enableAlbum()
        let song = try XCTUnwrap(p.album?.children.first)
        let firstMovement = try AlbumEditing.wrapContents(of: song, name: "첫 악장", in: &p)
        let secondMovement = try AlbumEditing.add(name: "둘째 악장", kind: .movement, parentID: song, in: &p)
        try AlbumEditing.selectArrangement(try XCTUnwrap(p.album?.composition(secondMovement)?.selectedArrangementID), in: &p)
        _ = p.addSection(name: "짧은 구간", at: Point(), bars: 1)
        p.arrangements[p.activeIndex].uses[0].repeatCount = 2
        let otherSong = try AlbumEditing.add(name: "다음 곡", kind: .song, in: &p)
        try AlbumEditing.selectArrangement(try XCTUnwrap(p.album?.composition(otherSong)?.selectedArrangementID), in: &p)
        _ = p.addSection(name: "후렴", at: Point(), bars: 1)
        p.album?.compositions[0].repeatCount = 2
        let plan = try AlbumCompiler.compile(p)
        XCTAssertEqual(plan.compositions.map(\.compositionID), [firstMovement, secondMovement, firstMovement, secondMovement, otherSong])
        XCTAssertEqual(plan.compositions.map(\.start), [0, 4, 8, 12, 16])
        XCTAssertEqual(plan.duration, 18)
        XCTAssertEqual(plan.compositions[2].path, [song, firstMovement])
        XCTAssertEqual(plan.compositions[2].iterations, [1, 0])
        XCTAssertEqual(plan.compositions[1].plan.occurrences.count, 2)
    }

    func testEveryLevelInheritsParentAndGlobalBypassesAllParents() throws {
        var p = try legacySong(); p.enableAlbum(); p.global.tempo = 120
        let song = try XCTUnwrap(p.album?.children.first)
        let movement = try AlbumEditing.wrapContents(of: song, name: "악장", in: &p)
        p.album?.compositions[0].settings.tempo = .local(90)
        p.album?.compositions[0].settings.scale = .local(Scale(root: 5))
        let mi = try XCTUnwrap(p.album?.compositions.firstIndex(where: { $0.id == movement }))
        p.album?.compositions[mi].settings.meter = .local(Meter(7, 8))
        var result = try ArrangementCompiler.compile(p).occurrences[0]
        XCTAssertEqual(result.context.tempo, 90); XCTAssertEqual(result.context.scale.root, 5)
        XCTAssertEqual(result.clock.beats, 7)
        p.sections[0].settings.tempo = .local(60)
        XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences[0].context.tempo, 60)
        p.arrangements[0].uses[0].settings.tempo = Setting(source: .global)
        result = try ArrangementCompiler.compile(p).occurrences[0]
        XCTAssertEqual(result.context.tempo, 120)
        XCTAssertEqual(result.context.meter, Meter(7, 8))
        XCTAssertEqual(result.lanes[0].notes[0].pitch, 67)
    }

    func testNonActiveSongCompilationUsesItsOwnContext() throws {
        var p = try legacySong(); p.enableAlbum()
        p.album?.compositions[0].settings.tempo = .local(60)
        let first = p.activeArrangementID
        let song = try AlbumEditing.add(name: "빠른 곡", kind: .song, in: &p)
        let second = try XCTUnwrap(p.album?.composition(song)?.selectedArrangementID)
        try AlbumEditing.selectArrangement(second, in: &p)
        _ = p.addSection(name: "섹션", at: Point(), bars: 2)
        p.album?.compositions[1].settings.tempo = .local(180)
        XCTAssertEqual(try ArrangementCompiler.compile(p, arrangementID: first).duration, 8)
        XCTAssertEqual(try ArrangementCompiler.compile(p, arrangementID: second).duration, 8.0 / 3, accuracy: 1e-9)
        try ProjectStore.validateStructure(p)
    }

    func testArrangementDuplicationStaysInItsComposition() throws {
        var p = try legacySong(); p.enableAlbum()
        let owner = try XCTUnwrap(p.album?.children.first), original = p.activeArrangementID
        ProjectEditing.duplicateArrangement(in: &p, name: "대안")
        XCTAssertEqual(p.album?.owner(of: p.activeArrangementID)?.id, owner)
        XCTAssertEqual(p.album?.composition(owner)?.selectedArrangementID, p.activeArrangementID)
        XCTAssertEqual(p.album?.composition(owner)?.arrangementIDs.count, 2)
        try AlbumEditing.selectArrangement(original, in: &p)
        XCTAssertEqual(p.album?.composition(owner)?.selectedArrangementID, original)
        try ProjectStore.validateStructure(p)
    }

    func testReorderAndSpatialLayoutAreIndependentAndInvalidMoveIsAtomic() throws {
        var p = try legacySong(); p.enableAlbum()
        let first = try XCTUnwrap(p.album?.children.first)
        let second = try AlbumEditing.add(name: "다음 곡", kind: .song, at: Point(400, 250), in: &p)
        let before = try AlbumCompiler.compile(p)
        p.album?.layout.positions[first] = Point(900, -380)
        p.album?.layout.zoom = 0.4
        XCTAssertEqual(try AlbumCompiler.compile(p).compositions.map(\.compositionID), before.compositions.map(\.compositionID))
        try AlbumEditing.move(second, to: nil, index: 0, in: &p)
        XCTAssertEqual(try AlbumCompiler.compile(p).compositions.map(\.compositionID), [second, first])
        let saved = p
        XCTAssertThrowsError(try AlbumEditing.move(first, to: first, index: 0, in: &p))
        XCTAssertEqual(p, saved)
        XCTAssertThrowsError(try AlbumEditing.move(first, to: second, index: 0, in: &p))
        XCTAssertEqual(p, saved)
    }

    func testCorruptOwnershipCycleOrphanAndSettingAreRejected() throws {
        var p = try legacySong(); p.enableAlbum()
        let song = try XCTUnwrap(p.album?.children.first)
        let movement = try AlbumEditing.wrapContents(of: song, name: "악장", in: &p)
        let valid = p
        p.album?.children.append(movement)
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
        p = valid; p.album?.children = []; p.album?.compositions[1].children = [song]
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
        p = valid; p.album?.compositions[0].children = ["missing"]
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
        p = valid; p.album?.compositions[1].arrangementIDs.append(p.activeArrangementID)
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
        p = valid; p.album?.compositions[0].settings.tempo = .local(.nan)
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
        p = valid; p.album?.compositions[0].repeatCount = 257
        XCTAssertThrowsError(try AlbumCompiler.compile(p))
    }

    func testVersionOneDecodeAndVersionTwoPackageRoundTrip() throws {
        let old = try legacySong()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let oldData = try encoder.encode(old)
        XCTAssertFalse(String(decoding: oldData, as: UTF8.self).contains("\"album\""))
        var p = try JSONDecoder().decode(Project.self, from: oldData)
        XCTAssertNil(p.album); p.enableAlbum()
        _ = try AlbumEditing.wrapContents(of: try XCTUnwrap(p.album?.children.first), name: "악장", in: &p)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-album-test-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyURL = root.appendingPathComponent("legacy.circlr")
        try ProjectStore.save(old, to: legacyURL, mediaRoot: nil)
        let legacyData = try Data(contentsOf: legacyURL.appendingPathComponent("manifest.json"))
        let newURL = root.appendingPathComponent("album.circlr")
        let saved = try ProjectStore.save(p, to: newURL, mediaRoot: nil)
        let loaded = try ProjectStore.load(newURL).project
        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(try AlbumCompiler.compile(loaded).duration, 4)
        XCTAssertEqual(try Data(contentsOf: legacyURL.appendingPathComponent("manifest.json")), legacyData)
        XCTAssertEqual(try ProjectStore.load(legacyURL).project, old)
    }

    func testUnknownSchemaIsNeverDowngradedAndEmptyMusicStillValidatesContext() throws {
        var unknown = Project(); unknown.schemaVersion = 99
        let original = unknown; unknown.enableAlbum()
        XCTAssertEqual(unknown, original)
        XCTAssertThrowsError(try AlbumCompiler.compile(unknown))
        XCTAssertThrowsError(try AlbumEditing.add(name: "곡", kind: .song, in: &unknown))
        XCTAssertEqual(unknown, original)
        var empty = Project(); empty.enableAlbum()
        empty.album?.compositions[0].settings.tempo = .local(-1)
        XCTAssertThrowsError(try AlbumCompiler.compile(empty))
    }
}
