import XCTest
@testable import CirclrCore

final class InstrumentClockTests: XCTestCase {
    func testExactPartialClockWithTempoAndMeterChanges() throws {
        var context=MusicContext();context.tempo=120
        let parent=try MusicClock(bars:4,context:context,meterChanges:[MeterChange(bar:1,meter:Meter(3,4))],tempoChanges:[TempoChange(beat:2,bpm:87),TempoChange(beat:6,bpm:143)])
        let sliced=try MusicClock(parent:parent,start:1.25,length:7.125,context:context,inheritTempo:true,inheritMeter:true)
        let restored=try MusicClock(barStarts:sliced.barStarts,barContinuationBeat:sliced.barContinuationBeat,meters:sliced.meters,tempos:sliced.tempos)
        XCTAssertEqual(restored,sliced)
        for beat in stride(from:0.0,through:sliced.beats+2,by:0.125) {
            XCTAssertEqual(restored.seconds(at:beat),sliced.seconds(at:beat))
            XCTAssertEqual(restored.bar(at:beat),sliced.bar(at:beat))
            XCTAssertEqual(restored.beat(atSeconds:restored.seconds(at:beat)),sliced.beat(atSeconds:sliced.seconds(at:beat)))
        }
    }
    func testRejectsMalformedExactClockBeforeUse() throws {
        func make(_ starts:[Double],_ continuation:Double=4,_ tempos:[TempoChange]=[TempoChange(beat:0,bpm:120)])throws {
            _ = try MusicClock(barStarts:starts,barContinuationBeat:continuation,meters:[Meter(4,4)],tempos:tempos)
        }
        for starts in [[0,0],[1,4],[0,Double.nan],[0,Double.infinity],[0,5],[0,2,4]] {XCTAssertThrowsError(try make(starts))}
        XCTAssertThrowsError(try make([0,4],3))
        XCTAssertThrowsError(try make([0,4],.infinity))
        XCTAssertThrowsError(try make([0,4],4,[]))
        XCTAssertThrowsError(try make([0,4],4,[TempoChange(beat:1,bpm:120)]))
        XCTAssertThrowsError(try make([0,4],4,[TempoChange(beat:0,bpm:120),TempoChange(beat:0,bpm:90)]))
        XCTAssertThrowsError(try make([0,4],4,[TempoChange(beat:0,bpm:.nan)]))
    }
}
