import XCTest
@testable import CirclrApp

final class MoviePresentationClockTests: XCTestCase {
    func testOneLateHelperReportBridgesAnEightyMillisecondHardwareGap() {
        var clock = MoviePresentationClock()
        let first = clock.next(workerSeconds: 1.000, captureUptime: 100)
        let bridge = clock.next(workerSeconds: 1.000, captureUptime: 100 + 1.0 / 30)
        let resumed = clock.next(workerSeconds: 1.080, captureUptime: 100 + 2.0 / 30)

        XCTAssertEqual(first ?? -1, 1.000, accuracy: 0.000_001)
        XCTAssertNotNil(bridge)
        XCTAssertGreaterThan(bridge ?? 0, first ?? 0)
        XCTAssertLessThanOrEqual(bridge ?? 0, 1.020_001)
        XCTAssertEqual(resumed ?? -1, 1.080, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual((resumed ?? 0) - (bridge ?? 0), 2.0 / 30 + 0.000_001)
        XCTAssertEqual(clock.diagnostics["staleInterpolatedFrames"] as? Int, 1)
    }

    func testOneLateHelperReportBridgesASeventyMillisecondHardwareGap() {
        var clock = MoviePresentationClock()
        XCTAssertEqual(clock.next(workerSeconds: 5.000, captureUptime: 100) ?? -1, 5.000, accuracy: 0.000_001)
        let bridge = clock.next(workerSeconds: 5.000, captureUptime: 100 + 1.0 / 30)
        let resumed = clock.next(workerSeconds: 5.070, captureUptime: 100 + 2.0 / 30)

        XCTAssertNotNil(bridge)
        XCTAssertLessThanOrEqual(bridge ?? 0, 5.020_001)
        XCTAssertEqual(resumed ?? -1, 5.070, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual((resumed ?? 0) - (bridge ?? 0), 2.0 / 30 + 0.000_001)
    }

    func testStoppedHardwareClockEmitsAtMostOneBoundedFrame() {
        var clock = MoviePresentationClock()
        XCTAssertEqual(clock.next(workerSeconds: 1, captureUptime: 100) ?? -1, 1, accuracy: 0.000_001)
        let bridge = clock.next(workerSeconds: 1, captureUptime: 100 + 1.0 / 30)
        XCTAssertNotNil(bridge)
        XCTAssertLessThanOrEqual(bridge ?? 0, 1.020_001)
        XCTAssertNil(clock.next(workerSeconds: 1, captureUptime: 100 + 2.0 / 30))
        XCTAssertNil(clock.next(workerSeconds: 1, captureUptime: 101))
        XCTAssertEqual(clock.diagnostics["staleInterpolatedFrames"] as? Int, 1)
        XCTAssertEqual(clock.lastWorkerSeconds, 1)
    }

    func testLateOrUnconfirmedSamplesCannotResumeAStoppedClock() {
        var clock = MoviePresentationClock()
        XCTAssertNil(clock.next(workerSeconds: 0, captureUptime: 100))
        XCTAssertEqual(clock.next(workerSeconds: 1, captureUptime: 101) ?? -1, 1, accuracy: 0.000_001)
        XCTAssertNil(clock.next(workerSeconds: 1, captureUptime: 101.100))
        XCTAssertNil(clock.next(workerSeconds: 0.9, captureUptime: 101.110))
        XCTAssertNil(clock.next(workerSeconds: .nan, captureUptime: 101.120))
        XCTAssertEqual(clock.next(workerSeconds: 1.2, captureUptime: 101.133) ?? -1, 1.2, accuracy: 0.000_001)
    }
}
