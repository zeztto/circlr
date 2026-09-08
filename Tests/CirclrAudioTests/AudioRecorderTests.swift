import XCTest
import AVFAudio
import CirclrCore
@testable import CirclrAudio

private final class DelayedCapture:AudioCaptureBackend,@unchecked Sendable {
    let entered:XCTestExpectation?
    let startGate:DispatchSemaphore?,stopGate:DispatchSemaphore?
    let failsStart:Bool,failsStop:Bool
    private let lock=NSLock()
    private var starts=0,stops=0,control:CaptureControl?
    init(entered:XCTestExpectation?=nil,startGate:DispatchSemaphore?=nil,stopGate:DispatchSemaphore?=nil,failsStart:Bool=false,failsStop:Bool=false){self.entered=entered;self.startGate=startGate;self.stopGate=stopGate;self.failsStart=failsStart;self.failsStop=failsStop}
    var counts:(Int,Int){lock.withLock{(starts,stops)}}
    func interrupt(){lock.withLock{control?.interrupt()}}
    var collecting:Bool {lock.withLock{control?.enabled ?? false}}
    func start(to:URL,maximumSeconds:Double,control:CaptureControl)throws->CaptureFormat {
        XCTAssertFalse(Thread.isMainThread)
        let first=lock.withLock{starts+=1;self.control=control;return starts==1}
        if first {entered?.fulfill();startGate?.wait()}
        if failsStart && first {throw CirclrError("입력 시작 실패")}
        return CaptureFormat(sampleRate:48000,channels:2)
    }
    func stop()throws->CapturedAudio? {
        XCTAssertFalse(Thread.isMainThread);lock.withLock{stops+=1};stopGate?.wait()
        if failsStop {throw CirclrError("녹음 파일 마무리 실패")}
        return CapturedAudio(url:URL(fileURLWithPath:"/tmp/circlr-capture-fixture.caf"),format:CaptureFormat(sampleRate:48000,channels:2),frames:96000)
    }
}

