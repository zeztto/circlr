import XCTest
@testable import CirclrCore

final class AutomationDisplayTests:XCTestCase {
    func testFittedViewportRemainsStableWhenLastPointMovesOrIsRemoved() {
        var view=AutomationViewport(),points=[AutomationPoint(beat:0,value:1),AutomationPoint(beat:96,value:1)]
        XCTAssertEqual(view.displayedBeats(base:64),64)
        view.fit(base:64,points:points)
        points[1].beat=80
        XCTAssertEqual(view.displayedBeats(base:64),96)
        points.removeLast()
        XCTAssertEqual(view.displayedBeats(base:64),96)
        view.reset()
        XCTAssertEqual(view.displayedBeats(base:64),64)
    }
    func testViewportCanRefitNewOutsidePointAndRespectChangedBaseLength() {
        var view=AutomationViewport(),points=[AutomationPoint(beat:96,value:1)]
        view.fit(base:64,points:points)
        points.append(AutomationPoint(beat:128,value:1))
        XCTAssertEqual(view.displayedBeats(base:64),96)
        view.fit(base:64,points:points)
        XCTAssertEqual(view.displayedBeats(base:64),128)
        XCTAssertEqual(view.displayedBeats(base:160),160)
        view.reset();view.fit(base:64,points:[])
        XCTAssertEqual(view.displayedBeats(base:64),64)
    }
    func testOverlappingHitsCycleAndNormalClickKeepsSelectedPoint() {
        let ids=["start","middle","end"]
        XCTAssertEqual(AutomationDisplay.hit(in:ids,selected:nil,cycle:false),"start")
        XCTAssertEqual(AutomationDisplay.hit(in:ids,selected:"start",cycle:true),"middle")
        XCTAssertEqual(AutomationDisplay.hit(in:ids,selected:"middle",cycle:true),"end")
        XCTAssertEqual(AutomationDisplay.hit(in:ids,selected:"end",cycle:true),"start")
        XCTAssertEqual(AutomationDisplay.hit(in:ids,selected:"end",cycle:false),"end")
        XCTAssertEqual(AutomationDisplay.hit(in:ids,selected:"removed",cycle:true),"start")
        XCTAssertEqual(AutomationDisplay.hit(in:["single"],selected:"single",cycle:true),"single")
        XCTAssertNil(AutomationDisplay.hit(in:[],selected:"start",cycle:true))
    }
    func testPanPercentageInputPreservesRawUntouchedPrecisionAndRejectsInvalidRange()throws {
        let raw=0.123456789012345
        var edit=NumberEditSession<Int>(presentation:.panPercent);edit.begin(value:raw,context:1)
        XCTAssertEqual(edit.text,"12.35");XCTAssertNil(try edit.resolve(value:raw,context:1,range:-1...1))
        for (text,expected) in [("−100",-1.0),("0",0.0),("+50",0.5),("100",1.0)] {
            edit.text=text;XCTAssertEqual(try edit.resolve(value:raw,context:1,range:-1...1),expected)
        }
        for text in ["101","-100.01","nan","inf","50%",""] {
            edit.text=text;XCTAssertThrowsError(try edit.resolve(value:raw,context:1,range:-1...1))
        }
        edit.text="-50";XCTAssertThrowsError(try edit.resolve(value:raw,context:2,range:-1...1))
        XCTAssertThrowsError(try edit.resolve(value:0.3,context:1,range:-1...1))
    }
    func testGainNudgeUsesDecibelsAndClampsSilenceAndMaximum() {
        for gain in [0.1,0.5,1.0] {
            XCTAssertEqual(AutomationDisplay.nudge(gain,parameter:.gain,direction:1)/gain,pow(10,0.5/20),accuracy:1e-12)
            XCTAssertEqual(AutomationDisplay.nudge(gain,parameter:.gain,direction:-1,fine:true)/gain,pow(10,-0.1/20),accuracy:1e-12)
            XCTAssertEqual(AutomationDisplay.nudge(gain,parameter:.gain,direction:1,coarse:true)/gain,pow(10,3.0/20),accuracy:1e-12)
        }
        XCTAssertEqual(AutomationDisplay.nudge(0,parameter:.gain,direction:-1),0)
        XCTAssertGreaterThan(AutomationDisplay.nudge(0,parameter:.gain,direction:1),0)
        XCTAssertEqual(AutomationDisplay.nudge(4,parameter:.gain,direction:1),4)
        XCTAssertEqual(AutomationDisplay.nudge(0.123456789,parameter:.gain,direction:0),0.123456789)
    }
    func testPanNudgeUnitsAndAccessibleDescriptions() {
        XCTAssertEqual(AutomationDisplay.nudge(0,parameter:.pan,direction:1),0.05)
        XCTAssertEqual(AutomationDisplay.nudge(0,parameter:.pan,direction:-1,fine:true),-0.01)
        XCTAssertEqual(AutomationDisplay.nudge(0.9,parameter:.pan,direction:1,coarse:true),1)
        XCTAssertEqual(AutomationDisplay.nudge(-1,parameter:.pan,direction:-1),-1)
        XCTAssertEqual(AutomationDisplay.value(0,parameter:.pan),"중앙")
        XCTAssertEqual(AutomationDisplay.value(-0.5,parameter:.pan),"L 50.00%")
        XCTAssertEqual(AutomationDisplay.value(0,parameter:.gain),"−∞ dB")
        XCTAssertEqual(AutomationDisplay.value(1,parameter:.gain),"0.00 dB")
    }
    func testDisplayedTimeUsesLocalTempoMap()throws {
        let c=MusicContext(),clock=try MusicClock(bars:2,context:c,tempoChanges:[.init(beat:2,bpm:60)])
        XCTAssertEqual(AutomationDisplay.time(3,clock:clock),"3.000박 · 2.00초")
        var localContext=MusicContext();localContext.tempo=240
        let local=try MusicClock(beats:8,context:localContext)
        XCTAssertEqual(AutomationDisplay.time(3,clock:local),"3.000박 · 0.75초")
    }
}
