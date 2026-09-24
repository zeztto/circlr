import AppKit
import XCTest
import CirclrCore
@testable import CirclrApp

@MainActor final class MIDIRecordingFidelityTests: XCTestCase {
    private func makeStore(tempo: Double = 120, repeats: Int = 1) throws -> (AppStore, URL, ID, ID, ID) {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-midi-fidelity-\(UUID().uuidString)")
        let store = AppStore(storageRootOverride: root)
        store.project.global.tempo = tempo
        let useID = store.project.addSection(name: "MIDI take", at: Point(), bars: 1)
        let trackID = try XCTUnwrap(store.selectedTrackID)
        let useIndex = try XCTUnwrap(store.project.active.uses.firstIndex { $0.id == useID })
        store.project.arrangements[store.project.activeIndex].uses[useIndex].repeatCount = repeats
        store.selection = [useID]
        let sectionID = store.project.active.uses[useIndex].sectionID
        return (store, root, useID, sectionID, trackID)
    }

    private func send(_ store: AppStore, channel: UInt8, pitch: Int, velocity: Int, on: Bool, at time: Double) {
        store.midi(status: (on ? 0x90 : 0x80) | channel, pitch: pitch, velocity: velocity, time: time)
    }

    func testDifferentChannelsOfSamePitchSurviveInterleavedOffAndTakeUndo() async throws {
        let (store, root, useID, sectionID, trackID) = try makeStore()
        defer { store.stop(); try? FileManager.default.removeItem(at: root) }
        store.startMIDIRecording()
        XCTAssertTrue(store.midiRecording)
        let start = ProcessInfo.processInfo.systemUptime
        send(store, channel: 0, pitch: 60, velocity: 71, on: true, at: start + 0.01)
        send(store, channel: 1, pitch: 60, velocity: 109, on: true, at: start + 0.04)
        store.midi(status: 0x90,pitch:60,velocity:0,time:start + 0.08) // MIDI Note On at zero velocity means Note Off.
        XCTAssertEqual(store.auditionOutput.status.heldNotes, 1, "다른 채널이 유지하는 음을 라이브 미리 듣기에서 끊지 않아야 합니다")
        send(store, channel: 1, pitch: 60, velocity: 0, on: false, at: start + 0.12)
        XCTAssertEqual(store.auditionOutput.status.heldNotes, 0)
        try await Task.sleep(for: .milliseconds(150))
        store.stopRecording()

        let take = try XCTUnwrap(store.project.takes?.last)
        XCTAssertEqual(take.useID, useID)
        XCTAssertEqual(take.lane.trackID, trackID)
        let notes = take.lane.notes.sorted { $0.beat < $1.beat }
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.map(\.velocity), [71, 109])
        XCTAssertEqual(notes.map(\.pitch), [60, 60])
        let first = try XCTUnwrap(notes.first)
        let second = try XCTUnwrap(notes.dropFirst().first)
        XCTAssertEqual(second.beat - first.beat, 0.06, accuracy: 0.02)
        XCTAssertEqual(first.length, 0.14, accuracy: 0.02)
        XCTAssertEqual(second.length, 0.16, accuracy: 0.02)
        let active = try XCTUnwrap(store.project.sections.first { $0.id == sectionID })
        let activeUse = try XCTUnwrap(store.project.active.uses.first { $0.id == useID })
        XCTAssertEqual(try ArrangementCompiler.effectiveLanes(section: active,use: activeUse).first { $0.trackID == trackID }?.notes.count, 2)
        store.undo()
        XCTAssertEqual(store.project.takes?.count, 1)
        let restoredSection = try XCTUnwrap(store.project.sections.first { $0.id == sectionID })
        let restoredUse = try XCTUnwrap(store.project.active.uses.first { $0.id == useID })
        XCTAssertEqual(try ArrangementCompiler.effectiveLanes(section: restoredSection,use: restoredUse).first { $0.trackID == trackID }?.notes.count, 0)
        store.undo()
        XCTAssertEqual(store.project.takes?.count ?? 0, 0)
    }

    func testSameChannelRetriggerClosesPreviousAtNewOnAndKeepsBothVelocities() async throws {
        let (store, root, _, _, _) = try makeStore()
        defer { store.stop(); try? FileManager.default.removeItem(at: root) }
        store.startMIDIRecording()
        let start = ProcessInfo.processInfo.systemUptime
        send(store, channel: 3, pitch: 64, velocity: 65, on: true, at: start + 0.01)
        send(store, channel: 3, pitch: 64, velocity: 112, on: true, at: start + 0.06)
        send(store, channel: 3, pitch: 64, velocity: 0, on: false, at: start + 0.11)
        try await Task.sleep(for: .milliseconds(140))
        store.stopRecording()

        let notes = try XCTUnwrap(store.project.takes?.last?.lane.notes.sorted { $0.beat < $1.beat })
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.map(\.velocity), [65, 112])
        let first = try XCTUnwrap(notes.first)
        let second = try XCTUnwrap(notes.dropFirst().first)
        XCTAssertEqual(second.beat - first.beat, 0.10, accuracy: 0.02)
        XCTAssertEqual(first.length, 0.10, accuracy: 0.02)
        XCTAssertEqual(second.length, 0.10, accuracy: 0.02)
    }

    func testSecondChannelAttackRearticulatesPreviewButFirstOffKeepsSounding() async throws {
        let (store, root, _, _, _) = try makeStore()
        defer { store.stop(); try? FileManager.default.removeItem(at: root) }
        store.startMIDIRecording()
        var commands: [String] = []
        store.onMIDIRecordingPreviewCommand = { pitch,velocity,on in
            commands.append("\(pitch):\(velocity):\(on ? "on":"off")")
        }
        let start = ProcessInfo.processInfo.systemUptime
        send(store, channel: 0, pitch: 69, velocity: 72, on: true, at: start + 0.01)
        send(store, channel: 1, pitch: 69, velocity: 111, on: true, at: start + 0.04)
        XCTAssertEqual(commands, ["69:72:on", "69:111:on"], "두 번째 채널의 Note On도 미리 듣기에 전달해야 합니다")
        send(store, channel: 0, pitch: 69, velocity: 0, on: false, at: start + 0.08)
        XCTAssertEqual(commands.count, 2, "첫 채널 Note Off는 아직 소리 내는 두 번째 채널을 끊지 않아야 합니다")
        send(store, channel: 1, pitch: 69, velocity: 0, on: false, at: start + 0.12)
        XCTAssertEqual(commands, ["69:72:on", "69:111:on", "69:0:off"])
        try await Task.sleep(for: .milliseconds(150))
        store.stopRecording()
    }

    func testStopFlushSplitsHeldNotesAtRepeatBoundaryWithoutDroppingOtherChannel() async throws {
        let (store, root, _, _, _) = try makeStore(tempo: 999, repeats: 2)
        defer { store.stop(); try? FileManager.default.removeItem(at: root) }
        let clock = try XCTUnwrap(store.recordingClock)
        XCTAssertGreaterThan(clock.seconds, 0.23)
        XCTAssertLessThan(clock.seconds, 0.25)
        store.startMIDIRecording()
        let start = ProcessInfo.processInfo.systemUptime
        send(store, channel: 0, pitch: 67, velocity: 75, on: true, at: start + 0.18)
        send(store, channel: 1, pitch: 67, velocity: 103, on: true, at: start + 0.20)
        send(store, channel: 0, pitch: 67, velocity: 0, on: false, at: start + 0.27)
        try await Task.sleep(for: .milliseconds(320))
        store.stopRecording()
        XCTAssertEqual(store.auditionOutput.status.heldNotes, 0)

        let takes = try XCTUnwrap(store.project.takes)
        XCTAssertEqual(takes.count, 2)
        let first = try XCTUnwrap(takes.first)
        let second = try XCTUnwrap(takes.dropFirst().first)
        XCTAssertEqual(first.lane.notes.map(\.velocity).sorted(), [75, 103])
        XCTAssertEqual(second.lane.notes.map(\.velocity).sorted(), [75, 103])
        XCTAssertTrue(first.lane.notes.allSatisfy { $0.beat + $0.length <= clock.beats + 0.000001 })
        XCTAssertTrue(second.lane.notes.allSatisfy { $0.beat >= 0 && $0.beat < clock.beats })
        XCTAssertEqual(store.project.takes?.last?.id, second.id)
    }
}
