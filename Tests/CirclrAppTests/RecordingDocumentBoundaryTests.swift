import AppKit
import XCTest
import CirclrAudio
import CirclrCore
@testable import CirclrApp

@MainActor final class RecordingDocumentBoundaryTests:XCTestCase {
    private func makeStore()->(AppStore,URL) {
        _ = NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-record-switch-\(UUID().uuidString)")
        return (AppStore(storageRootOverride:root),root)
    }

    private func assertDocumentActionsBlocked(_ store:AppStore,root:URL,file:StaticString=#filePath,line:UInt=#line) {
        let project=store.project,url=root.appendingPathComponent("original.circlr")
        let recovery=root.appendingPathComponent("unfinished.caf")
        store.projectURL=url;store.audioRecoveryURL=recovery
        store.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path),file:file,line:line)
        XCTAssertTrue(store.status.contains("녹음 정지"),file:file,line:line)
        store.newProject()
        store.open(root.appendingPathComponent("absent.circlr"))
        store.createStarter("blank",name:"전환 금지")
        store.openBundledDemo(id:"absent-demo")
        XCTAssertFalse(store.applyLoadedBundledDemo(.init(project:Project(),root:root.appendingPathComponent("loaded.circlr"),lease:nil)),file:file,line:line)
        XCTAssertEqual(store.project,project,file:file,line:line)
        XCTAssertEqual(store.projectURL,url,file:file,line:line)
        XCTAssertEqual(store.audioRecoveryURL,recovery,file:file,line:line)
        XCTAssertFalse(store.demoLoading,file:file,line:line)
        XCTAssertTrue(store.status.contains("파일 마무리"),file:file,line:line)
    }

    func testAudioPendingAndFinalizationRejectEveryDocumentReplacementAndSave() {
        let (store,root)=makeStore();defer{try? FileManager.default.removeItem(at:root)}
        store.audioRecordPending=true
        assertDocumentActionsBlocked(store,root:root)
        store.audioRecordPending=false
        for phase in [AudioRecorder.Phase.starting,.recording,.finishing,.cancelling] {
            store.audioCapturePhase=phase
            assertDocumentActionsBlocked(store,root:root)
        }
    }

    func testMIDIRecordingRejectsEveryDocumentReplacementAndSave() {
        let (store,root)=makeStore();defer{try? FileManager.default.removeItem(at:root)}
        store.midiRecording=true
        assertDocumentActionsBlocked(store,root:root)
    }

    func testDemoCommitResumesOnlyAfterRecordingFinalization() throws {
        let (store,root)=makeStore();defer{try? FileManager.default.removeItem(at:root)}
        let incoming=try ProjectStarters.make(id:"blank",name:"새 데모")
        let copy=BundledDemo.Copy(project:incoming,root:root.appendingPathComponent("demo.circlr"),lease:nil)
        let original=store.project
        store.audioCapturePhase = .finishing
        XCTAssertFalse(store.applyLoadedBundledDemo(copy))
        XCTAssertEqual(store.project,original)
        store.audioCapturePhase = .idle
        XCTAssertTrue(store.applyLoadedBundledDemo(copy))
        XCTAssertEqual(store.project,incoming)
        XCTAssertTrue(store.dirty)
    }

    func testMIDITimerUsesMonotonicRecordingElapsedTime() async throws {
        let (store,root)=makeStore();defer{try? FileManager.default.removeItem(at:root)}
        XCTAssertEqual(store.midiRecordingElapsedSeconds,0)
        let use=store.project.addSection(name:"녹음 섹션",at:Point(),bars:1)
        store.selection=[use]
        store.startMIDIRecording()
        XCTAssertTrue(store.midiRecording)
        let first=store.midiRecordingElapsedSeconds
        try await Task.sleep(for:.milliseconds(30))
        XCTAssertGreaterThan(store.midiRecordingElapsedSeconds,first)
        store.stopRecording()
        XCTAssertEqual(store.midiRecordingElapsedSeconds,0)
        XCTAssertEqual(store.meter.seconds,store.playback.seconds)
        XCTAssertFalse(store.meter.playing)
    }

    func testMIDITimerPublishesElapsedTimeAndReturnsToPlaybackAfterAutomaticStop() async throws {
        let (store,root)=makeStore();defer{try? FileManager.default.removeItem(at:root)}
        store.project.global.tempo=999
        let use=store.project.addSection(name:"짧은 녹음",at:Point(),bars:1)
        store.selection=[use]
        store.startMIDIRecording()
        XCTAssertTrue(store.midiRecording)
        try await Task.sleep(for:.milliseconds(90))
        store.tick()
        XCTAssertGreaterThan(store.meter.seconds,0)
        XCTAssertFalse(store.meter.playing)
        try await Task.sleep(for:.milliseconds(340))
        store.tick()
        XCTAssertFalse(store.midiRecording)
        XCTAssertEqual(store.meter.seconds,store.playback.seconds)
        XCTAssertFalse(store.meter.playing)
    }
}
