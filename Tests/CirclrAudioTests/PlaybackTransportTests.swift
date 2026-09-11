import XCTest
@testable import CirclrAudio
import CirclrCore

private final class PlaybackFixture:@unchecked Sendable {
    private let lock=NSLock()
    private var recorded:[String]=[]
    private var callbacks:[@Sendable()->Void]=[]
    var blocked:String?
    let release=DispatchSemaphore(value:0)
    var onEntered:(@Sendable()->Void)?
    var failStart=false
    func visit(_ name:String) {
        lock.lock();recorded.append(name+(Thread.isMainThread ? ".MAIN":""));lock.unlock()
        if name==blocked{onEntered?();_ = release.wait(timeout:.now()+5)}
    }
    func store(_ callback:@escaping @Sendable()->Void){lock.lock();callbacks.append(callback);lock.unlock()}
    func complete(_ index:Int){lock.lock();let callback=callbacks[index];lock.unlock();callback()}
    var events:[String]{lock.lock();defer{lock.unlock()};return recorded}
}
private final class TestPlaybackBackend:PlaybackBackend {
    let fixture:PlaybackFixture
    private var playing=false
    init(_ fixture:PlaybackFixture){self.fixture=fixture;fixture.visit("init")}
    deinit{fixture.visit("deinit")}
    func attach(){fixture.visit("attach")}
    func acquireOutput(){fixture.visit("device")}
    func route(){fixture.visit("route")}
    func start(_ pcm:PCM,from:Double,control:MediaPreviewCancellation,finished:@escaping @Sendable()->Void)throws {
        fixture.visit("start");if control.isCancelled{throw CancellationError()}
        if fixture.failStart{throw CirclrError("controlled start failure")}
        fixture.visit("audible");playing=true;fixture.store(finished)
    }
    func startLoop(_ pcm:PCM,from:Double,tail:PCM?,control:MediaPreviewCancellation)throws {
        fixture.visit("loop");if control.isCancelled{throw CancellationError()};playing=true
    }
    func stop(){fixture.visit("stop");playing=false}
    var running:Bool{playing}
    var seconds:Double{fixture.visit("clock");return 0.25}
}

