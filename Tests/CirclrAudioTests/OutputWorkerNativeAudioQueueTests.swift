import XCTest
@testable import CirclrAudio

/// Opt-in: run with CIRCLR_AUDIOQUEUE_NATIVE_QA=1 and CIRCLR_OUTPUT_WORKER
/// pointing to the built helper. The caller must bound the whole test process.
final class OutputWorkerNativeAudioQueueTests: XCTestCase {
    func testExplicitBuiltInStreamsPastPrefillAndCompletesThreeSeconds() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["CIRCLR_AUDIOQUEUE_NATIVE_QA"] == "1",
              let binary = env["CIRCLR_OUTPUT_WORKER"] else {
            throw XCTSkip("Real CoreAudio output host test is opt-in")
        }
        let host = OutputWorkerProcess(executable: URL(fileURLWithPath: binary))
        try await host.play(PCM(frames: 48_000 * 3), from: 0, timeout: 5,
                            selection: .deviceUID("BuiltInSpeakerDevice"))
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while host.status.transport.phase != .idle
              && host.status.transport.phase != .failed
              && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(host.status.transport.phase, .idle)
        XCTAssertEqual(host.status.transport.completedSeconds ?? -1, 3, accuracy: 0.000_001)
    }

    func testExplicitBuiltInLoopReplacementThenExitKeepsSampleBoundaries() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["CIRCLR_AUDIOQUEUE_NATIVE_QA"] == "1",
              let binary = env["CIRCLR_OUTPUT_WORKER"] else {
            throw XCTSkip("Real CoreAudio output host test is opt-in")
        }
        let host = OutputWorkerProcess(executable: URL(fileURLWithPath: binary))
        try await host.play(PCM(frames: 4_800), from: 0, timeout: 5,
                            selection: .deviceUID("BuiltInSpeakerDevice"), loop: true)
        let replacement = try await host.changeLoop(cycle: PCM(frames: 9_600),
                                                     tail: PCM(frames: 1_200))
        XCTAssertFalse(replacement.exiting)
        XCTAssertEqual(replacement.frames, 9_600)
        XCTAssertEqual(replacement.elapsedFrame % 4_800, 0)
        let progressDeadline = ProcessInfo.processInfo.systemUptime + 4
        while host.status.transport.seconds < Double(replacement.elapsedFrame + 9_600) / 48_000
              && ProcessInfo.processInfo.systemUptime < progressDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThanOrEqual(host.status.transport.seconds,
                                    Double(replacement.elapsedFrame + 9_600) / 48_000)
        let exit = try await host.changeLoop(cycle: nil)
        XCTAssertTrue(exit.exiting)
        XCTAssertEqual((exit.elapsedFrame - replacement.elapsedFrame) % 9_600, 0)
        let finishedDeadline = ProcessInfo.processInfo.systemUptime + 4
        while host.status.transport.completedSeconds == nil
              && ProcessInfo.processInfo.systemUptime < finishedDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(host.status.transport.completedSeconds ?? -1,
                       Double(exit.elapsedFrame + 1_200) / 48_000, accuracy: 0.000_001)
        while host.status.transport.phase == .stopping
              && ProcessInfo.processInfo.systemUptime < finishedDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(host.status.transport.phase, .idle)
    }

    func testExplicitBuiltInLoopExitUsesReservedBoundaryAndTail() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["CIRCLR_AUDIOQUEUE_NATIVE_QA"] == "1",
              let binary = env["CIRCLR_OUTPUT_WORKER"] else {
            throw XCTSkip("Real CoreAudio output host test is opt-in")
        }
        let host = OutputWorkerProcess(executable: URL(fileURLWithPath: binary))
        let cycle = PCM(frames: 4_800), tail = PCM(frames: 2_400)
        try await host.play(cycle, from: 0, timeout: 5,
                            selection: .deviceUID("BuiltInSpeakerDevice"),
                            loop: true, exitTail: tail)
        XCTAssertTrue(host.status.transport.didStart)
        XCTAssertFalse((host.status.actualOutputDeviceName ?? "").isEmpty)
        let change = try await host.changeLoop(cycle: nil)
        XCTAssertTrue(change.exiting)
        XCTAssertGreaterThan(change.elapsedFrame, 0)
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        while host.status.transport.completedSeconds == nil
              && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let expected = Double(change.elapsedFrame + Int64(tail.count)) / 48_000
        XCTAssertEqual(host.status.transport.completedSeconds ?? -1, expected, accuracy: 0.000_001)
        while host.status.transport.phase == .stopping
              && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(host.status.transport.phase, .idle)
    }

    func testExplicitBuiltInFinitePlaybackReportsExactNaturalEnd() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["CIRCLR_AUDIOQUEUE_NATIVE_QA"] == "1",
              let binary = env["CIRCLR_OUTPUT_WORKER"] else {
            throw XCTSkip("Real CoreAudio output host test is opt-in")
        }
        let host = OutputWorkerProcess(executable: URL(fileURLWithPath: binary))
        try await host.play(PCM(frames: 4_800), from: 0, timeout: 5,
                            selection: .deviceUID("BuiltInSpeakerDevice"))
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while host.status.transport.completedSeconds == nil
              && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(host.status.transport.completedSeconds ?? -1, 0.1, accuracy: 0.000_001)
        while host.status.transport.phase == .stopping
              && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(host.status.transport.phase, .idle)
    }

    func testExplicitBuiltInFinitePlaybackUsesQueueAndStopsThroughHost() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["CIRCLR_AUDIOQUEUE_NATIVE_QA"] == "1",
              let binary = env["CIRCLR_OUTPUT_WORKER"] else {
            throw XCTSkip("Real CoreAudio output host test is opt-in")
        }
        let host = OutputWorkerProcess(executable: URL(fileURLWithPath: binary))
        try await host.play(PCM(frames: 48_000 * 3), from: 0, timeout: 5,
                            selection: .deviceUID("BuiltInSpeakerDevice"))
        let started = host.status
        XCTAssertTrue(started.transport.didStart)
        XCTAssertFalse((started.actualOutputDeviceName ?? "").isEmpty)
        XCTAssertTrue(started.trace?.events.contains(where: {
            $0.stage == .queueAudible && $0.phase == .completed
        }) == true)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while host.status.transport.seconds < 0.08 && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThanOrEqual(host.status.transport.seconds, 0.08)
        host.cancel()
        let stopDeadline = ProcessInfo.processInfo.systemUptime + 3
        while ![PlaybackTransportStatus.Phase.idle, .failed].contains(host.status.transport.phase)
              && ProcessInfo.processInfo.systemUptime < stopDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(host.status.transport.phase, .idle)
        let encoded = String(decoding: try JSONEncoder().encode(host.status), as: UTF8.self)
        XCTAssertFalse(encoded.contains("BuiltInSpeakerDevice"))
    }
}
