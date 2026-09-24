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
        if mode == 'catalog-ok':
            if request.get('kind') != 'catalog': os._exit(8)
            send('catalogDevice', request, device=dict(uid='fixture-input-uid', name='Fixture Mic', isDefault=False))
            send('catalogDevice', request, device=dict(uid='default-mic', name='Default Mic', isDefault=True))
            send('catalogFinished', request)
            sys.exit(0)
        if mode == 'catalog-duplicate':
            send('catalogDevice', request, device=dict(uid='same', name='Mic A', isDefault=False))
            send('catalogDevice', request, device=dict(uid='same', name='Mic B', isDefault=False))
            send('catalogFinished', request)
            sys.exit(0)
        if mode == 'catalog-hang':
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            while True: time.sleep(1)
        if mode == 'selected-request':
            if request.get('deviceUID') != 'fixture-input-uid': os._exit(8)
        if mode == 'default-request':
            if request.get('deviceUID') is not None: os._exit(8)
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
        echoed_uid = request.get('deviceUID')
        if mode == 'selected-no-echo': echoed_uid = None
        if mode == 'selected-wrong-echo': echoed_uid = 'different-input-uid'
        send('started', request, sampleRate=48000, channels=2, deviceUID=echoed_uid)
        if mode == 'crash-after-start': os._exit(7)
        if mode == 'wrong-session':
            while True: time.sleep(1)
        progress_frames = 1500 if mode == 'recover-shorter' else (0 if mode == 'empty' else 500)
        send('progress', request, frames=progress_frames, peak=(0 if mode == 'empty' else 0.2), reachedLimit=(mode != 'empty'), interrupted=(mode != 'empty'))
        stop = json.loads(sys.stdin.readline())
        if mode == 'hang-stop':
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            while True: time.sleep(1)
        if mode != 'empty' and mode != 'recover-empty': shutil.copyfile(fixture, os.path.join(request['directory'], 'take.caf'))
        if mode == 'selected-uid-changed-stop':
            send('failed', request, error='입력 장치가 변경되었습니다')
        elif mode == 'recover-stop' or mode == 'recover-shorter':
            send('finished', request, sampleRate=48000, channels=2, frames=1000, error='입력 장치가 연결 해제되었습니다')
        elif mode == 'recover-bad-file':
            send('finished', request, sampleRate=48000, channels=2, frames=2000, error='입력 장치가 연결 해제되었습니다')
        elif mode == 'recover-empty':
            send('finished', request, sampleRate=48000, channels=2, frames=0, error='입력 장치가 연결 해제되었습니다')
        elif mode == 'bad-file':
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

    func testWorkerStartSelectionDecodeFailsClosed() throws {
        let session=UUID()
        let defaultStart=InputCaptureWorkerMessage(session:session,kind:.start)
        XCTAssertEqual(try InputCaptureWorkerWire.checkedSelection(defaultStart),.systemDefault)
        let selected=InputCaptureWorkerMessage(session:session,kind:.start,deviceUID:"input-a")
        XCTAssertEqual(try InputCaptureWorkerWire.checkedSelection(selected),.deviceUID("input-a"))
        let decoded=try InputCaptureWorkerWire.decode(Data(try InputCaptureWorkerWire.encode(selected).dropLast()))
        XCTAssertEqual(try InputCaptureWorkerWire.checkedSelection(decoded),.deviceUID("input-a"))
        for uid in ["", "bad\nuid",String(repeating:"x",count:1025)] {
            let invalid=InputCaptureWorkerMessage(session:session,kind:.start,deviceUID:uid)
            XCTAssertThrowsError(try InputCaptureWorkerWire.checkedSelection(invalid)) {
                XCTAssertEqual($0 as? InputDeviceBindingError,.invalidSelection)
            }
        }
    }

    func testSelectedUIDCrossesOnlyChildStartWireAndValidatesBeforeLaunch() async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let worker=script(root,mode:"selected-request",fixture:try fixture(root))
        let target=root.appendingPathComponent("selected.caf")
        let backend=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.3,grace:0.05,
            selection:.deviceUID("fixture-input-uid"))
        let control=try CaptureControl()
        let format=try await Task.detached{try backend.start(to:target,maximumSeconds:2,control:control)}.value
        XCTAssertEqual(format,CaptureFormat(sampleRate:48000,channels:2))
        let take=try await Task.detached{try backend.stop()}.value
        XCTAssertEqual(take?.frames,1000)
        XCTAssertTrue(backend.reaped)

        let invalid=InputCaptureWorkerBackend(executable:worker,selection:.deviceUID("bad\nuid"))
        do {_ = try await Task.detached{try invalid.start(to:root.appendingPathComponent("invalid.caf"),maximumSeconds:2,control:try CaptureControl())}.value
            XCTFail("Invalid UID reached worker")
        }catch {XCTAssertEqual(error as? InputDeviceBindingError,.invalidSelection)}
        XCTAssertNil(invalid.childPID)
    }

    func testDefaultStartWireContainsNoSelectedUID() async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let worker=script(root,mode:"default-request",fixture:try fixture(root))
        let backend=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.3,grace:0.05)
        let target=root.appendingPathComponent("default.caf")
        _ = try await Task.detached{try backend.start(to:target,maximumSeconds:2,control:try CaptureControl())}.value
        let take=try await Task.detached{try backend.stop()}.value
        XCTAssertEqual(take?.frames,1000)
    }

    func testSelectedInputRejectsOlderOrMismatchedWorkerEchoWithoutPublishing() async throws {
        for mode in ["selected-no-echo","selected-wrong-echo"] {
            let root=try root();defer{try? FileManager.default.removeItem(at:root)}
            let worker=script(root,mode:mode,fixture:try fixture(root))
            let target=root.appendingPathComponent("wrong-input.caf")
            let backend=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.2,grace:0.05,
                selection:.deviceUID("fixture-input-uid"))
            do {_ = try await Task.detached{try backend.start(to:target,maximumSeconds:2,control:try CaptureControl())}.value
                XCTFail("Worker without matching UID echo started selected capture: \(mode)")
            }catch {XCTAssertTrue(error.localizedDescription.contains("시작 응답"),"\(mode): \(error)")}
            XCTAssertTrue(backend.reaped)
            XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        }
    }

    func testSelectedStopErrorPublishesValidatedRecoveryThenReturnsFailure() async throws {
        for mode in ["recover-stop","recover-shorter"] {
            let root=try root();defer{try? FileManager.default.removeItem(at:root)}
            let worker=script(root,mode:mode,fixture:try fixture(root))
            let target=root.appendingPathComponent("recover.caf")
            let backend=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.3,grace:0.05,
                selection:.deviceUID("fixture-input-uid"))
            _ = try await Task.detached{try backend.start(to:target,maximumSeconds:2,control:try CaptureControl())}.value
            do {_ = try await Task.detached{try backend.stop()}.value;XCTFail("Recovery must report stop failure")}
            catch {XCTAssertTrue(error.localizedDescription.contains("복구 저장"))}
            XCTAssertTrue(backend.reaped)
            XCTAssertEqual(try PCM.read(target).count,1000)
        }
    }

    func testSelectedRecoveryRejectsUIDChangeEmptyAndInvalidCAF() async throws {
        for mode in ["selected-uid-changed-stop","recover-empty","recover-bad-file"] {
            let root=try root();defer{try? FileManager.default.removeItem(at:root)}
            let worker=script(root,mode:mode,fixture:try fixture(root))
            let target=root.appendingPathComponent("rejected.caf")
            let backend=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.2,grace:0.05,
                selection:.deviceUID("fixture-input-uid"))
            _ = try await Task.detached{try backend.start(to:target,maximumSeconds:2,control:try CaptureControl())}.value
            do {_ = try await Task.detached{try backend.stop()}.value;XCTFail("Invalid recovery accepted: \(mode)")}
            catch {XCTAssertFalse(error.localizedDescription.contains("복구 저장"),"\(mode)")}
            XCTAssertTrue(backend.reaped,mode)
            XCTAssertFalse(FileManager.default.fileExists(atPath:target.path),mode)
        }
    }

    func testSelectedRecoveryWillNotOverwriteOrPublishAfterCancel() async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let worker=script(root,mode:"recover-stop",fixture:try fixture(root))
        let existing=root.appendingPathComponent("existing.caf")
        try Data("original".utf8).write(to:existing)
        let first=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.3,grace:0.05,
            selection:.deviceUID("fixture-input-uid"))
        _ = try await Task.detached{try first.start(to:existing,maximumSeconds:2,control:try CaptureControl())}.value
        do {_ = try await Task.detached{try first.stop()}.value;XCTFail("Recovery overwrote an existing take")}
        catch {XCTAssertTrue(error.localizedDescription.contains("이미 있습니다"))}
        XCTAssertEqual(try Data(contentsOf:existing),Data("original".utf8))

        let entered=DispatchSemaphore(value:0),gate=DispatchSemaphore(value:0)
        defer{gate.signal()}
        let target=root.appendingPathComponent("cancelled-recovery.caf")
        let second=InputCaptureWorkerBackend(executable:worker,stopTimeout:0.3,grace:0.05,
            selection:.deviceUID("fixture-input-uid"),beforePublishRename:{entered.signal();gate.wait()})
        _ = try await Task.detached{try second.start(to:target,maximumSeconds:2,control:try CaptureControl())}.value
        let stop=Task.detached{try second.stop()}
        try await until{entered.wait(timeout:.now()) == .success}
        second.cancel();gate.signal()
        do {_ = try await stop.value;XCTFail("Cancelled recovery was published")}
        catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        XCTAssertTrue(second.reaped)
    }

    func testIsolatedCatalogReturnsValidatedDevicesAndReapsHelper() async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let worker=script(root,mode:"catalog-ok")
        let devices=try await IsolatedInputDeviceCatalog.available(executable:worker,timeout:1)
        XCTAssertEqual(devices,[InputDeviceDescriptor(uid:"fixture-input-uid",name:"Fixture Mic",isDefault:false),
                                InputDeviceDescriptor(uid:"default-mic",name:"Default Mic",isDefault:true)])
        if let raw=try? String(contentsOf:root.appendingPathComponent("pid"),encoding:.utf8),let pid=Int32(raw) {
            XCTAssertTrue(dead(pid))
        }else{XCTFail("Catalog child PID was not recorded")}
    }

    func testIsolatedCatalogRejectsDuplicateAndTimesOutHungHelper() async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        do {_ = try await IsolatedInputDeviceCatalog.available(executable:script(root,mode:"catalog-duplicate"),timeout:1)
            XCTFail("Duplicate UID accepted")
        }catch {XCTAssertTrue(error.localizedDescription.contains("목록"))}
        do {_ = try await IsolatedInputDeviceCatalog.available(executable:script(root,mode:"catalog-hang"),timeout:0.1)
            XCTFail("Hung catalog accepted")
        }catch {XCTAssertTrue(error.localizedDescription.contains("제한 시간"))}
        let raw=try String(contentsOf:root.appendingPathComponent("pid"),encoding:.utf8)
        let pid=try XCTUnwrap(Int32(raw))
        try await until{self.dead(pid)}
    }

    func testIsolatedCatalogCancellationTerminatesChild() async throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let worker=script(root,mode:"catalog-hang")
        let query=Task{try await IsolatedInputDeviceCatalog.available(executable:worker,timeout:5)}
        try await until{FileManager.default.fileExists(atPath:root.appendingPathComponent("pid").path)}
        query.cancel()
        do {_ = try await query.value;XCTFail("Cancelled catalog returned")}
        catch {XCTAssertTrue(error is CancellationError)}
        let raw=try String(contentsOf:root.appendingPathComponent("pid"),encoding:.utf8)
        let pid=try XCTUnwrap(Int32(raw))
        try await until{self.dead(pid)}
    }

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
