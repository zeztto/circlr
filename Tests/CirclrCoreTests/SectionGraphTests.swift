import XCTest
@testable import CirclrCore

final class SectionGraphTests: XCTestCase {
    func song() throws -> Project {
        var p = Project(); _ = p.addTrack(name: "피아노")
        let id = p.addSection(name: "벌스", at: Point(), bars: 4)
        var lane = p.sections[0].lanes[0]
        lane.notes = [Note(beat: 0, length: 1, pitch: 60), Note(beat: 2, length: 1, pitch: 67)]
        try ProjectEditing.setLane(lane, for: id, original: true, in: &p)
        return p
    }
    func graph(_ p: Project) throws -> SectionGraph { try XCTUnwrap(SectionGraphEditing.effective(section: p.sections[0], use: p.active.uses[0])) }

    func testMigrationReferencesOriginalDataAndPreservesVariantsAndPerTrackEffects() throws {
        var legacy = try song()
        _ = legacy.addTrack(name: "기타")
        legacy.arrangements[0].uses[0].effects = [Effect(.drive, amount: 0.8), Effect(.lowpass, amount: 0.6)]
        var changed = legacy.sections[0].lanes[0]; changed.notes[0].pitch = 72
        try ProjectEditing.setLane(changed, for: legacy.active.uses[0].id, original: false, in: &legacy)
        let p = try SectionGraphMigration.migrate(legacy), plan = try ArrangementCompiler.compile(p)
        XCTAssertEqual(p.sections[0].lanes, legacy.sections[0].lanes)
        XCTAssertEqual(p.active.uses[0].laneOverrides, legacy.active.uses[0].laneOverrides)
        XCTAssertTrue(p.active.uses[0].effects.isEmpty)
        let signal = try XCTUnwrap(plan.occurrences[0].signalPlan)
        XCTAssertEqual(signal.orderedNodes.filter { if case .effect = $0.content { return true }; return false }.count, 4)
        XCTAssertEqual(signal.midi["midi:\(changed.id)"]?.first?.pitch, 72)
        XCTAssertEqual(signal.midi["midi:\(changed.id)"]?.count, 2)
        XCTAssertEqual(try SectionGraphMigration.migrate(p), p)
        XCTAssertEqual(plan.duration, try ArrangementCompiler.compile(legacy).duration)
    }

    func testMIDIToAudioAndCycleConnectionsFailWithoutMutation() throws {
        let p = try SectionGraphMigration.migrate(song()); var g = try graph(p)
        let midi = try XCTUnwrap(g.nodes.first { if case .midi = $0.content { return true }; return false })
        let mix = try XCTUnwrap(g.nodes.first { $0.content == .mix })
        let before = g
        XCTAssertThrowsError(try SectionGraphEditing.connect(from: midi.id, to: mix.id, in: &g))
        XCTAssertEqual(g, before)
        let effect = MusicCircle(name: "효과", content: .effect(Effect(.delay)))
        g.nodes.append(effect)
        try SectionGraphEditing.connect(from: mix.id, to: effect.id, in: &g)
        let acyclic = g
        XCTAssertThrowsError(try SectionGraphEditing.connect(from: effect.id, to: mix.id, in: &g))
        XCTAssertEqual(g, acyclic)
        XCTAssertThrowsError(try SectionGraphEditing.connect(from: mix.id, to: effect.id, sidechain: true, in: &g))
    }

    func testLocalTempoRepeatStartAndSectionBoundaryBecomeParentEvents() throws {
        var p = try SectionGraphMigration.migrate(song()); var g = try graph(p)
        let i = try XCTUnwrap(g.nodes.firstIndex { if case .midi = $0.content { return true }; return false })
        g.nodes[i].startBeat = 4; g.nodes[i].lengthBeats = 4; g.nodes[i].repeatCount = 2
        g.nodes[i].settings.tempo = .local(60); g.nodes[i].settings.scale = .local(Scale(root: 7))
        try SectionGraphEditing.set(g, useID: p.active.uses[0].id, original: false, in: &p)
        let occurrence = try ArrangementCompiler.compile(p).occurrences[0]
        let signal = try XCTUnwrap(occurrence.signalPlan)
        let notes = try XCTUnwrap(signal.midi[g.nodes[i].id])
        // Parent 120 BPM: 4 quarters = 2 seconds. The 60 BPM phrase repeats after 4 seconds.
        XCTAssertEqual(notes.map(\.beat), [4, 8, 12])
        XCTAssertEqual(notes.map(\.length), [2, 2, 2])
        XCTAssertEqual(notes.map(\.pitch), [60, 67, 60])
        XCTAssertEqual(p.sections[0].lanes[0].notes.count, 2)
        XCTAssertEqual(signal.contexts[g.nodes[i].id]?.scale.root, 7)
    }

