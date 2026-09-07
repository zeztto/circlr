import Foundation
import AVFAudio
import CirclrCore

public struct PCM {
    public static let rate = 48_000.0
    public var left: [Float]
    public var right: [Float]
    public var count: Int { left.count }
    public var duration: Double { Double(count) / Self.rate }
    public init(frames: Int) { left = [Float](repeating: 0, count: max(0, frames)); right = left }
    public mutating func mix(_ source: PCM, at offset: Int = 0, gain: Double = 1) {
        let start = max(0, offset), end = min(count, offset + source.count)
        guard end > start else { return }
        let g = Float(gain)
        for i in start..<end { left[i] += source.left[i-offset] * g; right[i] += source.right[i-offset] * g }
    }
    public mutating func multiply(_ gain: Double) { let g = Float(gain); for i in left.indices { left[i] *= g; right[i] *= g } }
    public func slice(_ range: Range<Int>) -> PCM {
        let start = max(0, min(count, range.lowerBound)), end = max(0, min(count, range.upperBound))
        guard end > start else { return PCM(frames: 0) }
        var p = PCM(frames: end-start); p.left = Array(left[start..<end]); p.right = Array(right[start..<end]); return p
    }
    public mutating func fadeInOut(_ frames: Int = 240) {
        let n = min(frames, count / 2)
        guard n > 0 else { return }
        for i in 0..<n { let g = Float(i)/Float(n); left[i] *= g; right[i] *= g; left[count-i-1] *= g; right[count-i-1] *= g }
    }
    public var peak: Float { var peak:Float = 0; for i in left.indices { peak = max(peak,abs(left[i]),abs(right[i])) }; return peak }
    public var rms: Double {
        guard count > 0 else { return 0 }
        var sum = 0.0; for i in left.indices { sum += Double(left[i])*Double(left[i]) + Double(right[i])*Double(right[i]) }
        return sqrt(sum / Double(count * 2))
    }
    public func buffer() throws -> AVAudioPCMBuffer {
        guard count <= Int(UInt32.max), let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 2), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)), let channels = buffer.floatChannelData else { throw CirclrError("오디오 buffer를 만들 수 없습니다") }
        buffer.frameLength = AVAudioFrameCount(count)
        left.withUnsafeBufferPointer { if let base = $0.baseAddress { channels[0].update(from: base, count: count) } }
        right.withUnsafeBufferPointer { if let base = $0.baseAddress { channels[1].update(from: base, count: count) } }
        return buffer
    }
    public static func read(_ url: URL, start:Double = 0, duration:Double? = nil) throws -> PCM {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, Double(file.length) / file.processingFormat.sampleRate <= 3600 else { throw CirclrError("비어 있거나 1시간을 넘는 오디오입니다") }
        guard file.processingFormat.channelCount <= 2 else { throw CirclrError("Mono 또는 stereo 파일을 사용하세요") }
        guard start.isFinite,start>=0,(duration == nil || (duration!.isFinite && duration!>0)) else { throw CirclrError("읽을 오디오 구간을 확인하세요") }
        let sourceRate=file.processingFormat.sampleRate
        let first=min(file.length,AVAudioFramePosition(min(Double(file.length),start*sourceRate)))
        let length=min(file.length-first,AVAudioFramePosition(min(Double(file.length),ceil((duration ?? Double(file.length)/sourceRate)*sourceRate))))
        guard length>0 else { return PCM(frames:0) }
        guard Double(length)*Double(file.processingFormat.channelCount)*4 < 268_435_456 else { throw CirclrError("오디오 clip을 더 짧은 구간으로 나누어 읽으세요") }
        file.framePosition=first
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(length)) else { throw CirclrError("오디오 파일 buffer 준비 실패") }
        try file.read(into: input)
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        guard let converter = AVAudioConverter(from: input.format, to: outputFormat) else { throw CirclrError("오디오 sample rate를 변환할 수 없습니다") }
        let frames = Int(ceil(Double(input.frameLength) * rate / input.format.sampleRate))
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(frames + 512)) else { throw CirclrError("변환 buffer 준비 실패") }
        var supplied = false, error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .endOfStream; return nil }
            supplied = true; inputStatus.pointee = .haveData; return input
        }
        if let error { throw error }
        guard status != .error, let channels = output.floatChannelData else { throw CirclrError("오디오 변환 실패") }
        var pcm = PCM(frames: Int(output.frameLength))
        pcm.left = Array(UnsafeBufferPointer(start: channels[0], count: pcm.count)); pcm.right = Array(UnsafeBufferPointer(start: channels[1], count: pcm.count))
        return pcm
    }
    public func writeWAV(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.rate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer())
    }
}
public enum NativeDSP {
    public static func process(_ input: PCM, effect: Effect, sidechain: PCM? = nil) throws -> PCM {
        guard effect.amount.isFinite, effect.secondary.isFinite else { throw CirclrError("Effect 설정값이 유효하지 않습니다") }
        var out = input
        let a = min(1, max(0, effect.amount)), b = min(0.95, max(0, effect.secondary))
        switch effect.kind {
        case .gain: out.multiply(effect.amount)
        case .pan:
            let pan = min(1, max(-1, effect.amount)); let l = Float(sqrt((1-pan)/2)*sqrt(2.0)), r = Float(sqrt((1+pan)/2)*sqrt(2.0))
            for i in out.left.indices { out.left[i] *= l; out.right[i] *= r }
        case .drive:
            let drive = Float(1 + a * 18), norm = tanh(drive)
            for i in out.left.indices { out.left[i] = tanh(input.left[i]*drive)/norm; out.right[i] = tanh(input.right[i]*drive)/norm }
        case .lowpass:
            let cutoff = 40 * pow(500, a), alpha = Float(1 - exp(-2 * Double.pi * cutoff / PCM.rate)); var l: Float = 0, r: Float = 0
            for i in out.left.indices { l += alpha * (input.left[i]-l); r += alpha * (input.right[i]-r); out.left[i] = l; out.right[i] = r }
        case .delay:
            let distance = max(1, Int((0.03 + a * 0.97) * PCM.rate)), wet = Float(b), feedback = Float(min(0.8, b))
            var l = [Float](repeating: 0, count: distance), r = l
            for i in out.left.indices { let p = i % distance; let dl = l[p], dr = r[p]; l[p] = input.left[i] + dr*feedback; r[p] = input.right[i] + dl*feedback; out.left[i] += dl*wet; out.right[i] += dr*wet }
        case .reverb:
            if effect.renderVersion==2 {out=try DiffuseReverb.process(input,size:a,wet:b);break}
            let lengths = [1493, 1601, 1747, 1867].map { max(1, Int(Double($0)*(0.5+a*2))) }
            for (index, length) in lengths.enumerated() {
                var line = [Float](repeating: 0, count: length); let feedback = Float(0.45 + a*0.38), wet = Float(b*0.3)
                for i in out.left.indices { let p = i%length, sample = line[p]; line[p] = (input.left[i]+input.right[i])*0.5 + sample*feedback; if index%2 == 0 { out.left[i] += sample*wet } else { out.right[i] += sample*wet } }
            }
        case .compressor:
            let threshold = Float(pow(10, (-36+a*30)/20)), ratio = Float(2+b*10); var envelope: Float = 0
            for i in out.left.indices {
                let detector: Float
                if let sc = sidechain, i < sc.count { detector = max(abs(sc.left[i]),abs(sc.right[i])) } else { detector = max(abs(input.left[i]),abs(input.right[i])) }
                envelope += (detector-envelope) * (detector > envelope ? 0.02 : 0.0005)
                let gain: Float = envelope > threshold ? pow(envelope/threshold, 1/ratio-1) : 1
                out.left[i] *= gain; out.right[i] *= gain
            }
        case .audioUnit: throw CirclrError("Audio Unit은 native host 경로로 처리해야 합니다")
        }
        guard out.left.allSatisfy(\.isFinite), out.right.allSatisfy(\.isFinite) else { throw CirclrError("Effect가 유효하지 않은 오디오를 만들었습니다") }
        return out
    }
}
