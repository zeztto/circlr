import XCTest
@testable import CirclrCore

final class MIDISustainStorageTests: XCTestCase {
    func fixture() throws -> Project { try HierarchyEditingTests().fixture() }
    var sequence: MIDISustainSequence { .init(channel: 3, events: [.init(beat: 0, rawValue: 127), .init(beat: 2, rawValue: 0)]) }

    func testLegacyNilCompatibilityAndNoPromotion() throws {
        let lane = try JSONDecoder().decode(Lane.self, from: Data(#"{"id":"lane","trackID":"track","notes":[],"audio":[]}"#.utf8))
        let pattern = try JSONDecoder().decode(RhythmPattern.self, from: Data(#"{"id":"pattern","name":"old","length":4,"meter":{"numerator":4,"denominator":4},"trackID":"track","notes":[],"audio":[]}"#.utf8))
        XCTAssertNil(lane.sustain); XCTAssertNil(pattern.sustain)
        for data in [try JSONEncoder().encode(lane), try JSONEncoder().encode(pattern)] {
            XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])["sustain"])
        }
        var p = try fixture(); let before = p
        try MIDISustainStorage.promote(in: &p); XCTAssertEqual(p, before)
    }

    func testUseOverrideAtomicPromotionAndHistoryRestoration() throws {
        var p = try fixture(); _ = try ProjectEditing.reuse(p.active.uses[0].id, in: &p, at: Point())
        let before = p, use = p.active.uses[0].id
        var lane = p.sections[0].lanes[0]; lane.sustain = sequence
        try ProjectEditing.setLane(lane, for: use, original: false, in: &p)
        XCTAssertEqual(p.schemaVersion, 7); XCTAssertEqual(p.sections, before.sections)
        XCTAssertEqual(p.active.uses[1], before.active.uses[1])
        XCTAssertEqual(p.active.uses[0].laneOverrides[lane.id]?.sustain, sequence)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p)), p)
        let restored = try CircleHistory.restore(before, layoutOnly: false, current: p)
        XCTAssertEqual(restored.schemaVersion, before.schemaVersion)
        XCTAssertNil(restored.active.uses[0].laneOverrides[lane.id])
        lane.sustain = nil; try ProjectEditing.setLane(lane, for: use, original: false, in: &p)
        XCTAssertEqual(p.schemaVersion, 7)
    }

    func testOriginalCopyDetachAndNoteEditingPreserveSustain() throws {
        var p = try fixture(); var lane = p.sections[0].lanes[0]; lane.sustain = sequence
        try ProjectEditing.setLane(lane, for: p.active.uses[0].id, original: true, in: &p)
        let edited = try MIDIEditing.apply(.transpose(1), to: lane, ids: Set(lane.notes.map(\.id)), beats: 8)
        XCTAssertEqual(edited.sustain, sequence)
        ProjectEditing.duplicateArrangement(in: &p, name: "대안")
        try ProjectEditing.detach(p.active.uses[0].id, in: &p)
        XCTAssertEqual(p.sections.last?.lanes.first { $0.id == lane.id }?.sustain, sequence)
        XCTAssertEqual(try SectionGraphMigration.migrate(p).schemaVersion, 7)
    }

    func testAllStoredScopesAndInactiveArrangementsValidateAtomically() throws {
        let base = try fixture()
        for scope in ["source", "override", "added", "pattern", "take", "inactive"] {
            var p = base, lane = p.sections[0].lanes[0]
            lane.sustain = sequence; lane.pitchBend = .init(channel: 4)
            switch scope {
            case "source": p.sections[0].lanes[0] = lane
            case "override": p.arrangements[0].uses[0].laneOverrides[lane.id] = lane
            case "added": lane.id = newID(); p.arrangements[0].uses[0].addedLanes.append(lane)
            case "pattern":
                var pattern = RhythmPattern(name: "공유", trackID: lane.trackID)
                pattern.sustain = lane.sustain; pattern.pitchBend = lane.pitchBend; p.patterns = [pattern]
            case "inactive":
                var other = p.active; other.id = newID(); other.uses[0].laneOverrides[lane.id] = lane; p.arrangements.append(other)
            default: p.takes = [RecordedTake(useID: p.active.uses[0].id, name: "녹음", lane: lane)]
            }
            let before = p
            XCTAssertThrowsError(try MIDISustainStorage.promote(in: &p), scope); XCTAssertEqual(p, before)
            p.schemaVersion = 7; XCTAssertThrowsError(try ProjectStore.validateStructure(p), scope)
        }
        var p = base, lane = p.sections[0].lanes[0]
        lane.sustain = .init(events: [.init(beat: 1, rawValue: 128)])
        XCTAssertThrowsError(try ProjectEditing.setLane(lane, for: p.active.uses[0].id, original: false, in: &p))
        XCTAssertEqual(p, base)
    }

    func testSharedPatternStorageAndChannelPair() throws {
        var p = try fixture(), pattern = RhythmPattern(name: "공유", trackID: "unused")
        pattern.trackID = p.tracks[0].id; pattern.notes = p.sections[0].lanes[0].notes
        pattern.sustain = sequence; pattern.pitchBend = .init(channel: 3); p.patterns = [pattern]
        XCTAssertThrowsError(try MIDISustainStorage.validate(in: p))
        try MIDISustainStorage.promote(in: &p)
        XCTAssertEqual(p.schemaVersion, 7); try ProjectStore.validateStructure(p)
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.patterns[0], pattern)
        p.patterns[0].sustain = nil; try MIDISustainStorage.promote(in: &p)
        XCTAssertEqual(p.schemaVersion, 7)
    }

    func testMIDITakeReplacesIncludingNilAndAudioOnlyKeepsExpression() throws {
        var p = try fixture(); let source = p.sections[0].lanes[0], use = p.active.uses[0].id
        var take = RecordedTake(useID: use, name: "MIDI", lane: source)
        take.targetLaneID = source.id; take.arrangementID = p.activeArrangementID; take.lane.sustain = sequence
        try ProjectEditing.activateTake(take, in: &p)
        XCTAssertEqual(p.active.uses[0].laneOverrides[source.id]?.sustain, sequence)
        let asset = Asset(name: "녹음", path: "take.wav", duration: 2, sampleRate: 48000); p.assets.append(asset)
        var audioOnly = take; audioOnly.lane.notes = []; audioOnly.lane.sustain = nil
        audioOnly.lane.audio = [AudioClip(assetID: asset.id, duration: 1)]
        try ProjectEditing.activateTake(audioOnly, in: &p)
        XCTAssertEqual(p.active.uses[0].laneOverrides[source.id]?.sustain, sequence)
        XCTAssertEqual(p.active.uses[0].laneOverrides[source.id]?.audio, audioOnly.lane.audio)
        take.lane.sustain = nil; try ProjectEditing.activateTake(take, in: &p)
        XCTAssertNil(p.active.uses[0].laneOverrides[source.id]?.sustain)
        XCTAssertNil(p.sections[0].lanes[0].sustain); XCTAssertEqual(p.schemaVersion, 7)
    }
}
