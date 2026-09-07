import Foundation
import AVFAudio
import CirclrCore

public struct WaveformOverview: Sendable {
    public var peaks: [Float]
    public var duration: Double
    public var sampleRate: Double
    /// Reads real samples in bounded chunks; never fabricates a visual waveform.
    public static func read(_ url: URL, bins: Int = 2048) throws -> WaveformOverview {
        let file = try AVAudioFile(forReading: url)
        let count = max(32, min(16_384, bins))
        guard file.length > 0, file.processingFormat.sampleRate > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { throw CirclrError("파형을 읽을 수 없는 오디오입니다") }
        var peaks = [Float](repeating: 0, count: count), cursor: Int64 = 0
        let framesPerBin = max(1, Double(file.length) / Double(count))
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: 8192)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { throw CirclrError("오디오 파형 sample을 읽지 못했습니다") }
            for index in 0..<Int(buffer.frameLength) {
                let bin = min(count-1, Int(Double(cursor + Int64(index)) / framesPerBin))
                for channel in 0..<Int(buffer.format.channelCount) {
                    let sample = abs(channels[channel][index])
                    if sample.isFinite { peaks[bin] = max(peaks[bin], sample) }
                }
            }
            cursor += Int64(buffer.frameLength)
        }
        return WaveformOverview(peaks: peaks, duration: Double(file.length)/file.processingFormat.sampleRate, sampleRate: file.processingFormat.sampleRate)
    }
    public func peak(at seconds: Double) -> Float {
        guard !peaks.isEmpty, duration > 0, seconds.isFinite, seconds >= 0, seconds < duration else { return 0 }
        return peaks[min(peaks.count-1, Int(seconds/duration*Double(peaks.count)))]
    }
}
