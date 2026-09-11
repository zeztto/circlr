import XCTest
import CirclrRealtime

final class SynthSustainAPITests: XCTestCase {
    private func engine(_ version: Int) throws -> OpaquePointer {
        let pointer: OpaquePointer?
        switch version {
        case 1: pointer = circlr_synth_create(0, 1200, 0.001, 0.1, 0.8, 0.1, 7)
        case 2: pointer = circlr_synth_create_v2(0, 1200, 0.001, 0.1, 0.8, 0.1, 7, 0.2, 0.7, 1)
        default: pointer = circlr_synth_create_v3(0, 1200, 0.001, 0.1, 0.8, 0.1, 7, 0.2, 0.7, 1, 0.5, 0.2)
        }
        return try XCTUnwrap(pointer)
    }
    private func pcm(_ engine: OpaquePointer, frames: Int = 257) -> [Float] {
        var left = [Float](repeating: 0, count: frames), right = left
        circlr_synth_render(engine, &left, &right, UInt32(frames))
        return left + right
    }
    private func start(_ engine: OpaquePointer, stream: UInt64 = 1, voice: UInt64 = 1) {
        XCTAssertEqual(circlr_synth_owned_note_on(engine, stream, voice, 60, 100, 0), 1)
    }

    func testLegacyNoteOffAndPedalOffZeroAreByteExactAllEngines() throws {
        for version in 1...3 {
            let a = try engine(version), b = try engine(version)
            defer { circlr_synth_destroy(a); circlr_synth_destroy(b) }
            start(a); start(b)
            XCTAssertEqual(pcm(a), pcm(b))
            XCTAssertEqual(circlr_synth_owned_note_off(a, 1, 1), 1)
            XCTAssertEqual(circlr_synth_owned_note_off_pedal(b, 1, 1, 0), 1)
            for _ in 0..<24 { XCTAssertEqual(pcm(a), pcm(b)) }
        }
    }

    func testInvalidArgumentsDoNotMutateDeferredVoicePCM() throws {
        XCTAssertEqual(circlr_synth_owned_note_off_pedal(nil, 1, 1, 1), 0)
        XCTAssertEqual(circlr_synth_owned_sustain_release(nil, 1), 0)
        for version in 1...3 {
            let a = try engine(version), b = try engine(version)
            defer { circlr_synth_destroy(a); circlr_synth_destroy(b) }
            start(a); start(b); XCTAssertEqual(pcm(a), pcm(b))
            XCTAssertEqual(circlr_synth_owned_note_off_pedal(a, 1, 1, 1), 1)
            XCTAssertEqual(circlr_synth_owned_note_off_pedal(b, 1, 1, 1), 1)
            for (stream, voice, down) in [(UInt64(0), UInt64(1), Int32(0)), (1, 0, 0), (1, 1, -1), (1, 1, 2)] {
                XCTAssertEqual(circlr_synth_owned_note_off_pedal(a, stream, voice, down), 0)
                XCTAssertEqual(pcm(a), pcm(b))
            }
            XCTAssertEqual(circlr_synth_owned_sustain_release(a, 0), 0)
            XCTAssertEqual(pcm(a), pcm(b))
        }
    }

    func testRepeatedReleaseCannotRecaptureVoiceAndStaleIdentityIsNoOp() throws {
        for version in 1...3 {
            let a = try engine(version), b = try engine(version)
            defer { circlr_synth_destroy(a); circlr_synth_destroy(b) }
            start(a); start(b); XCTAssertEqual(pcm(a), pcm(b))
            for e in [a, b] { XCTAssertEqual(circlr_synth_owned_note_off_pedal(e, 1, 1, 1), 1) }
            XCTAssertEqual(circlr_synth_owned_note_off_pedal(a, 1, 1, 1), 1)
            XCTAssertEqual(pcm(a), pcm(b))
            for e in [a, b] { XCTAssertEqual(circlr_synth_owned_sustain_release(e, 1), 1) }
            for _ in 0..<24 {
                XCTAssertEqual(circlr_synth_owned_note_off_pedal(a, 1, 1, 1), 1)
                XCTAssertEqual(circlr_synth_owned_sustain_release(a, 1), 1)
                XCTAssertEqual(circlr_synth_owned_note_off_pedal(a, 9, 1, 0), 1)
                XCTAssertEqual(circlr_synth_owned_note_off_pedal(a, 1, 999, 0), 1)
                XCTAssertEqual(pcm(a), pcm(b))
            }
        }
    }

    func testStealingDeferredVoiceDoesNotReleaseReplacement() throws {
        for version in 1...3 {
            let a = try engine(version), b = try engine(version)
            defer { circlr_synth_destroy(a); circlr_synth_destroy(b) }
            for e in [a, b] { start(e); XCTAssertEqual(circlr_synth_owned_note_off_pedal(e, 1, 1, 1), 1) }
            XCTAssertEqual(pcm(a), pcm(b)) // Make voice 1 uniquely oldest.
            for voice in UInt64(2)...65 { start(a, stream: 2, voice: voice); start(b, stream: 2, voice: voice) }
            XCTAssertEqual(circlr_synth_owned_note_off_pedal(a, 1, 1, 0), 1)
            XCTAssertEqual(circlr_synth_owned_sustain_release(a, 1), 1)
            let actual = pcm(a), expected = pcm(b)
            XCTAssertEqual(actual, expected); XCTAssertTrue(actual.allSatisfy(\.isFinite))
            XCTAssertGreaterThan(actual.map { abs($0) }.max() ?? 0, 0)
        }
    }

    func testPedalUpOnlyReleasesDeferredKeysInItsOwnStream() throws {
        for version in 1...3 {
            let a = try engine(version), b = try engine(version)
            defer { circlr_synth_destroy(a); circlr_synth_destroy(b) }
            for e in [a, b] {
                start(e); start(e, voice: 2); start(e, stream: 2, voice: 3)
            }
            XCTAssertEqual(pcm(a), pcm(b))
            for e in [a, b] {
                XCTAssertEqual(circlr_synth_owned_note_off_pedal(e, 1, 1, 1), 1)
                XCTAssertEqual(circlr_synth_owned_note_off_pedal(e, 2, 3, 1), 1)
            }
            XCTAssertEqual(circlr_synth_owned_sustain_release(a, 1), 1)
            XCTAssertEqual(circlr_synth_owned_note_off(b, 1, 1), 1)
            for _ in 0..<24 { XCTAssertEqual(pcm(a), pcm(b)) }
        }
    }
}
