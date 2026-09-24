import AVFAudio
import Darwin
import Foundation
import XCTest
import CirclrCore
@testable import CirclrAudio

private final class WorkerFixtureFactory:@unchecked Sendable {
    private let lock=NSLock()
    private var path:URL
    private var backend:InputCaptureWorkerBackend?
    init(_ path:URL){self.path=path}
    func use(_ value:URL){lock.lock();path=value;lock.unlock()}
    var current:InputCaptureWorkerBackend?{lock.lock();defer{lock.unlock()};return backend}
    func make()->AudioCaptureBackend {
        lock.lock();defer{lock.unlock()}
        let next=InputCaptureWorkerBackend(executable:path,stopTimeout:0.2,grace:0.05)
        backend=next;return next
    }
}
private final class WorkerSequence:@unchecked Sendable {
    private let lock=NSLock()
    private var queue:[AudioCaptureBackend]
    init(_ values:[AudioCaptureBackend]){queue=values}
    func make()->AudioCaptureBackend {lock.lock();defer{lock.unlock()};return queue.removeFirst()}
}
private final class WorkerHolder:@unchecked Sendable {
    private let lock=NSLock()
    private var backend:AudioCaptureBackend?
    init(_ backend:AudioCaptureBackend){self.backend=backend}
    func make()->AudioCaptureBackend {lock.lock();defer{lock.unlock()};return backend!}
    func clear(){lock.lock();backend=nil;lock.unlock()}
}
private final class CallbackFirstBackend:InterruptibleAudioCaptureBackend,@unchecked Sendable {
    private let lock=NSLock(),gate=DispatchSemaphore(value:0)
    private var ended=false,called=false,callback:(@Sendable ()->Void)?
    var callbackInvoked:Bool{lock.lock();defer{lock.unlock()};return called}
    var reaped:Bool{lock.lock();defer{lock.unlock()};return ended}
    var telemetry=InputCaptureTelemetry()
    func takePeak()->Float{0}
    func onDelayedReap(_ value:@escaping @Sendable ()->Void){lock.lock();callback=value;lock.unlock()}
    func start(to:URL,maximumSeconds:Double,control:CaptureControl)throws->CaptureFormat {
        gate.wait();throw CancellationError()
    }
    func cancel(){gate.signal()}
    func stop()throws->CapturedAudio? {
        lock.lock();ended=true;called=true;let value=callback;lock.unlock()
        value?() // deliberately enqueue reap callback before finish reply
        Thread.sleep(forTimeInterval:0.1)
        return nil
    }
}

