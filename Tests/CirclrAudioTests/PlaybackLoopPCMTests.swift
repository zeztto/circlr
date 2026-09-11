import XCTest
@testable import CirclrAudio

final class PlaybackLoopPCMTests: XCTestCase {
    private func pcm(_ values:[Float]) -> PCM {var p=PCM(frames:values.count);p.left=values;p.right=values.map { -$0 };return p}
    func testTailWrapsIncludingLongerThanOneBodyAndFirstPassIsSteadyState() throws {
        let loop=try PlaybackLoopPCM(mix:pcm([0.1,0.2,0.3,0.4,0.05]),bodySeconds:2/PCM.rate)
        XCTAssertEqual(loop.bodyFrames,2)
        XCTAssertEqual(loop.tailPolicy,.circularSteadyState)
        XCTAssertEqual(loop.cycle.left[0],0.45,accuracy:0.000001)
        XCTAssertEqual(loop.cycle.left[1],0.6,accuracy:0.000001)
        XCTAssertEqual(loop.cycle.right[0],-0.45,accuracy:0.000001)
        let rendered=(0..<8).map {loop.cycle.left[$0 % loop.bodyFrames]}
        XCTAssertEqual(rendered,Array(repeating:loop.cycle.left,count:4).flatMap {$0})
    }
    func testOffsetRotatesFullCycleWithoutTruncation() throws {
        let loop=try PlaybackLoopPCM(mix:pcm([0.1,0.2,0.3]),bodySeconds:3/PCM.rate)
        let rotated=try loop.rotated(from:4/PCM.rate)
        XCTAssertEqual(rotated.left,[0.2,0.3,0.1]);XCTAssertEqual(rotated.count,3)
        XCTAssertEqual(try loop.rotated(from:0).left,loop.cycle.left)
    }
    func testClockSeparatesWrappedPositionFromMultipleIterations() throws {
        let loop=try PlaybackLoopPCM(mix:PCM(frames:48000),bodySeconds:1)
        XCTAssertEqual(loop.position(elapsed:3.25,offset:0.5),0.75,accuracy:0.000001)
        XCTAssertEqual(loop.iteration(elapsed:3.25,offset:0.5),3)
        XCTAssertEqual(loop.position(elapsed:1),0)
        XCTAssertEqual(loop.iteration(elapsed:1),1)
        XCTAssertEqual(loop.position(elapsed:20_000),0)
    }
    func testRejectsInvalidRangeSamplesAndMemoryBeforeAllocation() throws {
        for seconds in [Double.nan,Double.infinity,0,-1,1] {
            XCTAssertThrowsError(try PlaybackLoopPCM(mix:pcm([0.1]),bodySeconds:seconds))
        }
        XCTAssertThrowsError(try PlaybackLoopPCM(mix:pcm([.nan]),bodySeconds:1/PCM.rate))
        var unequal=pcm([0.1]);unequal.right=[]
        XCTAssertThrowsError(try PlaybackLoopPCM(mix:unequal,bodySeconds:1/PCM.rate))
        XCTAssertThrowsError(try PlaybackLoopPCM(mix:pcm([0.1]),bodySeconds:1/PCM.rate,byteLimit:1))
    }
    func testTailClippingIsExplicitFailureNotSilentNormalization() throws {
        XCTAssertThrowsError(try PlaybackLoopPCM(mix:pcm([0.6,0.6]),bodySeconds:1/PCM.rate))
    }
}
