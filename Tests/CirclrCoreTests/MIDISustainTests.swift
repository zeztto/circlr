import XCTest
@testable import CirclrCore

final class MIDISustainTests: XCTestCase {
    func testThresholdAndRawValuesArePreserved() throws {
        for value in [0, 1, 63, 64, 100, 127] {
            let state = try MIDISustainSequence(initialValue: value).state(atBeat: 0)
            XCTAssertEqual(state.rawValue, value)
            XCTAssertEqual(state.isDown, value >= 64)
        }
    }

    func testInitialSeedAndOrderedSameBeatRoundTripWithoutMutation() throws {
        let sequence = MIDISustainSequence(channel: 15, initialValue: 100, events: [
            .init(beat: 1, rawValue: 127), .init(beat: 1, rawValue: 0),
            .init(beat: 1, rawValue: 64), .init(beat: 2, rawValue: 63)
        ])
        let before = sequence
        XCTAssertEqual(try sequence.state(atBeat: 0).rawValue, 100)
        XCTAssertEqual(try sequence.state(atBeat: 1).rawValue, 64)
        XCTAssertFalse(try sequence.state(atBeat: 131072).isDown)
        let decoded = try JSONDecoder().decode(MIDISustainSequence.self, from: JSONEncoder().encode(sequence))
        XCTAssertEqual(decoded, sequence)
        XCTAssertEqual(decoded.events.map(\.rawValue), [127, 0, 64, 63])
        XCTAssertEqual(sequence, before)
        XCTAssertEqual(try MIDISustainSequence(initialValue: 127).state(atBeat: 131072).rawValue, 127)
    }

    func testInvalidSourceAndQueryBounds() throws {
        for beat in [-1, Double.nan, Double.infinity, -Double.infinity, 131073] {
            XCTAssertThrowsError(try MIDISustainSequence().state(atBeat: beat))
            XCTAssertThrowsError(try MIDISustainEvent(beat: beat, rawValue: 0).validate())
        }
        for value in [-1, 128] {
            XCTAssertThrowsError(try MIDISustainSequence(initialValue: value).validate())
            XCTAssertThrowsError(try MIDISustainEvent(beat: 0, rawValue: value).validate())
        }
        for channel in [-1, 16] { XCTAssertThrowsError(try MIDISustainSequence(channel: channel).validate()) }
        try MIDISustainEvent(beat: 131072, rawValue: 127).validate()
        XCTAssertThrowsError(try MIDISustainSequence(events: [.init(beat: 2, rawValue: 0), .init(beat: 1, rawValue: 127)]).validate())
    }

    func testEarlyQueryValidatesEntireSource() {
        for bad in [MIDISustainEvent(beat: 10, rawValue: 128), .init(beat: .nan, rawValue: 0)] {
            let sequence = MIDISustainSequence(events: [.init(beat: 0, rawValue: 64), bad])
            XCTAssertThrowsError(try sequence.state(atBeat: 0))
        }
    }

    func testEventBudgetIncludesEqualBeatEvents() throws {
        var sequence = MIDISustainSequence(events: Array(repeating: .init(beat: 0, rawValue: 64), count: 100000))
        XCTAssertTrue(try sequence.state(atBeat: 0).isDown)
        sequence.events.append(.init(beat: 0, rawValue: 0))
        XCTAssertThrowsError(try sequence.validate())
        XCTAssertThrowsError(try sequence.state(atBeat: 0))
    }

    func testFoundationDoesNotChangeProjectSchemaOrEncoding() throws {
        let project = Project()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(project)
        let sequence = MIDISustainSequence(events: [.init(beat: 0, rawValue: 127)])
        _ = try sequence.state(atBeat: 0)
        XCTAssertEqual(project.schemaVersion, 1)
        XCTAssertEqual(try encoder.encode(project), before)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        XCTAssertNil(object["sustain"])
    }
}