@MainActor final class InputCaptureWorkerTests:XCTestCase {
    private func root()throws->URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-input-test-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false)
        return url
    }
    private func fixture(_ root:URL)throws->URL {
        let url=root.appendingPathComponent("fixture.caf")
        let format=try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate:48000,channels:2))
        let buffer=try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1000))
        buffer.frameLength=1000
        for index in 0..<1000 {buffer.floatChannelData![0][index]=0.1;buffer.floatChannelData![1][index]=0.2}
        let file=try AVAudioFile(forWriting:url,settings:format.settings)
        try file.write(from:buffer)
        return url
    }
    private func script(_ root:URL,mode:String,fixture:URL?=nil)->URL {
        let url=root.appendingPathComponent("fixture-worker.py")
        let fixturePath=fixture?.path ?? ""
        let source="""
        #!/usr/bin/python3
        import json, os, shutil, signal, sys, time
        mode = \(String(reflecting:mode))
        fixture = \(String(reflecting:fixturePath))
        pidfile = \(String(reflecting:root.appendingPathComponent("pid").path))
        with open(pidfile, 'w') as f: f.write(str(os.getpid()))
        def send(kind, request, **kw):
            value = dict(version=1, session=request['session'], kind=kind, directory=None, maximumSeconds=None,
                         sampleRate=None, channels=None, frames=None, peak=None, reachedLimit=None, interrupted=None, error=None)
            value.update(kw)
            sys.stdout.write(json.dumps(value) + '\\n'); sys.stdout.flush()
        request = json.loads(sys.stdin.readline())
        if mode == 'crash-start': os._exit(7)
        if mode == 'hang-start':
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            while True: time.sleep(1)
        if mode == 'late-start':
            def late(sig, frame): send('started', request, sampleRate=48000, channels=2)
            signal.signal(signal.SIGTERM, late)
            while True: time.sleep(1)
        if mode == 'oversized':
            sys.stdout.write('x' * 5000 + '\\n'); sys.stdout.flush()
            while True: time.sleep(1)
        if mode == 'wrong-session': request['session'] = '00000000-0000-0000-0000-000000000000'
        send('started', request, sampleRate=48000, channels=2)
        if mode == 'crash-after-start': os._exit(7)
        if mode == 'wrong-session':
            while True: time.sleep(1)
        send('progress', request, frames=(0 if mode == 'empty' else 500), peak=(0 if mode == 'empty' else 0.2), reachedLimit=(mode != 'empty'), interrupted=(mode != 'empty'))
        stop = json.loads(sys.stdin.readline())
        if mode == 'hang-stop':
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            while True: time.sleep(1)
        if mode != 'empty': shutil.copyfile(fixture, os.path.join(request['directory'], 'take.caf'))
        if mode == 'bad-file':
            send('finished', request, sampleRate=48000, channels=2, frames=2000)
        else:
            send('finished', request, sampleRate=48000, channels=2, frames=(0 if mode == 'empty' else 1000))
        if mode == 'late-progress':
            send('progress', request, frames=1000, peak=0.1, reachedLimit=True, interrupted=True)
            time.sleep(0.1)
        """
        try! source.write(to:url,atomically:true,encoding:.utf8)
        try! FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:url.path)
        return url
    }
    private func until(_ condition:@escaping ()->Bool,seconds:Double=2)async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+seconds
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime<deadline else{throw CirclrError("입력 worker 테스트 대기 시간 초과")}
            try await Task.sleep(for:.milliseconds(10))
        }
    }
    private func dead(_ pid:Int32)->Bool {Darwin.kill(pid,0) != 0 && errno==ESRCH}

    func testHungStartCancellationReapsPIDAndAllowsFreshRetry()async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let hanging=script(root,mode:"hang-start")
        let factory=WorkerFixtureFactory(hanging),recorder=AudioRecorder(factory:{factory.make()})
        let destination=root.appendingPathComponent("output.caf")
        var completions=0
        try recorder.start(to:destination,maximumSeconds:2,timeout:0.1){_ in completions+=1}
        try await until{factory.current?.childPID != nil}
        let pid=try XCTUnwrap(factory.current?.childPID)
        try await until{completions==1 && !recorder.busy}
        XCTAssertEqual(completions,1);XCTAssertTrue(dead(pid));XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path))
        let good=script(root,mode:"success",fixture:try fixture(root))
        factory.use(good)
        try await withCheckedThrowingContinuation {(reply:CheckedContinuation<Void,Error>) in
            do {try recorder.start(to:destination,maximumSeconds:2){result in reply.resume(with:result.map{_ in ()})}}
            catch {reply.resume(throwing:error)}
        }
        let captured=try await withCheckedThrowingContinuation {(reply:CheckedContinuation<CapturedAudio?,Error>) in recorder.stop{reply.resume(with:$0)}}
        XCTAssertEqual(captured?.frames,1000);XCTAssertFalse(recorder.busy)
    }
    func testLateStartedAfterTimeoutCannotReactivateOrPublish()async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let late=script(root,mode:"late-start")
        let factory=WorkerFixtureFactory(late),recorder=AudioRecorder(factory:{factory.make()})
        let destination=root.appendingPathComponent("late.caf")
        var completions=0,successes=0
        try recorder.start(to:destination,maximumSeconds:2,timeout:0.1){result in
            completions+=1;if case .success=result{successes+=1}
        }
        try await until{factory.current?.childPID != nil}
        let pid=try XCTUnwrap(factory.current?.childPID)
        try await until{completions==1 && !recorder.busy}
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertEqual(completions,1);XCTAssertEqual(successes,0)
        XCTAssertFalse(recorder.recording);XCTAssertTrue(dead(pid))
        XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path))
        factory.use(script(root,mode:"success",fixture:try fixture(root)))
        try await withCheckedThrowingContinuation {(reply:CheckedContinuation<Void,Error>) in
            do {try recorder.start(to:destination,maximumSeconds:2){reply.resume(with:$0.map{_ in ()})}}
            catch {reply.resume(throwing:error)}
        }
        let result=try await withCheckedThrowingContinuation {(reply:CheckedContinuation<CapturedAudio?,Error>) in recorder.stop{reply.resume(with:$0)}}
        XCTAssertEqual(result?.frames,1000)
    }
    func testSuccessfulCAFProgressAndStopRetry()async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let worker=script(root,mode:"success",fixture:try fixture(root))
        for iteration in 0..<2 {
            let destination=root.appendingPathComponent("take-\(iteration).caf")
            let backend=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.3,grace:0.05)
            let control=try CaptureControl()
            let format=try await Task.detached{try backend.start(to:destination,maximumSeconds:2,control:control)}.value
            XCTAssertEqual(format,CaptureFormat(sampleRate:48000,channels:2))
            try await until{backend.telemetry.frames==500}
            XCTAssertEqual(backend.takePeak(),0.2,accuracy:0.0001)
            XCTAssertEqual(backend.takePeak(),0)
            XCTAssertTrue(backend.telemetry.reachedLimit);XCTAssertTrue(backend.telemetry.interrupted)
            let pid=try XCTUnwrap(backend.childPID)
            let result=try await Task.detached{try backend.stop()}.value
            XCTAssertEqual(result?.frames,1000);XCTAssertTrue(backend.reaped);XCTAssertTrue(dead(pid))
            let pcm=try PCM.read(destination);XCTAssertEqual(pcm.left[100],0.1,accuracy:0.0001)
        }
    }
    func testHungStopAndMalformedResponsesNeverCommit()async throws {
        for mode in ["hang-stop","wrong-session","oversized","bad-file","empty"] {
            let root=try root();defer{try? FileManager.default.removeItem(at:root)}
            let worker=script(root,mode:mode,fixture:try fixture(root))
            let destination=root.appendingPathComponent("take.caf")
            let backend=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.15,grace:0.05)
            let control=try CaptureControl()
            if mode == "wrong-session" || mode == "oversized" {
                do {_ = try await Task.detached{try backend.start(to:destination,maximumSeconds:2,control:control)}.value
                    XCTFail("Invalid response started capture: \(mode)")
                }catch {
                    let expected=mode == "wrong-session" ? "세션" : "너무 큽니다"
                    XCTAssertTrue(error.localizedDescription.contains(expected),"\(mode): \(error)")
                }
            }else{
                _ = try await Task.detached{try backend.start(to:destination,maximumSeconds:2,control:control)}.value
                if mode == "empty" {
                    let result=try await Task.detached{try backend.stop()}.value
                    XCTAssertNil(result)
                }else{
                    do {_ = try await Task.detached{try backend.stop()}.value
                        XCTFail("Expected rejected capture: \(mode)")
                    }catch {
                        let expected=mode == "hang-stop" ? "제한 시간" : "CAF의 프레임"
                        XCTAssertTrue(error.localizedDescription.contains(expected),"\(mode): \(error)")
                    }
                }
            }
            XCTAssertTrue(backend.reaped,mode)
            if let pid=backend.childPID{XCTAssertTrue(dead(pid),mode)}
            XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path),mode)
        }
    }
    func testCrashBeforeAndAfterStartStillOwnsReap()async throws {
        for mode in ["crash-start","crash-after-start"] {
            let root=try root();defer{try? FileManager.default.removeItem(at:root)}
            let worker=script(root,mode:mode)
            let destination=root.appendingPathComponent("take.caf")
            let backend=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.1,grace:0.05)
            let control=try CaptureControl()
            if mode == "crash-start" {
                do {_ = try await Task.detached{try backend.start(to:destination,maximumSeconds:2,control:control)}.value
                    XCTFail("Crash returned started")
                }catch {XCTAssertFalse(error is CancellationError)}
            }else{
                _ = try await Task.detached{try backend.start(to:destination,maximumSeconds:2,control:control)}.value
                try await Task.sleep(for:.milliseconds(30))
                backend.cancel()
                _ = try await Task.detached{try backend.stop()}.value
            }
            XCTAssertTrue(backend.reaped)
            if let pid=backend.childPID{XCTAssertTrue(dead(pid))}
            XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path))
        }
    }
    func testMeterAfterFinishedDoesNotRejectValidatedCAF()async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let worker=script(root,mode:"late-progress",fixture:try fixture(root))
        let backend=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.4,grace:0.2)
        let control=try CaptureControl(),destination=root.appendingPathComponent("take.caf")
        _ = try await Task.detached{try backend.start(to:destination,maximumSeconds:2,control:control)}.value
        let result=try await Task.detached{try backend.stop()}.value
        XCTAssertEqual(result?.frames,1000);XCTAssertTrue(backend.reaped)
        XCTAssertTrue(FileManager.default.fileExists(atPath:destination.path))
    }
    func testDelayedReapKeepsBusyThenClearsAndAllowsSameRecorderRetry()async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let hanging=script(root,mode:"hang-start")
        let hangingCopy=root.appendingPathComponent("hung-worker.py")
        try FileManager.default.copyItem(at:hanging,to:hangingCopy)
        let deadline=ProcessInfo.processInfo.systemUptime+2.3
        let first=InputCaptureWorkerBackend(executable:hangingCopy,stopTimeout:0.1,grace:0.05,reapProbe:{pid in
            if ProcessInfo.processInfo.systemUptime<deadline{return 0}
            return Darwin.waitpid(pid,nil,WNOHANG)
        })
        let good=script(root,mode:"success",fixture:try fixture(root))
        // The first worker path is copied before the script is replaced.
        let goodCopy=root.appendingPathComponent("good-worker.py")
        try FileManager.default.copyItem(at:good,to:goodCopy)
        let sequence=WorkerSequence([first,InputCaptureWorkerBackend(executable:goodCopy,stopTimeout:0.2,grace:0.05)])
        let recorder=AudioRecorder(factory:{sequence.make()})
        let destination=root.appendingPathComponent("take.caf")
        var completions=0
        try recorder.start(to:destination,maximumSeconds:2,timeout:0.05){_ in completions+=1}
        try await until{first.childPID != nil}
        let pid=try XCTUnwrap(first.childPID)
        try await until({recorder.phase == .failed && recorder.busy && completions==1},seconds:2)
        XCTAssertFalse(first.reaped);XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path))
        try await until({!recorder.busy},seconds:4)
        XCTAssertTrue(first.reaped);XCTAssertTrue(dead(pid));XCTAssertEqual(completions,1)
        try await withCheckedThrowingContinuation {(reply:CheckedContinuation<Void,Error>) in
            do {try recorder.start(to:destination,maximumSeconds:2){reply.resume(with:$0.map{_ in ()})}}
            catch {reply.resume(throwing:error)}
        }
        let take=try await withCheckedThrowingContinuation {(reply:CheckedContinuation<CapturedAudio?,Error>) in recorder.stop{reply.resume(with:$0)}}
        XCTAssertEqual(take?.frames,1000)
    }
    func testPublishWillNotOverwriteAndCancelBeforeRenameKeepsDestinationAbsent()async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let worker=script(root,mode:"success",fixture:try fixture(root))
        let existing=root.appendingPathComponent("existing.caf")
        try Data("original".utf8).write(to:existing)
        let first=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.2,grace:0.05)
        let control=try CaptureControl()
        _ = try await Task.detached{try first.start(to:existing,maximumSeconds:2,control:control)}.value
        do {_ = try await Task.detached{try first.stop()}.value;XCTFail("Existing take overwritten")}
        catch {XCTAssertTrue(error.localizedDescription.contains("이미 있습니다"))}
        XCTAssertEqual(try Data(contentsOf:existing),Data("original".utf8))
        let entered=DispatchSemaphore(value:0),gate=DispatchSemaphore(value:0)
        defer{gate.signal()}
        let target=root.appendingPathComponent("cancelled.caf")
        let second=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.2,grace:0.05,beforePublishRename:{entered.signal();gate.wait()})
        let next=try CaptureControl()
        _ = try await Task.detached{try second.start(to:target,maximumSeconds:2,control:next)}.value
        let stop=Task.detached{try second.stop()}
        try await until{entered.wait(timeout:.now()) == .success}
        second.cancel();gate.signal()
        do {_ = try await stop.value;XCTFail("Cancelled take published")}
        catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        XCTAssertTrue(second.reaped)
    }
    func testDelayedReaperRetainsPIDOwnershipAfterRecorderIsReleased()async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let worker=script(root,mode:"hang-start")
        let deadline=ProcessInfo.processInfo.systemUptime+2.3
        var backend:InputCaptureWorkerBackend?=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.1,grace:0.05,reapProbe:{pid in
            if ProcessInfo.processInfo.systemUptime<deadline{return 0}
            return Darwin.waitpid(pid,nil,WNOHANG)
        })
        weak let released=backend
        let holder=WorkerHolder(backend!)
        var recorder:AudioRecorder?=AudioRecorder(factory:{holder.make()})
        let destination=root.appendingPathComponent("take.caf")
        try recorder!.start(to:destination,maximumSeconds:2,timeout:0.05){_ in}
        try await until{backend?.childPID != nil}
        let pid=try XCTUnwrap(backend?.childPID)
        try await until({recorder?.phase == .failed && recorder?.busy == true},seconds:2)
        recorder=nil;holder.clear();backend=nil
        try await until({released == nil},seconds:4)
        XCTAssertTrue(dead(pid))
        XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path))
    }
    func testReapCallbackBeforeFinishReplyDoesNotLoseBusyCleanup()async throws {
        let backend=CallbackFirstBackend(),recorder=AudioRecorder(factory:{backend})
        let destination=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-callback-order-"+UUID().uuidString+".caf")
        var completions=0
        try recorder.start(to:destination,maximumSeconds:2,timeout:0.05){_ in completions+=1}
        try await until{backend.callbackInvoked}
        XCTAssertTrue(recorder.busy)
        try await until{!recorder.busy}
        XCTAssertEqual(completions,1);XCTAssertEqual(recorder.phase,.failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path))
    }
}
