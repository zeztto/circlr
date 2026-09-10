import XCTest
@testable import CirclrCore

final class MIDIPitchBendExportTests:XCTestCase {
    func testLegacySourceExportMatchesExistingNotesBytes()throws {
        var lane=Lane(trackID:"track");lane.notes=[.init(beat:0,length:1,pitch:60)]
        XCTAssertEqual(try MIDIFile.encode(sources:[("연주",lane)],tempo:120,meter:Meter()),
                       try MIDIFile.encode(lanes:[("연주",lane.notes)],tempo:120,meter:Meter()))
    }
    func testAnyExpressionInActualTargetsRejectsIncludingCenterSeed()throws {
        var ordinary=Lane(trackID:"plain");ordinary.notes=[.init(beat:0,length:1,pitch:60)]
        for sequence in [MIDIPitchBendSequence(),.init(initialValue:0),.init(events:[.init(beat:1,kind:.range(.init(semitones:12)))])] {
            var expressive=Lane(trackID:"bend");expressive.notes=ordinary.notes;expressive.pitchBend=sequence
            let before=expressive
            XCTAssertThrowsError(try MIDIFile.encode(sources:[("원본",ordinary),("표현",expressive)],tempo:120,meter:Meter())) {error in
                XCTAssertTrue(error.localizedDescription.contains("피치 벤드"))
            }
            XCTAssertEqual(expressive,before)
            // Unselected expression must not block a plain source's export.
            XCTAssertNoThrow(try MIDIFile.encode(sources:[("원본",ordinary)],tempo:120,meter:Meter()))
        }
    }
    func testSharedPatternSourceCannotLoseExpressionDuringExport()throws {
        var pattern=RhythmPattern(name:"공유",trackID:"track");pattern.pitchBend = .init(initialValue:0)
        var source=Lane(trackID:pattern.trackID);source.notes=pattern.notes;source.audio=pattern.audio;source.pitchBend=pattern.pitchBend
        XCTAssertThrowsError(try MIDIFile.encode(sources:[(pattern.name,source)],tempo:120,meter:Meter()))
    }
}