@MainActor final class AudioRecorderTests:XCTestCase {
    let url=URL(fileURLWithPath:"/tmp/circlr-capture-fixture.caf")
    func until(_ condition:@escaping ()->Bool)async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while !condition() {guard ProcessInfo.processInfo.systemUptime<deadline else{throw CirclrError("조건 대기 시간 초과")};try await Task.sleep(for:.milliseconds(5))}
    }
    func start(_ recorder:AudioRecorder)async throws->CaptureFormat {
        try await withCheckedThrowingContinuation {reply in
            do {try recorder.start(to:url,maximumSeconds:2){reply.resume(with:$0)}}catch{reply.resume(throwing:error)}
        }
    }
    func stop(_ recorder:AudioRecorder)async throws->CapturedAudio? {
        try await withCheckedThrowingContinuation{reply in recorder.stop{reply.resume(with:$0)}}
    }
    func testCancelledSlowStartRejectsDuplicateAndCleansBeforeRetry()async throws {
        let entered=expectation(description:"worker entered"),gate=DispatchSemaphore(value:0),backend=DelayedCapture(entered:entered,startGate:gate),recorder=AudioRecorder(factory:{backend})
        var cancelled=false;try recorder.start(to:url,maximumSeconds:2){if case .failure(let e)=$0{cancelled=e is CancellationError}}
        await fulfillment(of:[entered],timeout:1)
        XCTAssertThrowsError(try recorder.start(to:url,maximumSeconds:2){_ in})
        recorder.cancelStart();XCTAssertTrue(cancelled);XCTAssertFalse(backend.collecting);XCTAssertEqual(recorder.phase,.cancelling);XCTAssertTrue(recorder.busy)
        gate.signal();try await until{!recorder.busy};XCTAssertEqual(backend.counts.1,1);XCTAssertEqual(recorder.phase,.idle)
        let format=try await start(recorder);XCTAssertEqual(format.channels,2);XCTAssertEqual(recorder.phase,.recording)
        let audio=try await stop(recorder);XCTAssertEqual(audio?.frames,96000);XCTAssertEqual(backend.counts.1,2)
    }
    func testTimeoutDisablesLateStartWithoutBlockingMainActor()async throws {
        let entered=expectation(description:"worker entered"),gate=DispatchSemaphore(value:0),backend=DelayedCapture(entered:entered,startGate:gate),recorder=AudioRecorder(factory:{backend})
        var failed=false;try recorder.start(to:url,maximumSeconds:2,timeout:0.05){if case .failure=$0{failed=true}}
        await fulfillment(of:[entered],timeout:1);try await until{failed}
        XCTAssertEqual(recorder.phase,.cancelling);XCTAssertFalse(backend.collecting);XCTAssertTrue(recorder.busy)
        gate.signal();try await until{!recorder.busy};XCTAssertEqual(recorder.phase,.failed);XCTAssertEqual(backend.counts.1,1)
    }
    func testStartFailureCleansAndAllowsRetry()async throws {
        let backend=DelayedCapture(failsStart:true),recorder=AudioRecorder(factory:{backend})
        do {_=try await start(recorder);XCTFail("Expected failure")}catch{}
        XCTAssertEqual(recorder.phase,.failed);XCTAssertFalse(recorder.busy);XCTAssertEqual(backend.counts.1,1)
        _=try await start(recorder);XCTAssertTrue(recorder.recording);_=try await stop(recorder)
    }
    func testSlowFinishClosesGateImmediatelyAndKeepsMainResponsive()async throws {
        let gate=DispatchSemaphore(value:0),backend=DelayedCapture(stopGate:gate),recorder=AudioRecorder(factory:{backend})
        _=try await start(recorder);var completed=false
        recorder.stop{if case .success=$0{completed=true}}
        XCTAssertEqual(recorder.phase,.finishing);XCTAssertFalse(backend.collecting)
        try await Task.sleep(for:.milliseconds(20));XCTAssertFalse(completed);XCTAssertTrue(recorder.busy)
        XCTAssertThrowsError(try recorder.start(to:url,maximumSeconds:2){_ in})
        gate.signal();try await until{completed};XCTAssertFalse(recorder.busy);XCTAssertEqual(recorder.phase,.idle)
    }
    func testFinishErrorIsVisibleAndReleasesAttempt()async throws {
        let backend=DelayedCapture(failsStop:true),recorder=AudioRecorder(factory:{backend});_=try await start(recorder)
        do {_=try await stop(recorder);XCTFail("Expected failure")}catch{}
        XCTAssertEqual(recorder.phase,.failed);XCTAssertFalse(recorder.busy);XCTAssertTrue(recorder.message.contains("마무리 실패"))
    }
    func testFrameLimitMeterAndLargeMultichannelInputPreserveFirstTwoChannels()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-capture-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let layout=try XCTUnwrap(AVAudioChannelLayout(layoutTag:kAudioChannelLayoutTag_DiscreteInOrder | 6))
        let input=AVAudioFormat(standardFormatWithSampleRate:48000,channelLayout:layout),format=try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate:48000,channels:2))
        let buffer=AVAudioPCMBuffer(pcmFormat:input,frameCapacity:12000)!;buffer.frameLength=12000
        for c in 0..<6 {for i in 0..<12000 {buffer.floatChannelData![c][i]=Float(c+1)/10}}
        let writer=try TakeWriter(url:root.appendingPathComponent("take.caf"),format:format),control=try CaptureControl()
        control.limit(frames:10000);control.append(buffer,to:writer,channels:2);control.append(buffer,to:writer,channels:2)
        XCTAssertEqual(control.frames,10000);XCTAssertTrue(control.reachedLimit);XCTAssertEqual(control.takePeak(),0.2,accuracy:1e-6);XCTAssertEqual(control.takePeak(),0)
        control.disable();control.append(buffer,to:writer,channels:2);control.waitForCallbacks();try writer.finish()
        XCTAssertEqual(writer.frames,10000);let file=try AVAudioFile(forReading:writer.url);XCTAssertEqual(file.processingFormat.channelCount,2)
        let audio=try PCM.read(writer.url);XCTAssertEqual(audio.count,10000);XCTAssertEqual(audio.left[9000],0.1,accuracy:1e-6);XCTAssertEqual(audio.right[9000],0.2,accuracy:1e-6)
    }
    func testInputInterruptionClosesGateAndAllowsFinalization()async throws {
        let backend=DelayedCapture(),recorder=AudioRecorder(factory:{backend});_=try await start(recorder)
        backend.interrupt();XCTAssertTrue(recorder.interrupted);XCTAssertFalse(backend.collecting)
        let audio=try await stop(recorder);XCTAssertEqual(audio?.duration,2);XCTAssertFalse(recorder.busy)
    }
    func testReleasingRecorderClosesGateAndCleansOnWorker()async throws {
        let backend=DelayedCapture();var recorder:AudioRecorder?=AudioRecorder(factory:{backend})
        _=try await start(recorder!);recorder=nil
        XCTAssertFalse(backend.collecting);try await until{backend.counts.1==1}
    }
    func testCancelledControlNeverAcceptsInput()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-cancel-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let buffer=try PCM(frames:1024).buffer(),writer=try TakeWriter(url:root.appendingPathComponent("empty.caf"),format:buffer.format),control=try CaptureControl()
        control.disable();control.append(buffer,to:writer,channels:2);try writer.finish();XCTAssertEqual(control.frames,0);XCTAssertEqual(writer.frames,0)
    }
}
