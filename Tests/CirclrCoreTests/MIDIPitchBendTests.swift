import XCTest
@testable import CirclrCore

final class MIDIPitchBendTests:XCTestCase {
    func testDefaultCenterAndIndependentSourceState()throws {
        let centered=MIDIPitchBendSequence()
        XCTAssertEqual(centered.channel,0);XCTAssertEqual(centered.initialValue,8192)
        XCTAssertEqual(centered.initialRange,.init(semitones:2,cents:0))
        XCTAssertEqual(try centered.state(atBeat:0).semitones,0)
        var other=centered;other.initialValue=0;other.channel=15
        XCTAssertEqual(try other.state(atBeat:131072).semitones,-2)
        XCTAssertEqual(try centered.state(atBeat:131072).rawValue,8192)
        // Foundation types alone do not upgrade existing projects.
        XCTAssertEqual(Project().schemaVersion,1)
    }
    func testAsymmetricRawEndpointsAndInitialRangeSeed()throws {
        let range=MIDIPitchBendRange(semitones:12,cents:50)
        let low=MIDIPitchBendSequence(initialValue:0,initialRange:range)
        let high=MIDIPitchBendSequence(initialValue:16383,initialRange:range)
        XCTAssertEqual(try low.state(atBeat:0).semitones,-12.5)
        XCTAssertEqual(try high.state(atBeat:0).semitones,8191.0/8192*12.5)
        XCTAssertLessThan(try high.state(atBeat:0).semitones,12.5)
        let cents=MIDIPitchBendRange(semitones:127,cents:127)
        XCTAssertNoThrow(try cents.validate());XCTAssertEqual(cents.totalSemitones,128.27)
    }
    func testRangeOnlyChangeReinterpretsHeldWheelAndBoundaryHolds()throws {
        let sequence=MIDIPitchBendSequence(initialValue:12288,events:[
            .init(beat:2,kind:.range(.init(semitones:12,cents:0))),
            .init(beat:4,kind:.value(8192))])
        XCTAssertEqual(try sequence.state(atBeat:1.999).semitones,1)
        XCTAssertEqual(try sequence.state(atBeat:2).semitones,6)
        XCTAssertEqual(try sequence.state(atBeat:3.999).rawValue,12288)
        XCTAssertEqual(try sequence.state(atBeat:4).semitones,0)
        XCTAssertEqual(try sequence.state(atBeat:131072).semitones,0)
    }
    func testSameBeatArrayOrderIsPreservedWithoutCoalescing()throws {
        let sequence=MIDIPitchBendSequence(events:[
            .init(beat:0,kind:.value(0)),.init(beat:0,kind:.value(12288)),
            .init(beat:0,kind:.range(.init(semitones:12))),.init(beat:0,kind:.range(.init(semitones:7,cents:50)))])
        let before=sequence,state=try sequence.state(atBeat:0)
        XCTAssertEqual(state.rawValue,12288);XCTAssertEqual(state.range,.init(semitones:7,cents:50))
        XCTAssertEqual(state.semitones,3.75);XCTAssertEqual(sequence,before)
        var reversed=sequence;reversed.events.reverse()
        XCTAssertEqual(try reversed.state(atBeat:0).rawValue,0)
        XCTAssertEqual(try reversed.state(atBeat:0).semitones,-12)
        XCTAssertNotEqual(sequence,reversed)
    }
    func testCodablePreservesInitialStateAndRepeatedBeatEvents()throws {
        let sequence=MIDIPitchBendSequence(channel:9,initialValue:4096,initialRange:.init(semitones:0,cents:127),events:[
            .init(beat:1.25,kind:.range(.init(semitones:127,cents:0))),
            .init(beat:1.25,kind:.value(16383)),.init(beat:131072,kind:.value(8192))])
        let decoded=try JSONDecoder().decode(MIDIPitchBendSequence.self,from:JSONEncoder().encode(sequence))
        XCTAssertEqual(decoded,sequence);XCTAssertEqual(decoded.events.count,3)
        XCTAssertEqual(try decoded.state(atBeat:1.25),try sequence.state(atBeat:1.25))
    }
    func testChannelValueRangeAndTimeValidation()throws {
        for channel in [-1,16,Int.max] {XCTAssertThrowsError(try MIDIPitchBendSequence(channel:channel).validate())}
        for value in [-1,16384,Int.max] {
            XCTAssertThrowsError(try MIDIPitchBendSequence(initialValue:value).validate())
            XCTAssertThrowsError(try MIDIPitchBendSequence(events:[.init(beat:0,kind:.value(value))]).validate())
        }
        for range in [MIDIPitchBendRange(semitones:-1),.init(semitones:128),.init(cents:-1),.init(cents:128)] {
            XCTAssertThrowsError(try MIDIPitchBendSequence(initialRange:range).validate())
            XCTAssertThrowsError(try MIDIPitchBendSequence(events:[.init(beat:0,kind:.range(range))]).validate())
        }
        for beat in [-1.0,131073,.nan,.infinity,-Double.infinity] {
            XCTAssertThrowsError(try MIDIPitchBendSequence().state(atBeat:beat))
            XCTAssertThrowsError(try MIDIPitchBendSequence(events:[.init(beat:beat,kind:.value(8192))]).validate())
        }
    }
    func testDescendingAndInvalidFutureEventsCannotHideBehindEarlierQuery()throws {
        let descending=MIDIPitchBendSequence(events:[.init(beat:2,kind:.value(0)),.init(beat:1,kind:.value(8192))])
        XCTAssertThrowsError(try descending.validate());XCTAssertThrowsError(try descending.state(atBeat:0))
        let future=MIDIPitchBendSequence(events:[.init(beat:100,kind:.value(20000))])
        XCTAssertThrowsError(try future.state(atBeat:0))
    }
    func testEventCountBoundaryAllowsExactlyLimit()throws {
        let event=MIDIPitchBendEvent(beat:0,kind:.value(8192))
        var sequence=MIDIPitchBendSequence(events:Array(repeating:event,count:100000))
        XCTAssertNoThrow(try sequence.validate());XCTAssertEqual(try sequence.state(atBeat:0).rawValue,8192)
        sequence.events.append(event);XCTAssertThrowsError(try sequence.validate())
    }
}
