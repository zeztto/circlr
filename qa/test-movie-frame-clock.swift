import Foundation

@main struct TestMovieFrameClock {
    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted[Int(Double(sorted.count - 1) * fraction)]
    }

    static func main() {
        var clock = MoviePresentationClock()
        var workerTimes = [Double]()
        var videoTimes = [Double]()
        // 30 Hz capture against the actual output helper's 20 ms clock packets.
        for frame in 1...375 {
            let uptime = Double(frame) / 30
            let worker = Double(Int((uptime - 0.004) / 0.020)) * 0.020
            guard let video = clock.next(workerSeconds: worker, captureUptime: uptime) else {
                fatalError("Fresh hardware clock was skipped at frame \(frame)")
            }
            assert(video >= worker && video <= worker + 0.020 + 0.000_001)
            assert(videoTimes.last.map { video > $0 } ?? true)
            workerTimes.append(worker)
            videoTimes.append(video)
        }
        let rawGaps = zip(workerTimes.dropFirst(), workerTimes).map(-)
        let pacedGaps = zip(videoTimes.dropFirst(), videoTimes).map(-)
        assert(percentile(rawGaps, 0.95) >= 0.039)
        assert(percentile(pacedGaps, 0.95) <= 0.034)
        assert(pacedGaps.max()! <= 0.041)

        let held = clock.lastWorkerSeconds
        assert(clock.next(workerSeconds: held, captureUptime: 12.8) == nil)
        assert(clock.next(workerSeconds: held, captureUptime: 13.1) == nil)
        // A resumed worker sample cannot let wall-clock elapsed time create a
        // 600 ms leap or run more than one helper period ahead of audible time.
        let resumed = clock.next(workerSeconds: held + 0.020, captureUptime: 13.13)!
        assert(resumed > videoTimes.last!)
        assert(resumed <= held + 0.040 + 0.000_001)
        // Elapsed hardware time is monotonic across musical loop wraps.
        let nextLoop = clock.next(workerSeconds: held + 0.060, captureUptime: 13.163)!
        assert(nextLoop > resumed)

        // A new recording has no timestamp history from the stopped one.
        clock = MoviePresentationClock()
        assert(clock.next(workerSeconds: 0, captureUptime: 20) == nil)
        assert(clock.next(workerSeconds: 0.020, captureUptime: 20.033) == 0.020)
        assert(clock.next(workerSeconds: .nan, captureUptime: 20.066) == nil)

        var timing = CanvasFrameTiming()
        for sample in 0..<650 {
            let start = 1 + Double(sample) * 0.020
            timing.record(start: start, end: start + 0.004)
        }
        let values = timing.diagnostics
        assert(values["startGapSampleCount"] as? Int == 600)
        assert(abs((values["startGapP95Milliseconds"] as! Double) - 20) < 0.001)
        assert(abs((values["p95Milliseconds"] as! Double) - 4) < 0.001)
        print("MovieFrameClock QA PASS: raw p95 \(percentile(rawGaps, 0.95) * 1000) ms; paced p95 \(percentile(pacedGaps, 0.95) * 1000) ms")
    }
}
