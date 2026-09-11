import XCTest
@testable import CirclrCore

final class TransitionTimingTests:XCTestCase {
    func clocks() throws -> (MusicClock,MusicClock) {
        var source=MusicContext();source.tempo=120
        var target=MusicContext();target.tempo=90;target.meter=Meter(7,8)
        return (try MusicClock(bars:3,context:source,meterChanges:[MeterChange(bar:2,meter:Meter(3,4))],tempoChanges:[TempoChange(beat:4,bpm:60)]),
                try MusicClock(bars:2,context:target))
    }
    func testFractionalBarsUseSourceTailAndTargetHeadMaps() throws {
        let (source,target)=try clocks();var t=Transition();t.length=1.5
        XCTAssertEqual(source.seconds,9,accuracy:1e-12)
        XCTAssertEqual(try TransitionTiming(t,source:source,target:target).duration,5,accuracy:1e-12)
        t.anchor = .targetBars
        XCTAssertEqual(try TransitionTiming(t,source:source,target:target).duration,3.5,accuracy:1e-12)
    }
    func testModesUseOffsetsFromSourceEndAndZeroIsValid() throws {
        let (source,target)=try clocks();var t=Transition();t.anchor = .seconds;t.length=2
        for (mode,start,next) in [(TransitionMode.within,-2.0,0.0),(.insert,0.0,2.0),(.overlap,-2.0,-2.0)] {
            t.mode=mode;let value=try TransitionTiming(t,source:source,target:target)
            XCTAssertEqual(value.duration,2);XCTAssertEqual(value.startOffset,start);XCTAssertEqual(value.targetOffset,next)
            var zero=t;zero.length=0
            let empty=try TransitionTiming(zero,source:source,target:target)
            XCTAssertEqual(empty.duration,0);XCTAssertEqual(empty.startOffset,0);XCTAssertEqual(empty.targetOffset,0)
        }
    }
    func testInvalidLengthsAndOverlapEqualityAreRejected() throws {
        let (source,target)=try clocks();var t=Transition()
        for length in [-1,Double.nan,.infinity,4] {t.length=length;XCTAssertThrowsError(try TransitionTiming(t,source:source,target:target))}
        t.anchor = .targetBars;t.length=3;XCTAssertThrowsError(try TransitionTiming(t,source:source,target:target))
        t.anchor = .seconds;t.length=10;XCTAssertThrowsError(try TransitionTiming(t,source:source,target:target))
        t.mode = .overlap;t.length=target.seconds;XCTAssertThrowsError(try TransitionTiming(t,source:source,target:target))
        t.length=target.seconds.nextDown;XCTAssertNoThrow(try TransitionTiming(t,source:source,target:target))
    }
    func testCompilerSchedulesTransitionOnlyAfterLastRepeat() throws {
        var p=Project();let source=p.addSection(name:"앞",at:Point(),bars:3),target=p.addSection(name:"뒤",at:Point(200,0),bars:2)
        p.sections[0].meterChanges=[MeterChange(bar:2,meter:Meter(3,4))]
        p.sections[0].tempoChanges=[TempoChange(beat:4,bpm:60)]
        p.arrangements[0].uses[0].repeatCount=2
        p.arrangements[0].uses[1].settings.tempo = .local(90)
        p.arrangements[0].uses[1].settings.meter = .local(Meter(7,8))
        try ProjectEditing.connect(from:source,to:target,in:&p)
        p.arrangements[0].edges[0].transition.length=1
        for (mode,start,next) in [(TransitionMode.within,15.0,18.0),(.insert,18.0,21.0),(.overlap,15.0,15.0)] {
            p.arrangements[0].edges[0].transition.mode=mode
            let plan=try ArrangementCompiler.compile(p),transition=try XCTUnwrap(plan.transitions.first)
            XCTAssertEqual(plan.transitions.count,1);XCTAssertEqual(plan.occurrences.count,3)
            XCTAssertEqual(transition.duration,3,accuracy:1e-12);XCTAssertEqual(transition.start,start,accuracy:1e-12)
            XCTAssertEqual(plan.occurrences[2].start,next,accuracy:1e-12)
            XCTAssertEqual(transition.sourceOccurrenceID,plan.occurrences[1].id)
        }
    }
}
