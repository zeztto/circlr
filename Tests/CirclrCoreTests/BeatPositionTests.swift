import XCTest
@testable import CirclrCore

final class BeatPositionTests:XCTestCase {
    func testPositionInputStoresZeroBasedBeatAndKeepsDuration()throws {
        let note=Note(beat:8.5,length:0.75,pitch:60,velocity:96)
        var position=NumberEditSession<Int>(presentation:.beatPosition)
        position.begin(value:note.beat,context:1)
        XCTAssertEqual(position.text,"9.5")
        position.text="12.25"
        let changed=try XCTUnwrap(position.resolve(value:note.beat,context:1,range:0...63.25))
        XCTAssertEqual(changed,11.25)
        var length=NumberEditSession<Int>();length.begin(value:note.length,context:1)
        XCTAssertEqual(length.text,"0.75")
        XCTAssertNil(try length.resolve(value:note.length,context:1,range:0.03125...64))
        XCTAssertEqual(note.beat,8.5)
    }
    func testUntouchedAndCancelledFractionalPositionPreservesRawPrecision()throws {
        for beat in [0.00000000012345,8.123456789012345,131071.123456789] {
            var edit=NumberEditSession<Int>(presentation:.beatPosition);edit.begin(value:beat,context:1)
            XCTAssertNil(try edit.resolve(value:beat,context:1,range:0...131072))
            edit.text="12.25";edit.reset(value:beat)
            XCTAssertNil(try edit.resolve(value:beat,context:1,range:0...131072))
            XCTAssertEqual(edit.text,BeatPosition.text(beat))
        }
    }
    func testBoundsAreDisplayedAsPositionsAndInvalidInputCannotCommit()throws {
        var edit=NumberEditSession<Int>(presentation:.beatPosition);edit.begin(value:4,context:1)
        for text in ["0","-1","17","nan","inf","1e999",""] {
            edit.text=text
            XCTAssertThrowsError(try edit.resolve(value:4,context:1,range:0...15.5))
        }
        edit.text="0"
        XCTAssertThrowsError(try edit.resolve(value:4,context:1,range:0...15.5)) {
            XCTAssertEqual($0.localizedDescription,"입력 범위: 1–16.5 박")
        }
        edit.text="1";XCTAssertEqual(try edit.resolve(value:4,context:1,range:0...15.5),0)
        edit.text="16.5";XCTAssertEqual(try edit.resolve(value:4,context:1,range:0...15.5),15.5)
    }
    func testPositionDraftKeepsRevisionAndValueGuards()throws {
        var edit=NumberEditSession<String>(presentation:.beatPosition);edit.begin(value:8.5,context:"a:r1")
        edit.text="10";edit.refresh(value:8.5,context:"a:r2",editing:true)
        XCTAssertThrowsError(try edit.resolve(value:8.5,context:"a:r2",range:0...64))
        XCTAssertThrowsError(try edit.resolve(value:8.5,context:"b:r1",range:0...64))
        XCTAssertThrowsError(try edit.resolve(value:9,context:"a:r1",range:0...64))
        XCTAssertEqual(try edit.resolve(value:8.5,context:"a:r1",range:0...64),9)
    }
    func testDisplayDoesNotConfuseTimeWithOrdinalInVariableClock()throws {
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(beats:8,context:context,tempoChanges:[TempoChange(beat:4,bpm:60)])
        XCTAssertEqual(BeatPosition.text(4.5),"5.5")
        XCTAssertEqual(AutomationDisplay.time(4.5,clock:clock),"5.5박 · 2.50초")
        XCTAssertEqual(clock.beat(atSeconds:2.5),4.5)
    }
}
