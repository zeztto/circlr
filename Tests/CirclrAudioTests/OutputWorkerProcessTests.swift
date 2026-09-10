import XCTest
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
emit({'helloCapabilities':{'outputDeviceSelection':True}} if mode.startswith('device-') else {'hello':{}})
for line in sys.stdin:
 packet=json.loads(line);p=packet['payload']
 if 'prepare' in p or 'prepareOutput' in p:
  assert open(os.path.join(directory,'audio.caf'),'rb').read(4)==b'caff'
  if mode=='malformed':
   print('{bad',flush=True);continue
  if mode.startswith('trace') or mode=='device-trace':
   trace('fileValidation','entered');trace('fileValidation','completed')
  emit({'prepared':{}})
 elif 'play' in p:
  run=p['play']['run']
  if mode=='ignore':
   open(os.path.join(directory,'ignoring'),'w').write(str(os.getpid()))
   while True:time.sleep(1)
  if mode=='late':time.sleep(.3)
  if mode=='disconnect':sys.exit(2)
  if mode.startswith('trace') or mode=='device-trace':
   stages=['engineCreation']+(['outputNodeAcquisition','deviceSelection'] if mode=='device-trace' else [])+['mixerAcquisition','routing','scheduling','engineStart','playerPlay']
   for stage in stages:
    trace(stage,'entered')
    if stage=='mixerAcquisition' and mode in ['trace-delay','trace-eof']:
     if mode=='trace-eof':sys.exit(2)
     time.sleep(2)
    trace(stage,'completed')
  if mode.startswith('device-') and mode != 'device-missing':
   emit({'outputDevice':{'descriptor':{'uid':'other' if mode=='device-mismatch' else 'selected','name':'Fixture output'}}})
  emit({'started':{'run':run}})
  emit({'clock':{'run':run,'seconds':0.125}})
  if mode=='finished':emit({'finished':{'run':run}})
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
