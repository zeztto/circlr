import XCTest
@testable import CirclrCore

final class AutomationRulerTests:XCTestCase {
    func testTicksContinuePastFullCircleWithBoundedDensityAndNoEndDuplicate()throws {
        let clock=try MusicClock(bars:16,context:MusicContext())
        let ticks=AutomationRuler.ticks(clock:clock,end:128,capacity:8)
        XCTAssertEqual(ticks.map(\.bar),[1,5,9,13,17,21,25,29])
        XCTAssertEqual(ticks.map(\.beat),[0,16,32,48,64,80,96,112])
        XCTAssertEqual(AutomationRuler.position(at:96,clock:clock)?.bar,25)
        XCTAssertEqual(AutomationRuler.position(at:96,clock:clock)?.beat,1)
    }
    func testMeterChangesAndPartialLastBarKeepActualBoundaries()throws {
        let clock=try MusicClock(bars:3,context:MusicContext(),meterChanges:[.init(bar:1,meter:Meter(7,8))])
        XCTAssertEqual(AutomationRuler.ticks(clock:clock,end:18,capacity:12).map(\.beat),[0,4,7.5,11,14.5])
        XCTAssertEqual(AutomationRuler.text(at:15.25,clock:clock),"5마디 · 2.50박")
        let partial=try MusicClock(beats:6,context:MusicContext())
        XCTAssertEqual(partial.barContinuationBeat,8)
        XCTAssertEqual(AutomationRuler.ticks(clock:partial,end:13,capacity:12).map(\.beat),[0,4,8,12])
        XCTAssertEqual(AutomationRuler.text(at:7,clock:partial),"2마디 · 4.00박")
        XCTAssertEqual(AutomationRuler.text(at:8,clock:partial),"3마디 · 1.00박")
        let nested=try MusicClock(parent:partial,start:5,length:0.5,context:MusicContext(),inheritTempo:true,inheritMeter:true)
        XCTAssertEqual(nested.barContinuationBeat,3)
        XCTAssertEqual(AutomationRuler.ticks(clock:nested,end:8,capacity:12).map(\.beat),[0,3,7])
    }
    func testInheritedMiddleOfBarAndTempoMapPreserveDisplayAndAudioClock()throws {
        let parent=try MusicClock(bars:3,context:MusicContext(),meterChanges:[.init(bar:1,meter:Meter(3,4))],tempoChanges:[.init(beat:4,bpm:60)])
        let short=try MusicClock(parent:parent,start:2,length:1,context:MusicContext(),inheritTempo:true,inheritMeter:true)
        XCTAssertEqual(short.barContinuationBeat,2)
        XCTAssertEqual(AutomationRuler.ticks(clock:short,end:8,capacity:12).map(\.beat),[0,2,6])
        let spanning=try MusicClock(parent:parent,start:2,length:6,context:MusicContext(),inheritTempo:true,inheritMeter:true)
        XCTAssertEqual(spanning.barContinuationBeat,8)
        XCTAssertEqual(AutomationRuler.ticks(clock:spanning,end:12,capacity:12).map(\.beat),[0,2,5,8,11])
        XCTAssertEqual(spanning.seconds(at:10),9,accuracy:1e-10)
        XCTAssertEqual(spanning.beat(atSeconds:9),10,accuracy:1e-10)
    }
    func testMaximumRangeIsSparseAndInvalidRangesDoNotTrap()throws {
        var context=MusicContext();context.meter=Meter(1,32)
        let clock=try MusicClock(bars:1,context:context)
        let ticks=AutomationRuler.ticks(clock:clock,end:1_048_576,capacity:12)
        XCTAssertLessThanOrEqual(ticks.count,12);XCTAssertEqual(ticks.first?.beat,0)
        XCTAssertTrue(zip(ticks,ticks.dropFirst()).allSatisfy{$0.beat<$1.beat && $0.bar<$1.bar})
        XCTAssertEqual(AutomationRuler.position(at:1_048_576,clock:clock)?.bar,8_388_609)
        for value in [Double.nan,Double.infinity,-1,1_048_577] {
            XCTAssertTrue(AutomationRuler.ticks(clock:clock,end:value,capacity:Int.max).isEmpty)
            XCTAssertNil(AutomationRuler.position(at:value,clock:clock))
        }
        XCTAssertTrue(AutomationRuler.ticks(clock:nil,end:8,capacity:4).isEmpty)
        XCTAssertEqual(AutomationRuler.ticks(clock:clock,end:8,capacity:Int.min).count,1)
    }
    func testRevealOnlyExpandsAndDoesNotRefitAfterPointEdits() {
        var view=AutomationViewport();view.reveal(base:64,beat:32)
        XCTAssertNil(view.fittedBeats)
        view.reveal(base:64,beat:96);XCTAssertEqual(view.displayedBeats(base:64),96)
        view.reveal(base:64,beat:80);XCTAssertEqual(view.displayedBeats(base:64),96)
        for value in [Double.nan,Double.infinity,-1,1_048_577] {view.reveal(base:64,beat:value)}
        XCTAssertEqual(view.displayedBeats(base:64),96)
        view.reveal(base:64,beat:128);XCTAssertEqual(view.displayedBeats(base:64),128)
        view.reset();XCTAssertEqual(view.displayedBeats(base:64),64)
    }
}
