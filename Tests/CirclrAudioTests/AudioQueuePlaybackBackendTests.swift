import XCTest
import AVFAudio
@testable import CirclrAudio

final class AudioQueuePlaybackBackendTests: XCTestCase {
    func testQueueProgressWatchdogRejectsStallButAcceptsNewSample() throws {
        var watchdog = AudioQueueProgressWatchdog(startedAt: 10)
        try watchdog.observe(0, at: 11.9)
        try watchdog.observe(0.1, at: 12)
        try watchdog.observe(0.1, at: 13.9)
        XCTAssertThrowsError(try watchdog.observe(0.1, at: 14.01))
        var advancing = AudioQueueProgressWatchdog(startedAt: 10)
        try advancing.observe(0.1, at: 10.1)
        try advancing.observe(0.2, at: 11.9)
        try advancing.observe(0.3, at: 13.8)
        XCTAssertThrowsError(try advancing.observe(.nan, at: 13.9))
    }

    private func loopAudio(_ cycle: [Float], tail: [Float] = []) throws -> OutputWorkerLoopScheduler.Audio {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        func buffer(_ values: [Float]) throws -> AVAudioPCMBuffer {
            let result = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
                                                        frameCapacity: AVAudioFrameCount(values.count)))
            result.frameLength = AVAudioFrameCount(values.count)
            let channels = try XCTUnwrap(result.floatChannelData)
            for (frame, value) in values.enumerated() {
                channels[0][frame] = value
                channels[1][frame] = -value
            }
            return result
        }
        return try .init(cycle: buffer(cycle), tail: tail.isEmpty ? nil : buffer(tail))
    }

    func testLoopReplacementAndExitLandOnExactUnqueuedSampleBoundaries() throws {
        let reader = try AudioQueueLoopChunkReader(audio: loopAudio([10, 11, 12, 13, 14]), fromFrame: 2)
        var samples = [Float](repeating: 0, count: 12)
        XCTAssertEqual(try samples.withUnsafeMutableBufferPointer { try reader.fill($0) }, 6)
        XCTAssertEqual(stride(from: 0, to: 12, by: 2).map { samples[$0] }, [12, 13, 14, 10, 11, 12])
        let replacement = UUID()
        let change = try reader.request(id: replacement, audio: loopAudio([20, 21, 22], tail: [90, 91]))
        XCTAssertEqual(change.elapsedFrame, 8)
        XCTAssertEqual(change.sourceFrames, 3)
        XCTAssertThrowsError(try reader.request(id: UUID(), audio: nil))
        XCTAssertEqual(try samples.withUnsafeMutableBufferPointer { try reader.fill($0) }, 6)
        XCTAssertEqual(stride(from: 0, to: 12, by: 2).map { samples[$0] }, [13, 14, 20, 21, 22, 20])
        let exit = try reader.request(id: UUID(), audio: nil)
        XCTAssertEqual(exit.elapsedFrame, 14)
        XCTAssertEqual(exit.sourceFrames, 3)
        samples = [Float](repeating: 0, count: 20)
        XCTAssertEqual(try samples.withUnsafeMutableBufferPointer { try reader.fill($0) }, 4)
        XCTAssertEqual(stride(from: 0, to: 8, by: 2).map { samples[$0] }, [21, 22, 90, 91])
        XCTAssertEqual(stride(from: 1, to: 8, by: 2).map { samples[$0] }, [-21, -22, -90, -91])
        XCTAssertTrue(reader.finished)
        XCTAssertEqual(reader.submittedFrames, 16)
        XCTAssertEqual(try samples.withUnsafeMutableBufferPointer { try reader.fill($0) }, 0)
    }

    func testLoopRequestAcknowledgesBoundaryAfterAlreadySubmittedAudio() throws {
        let reader = try AudioQueueLoopChunkReader(audio: loopAudio([1, 2, 3]), fromFrame: 0)
        var queued = [Float](repeating: 0, count: 4_096 * 2)
        XCTAssertEqual(try queued.withUnsafeMutableBufferPointer { try reader.fill($0) }, 4_096)
        let boundary = try reader.request(id: UUID(), audio: loopAudio([8, 9]))
        XCTAssertEqual(boundary.elapsedFrame, 4_098)
        var next = [Float](repeating: 0, count: 10)
        XCTAssertEqual(try next.withUnsafeMutableBufferPointer { try reader.fill($0) }, 5)
        XCTAssertEqual(stride(from: 0, to: 10, by: 2).map { next[$0] }, [2, 3, 8, 9, 8])
    }

    func testLoopExitWithoutTailEndsAtBoundary() throws {
        let reader = try AudioQueueLoopChunkReader(audio: loopAudio([1, 2, 3]), fromFrame: 0)
        var first = [Float](repeating: 0, count: 4)
        XCTAssertEqual(try first.withUnsafeMutableBufferPointer { try reader.fill($0) }, 2)
        let boundary = try reader.request(id: UUID(), audio: nil)
        XCTAssertEqual(boundary.elapsedFrame, 3)
        var remaining = [Float](repeating: 0, count: 20)
        XCTAssertEqual(try remaining.withUnsafeMutableBufferPointer { try reader.fill($0) }, 1)
        XCTAssertEqual(remaining[0], 3)
        XCTAssertTrue(reader.finished)
        XCTAssertEqual(reader.submittedFrames, 3)
    }

    func testOptionalNativeLoopExitReportsReservedBoundaryAndTailEnd() throws {
        guard ProcessInfo.processInfo.environment["CIRCLR_AUDIOQUEUE_NATIVE_QA"] == "1" else {
            throw XCTSkip("Native CoreAudio smoke is opt-in and must run in a timeout-bounded child")
        }
        final class Frames: @unchecked Sendable {
            let lock = NSLock()
            private var boundary: Int64?
            private var end: Int64?
            func setBoundary(_ value: Int64) { lock.lock(); boundary = value; lock.unlock() }
            func setEnd(_ value: Int64) { lock.lock(); end = value; lock.unlock() }
            func values() -> (Int64?, Int64?) { lock.lock(); defer { lock.unlock() }; return (boundary, end) }
        }
        let frames = Frames()
        let acknowledged = expectation(description: "reserved boundary acknowledged immediately")
        let finished = expectation(description: "loop tail played to completion")
        let audio = try loopAudio([Float](repeating: 0, count: 2_400),
                                  tail: [Float](repeating: 0, count: 600))
        let backend = try AudioQueuePlaybackBackend(loopAudio: audio, fromFrame: 500,
                                                    selection: .deviceUID("BuiltInSpeakerDevice"),
                                                    onBoundary: { boundary in
                                                        frames.setBoundary(boundary.elapsedFrame)
                                                        acknowledged.fulfill()
                                                    },
                                                    onFinished: { end in
                                                        frames.setEnd(end)
                                                        finished.fulfill()
                                                    },
                                                    onFailure: { error in
                                                        XCTFail("Native loop failed: \(error)")
                                                        finished.fulfill()
                                                    })
        defer { backend.stop() }
        try backend.prepareAudible()
        try backend.startPrepared()
        try backend.requestLoopChange(id: UUID(), audio: nil)
        wait(for: [acknowledged], timeout: 0.5)
        wait(for: [finished], timeout: 3)
        let (boundary, end) = frames.values()
        XCTAssertNotNil(boundary)
        XCTAssertEqual(end, boundary.map { $0 + 600 })
        XCTAssertEqual(try backend.checkedSeconds(), Double(end ?? 0) / 48_000, accuracy: 0.005)
    }

    func testOptionalNativeBuiltInOutputCompletesSilentFiniteFile() throws {
        guard ProcessInfo.processInfo.environment["CIRCLR_AUDIOQUEUE_NATIVE_QA"] == "1" else {
            throw XCTSkip("Native CoreAudio smoke is opt-in and must run in a timeout-bounded child")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("circlr-audioqueue-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let silence = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        silence.frameLength = 4_800
        let channels = try XCTUnwrap(silence.floatChannelData)
        for frame in 0..<4_800 { channels[0][frame] = 0; channels[1][frame] = 0 }
        var writer: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings,
                                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try writer?.write(from: silence)
        writer = nil
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let finished = expectation(description: "AudioQueue played its finite buffer")
        let backend = try AudioQueuePlaybackBackend(file: file, selection: .deviceUID("BuiltInSpeakerDevice"),
                                                    onFinished: { finished.fulfill() },
                                                    onFailure: { error in
                                                        XCTFail("AudioQueue failed: \(error)")
                                                        finished.fulfill()
                                                    })
        defer { backend.stop() }
        XCTAssertEqual(backend.outputDevice.uid, "BuiltInSpeakerDevice")
        try backend.startMuted()
        XCTAssertEqual(try backend.revalidate().uid, "BuiltInSpeakerDevice")
        try backend.makeAudible()
        wait(for: [finished], timeout: 4)
        XCTAssertEqual(try backend.checkedSeconds(), 0.1, accuracy: 0.005)
    }

    func testOptionalNativeStopSuppressesFinishCallback() throws {
        guard ProcessInfo.processInfo.environment["CIRCLR_AUDIOQUEUE_NATIVE_QA"] == "1" else {
            throw XCTSkip("Native CoreAudio smoke is opt-in and must run in a timeout-bounded child")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("circlr-audioqueue-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let silence = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        silence.frameLength = 48_000
        let channels = try XCTUnwrap(silence.floatChannelData)
        for frame in 0..<48_000 { channels[0][frame] = 0; channels[1][frame] = 0 }
        var writer: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings,
                                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try writer?.write(from: silence)
        writer = nil
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let unexpectedlyFinished = expectation(description: "stop must suppress finish")
        unexpectedlyFinished.isInverted = true
        let backend = try AudioQueuePlaybackBackend(file: file, selection: .deviceUID("BuiltInSpeakerDevice"),
                                                    onFinished: { unexpectedlyFinished.fulfill() },
                                                    onFailure: { _ in unexpectedlyFinished.fulfill() })
        try backend.startMuted()
        try backend.makeAudible()
        Thread.sleep(forTimeInterval: 0.05)
        backend.stop()
        wait(for: [unexpectedlyFinished], timeout: 0.15)
        XCTAssertLessThan(try backend.checkedSeconds(), 1)
    }

    func testFloatStereoStreamingPreservesSamplesAcrossBufferBoundary() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("circlr-audioqueue-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 5_003))
        source.frameLength = 5_003
        let channels = try XCTUnwrap(source.floatChannelData)
        for i in 0..<5_003 {
            channels[0][i] = Float(i % 101) / 100
            channels[1][i] = -Float(i % 73) / 72
        }
        // Float PCM may contain legitimate values above 0 dBFS before the
        // device's final conversion. The playback stream must not quantize it.
        channels[0][4_095] = 1.125
        channels[1][4_096] = -1.25
        var writer: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings,
                                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try writer?.write(from: source)
        writer = nil
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let reader = try AudioQueuePCMChunkReader(file: file)
        var samples = [Float](repeating: 0, count: AudioQueuePCMChunkReader.framesPerBuffer * 2)
        let first = try samples.withUnsafeMutableBufferPointer { try reader.fill($0) }
        XCTAssertEqual(first, 4_096)
        XCTAssertEqual(samples[4_095 * 2], 1.125)
        XCTAssertEqual(samples[4_095 * 2 + 1], channels[1][4_095], accuracy: 0.000_001)
        let second = try samples.withUnsafeMutableBufferPointer { try reader.fill($0) }
        XCTAssertEqual(second, 907)
        XCTAssertEqual(samples[1], -1.25)
        XCTAssertEqual(samples[(second - 1) * 2], channels[0][5_002], accuracy: 0.000_001)
        XCTAssertEqual(try samples.withUnsafeMutableBufferPointer { try reader.fill($0) }, 0)
    }

    func testRejectsNonFiniteSourceSamples() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("circlr-audioqueue-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        source.frameLength = 1
        let channels = try XCTUnwrap(source.floatChannelData)
        channels[0][0] = .nan
        channels[1][0] = 0
        var writer: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings,
                                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try writer?.write(from: source)
        writer = nil
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let reader = try AudioQueuePCMChunkReader(file: file)
        var samples = [Float](repeating: 0, count: 2)
        XCTAssertThrowsError(try samples.withUnsafeMutableBufferPointer { try reader.fill($0) })
    }
}
