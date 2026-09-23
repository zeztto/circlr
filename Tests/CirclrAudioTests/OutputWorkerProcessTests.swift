import XCTest
import Darwin
@testable import CirclrAudio
import CirclrCore

@MainActor final class OutputWorkerProcessTests: XCTestCase {
    private var scripts: [URL] = []
    override func tearDown() {
        for path in scripts { try? FileManager.default.removeItem(at: path) }
        scripts = []
    }
    private func fixture(_ mode: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-worker-test-" + UUID().uuidString)
        let source = #"""
#!/usr/bin/python3
import sys,json,time,os,signal
mode = "MODE"
session=sys.argv[2];directory=sys.argv[4];seq=0
if mode=='ignore':
 signal.signal(signal.SIGTERM,signal.SIG_IGN)
def emit(payload):
 global seq
 seq+=1
 print(json.dumps(dict(version=1,session=session,sequence=seq,payload=payload)),flush=True)
if mode=='exit':sys.exit(1)
origin=time.monotonic()
def trace(stage,phase):
 emit({'trace':dict(stage=stage,phase=phase,elapsedSeconds=time.monotonic()-origin)})
emit({'helloBoundaryLoopCapabilities':{'outputDeviceSelection':mode=='device-queue-loop'}} if mode.startswith('boundary-') or mode=='device-queue-loop' else ({'helloLoopCapabilities':{'outputDeviceSelection':False}} if mode.startswith('loop-') else ({'helloCapabilities':{'outputDeviceSelection':True}} if mode.startswith('device-') or mode=='trace-output-delay' else {'hello':{}})))
cycle_frames=480
first_frame=0
phase_frame=0
tail_frames=0
boundary_frame=48000
for line in sys.stdin:
 packet=json.loads(line);p=packet['payload']
 if 'prepare' in p or 'prepareOutput' in p or 'prepareLoop' in p or 'prepareLoopRange' in p:
  if 'prepareLoopRange' in p:
   cycle_frames=p['prepareLoopRange']['cycleFrames'];first_frame=p['prepareLoopRange']['startFrame']
   tail_frames=p['prepareLoopRange']['frames']-cycle_frames
  assert open(os.path.join(directory,'audio.caf'),'rb').read(4)==b'caff'
  if mode=='malformed':
   print('{bad',flush=True);continue
  if mode.startswith('trace') or mode=='device-trace' or mode.startswith('device-queue'):
   trace('fileValidation','entered');trace('fileValidation','completed')
  if mode=='device-queue-early':emit({'audioQueueBackend':{}})
  emit({'prepared':{}})
 elif 'play' in p:
  run=p['play']['run']
  if mode=='ignore':
   open(os.path.join(directory,'ignoring'),'w').write(str(os.getpid()))
   while True:time.sleep(1)
  if mode=='late':time.sleep(.3)
  if mode=='disconnect':sys.exit(2)
  if mode.startswith('inherited-'):
   pid=os.fork()
   if pid==0:
    os.close(0)
    unused=2 if mode=='inherited-stdout' else 1
    null=os.open('/dev/null',os.O_WRONLY);os.dup2(null,unused);os.close(null)
    time.sleep(20)
    os._exit(0)
   with open(sys.argv[0]+'.descendant','w') as marker:marker.write(str(pid))
   os._exit(2)
  if mode.startswith('device-queue'):
   emit({'audioQueueBackend':{}})
   for stage in ['queueCreation','queueAudible','queueStart']:
    if mode=='device-queue-incomplete' and stage=='queueStart':break
    trace(stage,'entered');trace(stage,'completed')
  elif mode.startswith('trace') or mode=='device-trace':
   stages=['engineCreation']+(['outputNodeAcquisition','deviceSelection'] if mode in ['device-trace','trace-output-delay'] else [])+['mixerAcquisition','routing','scheduling','engineStart','playerPlay']
   for stage in stages:
    trace(stage,'entered')
    if stage=='outputNodeAcquisition' and mode=='trace-output-delay' and not os.path.exists(sys.argv[0]+'.retry'):
     time.sleep(2)
    if stage=='mixerAcquisition' and mode in ['trace-delay','trace-eof']:
     if mode=='trace-eof':sys.exit(2)
     time.sleep(2)
    trace(stage,'completed')
  if (mode.startswith('device-') and mode != 'device-missing') or mode=='trace-output-delay':
   emit({'outputDevice':{'descriptor':{'uid':'other' if mode=='device-mismatch' else 'selected','name':'Fixture output'}}})
  emit({'started':{'run':run}})
  emit({'loopClock' if mode.startswith('loop-') or mode.startswith('boundary-') or mode=='device-queue-loop' else 'clock':{'run':run,'seconds':20000 if mode.startswith('loop-') else 0.125}})
  if mode=='loop-finish':emit({'finished':{'run':run}})
  if mode=='finished':emit({'finished':{'run':run}})
 elif 'queueLoopChange' in p or 'exitLoop' in p:
  exit_loop='exitLoop' in p
  item=p['exitLoop'] if exit_loop else p['queueLoopChange']
  change=item['change']
  if not exit_loop:
   assert open(os.path.join(directory,'loop-'+change+'.caf'),'rb').read(4)==b'caff'
  if mode=='boundary-reject':
   emit({'loopChangeRejected':dict(change=change,message='fixture rejected')});continue
  if mode=='boundary-stale':change='00000000-0000-0000-0000-000000000000'
  count=cycle_frames if exit_loop else item['cycleFrames']
  boundary_frame=phase_frame+((boundary_frame-phase_frame+first_frame+cycle_frames-1)//cycle_frames)*cycle_frames-first_frame
  emit({'loopChangeScheduled':dict(change=change,elapsedFrame=boundary_frame,frames=count,exiting=exit_loop)})
  if not exit_loop:tail_frames=item['frames']-count
  emit({'loopClock':dict(run=run,seconds=boundary_frame/48000+(tail_frames/48000 if exit_loop else .01))})
  phase_frame=boundary_frame
  cycle_frames=count;first_frame=0
  boundary_frame+=48000
  if exit_loop:
   end_frame=phase_frame+tail_frames
   emit({'loopClock':dict(run=run,seconds=end_frame/48000+.02)})
   emit({'loopFinished':dict(run=run,elapsedFrame=end_frame)})
 elif 'stop' in p:
  emit({'stopped':{'run':p['stop']['run']}})
"""#.replacingOccurrences(of: "MODE", with: mode)
        try source.write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        scripts.append(url)
        return url
    }
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !predicate() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { XCTFail("Host state timed out");throw CancellationError() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func temporary(_ id: UUID) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("circlr-output-" + id.uuidString)
    }
    func testCancelledOldBoundaryTaskCannotStopRestartedSession()async throws {
        let entered=expectation(description:"old change acknowledged")
        let (stream,continuation)=AsyncStream<Void>.makeStream()
        let host=OutputWorkerProcess(executable:try fixture("boundary-normal"),beforeLoopChangeReturn:{
            entered.fulfill()
            for await _ in stream {break}
        })
        try await host.play(PCM(frames:480),from:0,timeout:3,loop:true)
        let old=Task {try await host.changeLoop(cycle:PCM(frames:960))}
        await fulfillment(of:[entered],timeout:3)
        host.cancel();try await wait {host.status.phase == .idle}
        try await host.play(PCM(frames:480),from:0,timeout:3,loop:true)
        let newID=host.status.transport.id
        old.cancel();continuation.finish()
        do {_=try await old.value;XCTFail("Cancelled old task returned success")}catch {}
        XCTAssertEqual(host.status.transport.phase,.playing)
        XCTAssertEqual(host.status.transport.id,newID);XCTAssertEqual(host.status.attempts,2)
        host.cancel();try await wait {host.status.phase == .idle}
    }
    private func loopAudio(frames:Int)throws->PreparedAudio {
        var project=Project();_=project.addSection(name:"Loop",at:Point(),bars:1)
        var plan=try ArrangementCompiler.compile(project);plan.duration=Double(frames)/PCM.rate
        return PreparedAudio(plan:plan,mix:PCM(frames:frames),stems:[:],tailSeconds:0)
    }
    func testPlaybackBoundaryAckUpdatesPlanClockAndPreservesOffsetBoundary()async throws {
        let host=OutputWorkerProcess(executable:try fixture("boundary-normal")),playback=Playback(outputWorker:host)
        try await playback.play(loopAudio(frames:480),from:0.002,loop:true)
        var callbacks=0
        let change=try await playback.requestLoopChange(to:loopAudio(frames:960),onScheduled:{status,source in
            callbacks+=1;XCTAssertFalse(status.exiting);XCTAssertEqual(source?.bodyFrames,960)
        })
        XCTAssertEqual(change.elapsedFrame,48384,"First original musical boundary after the fixture's 48000 already-submitted frames")
        XCTAssertEqual((change.elapsedFrame+96)%480,0)
        XCTAssertGreaterThanOrEqual(change.elapsedFrame,48000)
        XCTAssertLessThan(change.elapsedFrame,48480)
        try await wait {playback.elapsedSeconds>=change.elapsedSeconds}
        XCTAssertEqual(playback.prepared?.plan.duration,0.02)
        XCTAssertEqual(playback.seconds,0.01,accuracy:0.000001)
        XCTAssertNil(playback.pendingLoopChange);XCTAssertEqual(callbacks,1)
        XCTAssertEqual(host.status.attempts,1)
        let exit=try await playback.finishLoopAtBoundary()
        XCTAssertEqual(exit.elapsedFrame,96384,"Replacement keeps its own absolute phase origin")
        XCTAssertEqual((exit.elapsedFrame-change.elapsedFrame)%960,0)
        try await wait {host.status.phase == .idle}
        XCTAssertEqual(playback.completedElapsedSeconds,exit.elapsedSeconds)
        XCTAssertNil(playback.pendingLoopChange,"Zero-tail natural completion still applies the ACK")
        XCTAssertEqual(host.status.attempts,1)
    }
    func testBoundaryRecorderCallbackFailureStopsAlreadyScheduledOutput()async throws {
        struct RecorderFailure:Error {}
        let host=OutputWorkerProcess(executable:try fixture("boundary-normal")),playback=Playback(outputWorker:host)
        try await playback.play(loopAudio(frames:480),loop:true)
        do {
            _=try await playback.requestLoopChange(to:loopAudio(frames:960),onScheduled:{_,_ in throw RecorderFailure()})
            XCTFail("Recorder failure ignored")
        } catch is RecorderFailure {} catch {throw error}
        XCTAssertFalse(playback.playing)
        try await wait {host.status.phase == .idle}
        XCTAssertEqual(host.status.attempts,1)
    }
    func testBoundaryReplacementAndFiniteExitKeepSingleOutputAttempt()async throws {
        let host=OutputWorkerProcess(executable:try fixture("boundary-normal"))
        try await host.play(PCM(frames:480),from:0,timeout:3,loop:true,exitTail:PCM(frames:96))
        let run=host.status.transport.id
        let changed=try await host.changeLoop(cycle:PCM(frames:960),tail:PCM(frames:48))
        XCTAssertEqual(changed.elapsedFrame,48000);XCTAssertEqual(changed.frames,960);XCTAssertFalse(changed.exiting)
        try await wait {host.status.transport.seconds>=changed.elapsedSeconds}
        let exit=try await host.changeLoop(cycle:nil)
        XCTAssertTrue(exit.exiting);XCTAssertEqual(exit.elapsedFrame,96000)
        try await wait {host.status.phase == .idle}
        XCTAssertEqual(host.status.transport.id,run);XCTAssertEqual(host.status.attempts,1)
        XCTAssertNil(host.status.transport.message)
        XCTAssertNotNil(host.status.transport.completedSeconds)
    }
    func testStaleBoundaryAckCannotChangeRunningSource()async throws {
        let host=OutputWorkerProcess(executable:try fixture("boundary-stale"))
        try await host.play(PCM(frames:480),from:0,timeout:3,loop:true)
        do {_=try await host.changeLoop(cycle:PCM(frames:480));XCTFail("Stale ACK accepted")}catch {}
        try await wait {host.status.phase == .idle}
        XCTAssertNil(host.status.transport.loopChange);XCTAssertEqual(host.status.transport.phase,.failed)
    }
    func testRejectedBoundaryPreparationPreservesExistingOutput()async throws {
        let host=OutputWorkerProcess(executable:try fixture("boundary-reject"))
        try await host.play(PCM(frames:480),from:0,timeout:3,loop:true)
        do {_=try await host.changeLoop(cycle:PCM(frames:480));XCTFail("Rejected change accepted")}catch {}
        XCTAssertEqual(host.status.transport.phase,.playing);XCTAssertNil(host.status.transport.loopChange)
        XCTAssertEqual(host.status.attempts,1)
        host.cancel();try await wait {host.status.phase == .idle}
    }
    func testLoopClockCanExceedSourceAndFourHoursWithoutAnotherRun() async throws {
        let host=OutputWorkerProcess(executable:try fixture("loop-clock"))
        try await host.play(PCM(frames:480),from:0,timeout:3,loop:true)
        try await wait {host.status.transport.seconds == 20000}
        XCTAssertEqual(host.status.attempts,1)
        XCTAssertEqual(host.status.transport.phase,.playing)
        host.cancel();try await wait {host.status.phase == .idle}
        XCTAssertEqual(host.status.transport.seconds,0)
        XCTAssertNil(host.status.transport.message)
    }
    func testLegacyHelperCannotSilentlyPlayLoopOnce() async throws {
        let host=OutputWorkerProcess(executable:try fixture("normal"))
        do {try await host.play(PCM(frames:480),from:0,timeout:3,loop:true);XCTFail("Legacy loop accepted")} catch {}
        try await wait {host.status.phase == .idle}
        XCTAssertFalse(host.status.transport.didStart)
        XCTAssertTrue(host.status.transport.message?.contains("루프") == true)
    }
    func testUnexpectedLoopFinishedIsFailure() async throws {
        let host=OutputWorkerProcess(executable:try fixture("loop-finish"))
        try? await host.play(PCM(frames:480),from:0,timeout:3,loop:true)
        try await wait {host.status.phase == .idle}
        XCTAssertEqual(host.status.transport.phase,.failed)
        XCTAssertNotNil(host.status.transport.message)
    }
    func testExitedHelperReleasesReadersDespiteInheritedDescendantPipes() async throws {
        for mode in ["inherited-stdout", "inherited-stderr"] {
            let executable = try fixture(mode)
            let marker = URL(fileURLWithPath: executable.path + ".descendant")
            scripts.append(marker)
            var descendant: pid_t = 0
            defer { if descendant > 0 { _ = Darwin.kill(descendant, SIGKILL) } }
            var host: OutputWorkerProcess? = OutputWorkerProcess(executable: executable)
            weak var releasedHost = host
            do {
                try await host!.play(PCM(frames: 480), from: 0, timeout: 5)
                XCTFail("Exited fixture unexpectedly started")
            } catch {}
            descendant = try XCTUnwrap(pid_t(String(contentsOf: marker, encoding: .utf8)))
            XCTAssertGreaterThan(descendant, 1)
            XCTAssertEqual(Darwin.kill(descendant, 0), 0, "Descendant must still hold its pipe")
            try await wait { host!.status.phase == .idle }
            let attempt = try XCTUnwrap(host!.status.attemptID)
            XCTAssertFalse(FileManager.default.fileExists(atPath: temporary(attempt).path))
            XCTAssertFalse(host!.status.transport.didStart)
            host = nil
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while releasedHost != nil && ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(Darwin.kill(descendant, 0), 0, "Reader release must not depend on descendant EOF")
            XCTAssertNil(releasedHost, "\(mode): exited helper reader retained host")
        }
    }
    func testExplicitSelectionRequiresCapabilityAndMatchingActualDevice() async throws {
        for mode in ["ready", "device-missing", "device-mismatch", "device-ready"] {
            let host = OutputWorkerProcess(executable: try fixture(mode))
            do {
                try await host.play(PCM(frames: 48000), from: 0, timeout: 2, selection: .deviceUID("selected"))
                XCTAssertEqual(mode, "device-ready")
            } catch { XCTAssertNotEqual(mode, "device-ready") }
            XCTAssertEqual(host.status.transport.didStart, mode == "device-ready")
            XCTAssertEqual(host.status.outputSelectionKind, "deviceUID")
            if mode == "device-ready" {
                XCTAssertEqual(host.status.actualOutputDeviceName, "Fixture output")
                let status = try JSONEncoder().encode(host.status)
                XCTAssertFalse(String(decoding: status, as: UTF8.self).contains("selected"))
            }
            host.cancel()
            try await wait { [.idle, .failed].contains(host.status.transport.phase) }
        }
    }
    func testCapableDefaultRequiresActualDevice() async throws {
        let host = OutputWorkerProcess(executable: try fixture("device-missing"))
        do { try await host.play(PCM(frames: 48000), from: 0, timeout: 2); XCTFail("missing actual device accepted") }
        catch {}
        XCTAssertFalse(host.status.transport.didStart)
        try await wait { [.idle, .failed].contains(host.status.transport.phase) }
    }
    func testCompleteTraceAndLegacyCompatibility() async throws {
        for mode in ["trace-ready", "ready", "device-trace"] {
            let host = OutputWorkerProcess(executable: try fixture(mode))
            try await host.play(PCM(frames: 48000), from: 0, timeout: 2)
            let trace = try XCTUnwrap(host.status.trace)
            XCTAssertEqual(trace.sessionID, host.status.attemptID)
            XCTAssertEqual(trace.helperReportsStages, mode != "ready")
            XCTAssertEqual(trace.events.count, mode == "device-trace" ? 22 : (mode == "trace-ready" ? 18 : 4))
            XCTAssertEqual(trace.events.first?.stage, .cafWrite)
            XCTAssertEqual(trace.events.last?.phase, .completed)
            XCTAssertTrue(zip(trace.events, trace.events.dropFirst()).allSatisfy { $0.elapsedSeconds <= $1.elapsedSeconds })
            host.cancel(); try await wait { host.status.transport.phase == .idle }
            XCTAssertEqual(host.status.trace, trace)
        }
    }
    func testAudioQueueBackendRequiresStartTraceBeforeStarted() async throws {
        let complete = OutputWorkerProcess(executable: try fixture("device-queue-trace"))
        try await complete.play(PCM(frames: 48000), from: 0, timeout: 2)
        let status = complete.status
        XCTAssertTrue(status.transport.didStart)
        XCTAssertTrue(status.trace?.helperReportsStages == true)
        XCTAssertEqual(status.trace?.events.count, 12)
        XCTAssertEqual(status.trace?.events.last?.stage, .queueStart)
        XCTAssertEqual(status.trace?.events.last?.phase, .completed)
        complete.cancel()
        try await wait { complete.status.phase == .idle }

        for mode in ["device-queue-incomplete", "device-queue-early"] {
            let host = OutputWorkerProcess(executable: try fixture(mode))
            do { try await host.play(PCM(frames: 48000), from: 0, timeout: 2); XCTFail("\(mode) started without a complete handshake") }
            catch { XCTAssertFalse(host.status.transport.didStart) }
            try await wait { host.status.phase == .idle }
        }
    }
    func testAudioQueueLoopWithExplicitDeviceAcceptsBoundaryReplacementAndFiniteExit() async throws {
        let host = OutputWorkerProcess(executable: try fixture("device-queue-loop"))
        try await host.play(PCM(frames: 480), from: 0, timeout: 3, selection: .deviceUID("selected"),
                            loop: true, exitTail: PCM(frames: 96))
        let run = try XCTUnwrap(host.status.transport.id)
        XCTAssertEqual(host.status.actualOutputDeviceName, "Fixture output")
        XCTAssertEqual(host.status.trace?.events.last?.stage, .queueStart)
        XCTAssertEqual(host.status.trace?.events.last?.phase, .completed)
        let changed = try await host.changeLoop(cycle: PCM(frames: 960), tail: PCM(frames: 48))
        XCTAssertEqual(changed.elapsedFrame, 48000)
        XCTAssertEqual(changed.frames, 960)
        XCTAssertFalse(changed.exiting)
        try await wait { host.status.transport.seconds >= changed.elapsedSeconds }
        let exit = try await host.changeLoop(cycle: nil)
        XCTAssertTrue(exit.exiting)
        XCTAssertEqual(exit.elapsedFrame, 96000)
        try await wait { host.status.phase == .idle }
        XCTAssertEqual(host.status.transport.id, run)
        XCTAssertEqual(host.status.attempts, 1)
        XCTAssertNil(host.status.transport.message)
        XCTAssertNotNil(host.status.transport.completedSeconds)
    }
    func testDelayedMixerTraceSurvivesTimeoutCancellationAndEOF() async throws {
        for mode in ["timeout", "cancel", "eof"] {
            let host = OutputWorkerProcess(executable: try fixture(mode == "eof" ? "trace-eof" : "trace-delay"))
            let task = Task { try await host.play(PCM(frames: 48000), from: 0, timeout: mode == "timeout" ? 1.5 : 4) }
            try await wait { host.status.trace?.events.last?.stage == .mixerAcquisition }
            if mode == "cancel" { host.cancel() }
            do { try await task.value; XCTFail("unfinished preparation succeeded") } catch {}
            try await wait { [.idle, .failed].contains(host.status.transport.phase) }
            let trace = try XCTUnwrap(host.status.trace)
            XCTAssertTrue(trace.helperReportsStages)
            XCTAssertEqual(trace.events.count, 9)
            XCTAssertEqual(trace.events.last?.stage, .mixerAcquisition)
            XCTAssertEqual(trace.events.last?.phase, .entered)
            XCTAssertFalse(host.status.transport.didStart)
            try await Task.sleep(for: .milliseconds(550))
            XCTAssertEqual(host.status.trace, trace)
        }
    }
    func testOutputNodeAcquisitionTimeoutCleansUpAndRetryStarts() async throws {
        let executable = try fixture("trace-output-delay")
        let host = OutputWorkerProcess(executable: executable)
        let attempt = Task { try await host.play(PCM(frames: 48000), from: 0, timeout: 1) }
        try await wait { host.status.trace?.events.last?.stage == .outputNodeAcquisition }
        do { try await attempt.value; XCTFail("stalled output node started") } catch {}
        try await wait { host.status.phase == .idle }
        let stalledID = try XCTUnwrap(host.status.attemptID)
        XCTAssertEqual(host.status.request, .timedOut)
        XCTAssertFalse(host.status.transport.didStart)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary(stalledID).path))
        let trace = try XCTUnwrap(host.status.trace)
        XCTAssertTrue(trace.helperReportsStages)
        XCTAssertEqual(trace.events.last?.stage, .outputNodeAcquisition)
        XCTAssertEqual(trace.events.last?.phase, .entered)

        let retryMarker = URL(fileURLWithPath: executable.path + ".retry")
        try Data().write(to: retryMarker)
        scripts.append(retryMarker)
        try await host.play(PCM(frames: 48000), from: 0, timeout: 2)
        XCTAssertTrue(host.status.transport.didStart)
        XCTAssertEqual(host.status.attempts, 2)
        XCTAssertNotEqual(host.status.attemptID, stalledID)
        host.cancel()
        try await wait { host.status.phase == .idle }
    }
    func testTerminationBeforePipeDeliveryRetainsLastTrace() async throws {
        let terminated = DispatchSemaphore(value: 0)
        let deliveredAfterExit = DispatchSemaphore(value: 0)
        let host = OutputWorkerProcess(executable: try fixture("trace-eof"), beforeEventDelivery: { packets in
            if packets.contains(where: {
                if case .trace(.mixerAcquisition, .entered, _) = $0.payload { return true }
                return false
            }) {
                if terminated.wait(timeout: .now() + 2) == .success { deliveredAfterExit.signal() }
            }
        }, onTerminationObserved: { terminated.signal() })
        do { try await host.play(PCM(frames: 48000), from: 0, timeout: 4); XCTFail("exited helper started") } catch {}
        try await wait { host.status.transport.phase == .failed }
        XCTAssertEqual(deliveredAfterExit.wait(timeout: .now()), .success)
        XCTAssertEqual(host.status.trace?.events.count, 9)
        XCTAssertEqual(host.status.trace?.events.last?.stage, .mixerAcquisition)
        XCTAssertEqual(host.status.trace?.events.last?.phase, .entered)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary(try XCTUnwrap(host.status.attemptID)).path))
    }
    func testLegacyStatusDecodesWithoutTrace() throws {
        let bytes = try JSONEncoder().encode(PlaybackOutputStatus())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object.removeValue(forKey: "trace")
        XCTAssertNil(try JSONDecoder().decode(PlaybackOutputStatus.self, from: JSONSerialization.data(withJSONObject: object)).trace)
    }
    func testStartClockStopCleanupAndRetry() async throws {
        let host = OutputWorkerProcess(executable: try fixture("ready"))
        try await host.play(PCM(frames: 48000), from: 0, timeout: 2)
        try await wait { host.status.transport.seconds == 0.125 }
        let first = try XCTUnwrap(host.status.attemptID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporary(first).path))
        host.cancel()
        XCTAssertEqual(host.status.transport.phase, .stopping)
        XCTAssertEqual(host.status.transport.seconds, 0)
        do { try await host.play(PCM(frames: 48000), from: 0, timeout: 2);XCTFail("cleanup must block retry") }
        catch { XCTAssertTrue(error is PlaybackTransportError) }
        try await wait { host.status.transport.phase == .idle }
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary(first).path))
        try await host.play(PCM(frames: 48000), from: 0, timeout: 2)
        XCTAssertNotEqual(host.status.attemptID, first); XCTAssertEqual(host.status.attempts, 2)
        host.cancel();try await wait { host.status.transport.phase == .idle }
    }
    func testStaleRequestCancellationPreservesReplacementSession() async throws {
        let host = OutputWorkerProcess(executable: try fixture("ready"))
        defer { host.cancel() }
        try await host.play(PCM(frames: 48000), from: 0, timeout: 2)
        let expiredID = try XCTUnwrap(host.status.attemptID)
        host.cancel()
        try await wait { host.status.transport.phase == .idle }

        try await host.play(PCM(frames: 48000), from: 0, timeout: 2)
        try await wait { host.status.transport.seconds == 0.125 }
        let replacementID = try XCTUnwrap(host.status.attemptID)
        XCTAssertNotEqual(replacementID, expiredID)

        let replacementTrace = host.status.trace

        // Reproduce the late timeout and catch cleanup from an older waiting request
        // after its child has exited and its replacement has acquired the host.
        host.cancel(expectedID: expiredID, timedOut: true)
        host.cancel(expectedID: expiredID)
        XCTAssertEqual(host.status.transport.phase, .playing)
        XCTAssertEqual(host.status.request, .none)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(host.status.trace, replacementTrace)
        XCTAssertEqual(host.status.attemptID, replacementID)
        XCTAssertEqual(host.status.transport.phase, .playing)
        XCTAssertEqual(host.status.transport.seconds, 0.125)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporary(replacementID).path))

        host.cancel(expectedID: replacementID)
        XCTAssertEqual(host.status.transport.phase, .stopping)
        try await wait { host.status.transport.phase == .idle }
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary(replacementID).path))
    }
    func testUnresponsiveChildIsKilledAndDirectoryRemoved() async throws {
        let host = OutputWorkerProcess(executable: try fixture("ignore"))
        let task = Task { try await host.play(PCM(frames: 48000), from: 0, timeout: 2) }
        try await wait {
            guard let id = host.status.attemptID else { return false }
            return FileManager.default.fileExists(atPath: temporary(id).appendingPathComponent("ignoring").path)
        }
        do { try await task.value;XCTFail("must time out") }
        catch { XCTAssertTrue(error is PlaybackTransportError) }
        let id = try XCTUnwrap(host.status.attemptID)
        XCTAssertEqual(host.status.request, .timedOut)
        try await wait { host.status.transport.phase == .idle }
        XCTAssertFalse(host.status.transport.didStart)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary(id).path))
    }
    func testCancelledStartCannotPublishLateStarted() async throws {
        let host = OutputWorkerProcess(executable: try fixture("late"))
        let task = Task { try await host.play(PCM(frames: 48000), from: 0, timeout: 2) }
        try await wait { host.status.step == .device }
        host.cancel()
        do { try await task.value;XCTFail("cancelled run started") } catch { XCTAssertTrue(error is CancellationError) }
        try await wait { host.status.transport.phase == .idle }
        XCTAssertFalse(host.status.transport.didStart)
        XCTAssertEqual(host.status.transport.seconds, 0)
    }
    func testMalformedAndEarlyExitAreRecoverableFailures() async throws {
        for mode in ["malformed", "exit", "disconnect"] {
            let host = OutputWorkerProcess(executable: try fixture(mode))
            do { try await host.play(PCM(frames: 48000), from: 0, timeout: 2);XCTFail("invalid child succeeded") }
            catch { XCTAssertTrue(error is PlaybackTransportError) }
            try await wait { host.status.transport.phase == .failed }
            XCTAssertFalse(FileManager.default.fileExists(atPath: temporary(try XCTUnwrap(host.status.attemptID)).path))
        }
    }
    func testNaturalCompletionRetainsStartEvidenceAndCleansUp() async throws {
        let host = OutputWorkerProcess(executable: try fixture("finished"))
        try await host.play(PCM(frames: 48000), from: 0, timeout: 2)
        try await wait { host.status.transport.phase == .idle }
        XCTAssertTrue(host.status.transport.didStart)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary(try XCTUnwrap(host.status.attemptID)).path))
    }
    func testPlaybackPublishesOffsetAndStopsWorker() async throws {
        let host = OutputWorkerProcess(executable: try fixture("ready"))
        let playback = Playback(outputWorker: host)
        var project = Project(); _ = project.addSection(name: "검증", at: Point(), bars: 1)
        let audio = PreparedAudio(plan: try ArrangementCompiler.compile(project), mix: PCM(frames: 48000), stems: [:], tailSeconds: 0)
        try await playback.start(audio, from: 0.25, timeout: 2)
        try await wait { playback.seconds > 0.25 }
        XCTAssertTrue(playback.playing)
        XCTAssertEqual(playback.seconds, 0.375, accuracy: 0.001)
        XCTAssertEqual(playback.prepared?.mix.count, 48000)
        playback.stop()
        XCTAssertFalse(playback.playing); XCTAssertEqual(playback.seconds, 0)
        try await wait { host.status.transport.phase == .idle }
    }
    func testCallerTaskCancellationTerminatesPendingChild() async throws {
        let host = OutputWorkerProcess(executable: try fixture("late"))
        let task = Task { try await host.play(PCM(frames: 48000), from: 0, timeout: 2) }
        try await wait { host.status.step == .device }
        task.cancel()
        do { try await task.value; XCTFail("cancelled task succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await wait { host.status.transport.phase == .idle }
        XCTAssertFalse(host.status.transport.didStart)
    }

    func testMissingHelperAndInvalidPCMFailWithoutDevice() async throws {
        let host = OutputWorkerProcess(executable: nil)
        do { try await host.play(PCM(frames: 32), from: 0, timeout: 1);XCTFail("missing helper succeeded") }
        catch { XCTAssertTrue(error is PlaybackTransportError) }
        try await wait { host.status.transport.phase == .failed }
        let invalid = OutputWorkerProcess(executable: try fixture("ready"))
        var pcm = PCM(frames: 32); pcm.left[0] = .nan
        do { try await invalid.play(pcm, from: 0, timeout: 1);XCTFail("NaN succeeded") }
        catch { XCTAssertTrue(error is PlaybackTransportError) }
        XCTAssertEqual(invalid.status.transport.phase, .failed)
    }
}
