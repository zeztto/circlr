import Foundation

/// Lightweight callback timing; these samples are not compositor-present timestamps.
struct CanvasFrameTiming {
    private var samples = [Double](repeating: 0, count: 600)
    private var cursor = 0
    private(set) var count = 0
    private(set) var maximumGap = 0.0
    private(set) var maximumDuration = 0.0
    private var previousStart = 0.0

    mutating func record(start: Double, end: Double) {
        guard start.isFinite, end.isFinite, end >= start else { return }
        if previousStart > 0 { maximumGap = max(maximumGap, start - previousStart) }
        previousStart = start
        let duration = end - start
        maximumDuration = max(maximumDuration, duration)
        samples[cursor] = duration
        cursor = (cursor + 1) % samples.count
        count += 1
    }

    var diagnostics: [String: Any] {
        let sorted = samples.prefix(min(count, samples.count)).sorted()
        func percentile(_ fraction: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return sorted[Int(Double(sorted.count - 1) * fraction)]
        }
        return ["calls": count, "p50Milliseconds": percentile(0.50) * 1000,
                "p95Milliseconds": percentile(0.95) * 1000,
                "p99Milliseconds": percentile(0.99) * 1000,
                "maximumMilliseconds": maximumDuration * 1000,
                "maximumStartGapMilliseconds": maximumGap * 1000,
                "sampleCount": sorted.count]
    }
}
