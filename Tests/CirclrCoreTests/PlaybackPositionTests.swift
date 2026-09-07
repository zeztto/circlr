import XCTest
@testable import CirclrCore

final class PlaybackPositionTests: XCTestCase {
    func fixture() throws -> Project {
        var p = Project(); _ = p.addTrack(name: "신스")
        let a = p.addSection(name: "벌스", at: Point(), bars: 2)
        let b = p.addSection(name: "후렴", at: Point(400, 0), bars: 2)
        p.arrangements[0].uses[0].isEnd = false
        p.arrangements[0].edges = [FlowEdge(from: a, to: b)]
        p.sections[0].lanes[0].notes = [Note(beat: 0, length: 1, pitch: 60)]
        p.enableAlbum()
        return try SectionGraphMigration.migrate(p)
    }
    func testOverlapChoosesIncomingSectionAndBothPlayheadsRemainActive() throws {
        var p = try fixture()
        p.arrangements[0].edges[0].transition.mode = .overlap
        p.arrangements[0].edges[0].transition.anchor = .seconds
        p.arrangements[0].edges[0].transition.length = 1
        let plan = try AlbumCompiler.executionPlan(p), album = try AlbumCompiler.compile(p), scene = try HierarchySceneBuilder.build(p)
        let incoming = plan.occurrences[1], seconds = incoming.start+0.25
        XCTAssertEqual(PlaybackPosition.followOccurrence(in: plan, at: seconds)?.id, incoming.id)
        for occurrence in plan.occurrences {
            let node = try XCTUnwrap(scene.node(.section(arrangementID: p.activeArrangementID, useID: occurrence.use.id)))
            XCTAssertEqual(try XCTUnwrap(PlaybackPosition.localSeconds(for: node, at: seconds, plan: plan, album: album, albumID: p.album?.id)), seconds-occurrence.start, accuracy: 1e-9)
        }
    }
    func testInsertAndTailHoldCameraButDoNotInventAnActiveSection() throws {
        var p = try fixture()
        p.arrangements[0].edges[0].transition.mode = .insert
        p.arrangements[0].edges[0].transition.anchor = .seconds
        p.arrangements[0].edges[0].transition.length = 1
        let plan = try AlbumCompiler.executionPlan(p), seconds = plan.occurrences[0].end+0.5
        XCTAssertNil(PlaybackPosition.occurrence(in: plan, at: seconds))
        XCTAssertEqual(PlaybackPosition.followOccurrence(in: plan, at: seconds)?.id, plan.occurrences[0].id)
        XCTAssertNil(PlaybackPosition.occurrence(in: plan, at: plan.duration+0.2))
        XCTAssertEqual(PlaybackPosition.followOccurrence(in: plan, at: plan.duration+0.2)?.id, plan.occurrences.last?.id)
        XCTAssertNil(PlaybackPosition.followOccurrence(in: plan, at: -.infinity))
        XCTAssertNil(PlaybackPosition.followOccurrence(in: plan, at: -0.1))
    }
    func testRepeatedSectionResetsLocalTimeAtExactBoundary() throws {
        var p = try fixture(); p.arrangements[0].uses[0].repeatCount = 2
        let plan = try AlbumCompiler.executionPlan(p), scene = try HierarchySceneBuilder.build(p)
        let node = try XCTUnwrap(scene.node(.section(arrangementID: p.activeArrangementID, useID: plan.occurrences[0].use.id)))
        let value = PlaybackPosition.localSeconds(for: node, at: plan.occurrences[1].start, plan: plan, album: nil, albumID: p.album?.id)
        XCTAssertEqual(value, 0)
        XCTAssertEqual(PlaybackPosition.followOccurrence(in: plan, at: plan.occurrences[1].start)?.iteration, 1)
    }
    func testLocalTempoAndRepeatsUsePreparedSourceTiming() throws {
        var p = try fixture()
        let use = p.active.uses[0]
        var graph = try XCTUnwrap(SectionGraphEditing.effective(section: p.sections[0], use: use))
        let index = try XCTUnwrap(graph.nodes.firstIndex { $0.content.output == .midi })
        graph.nodes[index].settings.tempo = .local(60); graph.nodes[index].lengthBeats = 1
        graph.nodes[index].repeatCount = 2; graph.nodes[index].startBeat = 1
        try SectionGraphEditing.set(graph, useID: use.id, original: false, in: &p)
        let scene = try HierarchySceneBuilder.build(p), plan = try AlbumCompiler.executionPlan(p)
        let node = try XCTUnwrap(scene.node(.music(arrangementID: p.activeArrangementID, useID: use.id, nodeID: graph.nodes[index].id)))
        func value(_ seconds: Double) -> Double? { PlaybackPosition.localSeconds(for: node, at: seconds, plan: plan, album: nil, albumID: p.album?.id) }
        XCTAssertNil(value(0.49)); XCTAssertEqual(try XCTUnwrap(value(0.75)), 0.25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(value(1.75)), 0.25, accuracy: 1e-9); XCTAssertNil(value(2.51))
    }
    func testSelectedSectionDoesNotShowAlbumOrOtherSectionProgress() throws {
        let p = try fixture(), use = p.active.uses[1]
        let plan = try ArrangementCompiler.compile(p, onlyUseID: use.id), scene = try HierarchySceneBuilder.build(p)
        let album = try XCTUnwrap(scene.node(.album))
        XCTAssertNil(PlaybackPosition.localSeconds(for: album, at: 0.5, plan: plan, album: nil, albumID: p.album?.id))
        let first = try XCTUnwrap(scene.node(.section(arrangementID: p.activeArrangementID, useID: p.active.uses[0].id)))
        XCTAssertNil(PlaybackPosition.localSeconds(for: first, at: 0.5, plan: plan, album: nil, albumID: p.album?.id))
        XCTAssertEqual(PlaybackPosition.followOccurrence(in: plan, at: 0.5)?.use.id, use.id)
    }
    func testCompositionRepeatResetsItsClockAndAlbumKeepsAbsoluteTime() throws {
        var p = try fixture(); p.album!.compositions[0].repeatCount = 2
        let plan = try AlbumCompiler.executionPlan(p), album = try AlbumCompiler.compile(p), scene = try HierarchySceneBuilder.build(p)
        let composition = try XCTUnwrap(scene.node(.composition(p.album!.children[0]))), seconds = album.compositions[1].start+0.5
        XCTAssertEqual(try XCTUnwrap(PlaybackPosition.localSeconds(for: composition, at: seconds, plan: plan, album: album, albumID: p.album?.id)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PlaybackPosition.localSeconds(for: try XCTUnwrap(scene.node(.album)), at: seconds, plan: plan, album: album, albumID: p.album?.id), seconds)
    }
    func testFollowYieldsToManualGestureAndExplicitOffPersists() {
        XCTAssertEqual(PlaybackFollowMode.following.interrupted(playing: true), .suspended)
        XCTAssertEqual(PlaybackFollowMode.following.interrupted(playing: false), .following)
        XCTAssertEqual(PlaybackFollowMode.suspended.toggled(), .following)
        XCTAssertEqual(PlaybackFollowMode.following.toggled(), .off)
        XCTAssertEqual(PlaybackFollowMode.off.startingPlayback(), .off)
        XCTAssertEqual(PlaybackFollowMode.suspended.startingPlayback(), .following)
    }
}
