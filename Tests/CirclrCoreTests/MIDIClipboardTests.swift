import XCTest
@testable import CirclrCore

final class MIDIClipboardTests: XCTestCase {
    func testPortablePhrasePreservesRelativeRhythmPitchLengthVelocityAndFreshIDs() throws {
        let source = [Note(beat: 2, length: 0.25, pitch: 36, velocity: 110), Note(beat: 2.75, length: 0.5, pitch: 42, velocity: 71)]
        let phrase = try MIDIClipboard.decode(MIDIClipboard(notes: source).encoded())
        let lane = Lane(trackID: "target")
        let pasted = try phrase.pasting(into: lane, at: 4, beats: 8)
        XCTAssertEqual(pasted.notes.map(\.beat), [4, 4.75])
        XCTAssertEqual(pasted.notes.map(\.length), source.map(\.length))
        XCTAssertEqual(pasted.notes.map(\.pitch), [36, 42]); XCTAssertEqual(pasted.notes.map(\.velocity), [110, 71])
        XCTAssertTrue(Set(source.map(\.id)).isDisjoint(with: pasted.notes.map(\.id)))
        let another = try phrase.pasting(into: lane, at: phrase.sourceStartBeat, beats: 8)
        XCTAssertEqual(another.notes.map(\.beat), [2, 2.75])
        XCTAssertTrue(Set(another.notes.map(\.id)).isDisjoint(with: pasted.notes.map(\.id)))
        let encoded = String(decoding: try phrase.encoded(), as: UTF8.self)
        for note in source { XCTAssertFalse(encoded.contains(note.id)) }
    }
    func testBoundaryOverflowRejectsWholePhraseWithoutCropping() throws {
        let phrase = try MIDIClipboard(notes: [Note(beat: 2, length: 1, pitch: 60), Note(beat: 3, length: 1, pitch: 64)])
        var lane = Lane(trackID: "target"); lane.notes = [Note(beat: 0, pitch: 30)]
        XCTAssertThrowsError(try phrase.pasting(into: lane, at: 3, beats: 4))
        XCTAssertThrowsError(try phrase.pasting(into: lane, at: -.infinity, beats: 4))
        XCTAssertEqual(lane.notes.count, 1)
        XCTAssertEqual(try phrase.pasting(into: lane, at: 2, beats: 4).notes.count, 3)
    }
    func testMalformedVersionNumericRangesAndResourceCapsRejected() throws {
        let valid: [String: Any] = ["version": 1, "sourceStartBeat": 0,
            "notes": [["relativeBeat": 0, "length": 1, "pitch": 60, "velocity": 90]]]
        for (field, bad) in [("version", 2), ("sourceStartBeat", -1)] {
            var object = valid; object[field] = bad
            XCTAssertThrowsError(try MIDIClipboard.decode(JSONSerialization.data(withJSONObject: object)))
        }
        for (field, bad) in [("relativeBeat", -1), ("length", 0), ("pitch", 128), ("velocity", 0)] {
            var entry = (valid["notes"] as! [[String: Int]])[0]; entry[field] = bad
            var object = valid; object["notes"] = [entry]
            XCTAssertThrowsError(try MIDIClipboard.decode(JSONSerialization.data(withJSONObject: object)))
        }
        XCTAssertThrowsError(try MIDIClipboard.decode(Data(repeating: 32, count: MIDIClipboard.maximumBytes + 1)))
        XCTAssertThrowsError(try MIDIClipboard(notes: Array(repeating: Note(beat: 0, pitch: 60), count: MIDIClipboard.maximumNotes + 1)))
        XCTAssertThrowsError(try MIDIClipboard(notes: []))
    }
}