@MainActor final class PlaybackTransportTests:XCTestCase {
    private func audio()throws->PreparedAudio {
        var project=Project();_ = project.addSection(name:"검증",at:Point(),bars:1)
        return PreparedAudio(plan:try ArrangementCompiler.compile(project),mix:PCM(frames:48000),stems:[:],tailSeconds:0)
    }
    private func eventually(_ check:()->Bool)async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while !check(){guard ProcessInfo.processInfo.systemUptime<deadline else{XCTFail("State not reached");throw PlaybackTransportError.timedOut};try await Task.sleep(for:.milliseconds(5))}
    }
    private func cancelled(_ task:Task<Void,Error>)async {
        do{try await task.value;XCTFail("Cancelled start succeeded")}catch{XCTAssertTrue(error is CancellationError)}
    }
    func testPreparedCallbackReceivesExactCycleBeforeBackendStarts()async throws {
        for loop in [false,true] {
            let fixture=PlaybackFixture(),playback=Playback(factory:{TestPlaybackBackend(fixture)})
            var input=try audio();input.mix=PCM(frames:Int((input.plan.duration*PCM.rate).rounded()))
            var calls=0
            try await playback.play(input,loop:loop,onPrepared:{cycle in
                calls+=1;fixture.visit("prepared")
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertFalse(playback.playing)
                XCTAssertFalse(fixture.events.contains("start"));XCTAssertFalse(fixture.events.contains("loop"))
                if loop {
                    XCTAssertEqual(cycle?.bodyFrames,input.mix.count)
                    XCTAssertEqual(cycle?.cycle.left,playback.loopPCM?.cycle.left)
                } else {XCTAssertNil(cycle)}
            })
            XCTAssertEqual(calls,1)
            let before=try XCTUnwrap(fixture.events.firstIndex(of:"prepared.MAIN"))
            let start=try XCTUnwrap(fixture.events.firstIndex(of:loop ? "loop":"start"))
            XCTAssertLessThan(before,start)
            playback.stop();try await eventually{playback.outputStatus.transport.phase == .idle}
        }
    }
    func testThrowingPreparedCallbackPreventsOutput()async throws {
        struct RecorderFailure:Error {}
        let fixture=PlaybackFixture(),playback=Playback(factory:{TestPlaybackBackend(fixture)})
        var calls=0
        do {
            try await playback.play(audio(),onPrepared:{_ in calls+=1;throw RecorderFailure()})
            XCTFail("Recorder failure started output")
        } catch is RecorderFailure {} catch {throw error}
        XCTAssertEqual(calls,1);XCTAssertFalse(playback.playing)
        XCTAssertTrue(fixture.events.isEmpty,"Backend must remain lazy when recorder creation fails")
        XCTAssertEqual(playback.outputStatus.attempts,0)
    }
    func testPreparedCallbackStopAndTaskCancellationCannotLaunchLateOutput()async throws {
        for cancelTask in [false,true] {
            let fixture=PlaybackFixture(),playback=Playback(factory:{TestPlaybackBackend(fixture)}),input=try audio()
            var calls=0
            let task=Task {
                try await playback.play(input,onPrepared:{_ in
                    calls+=1
                    if cancelTask {withUnsafeCurrentTask{$0?.cancel()}}
                    else {playback.stop()}
                })
            }
            await cancelled(task)
            XCTAssertEqual(calls,1);XCTAssertFalse(playback.playing)
            XCTAssertTrue(fixture.events.isEmpty);XCTAssertEqual(playback.outputStatus.attempts,0)
            // A fresh request starts exactly once; cancelled preparation left no queued start.
            try await playback.play(input)
            XCTAssertEqual(fixture.events.filter{$0=="start"}.count,1)
            playback.stop();try await eventually{playback.outputStatus.transport.phase == .idle}
        }
    }
    func testLoopUsesSingleBackendRunAndMonotonicClock()async throws {
        let fixture=PlaybackFixture(), playback=Playback(factory:{TestPlaybackBackend(fixture)})
        var input=try audio();input.mix=PCM(frames:Int((input.plan.duration*PCM.rate).rounded()))
        try await playback.play(input,loop:true)
        try await eventually{playback.elapsedSeconds>0}
        XCTAssertEqual(playback.elapsedSeconds,0.25)
        XCTAssertEqual(playback.seconds,0.25)
        XCTAssertEqual(fixture.events.filter{$0=="loop"}.count,1)
        XCTAssertFalse(fixture.events.contains("start"))
        playback.stop();XCTAssertEqual(playback.elapsedSeconds,0)
        try await eventually{playback.outputStatus.transport.phase == .idle}
    }
    func testBackendIsLazyAndAllOperationsIncludingReleaseAreOffMain()async throws {
        let fixture=PlaybackFixture()
        var playback:Playback?=Playback(factory:{TestPlaybackBackend(fixture)})
        XCTAssertEqual(playback?.outputStatus.phase,.idle);XCTAssertTrue(fixture.events.isEmpty)
        try await playback!.play(audio(),from:0.1)
        try await eventually{playback!.seconds>0.1}
        XCTAssertEqual(playback!.seconds,0.35,accuracy:0.001)
        playback!.stop();XCTAssertFalse(playback!.playing);XCTAssertEqual(playback!.seconds,0)
        try await eventually{playback!.outputStatus.transport.phase == .idle}
        playback=nil
        try await eventually{fixture.events.contains("deinit")}
        XCTAssertFalse(fixture.events.contains(where:{$0.contains("MAIN")}))
        XCTAssertEqual(fixture.events.filter{$0=="init"}.count,1)
    }
    func testBlockedStartCancelsWithoutBlockingMainOrStartingAnotherBackend()async throws {
        let f=PlaybackFixture(),entered=expectation(description:"start blocked");f.blocked="start";f.onEntered={entered.fulfill()}
        let p=Playback(factory:{TestPlaybackBackend(f)}),a=try audio()
        let first=Task{try await p.play(a)}
        await fulfillment(of:[entered],timeout:2)
        p.stop();XCTAssertFalse(p.playing);XCTAssertEqual(p.seconds,0)
        XCTAssertEqual(p.outputStatus.transport.phase,.stopping)
        do{try await p.play(a);XCTFail("Duplicated a physical start")}catch{XCTAssertTrue(error is PlaybackTransportError)}
        await cancelled(first)
        XCTAssertEqual(f.events.filter{$0=="start"}.count,1)
        f.release.signal();try await eventually{p.outputStatus.transport.phase == .idle}
        XCTAssertFalse(f.events.contains("audible"));XCTAssertFalse(p.playing)
        XCTAssertEqual(f.events.filter{$0=="stop"}.count,1)
    }
    func testStartTimeoutDrainsSameAttemptAndNeverPlaysLate()async throws {
        let f=PlaybackFixture();f.blocked="start"
        let p=Playback(factory:{TestPlaybackBackend(f)})
        do{try await p.start(audio(),timeout:0.06);XCTFail("Expected timeout")}
        catch PlaybackTransportError.timedOut{} catch{throw error}
        XCTAssertEqual(p.outputStatus.transport.phase,.stopping);XCTAssertFalse(p.playing)
        let id=p.outputStatus.transport.id
        f.release.signal();try await eventually{p.outputStatus.transport.phase == .idle}
        XCTAssertEqual(p.outputStatus.transport.id,id);XCTAssertFalse(f.events.contains("audible"))
    }
    func testBlockedClockAndStopKeepSnapshotsResponsive()async throws {
        let f=PlaybackFixture(),entered=expectation(description:"clock blocked");f.blocked="clock";f.onEntered={entered.fulfill()}
        let p=Playback(factory:{TestPlaybackBackend(f)})
        try await p.play(audio());await fulfillment(of:[entered],timeout:2)
        p.stop();XCTAssertFalse(p.playing);XCTAssertEqual(p.seconds,0)
        XCTAssertEqual(p.outputStatus.transport.phase,.stopping)
        f.release.signal();try await eventually{p.outputStatus.transport.phase == .idle}
        XCTAssertEqual(p.seconds,0);XCTAssertFalse(p.playing)
    }
    func testPhysicalStopMustCompleteBeforeRetryAndEngineIsReused()async throws {
        let f=PlaybackFixture(),entered=expectation(description:"stop blocked");entered.assertForOverFulfill=false
        f.blocked="stop";f.onEntered={entered.fulfill()}
        let p=Playback(factory:{TestPlaybackBackend(f)}),a=try audio()
        try await p.play(a);p.stop();await fulfillment(of:[entered],timeout:2)
        do{try await p.play(a);XCTFail("Retry during cleanup succeeded")}catch PlaybackTransportError.busy{}
        f.release.signal();try await eventually{p.outputStatus.transport.phase == .idle}
        try await p.play(a);XCTAssertTrue(p.playing)
        XCTAssertEqual(f.events.filter{$0=="init"}.count,1);XCTAssertEqual(f.events.filter{$0=="device"}.count,1)
        p.stop();f.release.signal();try await eventually{p.outputStatus.transport.phase == .idle}
    }
    func testNaturalCompletionAndOldCallbackCannotStopNewRun()async throws {
        let f=PlaybackFixture(),p=Playback(factory:{TestPlaybackBackend(f)}),a=try audio()
        try await p.play(a);f.complete(0)
        try await eventually{p.outputStatus.transport.phase == .idle};XCTAssertFalse(p.playing)
        try await p.play(a);let id=p.outputStatus.transport.id
        f.complete(0);try await Task.sleep(for:.milliseconds(35))
        XCTAssertTrue(p.playing);XCTAssertEqual(p.outputStatus.transport.id,id)
        f.complete(1);try await eventually{p.outputStatus.transport.phase == .idle}
    }
    func testFailureCleansUpAndIsReportedWithoutFalsePlaying()async throws {
        let f=PlaybackFixture();f.failStart=true
        let p=Playback(factory:{TestPlaybackBackend(f)})
        do{try await p.play(audio());XCTFail("Failure became success")}catch{XCTAssertEqual(error.localizedDescription,"controlled start failure")}
        XCTAssertEqual(p.outputStatus.transport.phase,.failed);XCTAssertFalse(p.playing)
        XCTAssertEqual(f.events.filter{$0=="stop"}.count,1)
    }
    func testInvalidEmptyAndPrecancelledStartsDoNotAcquireOutput()async throws {
        let f=PlaybackFixture(),p=Playback(factory:{TestPlaybackBackend(f)}),a=try audio()
        for position in [Double.nan,Double.infinity,-1] {
            do{try await p.play(a,from:position);XCTFail("Invalid position accepted")}catch PlaybackTransportError.invalidPosition{}
        }
        try await p.play(a,from:2)
        let task=Task{withUnsafeCurrentTask{$0?.cancel()};try await p.play(a)}
        await cancelled(task);XCTAssertTrue(f.events.isEmpty)
    }
}
