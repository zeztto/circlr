import AppKit
import XCTest
import CirclrCore
@testable import CirclrApp

@MainActor final class TakeRecordingEntryTests:XCTestCase {
    func testTopLevelEntryKeepsCapturedMIDITargetHiddenAfterSelectionChanges() async throws {
        _ = NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-take-entry-\(UUID().uuidString)")
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}

        XCTAssertEqual(store.takeRecordingTargetIssue,"녹음할 섹션 서클을 선택하세요")
        XCTAssertFalse(store.canStartMIDITake)
        XCTAssertFalse(store.canStartAudioTake)

        let useID=store.project.addSection(name:"Take entry",at:Point(),bars:1)
        store.selection=[useID]
        XCTAssertNil(store.takeRecordingTargetIssue)
        XCTAssertTrue(store.canStartMIDITake)
        XCTAssertTrue(store.canStartAudioTake)
        let originalTrackID=try XCTUnwrap(store.selectedTrackID)
        XCTAssertEqual(store.takeRecordingTargetTitle,"Take entry · 악기 1")

        store.startMIDIRecording()
        XCTAssertTrue(store.midiRecording)
        XCTAssertEqual(store.takeRecordingStatusTitle,"MIDI 녹음 중")
        XCTAssertNil(store.takeRecordingTargetTitle,"녹음 시작 후에는 변경 가능한 live 선택을 목적지로 표시하지 않아야 합니다")
        XCTAssertFalse(store.canStartAudioTake)
        let otherTrackID=store.project.addTrack(name:"다른 트랙")
        store.selectTrack(otherTrackID)
        XCTAssertNil(store.takeRecordingTargetTitle)
        let now=ProcessInfo.processInfo.systemUptime
        store.midi(status:0x90,pitch:60,velocity:90,time:now+0.01)
        store.midi(status:0x80,pitch:60,velocity:0,time:now+0.05)
        try await Task.sleep(for:.milliseconds(100))
        store.stopRecording()
        XCTAssertFalse(store.midiRecording)
        XCTAssertEqual(store.takeRecordingStatusTitle,"테이크 녹음")
        XCTAssertEqual(store.project.takes?.last?.lane.trackID,originalTrackID)
        XCTAssertEqual(store.takeRecordingTargetTitle,"Take entry · 다른 트랙")
    }

    func testCaptureEntryExplainsVideoConflictAndAudioAuthorizationFinalization() throws {
        _ = NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-take-entry-state-\(UUID().uuidString)")
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        let useID=store.project.addSection(name:"Take entry",at:Point(),bars:1)
        store.selection=[useID]

        store.moviePreparing=true
        XCTAssertEqual(store.takeRecordingTargetIssue,"영상 녹화를 마친 뒤 테이크를 녹음하세요")
        XCTAssertFalse(store.canStartMIDITake)
        XCTAssertFalse(store.canStartAudioTake)
        store.moviePreparing=false

        store.audioRecordPending=true
        XCTAssertEqual(store.takeRecordingStatusTitle,"마이크 확인 중")
        XCTAssertNil(store.takeRecordingTargetTitle)
        XCTAssertFalse(store.canStartMIDITake)
        XCTAssertFalse(store.canStartAudioTake)
        store.audioCapturePhase = .starting
        XCTAssertEqual(store.takeRecordingStatusTitle,"오디오 준비 중")
        store.audioCapturePhase = .recording
        XCTAssertEqual(store.takeRecordingStatusTitle,"오디오 녹음 중")
        store.audioCapturePhase = .finishing
        store.audioRecordPending=false
        XCTAssertEqual(store.takeRecordingStatusTitle,"파일 저장 중")
        XCTAssertEqual(store.takeRecordingCompactTitle,"저장 중")
        XCTAssertFalse(store.canStartMIDITake)
        XCTAssertFalse(store.canStartAudioTake)
        store.audioCapturePhase = .cancelling
        XCTAssertEqual(store.takeRecordingStatusTitle,"장치 정리 중")
        XCTAssertEqual(store.takeRecordingCompactTitle,"장치 정리")
        XCTAssertTrue(store.audioRecordingLocked)
    }
}
