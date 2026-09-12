import XCTest
import CirclrCore
@testable import CirclrAudio

final class DriveQualityTests: XCTestCase {
    private func tone(_ frequency: Double, count: Int = 12000) -> PCM {
        var p = PCM(frames: count)
        p.left = (0..<count).map { Float(0.7 * sin(2 * .pi * frequency * Double($0) / PCM.rate)) }
        p.right = p.left
        return p
    }
    private func amplitude(_ p: PCM, frequency: Double) -> Double {
        let range = 1000..<11000
        var real = 0.0, imaginary = 0.0
        for i in range {
            let phase = 2 * Double.pi * frequency * Double(i) / PCM.rate
            real += Double(p.left[i]) * cos(phase)
            imaginary += Double(p.left[i]) * sin(phase)
        }
        return hypot(real, imaginary) * 2 / Double(range.count)
    }
    func testNewDriveReducesFoldbackWithoutRemovingFundamental() throws {
        let input = tone(9000)
        var legacy = Effect(.drive, amount: 0.7); legacy.renderVersion = 1
        let old = try NativeDSP.process(input, effect: legacy)
        let new = try NativeDSP.process(input, effect: Effect(.drive, amount: 0.7))
        // Third harmonic at 27 kHz folds to 21 kHz in the original renderer.
        XCTAssertLessThan(amplitude(new, frequency: 21000), amplitude(old, frequency: 21000) * 0.1)
        XCTAssertGreaterThan(amplitude(new, frequency: 9000), amplitude(old, frequency: 9000) * 0.85)
    }
    func testLegacyAbsentAndVersionsOneAndTwoRemainSampleExact() throws {
        let decoded = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"drive","amount":0.7,"secondary":0.25}"#.utf8))
        XCTAssertNil(decoded.renderVersion)
        var explicit = decoded; explicit.renderVersion = 1
        let input = tone(1234)
        let a = try NativeDSP.process(input, effect: decoded), b = try NativeDSP.process(input, effect: explicit)
        XCTAssertEqual(a.left, b.left)
        let inherited = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"drive","amount":0.7,"secondary":0.25,"renderVersion":2}"#.utf8))
        XCTAssertEqual(try NativeDSP.process(input, effect: inherited).left, a.left)
        let gain = Float(1 + 0.7 * 18), normalization = tanh(gain)
        XCTAssertEqual(a.left, input.left.map { tanh($0 * gain) / normalization })
        let fresh = Effect(.drive)
        XCTAssertEqual(fresh.renderVersion, 3)
        XCTAssertEqual(try JSONDecoder().decode(Effect.self, from: JSONEncoder().encode(fresh)), fresh)
    }
    func testSilenceStereoIsolationLengthAndImpulseTiming() throws {
        for count in [0, 1, 31, 1023, 1024, 1025] {
            let silence = try NativeDSP.process(PCM(frames: count), effect: Effect(.drive))
            XCTAssertEqual(silence.count, count)
            XCTAssertEqual(silence.peak, 0)
        }
        var impulse = PCM(frames: 3072); impulse.left[1024] = 0.5
        let out = try NativeDSP.process(impulse, effect: Effect(.drive, amount: 1))
        XCTAssertEqual(out.right, impulse.right)
        XCTAssertEqual(out.left.indices.max(by: { abs(out.left[$0]) < abs(out.left[$1]) }), 1024)
        XCTAssertTrue(out.left.allSatisfy(\.isFinite))
        // Filtering can overshoot slightly; do not silently hard-clip or add gain normalization.
        XCTAssertLessThan(out.peak, 2)
    }
    func testLowFrequencyGainAndChunkBoundaries() throws {
        let input = tone(240)
        var old = Effect(.drive, amount: 0.3); old.renderVersion = 1
        let reference = try NativeDSP.process(input, effect: old)
        let result = try NativeDSP.process(input, effect: Effect(.drive, amount: 0.3))
        XCTAssertEqual(amplitude(result, frequency: 240), amplitude(reference, frequency: 240), accuracy: 0.01)
        // Shift the same signal by a non-chunk multiple: the stationary output must shift exactly.
        var shifted = PCM(frames: input.count + 137)
        shifted.left.replaceSubrange(137..<shifted.count, with: input.left)
        let moved = try NativeDSP.process(shifted, effect: Effect(.drive, amount: 0.3))
        for i in 64..<(input.count - 64) { XCTAssertEqual(result.left[i], moved.left[i + 137]) }
    }
}
