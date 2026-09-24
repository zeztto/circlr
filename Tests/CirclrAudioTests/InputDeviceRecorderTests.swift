import Foundation
import XCTest
import CirclrCore
@testable import CirclrAudio

private final class SelectionRecorderBackend:AudioCaptureBackend,@unchecked Sendable {
    private let lock=NSLock()
    private var _stops=0
    let startError:Error?
    init(startError:Error?=nil){self.startError=startError}
    var stops:Int {lock.withLock{_stops}}
    func start(to:URL,maximumSeconds:Double,control:CaptureControl) throws -> CaptureFormat {
        if let startError {throw startError}
        return CaptureFormat(sampleRate:48_000,channels:1)
    }
    func stop() throws -> CapturedAudio? {
        lock.withLock{_stops+=1}
        return nil
    }
}

private final class SelectionRecorderFactory:@unchecked Sendable {
    private let lock=NSLock()
    private var _selections:[InputDeviceSelection]=[]
    let failed=SelectionRecorderBackend(startError:InputDeviceBindingError.missingDevice)
    let working=SelectionRecorderBackend()
    var selections:[InputDeviceSelection] {lock.withLock{_selections}}
    func make(_ selection:InputDeviceSelection) -> AudioCaptureBackend {
        lock.withLock{_selections.append(selection)}
        if case .deviceUID("missing")=selection {return failed}
        return working
    }
}

@MainActor final class InputDeviceRecorderTests:XCTestCase {
    private let url=URL(fileURLWithPath:"/tmp/circlr-input-selection-test.caf")
    private func waitUntilIdle(_ recorder:AudioRecorder) async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while recorder.busy {
            guard ProcessInfo.processInfo.systemUptime<deadline else{throw CirclrError("입력 정리 시간 초과")}
            try await Task.sleep(for:.milliseconds(5))
        }
    }
    private func start(_ recorder:AudioRecorder,selection:InputDeviceSelection = .systemDefault) async throws -> CaptureFormat {
        try await withCheckedThrowingContinuation {reply in
            do {try recorder.start(to:url,maximumSeconds:2,selection:selection){reply.resume(with:$0)}}
            catch {reply.resume(throwing:error)}
        }
    }
    func testDefaultAndSelectedUIDReachSeparateAudioLayerSelection() async throws {
        let factory=SelectionRecorderFactory(),recorder=AudioRecorder(selectionFactory:{factory.make($0)})
        let first=try await start(recorder)
        XCTAssertEqual(first.channels,1)
        recorder.stop{_ in}
        try await waitUntilIdle(recorder)
        let second=try await start(recorder,selection:.deviceUID("input-a"))
        XCTAssertEqual(second.sampleRate,48_000)
        recorder.stop{_ in}
        try await waitUntilIdle(recorder)
        XCTAssertEqual(factory.selections,[.systemDefault,.deviceUID("input-a")])
        XCTAssertEqual(factory.working.stops,2)
    }
    func testMissingSelectedUIDFailsAndCleanupAllowsDefaultRetry() async throws {
        let factory=SelectionRecorderFactory(),recorder=AudioRecorder(selectionFactory:{factory.make($0)})
        do {_=try await start(recorder,selection:.deviceUID("missing"));XCTFail("Expected missing-device failure")}
        catch {XCTAssertEqual(error as? InputDeviceBindingError,.missingDevice)}
        XCTAssertEqual(recorder.phase,.failed)
        XCTAssertFalse(recorder.busy)
        XCTAssertEqual(factory.failed.stops,1)
        _=try await start(recorder)
        XCTAssertEqual(recorder.phase,.recording)
        recorder.stop{_ in}
        try await waitUntilIdle(recorder)
    }
    func testInvalidUIDFailsBeforeStartingWorker() throws {
        let factory=SelectionRecorderFactory(),recorder=AudioRecorder(selectionFactory:{factory.make($0)})
        XCTAssertThrowsError(try recorder.start(to:url,maximumSeconds:2,selection:.deviceUID(" \n")){_ in}) {
            XCTAssertEqual($0 as? InputDeviceBindingError,.invalidSelection)
        }
        XCTAssertTrue(factory.selections.isEmpty)
        XCTAssertFalse(recorder.busy)
    }
    func testProductionSelectedInputFailsClosedWithoutParentHALLookup() async throws {
        let recorder=AudioRecorder()
        do {_=try await start(recorder,selection:.deviceUID("circlr-missing-input-uid"));XCTFail("Missing input capture started")}
        catch {XCTAssertEqual(error as? InputDeviceBindingError,.selectedCaptureUnavailable)}
        XCTAssertEqual(recorder.phase,.failed)
        XCTAssertFalse(recorder.busy)
    }
    func testNativeKnownUIDFailsClosedWithoutChangingDefaultWhenRequested() async throws {
        guard let uid=ProcessInfo.processInfo.environment["CIRCLR_QA_INPUT_UID"],!uid.isEmpty else {
            throw XCTSkip("Set CIRCLR_QA_INPUT_UID for native selected-input preflight")
        }
        let access=CoreAudioInputDeviceAccess(),before=try access.defaultInputID()
        let recorder=AudioRecorder()
        do {_=try await start(recorder,selection:.deviceUID(uid));XCTFail("Unverified native capture started")}
        catch {XCTAssertEqual(error as? InputDeviceBindingError,.selectedCaptureUnavailable)}
        XCTAssertEqual(try access.defaultInputID(),before)
        XCTAssertFalse(recorder.busy)
    }
}
