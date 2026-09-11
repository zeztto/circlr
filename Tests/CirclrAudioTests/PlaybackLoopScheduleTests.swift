import XCTest
@testable import CirclrAudio

final class PlaybackLoopScheduleTests:XCTestCase {
    func testLongCycleReservationIsImmediateAndDoesNotConsumeQueuedAudio()throws {
        for seconds in [30,180] {
            let source=PlaybackLoopSchedule.Source(id:UUID(),frames:seconds*48000,tailFrames:48000)
            var scheduler=try PlaybackLoopSchedule(source:source)
            _=try scheduler.next(maxFrames:32768)
            let before=scheduler.elapsedFrame
            let reserved=try scheduler.request(.init(id:UUID(),replacement:nil))
            XCTAssertEqual(reserved.elapsedFrame,Int64(source.frames))
            XCTAssertEqual(scheduler.elapsedFrame,before,"ACK cannot wait for minutes of audio consumption")
            let next=try scheduler.next(maxFrames:4096)
            XCTAssertNil(next.boundary);XCTAssertEqual(next.chunk?.elapsedFrame,before)
        }
    }
    func testNonzeroStartAndQueuedReplacementHaveNoMissingOrRepeatedFrames()throws {
        let first=PlaybackLoopSchedule.Source(id:UUID(),frames:5,tailFrames:2)
        let second=PlaybackLoopSchedule.Source(id:UUID(),frames:3,tailFrames:0)
        var schedule=try PlaybackLoopSchedule(source:first,fromFrame:3)
        var actual:[String]=[],frames:[Int64]=[],boundaries:[PlaybackLoopSchedule.Boundary]=[]
        func append(_ step:PlaybackLoopSchedule.Step) {
            if let boundary=step.boundary {boundaries.append(boundary)}
            if let chunk=step.chunk {
                for i in 0..<chunk.count {
                    actual.append((chunk.source.id==first.id ? "A":"B")+String(chunk.sourceFrame+i))
                    frames.append(chunk.elapsedFrame+Int64(i))
                }
            }
        }
        append(try schedule.next(maxFrames:4096)) // Initial A3 A4 already scheduled.
        let change=PlaybackLoopSchedule.Change(id:UUID(),replacement:second)
        try schedule.request(change)
        append(try schedule.next(maxFrames:4096));append(try schedule.next(maxFrames:4096))
        XCTAssertEqual(actual,["A3","A4","B0","B1","B2","B0","B1","B2"])
        XCTAssertEqual(frames,Array(0..<8).map(Int64.init))
        XCTAssertEqual(boundaries.map(\.elapsedFrame),[2])
        XCTAssertEqual(boundaries.first?.change.id,change.id)
    }
    func testChangeUsesNextUnsubmittedBoundaryRatherThanRewritingQueuedAudio()throws {
        let source=PlaybackLoopSchedule.Source(id:UUID(),frames:10,tailFrames:3)
        var schedule=try PlaybackLoopSchedule(source:source)
        _=try schedule.next(maxFrames:7)
        try schedule.request(.init(id:UUID(),replacement:nil))
        let rest=try schedule.next(maxFrames:7)
        XCTAssertEqual(rest.chunk?.sourceFrame,7);XCTAssertEqual(rest.chunk?.count,3)
        XCTAssertNil(rest.boundary)
        let tail=try schedule.next(maxFrames:7)
        XCTAssertEqual(tail.boundary?.elapsedFrame,10)
        XCTAssertEqual(tail.chunk?.elapsedFrame,10);XCTAssertEqual(tail.chunk?.count,3)
        XCTAssertEqual(tail.chunk?.tail,true);XCTAssertTrue(tail.ended)
        XCTAssertNil(try schedule.next(maxFrames:7).chunk)
    }
    func testZeroTailExitTerminatesExactlyAtBoundaryAndCancelDropsPending()throws {
        let source=PlaybackLoopSchedule.Source(id:UUID(),frames:1,tailFrames:0)
        var schedule=try PlaybackLoopSchedule(source:source)
        _=try schedule.next(maxFrames:4096)
        try schedule.request(.init(id:UUID(),replacement:nil))
        let end=try schedule.next(maxFrames:4096)
        XCTAssertEqual(end.boundary?.elapsedFrame,1);XCTAssertNil(end.chunk);XCTAssertTrue(end.ended)
        var cancelled=try PlaybackLoopSchedule(source:source)
        try cancelled.request(.init(id:UUID(),replacement:nil))
        cancelled.cancel()
        let stopped=try cancelled.next(maxFrames:4096)
        XCTAssertNil(stopped.boundary);XCTAssertNil(stopped.chunk);XCTAssertTrue(stopped.ended)
    }
    func testLongFiniteExitTailMatchesHistoryWithoutNewBody()throws {
        var pcm=PCM(frames:7);pcm.left=[0.1,0.1,0.2,0.2,0.3,0.3,0.1];pcm.right=pcm.left
        let loop=try PlaybackLoopPCM(mix:pcm,bodySeconds:2/PCM.rate)
        XCTAssertEqual(loop.exitTail.count,5)
        for (actual,expected) in zip(loop.exitTail.left,[Float(0.6),0.5,0.4,0.3,0.1]) {
            XCTAssertEqual(actual,expected,accuracy:0.000001)
        }
    }
    func testPendingChangeCannotBeOverwrittenOrRevivedAfterCancel()throws {
        let source=PlaybackLoopSchedule.Source(id:UUID(),frames:480,tailFrames:0)
        var schedule=try PlaybackLoopSchedule(source:source)
        try schedule.request(.init(id:UUID(),replacement:nil))
        XCTAssertThrowsError(try schedule.request(.init(id:UUID(),replacement:source)))
        schedule.cancel()
        XCTAssertThrowsError(try schedule.request(.init(id:UUID(),replacement:source)))
    }
}
