import XCTest
@testable import CirclrCore

final class MIDIOrbitViewportTests:XCTestCase {
    func testPagesFollowRealMeterBoundariesAndClampLastPartialPage()throws {
        var view=MIDIOrbitViewport()
        let clock=try MusicClock(bars:6,context:MusicContext(),meterChanges:[.init(bar:2,meter:Meter(3,4))])
        XCTAssertEqual(view.beats(clock),0..<14)
        view.page=1;XCTAssertEqual(view.beats(clock),14..<20)
        view.page=999;XCTAssertEqual(view.beats(clock),14..<20)
        XCTAssertEqual(view.pageCount(clock),2)
        view.barsPerPage=0;XCTAssertEqual(view.beats(clock),0..<20)
    }
    func testPageCoordinatesRespectLocalTempoChanges()throws {
        var view=MIDIOrbitViewport();view.barsPerPage=1
        let clock=try MusicClock(bars:2,context:MusicContext(),tempoChanges:[.init(beat:2,bpm:60)])
        XCTAssertEqual(view.phase(2,clock:clock),1.0/3,accuracy:1e-12)
        XCTAssertEqual(view.beat(1.0/3,clock:clock),2,accuracy:1e-12)
        view.page=1
        XCTAssertEqual(view.beat(0,clock:clock),4,accuracy:1e-12)
        XCTAssertEqual(view.beat(0.5,clock:clock),6,accuracy:1e-12)
    }
    func testClippedNotesRemainVisibleButOnlyRealEndCanResize()throws {
        var view=MIDIOrbitViewport();view.barsPerPage=1;view.page=1
        let clock=try MusicClock(bars:3,context:MusicContext())
        let through=Note(beat:2,length:8,pitch:64)
        XCTAssertTrue(view.visible(through,clock:clock));XCTAssertFalse(view.showsEnd(through,clock:clock))
        XCTAssertFalse(view.visible(Note(beat:0,length:4,pitch:64),clock:clock))
        XCTAssertFalse(view.visible(Note(beat:8,length:1,pitch:64),clock:clock))
        XCTAssertTrue(view.showsEnd(Note(beat:2,length:6,pitch:64),clock:clock))
    }
    func testPitchFitAndRevealKeepEveryMidiPitchReachable()throws {
        var view=MIDIOrbitViewport();let clock=try MusicClock(bars:16,context:MusicContext())
        view.fitPitches([Note(beat:0,length:1,pitch:54),Note(beat:0,length:1,pitch:72)])
        XCTAssertEqual(view.rows,24);XCTAssertTrue((view.lowest...view.highest).contains(54))
        for pitch in 0...127 {
            let note=Note(beat:40,length:1,pitch:pitch);view.reveal(note,clock:clock)
            XCTAssertTrue(view.visible(note,clock:clock));XCTAssertGreaterThanOrEqual(view.lowest,0);XCTAssertLessThanOrEqual(view.highest,127)
        }
        XCTAssertEqual(view.page,2)
    }
    func testViewportAndOrderingPreserveNotesAndDeterministicChordOrder()throws {
        var a=Note(beat:0,length:1,pitch:60);a.id="a"
        var b=a;b.id="b"
        let notes=[b,Note(beat:1,length:1,pitch:50),a],original=notes
        var view=MIDIOrbitViewport();view.fitPitches(notes)
        XCTAssertEqual(Array(MIDIOrbitViewport.ordered(notes).prefix(2)).map(\.id),["a","b"])
        XCTAssertEqual(notes,original)
    }
    func testFittingAnExactOctaveDoesNotHideTheLowestPitch() {
        for low in [0,60,116] {
            var view=MIDIOrbitViewport();view.fitPitches([Note(beat:0,length:1,pitch:low),Note(beat:0,length:1,pitch:low+11)])
            XCTAssertEqual(view.rows,12);XCTAssertEqual(view.lowest,low);XCTAssertEqual(view.highest,low+11)
        }
    }
    func testSelectingAVisibleSustainedNoteKeepsTheCurrentPage()throws {
        var view=MIDIOrbitViewport();view.barsPerPage=1;view.page=1
        let clock=try MusicClock(bars:8,context:MusicContext())
        view.reveal(Note(beat:2,length:8,pitch:64),clock:clock)
        XCTAssertEqual(view.page,1)
        view.reveal(Note(beat:2,length:2,pitch:64),clock:clock)
        XCTAssertEqual(view.page,0)
        view.reveal(Note(beat:12,length:1,pitch:64),clock:clock)
        XCTAssertEqual(view.page,3)
    }
}
