import XCTest
@testable import CirclrCore

final class MIDINoteDragTests:XCTestCase {
    func fixture()->Lane {
        var lane=Lane(trackID:"keys")
        lane.notes=[Note(beat:0.13,length:0.6,pitch:60,velocity:91),Note(beat:0.38,length:0.2,pitch:64,velocity:87),Note(beat:3,length:1,pitch:67)]
        lane.audio=[AudioClip(assetID:"tone",duration:1)];return lane
    }
    func gesture(_ lane:Lane,ids:Set<ID>?=nil)throws->MIDINoteDrag {
        try MIDINoteDrag(lane:lane,ids:ids ?? Set(lane.notes.prefix(2).map(\.id)),beats:4,subdivisions:4)
    }
    func testMoveSnapsDeltaPreservesGrooveIntervalsAndUntouchedData()throws {
        let lane=fixture(),drag=try gesture(lane)
        XCTAssertEqual(drag.moving(beatDelta:0,pitchDelta:0),lane)
        XCTAssertEqual(drag.moving(beatDelta:0.04,pitchDelta:0),lane)
        let moved=drag.moving(beatDelta:0.3,pitchDelta:2)
        XCTAssertEqual(moved.notes[0].beat,0.38,accuracy:1e-9);XCTAssertEqual(moved.notes[1].beat,0.63,accuracy:1e-9)
        XCTAssertEqual(moved.notes.map(\.pitch),[62,66,67])
        XCTAssertEqual(moved.notes.map(\.id),lane.notes.map(\.id));XCTAssertEqual(moved.notes.map(\.velocity),lane.notes.map(\.velocity))
        XCTAssertEqual(moved.notes.map(\.length),lane.notes.map(\.length));XCTAssertEqual(moved.notes[2],lane.notes[2]);XCTAssertEqual(moved.audio,lane.audio)
        // A new pointer position derives from the original, not the previous preview.
        XCTAssertEqual(drag.moving(beatDelta:0,pitchDelta:0),lane)
    }
    func testWholeSelectionClampsAtTimeAndPitchEdgesWithoutFlattening()throws {
        let lane=fixture(),drag=try gesture(lane)
        let start=drag.moving(beatDelta:-10,pitchDelta:Int.min)
        XCTAssertEqual(start.notes[0].beat,0,accuracy:1e-9);XCTAssertEqual(start.notes[1].beat,0.25,accuracy:1e-9)
        XCTAssertEqual(start.notes.map(\.pitch),[0,4,67])
        let end=drag.moving(beatDelta:Double.greatestFiniteMagnitude,pitchDelta:Int.max)
        XCTAssertEqual(end.notes[0].beat+end.notes[0].length,4,accuracy:1e-9)
        XCTAssertEqual(end.notes[1].beat-end.notes[0].beat,0.25,accuracy:1e-9)
        XCTAssertEqual(end.notes.map(\.pitch),[123,127,67])
        XCTAssertEqual(end.notes[2],lane.notes[2])
    }
    func testCommonResizeKeepsLengthDifferencesAndShortNotesUntilChanged()throws {
        let lane=fixture(),drag=try gesture(lane)
        XCTAssertEqual(drag.resizing(lengthDelta:0),lane)
        XCTAssertEqual(drag.resizing(lengthDelta:-2),lane) // The existing short note is the common lower limit.
        let longer=drag.resizing(lengthDelta:0.51)
        XCTAssertEqual(longer.notes[0].length,1.1,accuracy:1e-9);XCTAssertEqual(longer.notes[1].length,0.7,accuracy:1e-9)
        XCTAssertEqual(longer.notes.map(\.beat),lane.notes.map(\.beat));XCTAssertEqual(longer.notes.map(\.pitch),lane.notes.map(\.pitch))
        let shorter=try gesture(longer).resizing(lengthDelta:-10)
        XCTAssertEqual(shorter.notes[0].length,0.65,accuracy:1e-9);XCTAssertEqual(shorter.notes[1].length,0.25,accuracy:1e-9)
        let end=drag.resizing(lengthDelta:100)
        XCTAssertEqual(end.notes[0].beat+end.notes[0].length,4,accuracy:1e-9)
        XCTAssertEqual(end.notes[0].length-end.notes[1].length,0.4,accuracy:1e-9)
        XCTAssertEqual(end.notes[2],lane.notes[2]);XCTAssertEqual(end.audio,lane.audio)
    }
    func testExistingTailIsNotCroppedOrExtendedByGesture()throws {
        var lane=fixture();lane.notes[1]=Note(beat:3,length:2,pitch:64)
        let drag=try gesture(lane)
        XCTAssertEqual(drag.moving(beatDelta:1,pitchDelta:0),lane)
        XCTAssertEqual(drag.resizing(lengthDelta:1),lane)
        let moved=drag.moving(beatDelta:-0.1,pitchDelta:2)
        XCTAssertEqual(moved.notes.map(\.beat),lane.notes.map(\.beat));XCTAssertEqual(moved.notes[1].length,2)
        let shorter=drag.resizing(lengthDelta:-0.25)
        XCTAssertEqual(shorter.notes[1].length,1.75);XCTAssertEqual(shorter.notes[0].length,0.35,accuracy:1e-9)
    }
    func testInvalidGestureIsRejectedAndNonfiniteMotionIsANoop()throws {
        let lane=fixture(),drag=try gesture(lane)
        for delta in [Double.nan,.infinity,-.infinity] {
            XCTAssertEqual(drag.moving(beatDelta:delta,pitchDelta:2),lane)
            XCTAssertEqual(drag.resizing(lengthDelta:delta),lane)
        }
        XCTAssertThrowsError(try gesture(lane,ids:[]));XCTAssertThrowsError(try gesture(lane,ids:["missing"]))
        for beats in [0,-1,Double.nan,.infinity] {XCTAssertThrowsError(try MIDINoteDrag(lane:lane,ids:drag.ids,beats:beats,subdivisions:4))}
        for grid in [0,65] {XCTAssertThrowsError(try MIDINoteDrag(lane:lane,ids:drag.ids,beats:4,subdivisions:grid))}
        var invalid=lane;invalid.notes[1].id=invalid.notes[0].id
        XCTAssertThrowsError(try gesture(invalid))
    }
}
