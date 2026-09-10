import XCTest
@testable import CirclrCore
@testable import CirclrAudio

/// Independent note-duration references, CPU synth only. No helpers or audio device.
final class MIDISustainRenderTests: XCTestCase {
    private func pedal(_ seconds: Double, _ raw: Int) -> MIDITimedSustainState {
        .init(seconds: seconds, state: .init(rawValue: raw))
    }
    private func stream(_ id: String, _ notes: [Note], down: Bool = false,
                        events: [MIDITimedSustainState] = [], start: Double = 0, end: Double = 2,
                        bends: [MIDITimedPitchBendState] = []) -> MIDIPerformanceStream {
        // A fixed non-center seed forces the same owned-voice path in both actual
        // and independently authored reference, including references with no pedal.
        .init(id: id, sourceNodeID: id, sourceChannel: 0, notes: notes,
              startSeconds: start, endSeconds: end,
              initialPitchBend: .init(rawValue: 12288, range: .init(semitones: 2)),
              pitchBendStates: bends, initialSustain: .init(rawValue: down ? 127 : 0),
              sustainStates: events, hasPitchBendExpression: true)
    }
    private func render(_ notes: [Note], _ streams: [MIDIPerformanceStream], version: Int = 3,
                        block: Int = 257, release: Double = 0.1,
                        automation: [AutomationPlan] = []) throws -> PCM {
        var context = MusicContext(); context.tempo = 120
        let clock = try MusicClock(bars: 1, context: context)
        var patch = SynthPatch(.pad); patch.engineVersion = version
        patch.attack = 0.003; patch.decay = 0.02; patch.sustain = 0.8; patch.release = release
        patch.detune = 0; patch.motion = 0; patch.stereoWidth = 0; patch.cutoff = 7500
        return try ProductionInstrument.synth(notes, patch: patch, clock: clock, tail: 0.5,
            automation: automation, performances: streams, blockSize: block)
    }
    private func longer(_ note: Note, until seconds: Double) -> Note {
        var result = note; result.length = seconds * 2 - result.beat; return result
    }
    private func exact(_ actual: PCM, _ expected: PCM, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.left, expected.left, file: file, line: line)
        XCTAssertEqual(actual.right, expected.right, file: file, line: line)
    }
    private func rms(_ pcm: PCM, _ start: Double, _ end: Double) -> Double {
        let samples = pcm.left[Int(start * PCM.rate)..<Int(end * PCM.rate)]
        return sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
    }

    func testPedalHeldKeyOffMatchesAuthoredLongNoteForEveryEngine() throws {
        let note = Note(beat: 0, length: 0.5, pitch: 60, velocity: 100)
        let reference = longer(note, until: 1)
        for engine in [1, 2, 3] {
            let actual = try render([note], [stream("voice", [note], down: true, events: [pedal(1, 0)])], version: engine)
            let expected = try render([reference], [stream("voice", [reference])], version: engine)
            exact(actual, expected)
            XCTAssertGreaterThan(rms(actual, 0.5, 0.8), 0.0001)
            XCTAssertLessThan(rms(actual, 1.4, 1.8), rms(actual, 0.5, 0.8) * 0.01)
        }
    }

    func testPedalUpDoesNotReleaseAKeyStillHeld() throws {
        let note = Note(beat: 0, length: 3, pitch: 64, velocity: 94)
        exact(try render([note], [stream("key", [note], down: true, events: [pedal(0.5, 0)])]),
              try render([note], [stream("key", [note])]))
    }

    func testSamePitchRetriggerKeepsBothVoiceLifetimesIndependent() throws {
        let first = Note(beat: 0, length: 0.5, pitch: 60, velocity: 77)
        let second = Note(beat: 1, length: 0.5, pitch: 60, velocity: 103)
        let held = [longer(first, until: 1), longer(second, until: 1)]
        let actual = try render([first, second], [stream("retrigger", [first, second], down: true, events: [pedal(1, 0)])])
        exact(actual, try render(held, [stream("retrigger", held)]))
        XCTAssertGreaterThan(rms(actual, 0.8, 0.95), 0.0001)
    }

    func testSamePitchSourcesDoNotSharePedalState() throws {
        let first = Note(beat: 0, length: 0.5, pitch: 60, velocity: 79)
        let second = Note(beat: 0, length: 0.5, pitch: 60, velocity: 99)
        let held = longer(first, until: 1)
        let actual = try render([first, second], [stream("A", [first], down: true, events: [pedal(1, 0)]), stream("B", [second])])
        let reference = try render([held, second], [stream("A", [held]), stream("B", [second])])
        exact(actual, reference)
        XCTAssertGreaterThan(rms(actual, 0.5, 0.8), 0.0001)
    }

    func testSameTimeUpThenDownReleasesDeferredVoiceWithoutRecapture() throws {
        let note = Note(beat: 0, length: 0.5, pitch: 65, velocity: 100)
        let reference = longer(note, until: 0.75)
        let actual = try render([note], [stream("ordered", [note], down: true,
            events: [pedal(0.75, 0), pedal(0.75, 127), pedal(1.5, 0)])], release: 0.3)
        exact(actual, try render([reference], [stream("ordered", [reference])], release: 0.3))
        let reversed = try render([note], [stream("ordered", [note], down: true,
            events: [pedal(0.75, 127), pedal(0.75, 0)])], release: 0.3)
        exact(actual, reversed)
        // Dropping the up transition and retaining only final down would incorrectly
        // sustain this note until 1.5, unlike the independently authored reference.
    }

    func testPedalDownCannotRecaptureAnAlreadyReleasingVoice() throws {
        let note = Note(beat: 0, length: 0.5, pitch: 62, velocity: 96)
        exact(try render([note], [stream("release", [note], events: [pedal(0.5, 127), pedal(1, 0)])], release: 0.8),
              try render([note], [stream("release", [note])], release: 0.8))
    }

    func testStreamEndReleasesDeferredVoicesButNotLongerHeldKeys() throws {
        let short = Note(beat: 0, length: 0.25, pitch: 60, velocity: 90)
        let long = Note(beat: 0.25, length: 2.75, pitch: 67, velocity: 95)
        let held = longer(short, until: 0.5)
        let actual = try render([short, long], [stream("boundary", [short, long], down: true, end: 0.5)])
        exact(actual, try render([held, long], [stream("boundary", [held, long], end: 0.5)]))
        XCTAssertGreaterThan(rms(actual, 0.8, 1.2), 0.0001)
    }

    func testLoopOverlapKeepsOldReleaseSeparateFromNewPedalDomain() throws {
        let first = Note(beat: 0, length: 0.25, pitch: 60, velocity: 80)
        let second = Note(beat: 1, length: 0.25, pitch: 60, velocity: 100)
        let expectedNotes = [longer(first, until: 0.5), longer(second, until: 1)]
        let actual = try render([first, second], [
            stream("loop-0", [first], down: true, end: 0.5),
            stream("loop-1", [second], down: true, start: 0.5, end: 1)], release: 0.4)
        let expected = try render(expectedNotes, [
            stream("loop-0", [expectedNotes[0]], end: 0.5),
            stream("loop-1", [expectedNotes[1]], start: 0.5, end: 1)], release: 0.4)
        exact(actual, expected)
        XCTAssertGreaterThan(rms(actual, 0.55, 0.7), 0.0001)
    }

    func testBendAndFilterAutomationCoexistAndAreBlockIndependent() throws {
        let note = Note(beat: 0, length: 0.25, pitch: 60, velocity: 98)
        let held = longer(note, until: 1.25)
        let bends: [MIDITimedPitchBendState] = [
            .init(seconds: 0.4000208333333333, state: .init(rawValue: 0, range: .init(semitones: 7))),
            .init(seconds: 0.9000208333333333, state: .init(rawValue: 12288, range: .init(semitones: 12)))]
        let cutoff = AutomationPlan(parameter: .synthCutoff, spans: [
            AutomationSpan(start: 0, end: 2, from: 300, to: 6400, shape: .linear)])
        let resonance = AutomationPlan(parameter: .synthResonance, spans: [
            AutomationSpan(start: 0, end: 2, from: 0.1, to: 0.7, shape: .linear)])
        for engine in [1, 2, 3] {
            let automation = engine == 1 ? [cutoff] : [cutoff, resonance]
            let expected = try render([held], [stream("combined", [held], bends: bends)], version: engine, automation: automation)
            for block in [31, 64, 257] {
                let actual = try render([note], [stream("combined", [note], down: true,
                    events: [pedal(1.25, 0)], bends: bends)], version: engine, block: block, automation: automation)
                exact(actual, expected)
                XCTAssertTrue(actual.left.allSatisfy(\.isFinite)); XCTAssertGreaterThan(actual.peak, 0)
            }
        }
    }
}