    func testInheritedTempoMapAndGlobalOverrideHaveDistinctTiming() throws {
        var p = try SectionGraphMigration.migrate(song())
        p.sections[0].tempoChanges = [TempoChange(beat: 4, bpm: 60)]
        var g = try graph(p)
        let i = try XCTUnwrap(g.nodes.firstIndex { if case .midi = $0.content { return true }; return false })
        g.nodes[i].startBeat = 4; g.nodes[i].lengthBeats = 4
        try SectionGraphEditing.set(g, useID: p.active.uses[0].id, original: false, in: &p)
        let inherited = try ArrangementCompiler.compile(p).occurrences[0]
        XCTAssertEqual(inherited.signalPlan?.midi[g.nodes[i].id]?.map(\.beat), [4, 6])
        g.nodes[i].settings.tempo = Setting(source: .global)
        try SectionGraphEditing.set(g, useID: p.active.uses[0].id, original: false, in: &p)
        let global = try ArrangementCompiler.compile(p).occurrences[0]
        XCTAssertEqual(global.signalPlan?.midi[g.nodes[i].id]?.map(\.beat), [4, 5])
        XCTAssertEqual(global.signalPlan?.midi[g.nodes[i].id]?.first?.length, 0.5)
    }

    func testSharedOriginalUnrelatedChangePropagatesAndDetachPreservesGraph() throws {
        var p = try SectionGraphMigration.migrate(song()); let first = p.active.uses[0].id
        let second = try ProjectEditing.reuse(first, in: &p, at: Point(300, 0))
        var g = try graph(p); g.nodes[0].name = "이번 악기"
        try SectionGraphEditing.set(g, useID: first, original: false, in: &p)
        p.sections[0].graph?.nodes[1].name = "공유 믹스 변경"
        XCTAssertEqual(try graph(p).nodes[0].name, "이번 악기")
        XCTAssertEqual(try graph(p).nodes[1].name, "공유 믹스 변경")
        XCTAssertNotEqual(try SectionGraphEditing.effective(section: p.sections[0], use: p.active.uses[1])?.nodes[0].name, "이번 악기")
        let effective = try graph(p)
        try ProjectEditing.detach(first, in: &p)
        let detached = try XCTUnwrap(p.sections.first { $0.id == p.active.uses[0].sectionID })
        XCTAssertEqual(detached.graph, effective)
        XCTAssertNil(p.active.uses[0].graphEdits)
        XCTAssertEqual(p.active.uses[1].id, second)
        try ProjectStore.validateStructure(p)
    }

    func testOrphanDataAndSharedGraphConflictsAreRejectedAtomically() throws {
        var p = try SectionGraphMigration.migrate(song())
        var g = try graph(p); g.nodes[0].name = "사용별 수정"
        try SectionGraphEditing.set(g, useID: p.active.uses[0].id, original: false, in: &p)
        var original = try XCTUnwrap(p.sections[0].graph)
        SectionGraphEditing.remove([g.nodes[0].id], from: &original)
        let before = p
        XCTAssertThrowsError(try SectionGraphEditing.set(original, useID: p.active.uses[0].id, original: true, in: &p))
        XCTAssertEqual(p, before)
        p.sections[0].lanes = []
        XCTAssertThrowsError(try ArrangementCompiler.compile(p))
    }

