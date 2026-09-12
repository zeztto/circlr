import Foundation

/// Drive renderVersion 3: versions nil/1/2 retain their original direct saturation.
/// Offline, four-times oversampled saturation. Symmetric FIRs compensate latency;
/// fixed-size chunks avoid allocating a whole high-rate copy of a song.
/// Samples beyond the buffer are zero, and output retains the input frame count.
enum OversampledDrive {
    private static let factor = 4
    private static let half = 64
    private static let kernel: [Double] = {
        let cutoff = 0.1125 // 21.6 kHz at 192 kHz, with a transition below Nyquist.
        var taps = (-half...half).map { offset -> Double in
            let x = Double(offset), position = Double(offset + half) / Double(half * 2)
            let sinc = offset == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * x) / (.pi * x)
            return sinc * (0.42 - 0.5 * cos(2 * .pi * position) + 0.08 * cos(4 * .pi * position))
        }
        let sum = taps.reduce(0, +)
        for i in taps.indices { taps[i] /= sum }
        return taps
    }()

    static func process(_ input: PCM, drive: Double) throws -> PCM {
        var output = PCM(frames: input.count)
        output.left = try channel(input.left, drive: drive)
        output.right = try channel(input.right, drive: drive)
        return output
    }

    private static func channel(_ input: [Float], drive: Double) throws -> [Float] {
        var output = [Float](repeating: 0, count: input.count)
        let normalization = tanh(drive)
        for start in stride(from: 0, to: input.count, by: 1024) {
            try Task.checkCancellation()
            let count = min(1024, input.count - start)
            let first = start * factor - half
            var shaped = [Double](repeating: 0, count: (count - 1) * factor + 2 * half + 1)
            for i in shaped.indices {
                let time = first + i
                var value = 0.0
                // Only original-rate positions contribute to the zero-stuffed FIR.
                let lower = max(0, Int(ceil(Double(time - half) / Double(factor))))
                let upper = min(input.count - 1, Int(floor(Double(time + half) / Double(factor))))
                if lower <= upper {
                    for sample in lower...upper {
                        value += Double(input[sample]) * kernel[time - sample * factor + half] * Double(factor)
                    }
                }
                shaped[i] = tanh(value * drive) / normalization
            }
            for i in 0..<count {
                var value = 0.0
                for tap in kernel.indices { value += shaped[i * factor + tap] * kernel[tap] }
                output[start + i] = Float(value)
            }
        }
        return output
    }
}
