import XCTest
@testable import CirclrCore

final class MIDIPerformanceTests: XCTestCase {
    func fixture() throws -> Project {
        var p = Project(); _ = p.addTrack(name: "신스")
        _ = p.addSection(name: "벌스", at: Point(), bars: 4)
        p.sections[0].lanes[0].notes = [Note(beat: 0, length: 3, pitch: 60), Note(beat: 2, length: 1, pitch: 64)]
        p = try SectionGraphMigration.migrate(p)
        p.schemaVersion = 5
        return p
    }
    var bend: MIDIPitchBendSequence { .init(channel: 3, initialValue: 8192, events: [.init(beat: 0, kind: .value(0)), .init(beat: 1, kind: .range(.init(semitones: 12))), .init(beat: 1, kind: .value(16383)), .init(beat: 4, kind: .value(8192))]) }
    func signal(_ p: Project) throws -> SectionSignalPlan {
        let execution = try ArrangementCompiler.compile(p)
        return try XCTUnwrap(execution.occurrences.first?.signalPlan)
    }
    func testNilNotesUnchangedAndSourcesHaveIndependentStableIdentity() throws {
        var p = try fixture()
        let before = try signal(p)
        XCTAssertTrue(before.midiPerformances.isEmpty)
        p.sections[0].lanes[0].pitchBend = bend
        var node = try XCTUnwrap(p.sections[0].graph?.nodes.first { if case .midi = $0.content { return true }; return false })
        let firstID = node.id; node.id = "second-source"; p.sections[0].graph?.nodes.append(node)
        let result = try signal(p), again = try signal(p)
        let first = try XCTUnwrap(result.midiPerformances[firstID]?.first)
        let second = try XCTUnwrap(result.midiPerformances[node.id]?.first)
        XCTAssertEqual(result.midi[firstID], before.midi[firstID])
        XCTAssertEqual(first.notes, result.midi[firstID])
        XCTAssertEqual(first.sourceChannel, 3)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(result.midiPerformances, again.midiPerformances)
        XCTAssertEqual(first.pitchBendStates.map(\.seconds), [0, 0.5, 0.5, 2])
        XCTAssertEqual(first.pitchBendStates[1].state.rawValue, 0)
        XCTAssertEqual(first.pitchBendStates[2].state.rawValue, 16383)
    }
    func testLocalClockRepeatAndSectionEndClip() throws {
        var p = try fixture(); p.sections[0].lanes[0].pitchBend = bend
        let i = try XCTUnwrap(p.sections[0].graph?.nodes.firstIndex { if case .midi = $0.content { return true }; return false })
        p.sections[0].graph?.nodes[i].startBeat = 4
        p.sections[0].graph?.nodes[i].lengthBeats = 4
        p.sections[0].graph?.nodes[i].repeatCount = 2
        p.sections[0].graph?.nodes[i].settings.tempo = .local(60)
        let id = p.sections[0].graph!.nodes[i].id, result = try signal(p)
        let streams = try XCTUnwrap(result.midiPerformances[id])
        XCTAssertEqual(streams.map(\.startSeconds), [2, 6]); XCTAssertEqual(streams.map(\.endSeconds), [6, 8])
        XCTAssertEqual(streams[0].pitchBendStates.map(\.seconds), [2, 3, 3])
        XCTAssertEqual(streams[1].pitchBendStates.map(\.seconds), [6, 7, 7])
        XCTAssertEqual(streams.flatMap(\.notes), result.midi[id])
        XCTAssertEqual(Set(streams.map(\.id)).count, 2)
        XCTAssertEqual(streams[1].initialPitchBend.rawValue, 8192)
    }
    func testTempoOverrideMovesControllersAndNotesOnSameClock() throws {
        var p = try fixture(); p.sections[0].lanes[0].pitchBend = bend
        p.arrangements[0].uses[0].tempoOverride = .init(initialBPM: 120, changes: [.init(beat: 2, bpm: 60)])
        let result = try signal(p), stream = try XCTUnwrap(result.midiPerformances.values.first?.first)
        XCTAssertEqual(stream.pitchBendStates.map(\.seconds), [0, 0.5, 0.5, 3])
        XCTAssertEqual(stream.endSeconds, 15)
        XCTAssertEqual(stream.notes, result.midi[stream.sourceNodeID])
    }
    func testSharedNestedRepeatsPreserveSwingAndOverlappingNotes() throws {
        var p = try fixture()
        var pattern = RhythmPattern(name: "공유", trackID: p.tracks[0].id)
        pattern.length = 4; pattern.notes = [Note(beat: 0.25, length: 5, pitch: 60)]
        pattern.pitchBend = bend; p.patterns = [pattern]; p.global.rhythm = RhythmAssignment(pattern.id)
        // Re-migrate to add the shared source, retaining the expression storage.
        p.sections[0].graph = nil; p = try SectionGraphMigration.migrate(p)
        let i = try XCTUnwrap(p.sections[0].graph?.nodes.firstIndex { if case .rhythmMIDI = $0.content { return true }; return false })
        p.sections[0].graph?.nodes[i].lengthBeats = 8; p.sections[0].graph?.nodes[i].repeatCount = 2
        p.global.beatGrid.swing = 0.5
        let result = try signal(p), id = p.sections[0].graph!.nodes[i].id
        let streams = try XCTUnwrap(result.midiPerformances[id])
        XCTAssertEqual(streams.count, 4)
        XCTAssertEqual(Set(streams.map(\.id)).count, 4)
        XCTAssertEqual(streams.flatMap(\.notes), result.midi[id])
        XCTAssertGreaterThan(streams[0].notes[0].beat + streams[0].notes[0].length, 4)
        XCTAssertEqual(streams[0].pitchBendStates.map(\.seconds), [0, 0.5, 0.5])
        XCTAssertEqual(streams[1].initialPitchBend.rawValue, 8192)
        XCTAssertThrowsError(try SectionGraphCompiler.expandedPattern(pattern, length: 16, grid: p.global.beatGrid))
    }
    func testMutedNoStreamsInvalidAndBudgetRejected() throws {
        var p = try fixture(); p.sections[0].lanes[0].pitchBend = bend
        let i = try XCTUnwrap(p.sections[0].graph?.nodes.firstIndex { if case .midi = $0.content { return true }; return false })
        p.sections[0].graph?.nodes[i].muted = true
        XCTAssertEqual(try signal(p).midiPerformances.values.flatMap { $0 }.count, 0)
        p.sections[0].lanes[0].pitchBend?.initialValue = -1
        XCTAssertThrowsError(try signal(p))
        p.sections[0].graph?.nodes[i].muted = false
        p.sections[0].lanes[0].pitchBend = .init(events: Array(repeating: .init(beat: 0, kind: .value(8192)), count: 100000))
        p.sections[0].graph?.nodes[i].lengthBeats = 1; p.sections[0].graph?.nodes[i].repeatCount = 16
        XCTAssertThrowsError(try signal(p))
    }
    func testLegacyCannotSilentlyDropExpression() throws {
        var p = try fixture(); p.sections[0].graph = nil; p.sections[0].lanes[0].pitchBend = bend
        XCTAssertThrowsError(try ArrangementCompiler.compile(p))
    }
}
