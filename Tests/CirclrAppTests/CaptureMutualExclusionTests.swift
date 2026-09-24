import AppKit
import XCTest
import CirclrAudio
import CirclrCore
@testable import CirclrApp

@MainActor final class CaptureMutualExclusionTests:XCTestCase {
    private func makeStore() -> (AppStore,URL) {
        _ = NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-capture-exclusion-\(UUID().uuidString)")
        let store=AppStore(storageRootOverride:root)
        let useID=store.project.addSection(name:"Capture target",at:Point(),bars:1)
        store.selection=[useID]
        return (store,root)
    }

    func testAlternateMIDICommandDoesNotCancelMoviePreparation() {
        let (store,root)=makeStore()
        defer {store.moviePreparing=false;store.stop();try? FileManager.default.removeItem(at:root)}
        store.moviePreparing=true
        let generation=store.movieGeneration

        store.startMIDIRecording()

        XCTAssertTrue(store.moviePreparing)
        XCTAssertEqual(store.movieGeneration,generation)
        XCTAssertFalse(store.midiRecording)
        XCTAssertEqual(store.project.takes?.count ?? 0,0)
        XCTAssertTrue(store.status.contains("영상 녹화"))
    }

    func testAlternateTakeCommandsDoNotCancelMovieFinalizationOrPreparation() {
        let (store,root)=makeStore()
        defer {store.movieFinalizing?.cancel();store.movieFinalizing=nil;store.moviePreparing=false;store.stop();try? FileManager.default.removeItem(at:root)}
        store.moviePreparing=true
        let preparingGeneration=store.movieGeneration
        store.startAudioRecording()
        XCTAssertTrue(store.moviePreparing)
        XCTAssertEqual(store.movieGeneration,preparingGeneration)
        XCTAssertFalse(store.audioRecordPending)
        XCTAssertFalse(store.recorder.busy)

        store.moviePreparing=false
        store.movieFinalizing=Task { }
        let finalizingGeneration=store.movieGeneration
        store.startMIDIRecording()
        store.startAudioRecording()
        XCTAssertNotNil(store.movieFinalizing)
        XCTAssertEqual(store.movieGeneration,finalizingGeneration)
        XCTAssertFalse(store.midiRecording)
        XCTAssertFalse(store.audioRecordPending)
        XCTAssertFalse(store.recorder.busy)
        XCTAssertTrue(store.status.contains("영상 녹화"))
    }

    func testAlternateAudioCommandDoesNotStopAnActiveMIDITake() {
        let (store,root)=makeStore()
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        store.startMIDIRecording()
        XCTAssertTrue(store.midiRecording)

        store.startAudioRecording()

        XCTAssertTrue(store.midiRecording)
        XCTAssertFalse(store.audioRecordPending)
        XCTAssertFalse(store.recorder.busy)
        XCTAssertEqual(store.project.takes?.count ?? 0,0)
        XCTAssertTrue(store.status.contains("MIDI 녹음"))
    }

    func testMovieCommandDoesNotOpenSavePanelOrCancelAudioPermissionPending() {
        let (store,root)=makeStore()
        defer {store.audioRecordPending=false;store.stop();try? FileManager.default.removeItem(at:root)}
        store.audioRecordPending=true
        let generation=store.movieGeneration

        store.toggleMovieRecording()

        XCTAssertTrue(store.audioRecordPending)
        XCTAssertEqual(store.movieGeneration,generation)
        XCTAssertFalse(store.moviePreparing)
        XCTAssertNil(store.movieWriter)
        XCTAssertTrue(store.status.contains("현재 작업"))
    }

    func testMovieCommandDoesNotOpenSavePanelWhileAudioRecorderIsBusy() throws {
        let (store,root)=makeStore()
        defer {store.recorder.cancelStart();store.stop();try? FileManager.default.removeItem(at:root)}
        // A nonexistent explicit UID uses the closed selected-input path: no
        // microphone prompt or physical input is opened, but busy is observable.
        try store.recorder.start(to:root.appendingPathComponent("blocked.caf"),maximumSeconds:1,
                                 selection:.deviceUID("circlr-test-no-device-\(UUID().uuidString)")){_ in}
        XCTAssertTrue(store.recorder.busy)
        // Exercise the recorder's authoritative state independently of the
        // published permission/starting flag.
        store.audioRecordPending=false
        XCTAssertFalse(store.audioRecordPending)
        let generation=store.movieGeneration

        store.toggleMovieRecording()

        XCTAssertTrue(store.recorder.busy)
        XCTAssertEqual(store.movieGeneration,generation)
        XCTAssertFalse(store.moviePreparing)
        XCTAssertNil(store.movieWriter)
        XCTAssertTrue(store.status.contains("현재 작업"))
    }

    func testAnActiveCaptureCanStillStopOrCancelItself() async throws {
        let (store,root)=makeStore()
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        store.startMIDIRecording()
        XCTAssertTrue(store.midiRecording)
        store.startMIDIRecording()
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while store.midiRecording && ProcessInfo.processInfo.systemUptime<deadline {
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertFalse(store.midiRecording)

        store.audioRecordPending=true
        store.startAudioRecording()
        XCTAssertFalse(store.audioRecordPending)

        store.moviePreparing=true
        let generation=store.movieGeneration
        store.toggleMovieRecording()
        XCTAssertFalse(store.moviePreparing)
        XCTAssertGreaterThan(store.movieGeneration,generation)
    }
}
