import Foundation

/// Lightweight callback timing; these samples are not compositor-present timestamps.
struct CanvasFrameTiming {
    private var samples = [Double](repeating: 0, count: 600)
    private var gaps = [Double](repeating: 0, count: 600)
    private var cursor = 0
    private var gapCursor = 0
    private var gapCount = 0
    private(set) var count = 0
    private(set) var maximumGap = 0.0
    private(set) var maximumDuration = 0.0
    private var previousStart = 0.0
    private var movieClock = MoviePresentationClock()

    var lastMovieWorkerSeconds: Double { movieClock.lastWorkerSeconds }
    mutating func resetMovieClock() { movieClock = MoviePresentationClock() }
    mutating func moviePresentationSeconds(workerSeconds: Double, captureUptime: Double) -> Double? {
        movieClock.next(workerSeconds: workerSeconds, captureUptime: captureUptime)
    }

    mutating func record(start: Double, end: Double) {
        guard start.isFinite, end.isFinite, end >= start else { return }
        if previousStart > 0 {
            let gap = start - previousStart
            maximumGap = max(maximumGap, gap)
            gaps[gapCursor] = gap
            gapCursor = (gapCursor + 1) % gaps.count
            gapCount += 1
        }
        previousStart = start
        let duration = end - start
        maximumDuration = max(maximumDuration, duration)
        samples[cursor] = duration
        cursor = (cursor + 1) % samples.count
        count += 1
    }

    var diagnostics: [String: Any] {
        let sorted = samples.prefix(min(count, samples.count)).sorted()
        let sortedGaps = gaps.prefix(min(gapCount, gaps.count)).sorted()
        func percentile(_ values: [Double], _ fraction: Double) -> Double {
            guard !values.isEmpty else { return 0 }
            return values[Int(Double(values.count - 1) * fraction)]
        }
        return ["calls": count, "p50Milliseconds": percentile(sorted, 0.50) * 1000,
                "p95Milliseconds": percentile(sorted, 0.95) * 1000,
                "p99Milliseconds": percentile(sorted, 0.99) * 1000,
                "maximumMilliseconds": maximumDuration * 1000,
                "maximumStartGapMilliseconds": maximumGap * 1000,
                "startGapP50Milliseconds": percentile(sortedGaps, 0.50) * 1000,
                "startGapP95Milliseconds": percentile(sortedGaps, 0.95) * 1000,
                "startGapP99Milliseconds": percentile(sortedGaps, 0.99) * 1000,
                "sampleCount": sorted.count, "startGapSampleCount": sortedGaps.count,
                "movieClock": movieClock.diagnostics]
    }
}

/// The helper reports hardware time every 20 ms while the canvas captures at
/// 30 Hz. Interpolate only between observed hardware samples; never continue
/// producing frames from the wall clock when the helper clock stalls.
struct MoviePresentationClock {
    private(set) var lastWorkerSeconds = 0.0
    private var lastPresentationSeconds = 0.0
    private var lastCaptureUptime: Double?
    private var resynchronizations = 0
    private var staleClockSkips = 0
    private var boundedInterpolations = 0

    mutating func next(workerSeconds: Double, captureUptime: Double) -> Double? {
        guard workerSeconds.isFinite, captureUptime.isFinite, workerSeconds >= 0,
              workerSeconds > lastWorkerSeconds else {
            staleClockSkips += 1
            return nil
        }
        let predicted = lastCaptureUptime.map { lastPresentationSeconds + max(0, captureUptime - $0) }
            ?? workerSeconds
        // The latest helper sample is a lower bound on audible output time.
        // One report interval is the largest lead a video PTS may take over it.
        let presentation = min(max(predicted, workerSeconds), workerSeconds + 0.020)
        guard presentation - lastPresentationSeconds >= 1.0 / 48_000 else {
            staleClockSkips += 1
            return nil
        }
        if predicted < workerSeconds { resynchronizations += 1 }
        if predicted > workerSeconds + 0.020 { boundedInterpolations += 1 }
        lastWorkerSeconds = workerSeconds
        lastPresentationSeconds = presentation
        lastCaptureUptime = captureUptime
        return presentation
    }

    var diagnostics: [String: Any] {
        ["lastWorkerSeconds": lastWorkerSeconds,
         "lastPresentationSeconds": lastPresentationSeconds,
         "leadMilliseconds": (lastPresentationSeconds - lastWorkerSeconds) * 1000,
         "resynchronizations": resynchronizations,
         "boundedInterpolations": boundedInterpolations,
         "staleClockSkips": staleClockSkips]
    }
}
