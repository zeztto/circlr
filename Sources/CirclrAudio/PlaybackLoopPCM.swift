import Foundation
import CirclrCore

/// A circular render: tails wrap onto the start, including on the first pass.
/// This is the steady-state sum of the finite rendered tail, not a re-render of
/// nonlinear instruments/effects with persistent state across repetitions.
public struct PlaybackLoopPCM: Sendable {
    public enum TailPolicy: String, Codable, Sendable { case circularSteadyState }
    public let cycle: PCM
    public let exitTail: PCM
    public let bodyFrames: Int
    public let tailPolicy: TailPolicy = .circularSteadyState
    public var duration: Double { Double(bodyFrames) / PCM.rate }

    public init(audio: PreparedAudio) throws {try self.init(audio:audio,additionalRetainedBytes:0)}
    init(audio:PreparedAudio,additionalRetainedBytes:Double)throws {
        let stemBytes=audio.stems.values.reduce(0.0) {$0+Double($1.count)*8}
        try self.init(mix: audio.mix, bodySeconds: audio.plan.duration,
                      byteLimit: ArrangementRenderer.preparationByteLimit-stemBytes-additionalRetainedBytes)
    }
    public init(mix: PCM, bodySeconds: Double) throws {
        try self.init(mix: mix, bodySeconds: bodySeconds, byteLimit: ArrangementRenderer.preparationByteLimit)
    }
    init(mix: PCM, bodySeconds: Double, byteLimit: Double) throws {
        guard bodySeconds.isFinite, bodySeconds > 0,
              bodySeconds * PCM.rate <= Double(OutputWorkerWire.maximumFrames),
              mix.left.count == mix.right.count else { throw PlaybackTransportError.invalidPosition }
        let frames = Int((bodySeconds * PCM.rate).rounded())
        guard frames > 0, frames <= mix.count,
              // Retained input, cycle, optional rotated copy and helper AV buffer.
              Double(mix.count) * 8 + Double(frames) * 24 + Double(mix.count-frames) * 16 <= byteLimit else {
            throw CirclrError("루프 오디오의 길이 또는 준비 메모리 범위를 확인하세요")
        }
        var result = PCM(frames: frames)
        for index in 0..<mix.count {
            if index % 4096 == 0 { try Task.checkCancellation() }
            let l = mix.left[index], r = mix.right[index]
            guard l.isFinite, r.isFinite else { throw CirclrError("루프 오디오 값이 올바르지 않습니다") }
            result.left[index % frames] += l; result.right[index % frames] += r
        }
        guard result.left.allSatisfy(\.isFinite), result.right.allSatisfy(\.isFinite), result.peak <= 1 else {
            throw CirclrError("루프 잔향 합산이 0 dBFS를 넘습니다. Gain을 낮추세요")
        }
        // At exit no new body begins. Retain tails from every preceding cycle,
        // accumulating backwards by one body length rather than dropping history.
        var ending=mix.slice(frames..<mix.count)
        if ending.count>0 {
            for i in stride(from:ending.count-1,through:0,by:-1) {
                if i % 4096 == 0 {try Task.checkCancellation()}
                if i+frames<ending.count {
                    ending.left[i]+=ending.left[i+frames];ending.right[i]+=ending.right[i+frames]
                }
            }
        }
        guard ending.left.allSatisfy(\.isFinite),ending.right.allSatisfy(\.isFinite),ending.peak<=1 else {
            throw CirclrError("루프 종료 잔향이 0 dBFS를 넘습니다. Gain을 낮추세요")
        }
        bodyFrames = frames; cycle = result;exitTail=ending
    }
    /// Rotation preserves the complete cycle when starting partway through it.
    public func frameOffset(from seconds: Double) throws -> Int {
        guard seconds.isFinite, seconds >= 0 else { throw PlaybackTransportError.invalidPosition }
        return Int((seconds.truncatingRemainder(dividingBy: duration) * PCM.rate).rounded()) % bodyFrames
    }
    public func rotated(from seconds: Double) throws -> PCM {
        let first = try frameOffset(from: seconds)
        guard first != 0 else { return cycle }
        var result = PCM(frames: bodyFrames)
        for i in 0..<bodyFrames {
            if i % 4096 == 0 { try Task.checkCancellation() }
            result.left[i] = cycle.left[(first+i) % bodyFrames]
            result.right[i] = cycle.right[(first+i) % bodyFrames]
        }
        return result
    }
    public func position(elapsed: Double, offset: Double = 0) -> Double {
        guard elapsed.isFinite, offset.isFinite, elapsed >= 0, offset >= 0 else { return 0 }
        return (elapsed.truncatingRemainder(dividingBy: duration) + offset.truncatingRemainder(dividingBy: duration)).truncatingRemainder(dividingBy: duration)
    }
    public func iteration(elapsed: Double, offset: Double = 0) -> Int {
        guard elapsed.isFinite, offset.isFinite, elapsed >= 0, offset >= 0 else { return 0 }
        return Int(min(Double(Int.max / 2), floor((elapsed + offset.truncatingRemainder(dividingBy: duration)) / duration)))
    }
}
