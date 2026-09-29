import AVFAudio
import XCTest
@testable import CirclrAudio

final class PlaybackLoopEnduranceTests: XCTestCase {
    func testHundredOffsetCyclesPreserveEverySampleClockAndSingleExitTail() throws {
        let bodyFrames = 257, startFrame = 17, tailFrames = 2 * 257 + 43
        var mix = PCM(frames: bodyFrames + tailFrames)
        for frame in 0..<mix.count {
            mix.left[frame] = Float((frame * 17) % 73 - 36) / 10_000
            mix.right[frame] = Float((frame * 11) % 61 - 30) / 12_000
        }
        let loop = try PlaybackLoopPCM(mix: mix, bodySeconds: Double(bodyFrames) / PCM.rate)
        XCTAssertEqual(loop.bodyFrames, bodyFrames)
        XCTAssertEqual(loop.exitTail.count, tailFrames)

        // Independent reference: sum finite prior renders at each sample position.
        // Do not use the production cycle, exitTail, scheduler, or wrapped clock
        // to compute expected sample values or frame boundaries.
        func reference(_ samples: [Float], startingAt index: Int) -> Double {
            stride(from: index, to: samples.count, by: bodyFrames).reduce(0.0) { $0 + Double(samples[$1]) }
        }
        let expectedCycleLeft = (0..<bodyFrames).map { reference(mix.left, startingAt: $0) }
        let expectedCycleRight = (0..<bodyFrames).map { reference(mix.right, startingAt: $0) }
        let expectedTailLeft = (0..<tailFrames).map { reference(mix.left, startingAt: bodyFrames + $0) }
        let expectedTailRight = (0..<tailFrames).map { reference(mix.right, startingAt: bodyFrames + $0) }

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: PCM.rate, channels: 2))
        func buffer(_ pcm: PCM) throws -> AVAudioPCMBuffer {
            let result = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count)))
            result.frameLength = AVAudioFrameCount(pcm.count)
            let channels = try XCTUnwrap(result.floatChannelData)
            for frame in 0..<pcm.count {
                channels[0][frame] = pcm.left[frame]
                channels[1][frame] = pcm.right[frame]
            }
            return result
        }
        let audio = try OutputWorkerLoopScheduler.Audio(cycle: buffer(loop.cycle), tail: buffer(loop.exitTail))
        // This is the actual production AudioQueue buffer source, without opening a device.
        let reader = try AudioQueueLoopChunkReader(audio: audio, fromFrame: startFrame)
        let chunkSizes = [1, 127, 509, 4_096, 73]
        var submitted = 0, chunkIndex = 0
        var maximumSampleError = 0.0
        func fillAndCheck(capacity: Int, exitFrame: Int? = nil) throws -> Int {
            var samples = [Float](repeating: .nan, count: capacity * 2)
            let count = try samples.withUnsafeMutableBufferPointer { try reader.fill($0) }
            XCTAssertLessThanOrEqual(count, capacity)
            for frame in 0..<count {
                let elapsedFrame = submitted + frame
                let left: Double, right: Double
                if let exitFrame, elapsedFrame >= exitFrame {
                    let tailIndex = elapsedFrame - exitFrame
                    guard tailIndex < tailFrames else {
                        XCTFail("Exit tail repeated or exceeded its finite length")
                        continue
                    }
                    left = expectedTailLeft[tailIndex]; right = expectedTailRight[tailIndex]
                } else {
                    let phase = (startFrame + elapsedFrame) % bodyFrames
                    left = expectedCycleLeft[phase]; right = expectedCycleRight[phase]
                }
                guard samples[frame * 2].isFinite, samples[frame * 2 + 1].isFinite else {
                    XCTFail("AudioQueue source left a nonfinite/unwritten sample")
                    continue
                }
                maximumSampleError = max(maximumSampleError, abs(Double(samples[frame * 2]) - left),
                                         abs(Double(samples[frame * 2 + 1]) - right))
            }
            submitted += count
            XCTAssertEqual(reader.submittedFrames, Int64(submitted))
            return count
        }
        // Cross 100 boundaries, then stop 31 frames into the next cycle.
        let beforeExitRequest = 100 * bodyFrames - startFrame + 31
        while submitted < beforeExitRequest {
            let capacity = min(chunkSizes[chunkIndex % chunkSizes.count], beforeExitRequest - submitted)
            let count = try fillAndCheck(capacity: capacity)
            XCTAssertEqual(count, capacity)
            guard count == capacity else { return }
            XCTAssertFalse(reader.finished)
            chunkIndex += 1
        }
        let offsetSeconds = Double(startFrame) / PCM.rate
        for cycle in 1...100 {
            let boundaryFrame = cycle * bodyFrames - startFrame
            for delta in [-1, 0, 1] {
                let elapsed = Double(boundaryFrame + delta) / PCM.rate
                let expectedIteration = delta < 0 ? cycle - 1 : cycle
                XCTAssertEqual(loop.iteration(elapsed: elapsed, offset: offsetSeconds), expectedIteration,
                               "Iteration mismatch at boundary \(boundaryFrame), offset \(delta) frame")
                let position = loop.position(elapsed: elapsed, offset: offsetSeconds)
                let expectedPosition = Double(delta < 0 ? bodyFrames - 1 : delta) / PCM.rate
                // On a circular timeline duration and zero represent the same phase.
                // Permit only sub-sample floating-point residue, not a skipped frame.
                let distance = abs(position - expectedPosition)
                let circularErrorFrames = min(distance, abs(loop.duration - distance)) * PCM.rate
                XCTAssertLessThan(circularErrorFrames, 0.000_001,
                                  "Phase drift at cycle \(cycle), offset \(delta) frame")
            }
        }
        // Sub-sample movie times must not be rounded onto the next cycle.
        for cycle in 1...100 {
            let boundaryFrame = Double(cycle * bodyFrames - startFrame)
            for fraction in [0.25, 0.0001] {
                XCTAssertEqual(loop.iteration(elapsed: (boundaryFrame - fraction) / PCM.rate,
                                              offset: offsetSeconds), cycle - 1)
                XCTAssertEqual(loop.iteration(elapsed: (boundaryFrame + fraction) / PCM.rate,
                                              offset: offsetSeconds), cycle)
            }
        }
        let saturation = Int(Double(Int.max / 2))
        XCTAssertEqual(loop.iteration(elapsed: Double.greatestFiniteMagnitude), saturation)
        XCTAssertEqual(loop.iteration(elapsed: Double.greatestFiniteMagnitude,
                                      offset: Double.greatestFiniteMagnitude), saturation)
        XCTAssertEqual(loop.iteration(elapsed: .nan), 0)
        XCTAssertEqual(loop.iteration(elapsed: .infinity), 0)
        XCTAssertEqual(loop.iteration(elapsed: -1), 0)
        XCTAssertEqual(loop.iteration(elapsed: 1, offset: .infinity), 0)
        XCTAssertEqual(loop.iteration(elapsed: 1, offset: -1), 0)
        let exitFrame = 101 * bodyFrames - startFrame
        let boundary = try reader.request(id: UUID(), audio: nil)
        XCTAssertEqual(boundary.elapsedFrame, Int64(exitFrame))
        XCTAssertEqual(boundary.sourceFrames, bodyFrames)
        while !reader.finished {
            let capacity = chunkSizes[chunkIndex % chunkSizes.count]
            let remaining = exitFrame + tailFrames - submitted
            XCTAssertEqual(try fillAndCheck(capacity: capacity, exitFrame: exitFrame), min(capacity, remaining))
            chunkIndex += 1
            if chunkIndex > 1_000 { XCTFail("Finite exit never completed"); break }
        }
        XCTAssertEqual(submitted, exitFrame + tailFrames)
        XCTAssertEqual(reader.submittedFrames, Int64(exitFrame + tailFrames))
        XCTAssertLessThan(maximumSampleError, 0.000_000_01, "All stereo samples must match independent overlap sums")
        XCTAssertEqual(try fillAndCheck(capacity: 509, exitFrame: exitFrame), 0)
        XCTAssertEqual(reader.submittedFrames, Int64(exitFrame + tailFrames), "Exit tail must be emitted exactly once")
    }
}