    func testRhythmUsesOneMIDIStreamAndMuteStopsIt() throws {
        var p = try song()
        var pattern = RhythmPattern(name: "리듬", trackID: p.tracks[0].id)
        pattern.notes = [Note(beat: 0, pitch: 36)]; pattern.length = 4
        p.patterns = [pattern]; p.global.rhythm = RhythmAssignment(pattern.id)
        p = try SectionGraphMigration.migrate(p)
        let first = try XCTUnwrap(ArrangementCompiler.compile(p).occurrences[0].signalPlan)
        let id = "rhythm-midi:\(p.tracks[0].id)"
        XCTAssertEqual(first.midi[id]?.map(\.beat), [0, 4, 8, 12])
        XCTAssertEqual(first.eventCount, 6)
        var g = try graph(p)
        let i = try XCTUnwrap(g.nodes.firstIndex { $0.id == id }); g.nodes[i].muted = true
        try SectionGraphEditing.set(g, useID: p.active.uses[0].id, original: false, in: &p)
        XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences[0].signalPlan?.midi[id]?.count, 0)
    }

    func testGraphAndAlbumPackageRoundTripRetainsRoutingAndContent() throws {
        var p = try SectionGraphMigration.migrate(song()); p.enableAlbum()
        var g = try graph(p)
        let effect = MusicCircle(name: "Delay", content: .effect(Effect(.delay, amount: 0.4)))
        g.nodes.append(effect)
        g.layout.positions[effect.id] = Point(410, 140)
        let mix = try XCTUnwrap(g.nodes.first { $0.content == .mix })
        let output = try XCTUnwrap(g.nodes.first { if case .output = $0.content { return true }; return false })
        g.edges.removeAll { $0.from == mix.id && $0.to == output.id }
        try SectionGraphEditing.connect(from: mix.id, to: effect.id, in: &g)
        try SectionGraphEditing.connect(from: effect.id, to: output.id, in: &g)
        try SectionGraphEditing.set(g, useID: p.active.uses[0].id, original: false, in: &p)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-graph-\(newID()).circlr")
        defer { try? FileManager.default.removeItem(at: path) }
        let saved = try ProjectStore.save(p, to: path, mediaRoot: nil)
        XCTAssertEqual(try ProjectStore.load(path).project, saved)
        XCTAssertEqual(try AlbumCompiler.compile(saved).compositions.first?.plan.occurrences.first?.signalPlan?.graph, g)
    }
    func testLaneEditingSynchronizesNewAndDeletedAudioWithoutRestoringDisconnectedRoutes() throws {
        var p = try SectionGraphMigration.migrate(song())
        let use = p.active.uses[0].id
        var g = try graph(p), lane = p.sections[0].lanes[0]
        let midi = "midi:\(lane.id)"
        g.edges.removeAll { $0.from == midi }
        try SectionGraphEditing.set(g, useID: use, original: false, in: &p)
        let asset = Asset(name: "recording", path: "/tmp/circlr-synchronization.wav", duration: 2, sampleRate: 48000)
        p.assets.append(asset)
        let clip = AudioClip(assetID: asset.id, duration: 1)
        lane.audio = [clip]
        try ProjectEditing.setLane(lane, for: use, original: false, in: &p)
        let imported = try graph(p)
        XCTAssertTrue(imported.nodes.contains { $0.content == .audio(laneID: lane.id, clipID: clip.id) })
        XCTAssertEqual(imported.edges.filter { $0.from == "audio:\(clip.id)" }.count, 1)
        XCTAssertFalse(imported.edges.contains { $0.from == midi })
        XCTAssertTrue(p.sections[0].lanes[0].audio.isEmpty)
        lane.audio = []
        try ProjectEditing.setLane(lane, for: use, original: false, in: &p)
        XCTAssertFalse(try graph(p).nodes.contains { $0.id == "audio:\(clip.id)" })
        XCTAssertFalse(try graph(p).edges.contains { $0.from == "audio:\(clip.id)" })
    }

    func testNoteEditDoesNotRecreateDeletedProcessingOrSourceCircles() throws {
        var p = try SectionGraphMigration.migrate(song())
        var g = try graph(p), lane = p.sections[0].lanes[0]
        let use = p.active.uses[0].id
        let removed = Set(g.nodes.filter { if case .instrument = $0.content { return true }; if case .rhythmMIDI = $0.content { return true }; return false }.map(\.id))
        SectionGraphEditing.remove(removed, from: &g)
        try SectionGraphEditing.set(g, useID: use, original: false, in: &p)
        lane.notes.append(Note(beat: 3, pitch: 69))
        try ProjectEditing.setLane(lane, for: use, original: false, in: &p)
        XCTAssertEqual(try graph(p), g)
        XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences[0].lanes[0].notes.count, 3)
    }

    func testNewMIDITrackBuildsOnePlayableSignalPathAndRejectsInvalidLaneAtomically() throws {
        var p = try SectionGraphMigration.migrate(song())
        let use = p.active.uses[0].id
        let track = p.addTrack(name: "새 악기")
        var lane = Lane(trackID: track); lane.notes = [Note(beat: 1, pitch: 65)]
        try ProjectEditing.setLane(lane, for: use, original: false, in: &p)
        let g = try graph(p)
        XCTAssertEqual(g.edges.filter { $0.from == "midi:\(lane.id)" }.map(\.to), ["instrument:\(track)"])
        XCTAssertEqual(g.edges.filter { $0.from == "instrument:\(track)" }.count, 1)
        let before = p
        lane.trackID = "missing-track"
        XCTAssertThrowsError(try ProjectEditing.setLane(lane, for: use, original: false, in: &p))
        XCTAssertEqual(p, before)
    }

}
