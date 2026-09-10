import XCTest
@testable import CirclrCore
@testable import CirclrAudio

/// CPU synth fixtures only: no sampler, AU worker, output device or live engine.
final class MIDIPitchBendRenderTests: XCTestCase {
    private func clock() throws -> MusicClock {
        var context = MusicContext(); context.tempo = 120
        return try MusicClock(bars: 1, context: context)
    }
    private func patch(_ version: Int = 3, release: Double = 0.05) -> SynthPatch {
        var p = SynthPatch(.pad); p.engineVersion = version
        p.cutoff = 18000; p.attack = 0.003; p.decay = 0.02; p.sustain = 0.8
        p.release = release; p.detune = 0; p.resonance = 0; p.stereoWidth = 0
        p.filterEnvelope = 0; p.motion = 0
        return p
    }
    private func state(_ raw: Int = 8192, range: Int = 2) -> MIDIPitchBendState {
        .init(rawValue: raw, range: .init(semitones: range))
    }
    private func stream(_ id: String, notes: [Note], initial: MIDIPitchBendState,
                        start: Double = 0, end: Double = 2, channel: Int = 0,
                        events: [MIDITimedPitchBendState] = [], source: String = "source") -> MIDIPerformanceStream {
        .init(id: id, sourceNodeID: source, sourceChannel: channel, notes: notes,
              startSeconds: start, endSeconds: end, initialPitchBend: initial, pitchBendStates: events)
    }
    private func render(_ notes: [Note], _ streams: [MIDIPerformanceStream],
                        version: Int = 3, block: Int = 1024, release: Double = 0.05,
                        automation: [AutomationPlan] = []) throws -> PCM {
        try ProductionInstrument.synth(notes, patch: patch(version, release: release), clock: clock(),
            tail: 0.6, automation: automation, performances: streams, blockSize: block)
    }
    private func assertExact(_ a: PCM, _ b: PCM, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.left, b.left, file: file, line: line)
        XCTAssertEqual(a.right, b.right, file: file, line: line)
    }
    /// Global fundamental-band spectral peak, independent of the asserted pitch.
    /// Hann-windowed Goertzel avoids autocorrelation's integer-period multiple ambiguity.
    private func frequency(_ pcm: PCM, from: Double, to: Double) -> Double {
        let first = Int(from * PCM.rate), last = Int(to * PCM.rate)
        let input = pcm.left[first..<last].map(Double.init)
        guard input.count > 512 else { return .nan }
        let samples = input.enumerated().map { index, value in
            value * (0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(input.count - 1)))
        }
        var peakPower = 0.0, peakHz = Double.nan
        for hz in 150...1000 {
            let coefficient = 2 * cos(2 * Double.pi * Double(hz) / PCM.rate)
            var previous = 0.0, previous2 = 0.0
            for sample in samples {
                let next = sample + coefficient * previous - previous2
                previous2 = previous; previous = next
            }
            let power = previous * previous + previous2 * previous2 - coefficient * previous * previous2
            if power > peakPower { peakPower = power; peakHz = Double(hz) }
        }
        return peakHz
    }
    private func energy(_ pcm: PCM, from: Double, to: Double) -> Double {
        let values = pcm.left[Int(from * PCM.rate)..<Int(to * PCM.rate)]
        return values.reduce(0) { $0 + Double($1) * Double($1) } / Double(values.count)
    }

    func testNilAndExplicitCenterPreserveLegacyPCMForAllEngines() throws {
        let notes = [Note(beat: 0, length: 2, pitch: 69, velocity: 100),
                     Note(beat: 0.5, length: 1, pitch: 64, velocity: 83)]
        for version in [1, 2, 3] {
            let legacy = try ProductionInstrument.synth(notes, patch: patch(version), clock: clock(), tail: 0.6)
            assertExact(legacy, try render(notes, [], version: version))
            let centered = stream("center", notes: notes, initial: state(), events: [
                .init(seconds: 0.25, state: state(8192, range: 24))])
            assertExact(legacy, try render(notes, [centered], version: version))
        }
    }

    func testConstantOctaveBendHasObjectiveFrequencyForEveryEngine() throws {
        let note = Note(beat: 0, length: 3.5, pitch: 69, velocity: 100)
        for version in [1, 2, 3] {
            let low = try render([note], [stream("low", notes: [note], initial: state(0, range: 12))], version: version)
            let high = try render([note], [stream("high", notes: [note], initial: state(12288, range: 24))], version: version)
            XCTAssertEqual(frequency(low, from: 0.5, to: 1.5), 220, accuracy: 3, "engine \(version) pad down octave")
            XCTAssertEqual(frequency(high, from: 0.5, to: 1.5), 880, accuracy: 3, "engine \(version) pad up octave")
        }
    }

    func testSamePitchFanInDifferentSourceReleaseDoesNotStopOtherVoice() throws {
        let short = Note(beat: 0, length: 0.4, pitch: 69, velocity: 90)
        let held = Note(beat: 0, length: 3.5, pitch: 69, velocity: 100)
        let streams = [stream("short", notes: [short], initial: state(0, range: 12), source: "lane-a"),
                       stream("held", notes: [held], initial: state(12288, range: 24), source: "lane-b")]
        let pcm = try render([short, held], streams)
        XCTAssertGreaterThan(energy(pcm, from: 0.5, to: 1.5), 0.000001)
        XCTAssertEqual(frequency(pcm, from: 0.5, to: 1.5), 880, accuracy: 3)
        let heldOnly = try render([held], [streams[1]])
        XCTAssertEqual(Array(pcm.left[48000..<72000]), Array(heldOnly.left[48000..<72000]))
    }

    func testRepeatDomainsHoldReleaseBendAndDoNotRetunePriorTail() throws {
        let first = Note(beat: 0, length: 0.8, pitch: 69, velocity: 100)
        let next = Note(beat: 1, length: 2.5, pitch: 69, velocity: 100)
        let previous = stream("repeat-0", notes: [first], initial: state(0, range: 12), end: 0.5)
        let repeated = stream("repeat-1", notes: [next], initial: state(12288, range: 24), start: 0.5)
        let both = try render([first, next], [previous, repeated], release: 0.4)
        let tail = try render([first], [previous], release: 0.4)
        // Before the next onset, adding its future domain changes no earlier samples.
        XCTAssertEqual(Array(both.left[..<24000]), Array(tail.left[..<24000]))
        XCTAssertGreaterThan(energy(tail, from: 0.5, to: 0.65), 0.0000001)
        XCTAssertEqual(frequency(tail, from: 0.5, to: 0.65), 220, accuracy: 10)
        XCTAssertEqual(frequency(both, from: 1.1, to: 1.6), 880, accuracy: 4)
    }

    func testRangeChangeIsHeldAndEqualSampleEventsUseStoredOrder() throws {
        let note = Note(beat: 0, length: 3.5, pitch: 69, velocity: 100)
        let up = state(12288, range: 24), center = state()
        let ordered = stream("ordered", notes: [note], initial: state(12288, range: 2), events: [
            .init(seconds: 0.5, state: center), .init(seconds: 0.5, state: up)])
        let reversed = stream("ordered", notes: [note], initial: state(12288, range: 2), events: [
            .init(seconds: 0.5, state: up), .init(seconds: 0.5, state: center)])
        let a = try render([note], [ordered]), b = try render([note], [reversed])
        XCTAssertEqual(Array(a.left[..<24000]), Array(b.left[..<24000]))
        XCTAssertEqual(frequency(a, from: 0.1, to: 0.4), 440 * pow(2, 1.0 / 12), accuracy: 7)
        XCTAssertEqual(frequency(a, from: 0.8, to: 1.5), 880, accuracy: 4)
        XCTAssertEqual(frequency(b, from: 0.8, to: 1.5), 440, accuracy: 4)
    }

    func testBendAndCutoffTogetherAreBlockIndependent() throws {
        let note = Note(beat: 0, length: 3, pitch: 69, velocity: 100)
        let expression = stream("block", notes: [note], initial: state(0, range: 12), events: [
            .init(seconds: 0.10002083333333334, state: state(12288, range: 24)),
            .init(seconds: 0.7000208333333333, state: state())])
        let cutoff = AutomationPlan(parameter: .synthCutoff, spans: [
            AutomationSpan(start: 0, end: 2, from: 400, to: 6400, shape: .linear)])
        for version in [1, 2, 3] {
            let expected = try render([note], [expression], version: version, block: 257, automation: [cutoff])
            for block in [64, 1024] {
                assertExact(expected, try render([note], [expression], version: version, block: block, automation: [cutoff]))
            }
            XCTAssertGreaterThan(expected.peak, 0)
            XCTAssertTrue(expected.left.allSatisfy(\.isFinite))
        }
    }

    func testInvalidStreamIsRejectedEvenWhenCenterWouldUseLegacyPath() throws {
        let note = Note(beat: 0, length: 1, pitch: 69)
        let valid = stream("valid", notes: [note], initial: state())
        let invalid = [stream("raw", notes: [note], initial: state(16384)),
                       stream("channel", notes: [note], initial: state(), channel: 16),
                       stream("time", notes: [note], initial: state(), events: [.init(seconds: .nan, state: state())]),
                       stream("range", notes: [note], initial: state(8192, range: 128)),
                       stream("end", notes: [note], initial: state(), events: [.init(seconds: 2, state: state())])]
        for value in invalid { XCTAssertThrowsError(try render([note], [value])) }
        XCTAssertThrowsError(try render([note], [valid, valid]))
        XCTAssertThrowsError(try render([], [valid]))
        XCTAssertThrowsError(try render([note], [valid], block: 0))
        XCTAssertThrowsError(try render([note], [valid], block: 65537))
    }

    func testEventBudgetRejectsBeforeRendering() throws {
        let note = Note(beat: 0, length: 1, pitch: 69)
        // Two note events each already exceed the one-million total-event budget.
        let excessive = Array(repeating: note, count: 500_001)
        XCTAssertThrowsError(try render(excessive, [stream("budget", notes: [], initial: state(0))]))
    }

    func testCompiledTempoOverrideReachesPreOutputBounceRender() async throws {
        var project = Project(); project.global.tempo = 137
        _ = project.addTrack(name: "CPU tempo bend")
        _ = project.addSection(name: "variable clock", at: Point(), bars: 1)
        project.tracks[0].instrument = .synthesizer(.pad)
        project.tracks[0].instrument.synth = patch()
        project.sections[0].lanes[0].notes = [Note(beat: 0, length: 3.8, pitch: 69, velocity: 100)]
        project.sections[0].lanes[0].pitchBend = .init(initialValue: 0, initialRange: .init(semitones: 12), events: [
            .init(beat: 2, kind: .range(.init(semitones: 24))), .init(beat: 2, kind: .value(12288))])
        project.schemaVersion = 5
        project = try SectionGraphMigration.migrate(project)
        project.arrangements[0].uses[0].tempoOverride = .init(initialBPM: 137, changes: [.init(beat: 2, bpm: 83)])
        let outputIndex = try XCTUnwrap(project.sections[0].graph?.nodes.firstIndex {
            if case .output = $0.content { return true }; return false
        })
        project.sections[0].graph?.nodes[outputIndex].gain = 0.25
        let before = project
        let compiled = try ArrangementCompiler.compile(project)
        let plan = try XCTUnwrap(compiled.occurrences.first?.signalPlan)
        let (_, _, clock) = try ArrangementCompiler.context(project: project, use: project.active.uses[0])
        let streams = plan.midiPerformances.values.flatMap { $0 }
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].pitchBendStates[0].seconds, 120.0 / 137, accuracy: 1e-12)
        XCTAssertEqual(clock.seconds, 120.0 / 137 + 120.0 / 83, accuracy: 1e-12)
        let pre = try await SectionGraphRenderer.render(plan, project: project, root: nil, clock: clock,
                                                       tail: 0.2, applyOutputGain: false)
        let post = try await SectionGraphRenderer.render(plan, project: project, root: nil, clock: clock,
                                                        tail: 0.2, applyOutputGain: true)
        let raw = try XCTUnwrap(pre[project.tracks[0].id]), gained = try XCTUnwrap(post[project.tracks[0].id])
        XCTAssertGreaterThan(raw.peak, 0)
        XCTAssertEqual(gained.peak, raw.peak * 0.25, accuracy: 1e-7)
        XCTAssertEqual(frequency(raw, from: 0.2, to: 0.7), 220, accuracy: 4)
        XCTAssertEqual(frequency(raw, from: 1.2, to: 1.8), 880, accuracy: 4)
        XCTAssertEqual(project, before)
    }

    func testCompiledSharedRepeatsWithLocalTempoRenderWithoutClockRoundoffRejection() async throws {
        var project = Project(); project.global.tempo = 120
        _ = project.addTrack(name: "CPU repeated bend")
        _ = project.addSection(name: "shared local clock", at: Point(), bars: 4)
        project.tracks[0].instrument = .synthesizer(.pad); project.tracks[0].instrument.synth = patch(release: 0.2)
        var pattern = RhythmPattern(name: "shared phrase", trackID: project.tracks[0].id)
        pattern.length = 2; pattern.notes = [Note(beat: 0.25, length: 2.5, pitch: 69, velocity: 100)]
        pattern.pitchBend = .init(initialValue: 0, initialRange: .init(semitones: 12), events: [
            .init(beat: 0.5, kind: .value(12288))])
        project.patterns = [pattern]; project.global.rhythm = RhythmAssignment(pattern.id); project.schemaVersion = 5
        project = try SectionGraphMigration.migrate(project)
        let index = try XCTUnwrap(project.sections[0].graph?.nodes.firstIndex {
            if case .rhythmMIDI = $0.content { return true }; return false
        })
        project.sections[0].graph?.nodes[index].lengthBeats = 4
        project.sections[0].graph?.nodes[index].repeatCount = 2
        project.sections[0].graph?.nodes[index].settings.tempo = .local(90)
        let plan = try XCTUnwrap(ArrangementCompiler.compile(project).occurrences.first?.signalPlan)
        let streams = plan.midiPerformances.values.flatMap { $0 }.sorted { $0.startSeconds < $1.startSeconds }
        XCTAssertEqual(streams.count, 4); XCTAssertEqual(Set(streams.map(\.id)).count, 4)
        for (stream, expected) in zip(streams, [0.0, 4.0 / 3, 8.0 / 3, 4.0]) {
            XCTAssertEqual(stream.startSeconds, expected, accuracy: 1e-12)
            XCTAssertEqual(stream.pitchBendStates[0].seconds, expected + 1.0 / 3, accuracy: 1e-12)
        }
        XCTAssertGreaterThan(streams[0].notes[0].beat + streams[0].notes[0].length, streams[1].notes[0].beat)
        let (_, _, clock) = try ArrangementCompiler.context(project: project, use: project.active.uses[0])
        let tracks = try await SectionGraphRenderer.render(plan, project: project, root: nil, clock: clock,
                                                          tail: 0.3, applyOutputGain: false)
        let pcm = try XCTUnwrap(tracks[project.tracks[0].id])
        XCTAssertGreaterThan(pcm.peak, 0); XCTAssertTrue(pcm.left.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(energy(pcm, from: 4.3, to: 4.6), 0.000001)
    }


    func testDecimalLocalClockRoundTripDoesNotRejectCompiledOnsets() async throws {
        var project = Project(); project.global.tempo = 123.45
        _ = project.addTrack(name: "decimal clock")
        _ = project.addSection(name: "repeats", at: Point(), bars: 4)
        project.tracks[0].instrument = .synthesizer(.pad); project.tracks[0].instrument.synth = patch()
        project.sections[0].lanes[0].notes = [Note(beat: 0, length: 0.1, pitch: 69)]
        project.sections[0].lanes[0].pitchBend = .init(initialValue: 0)
        project.schemaVersion = 5; project = try SectionGraphMigration.migrate(project)
        let index = try XCTUnwrap(project.sections[0].graph?.nodes.firstIndex {
            if case .midi = $0.content { return true }; return false
        })
        project.sections[0].graph?.nodes[index].startBeat = 0.375
        project.sections[0].graph?.nodes[index].lengthBeats = 0.25
        project.sections[0].graph?.nodes[index].repeatCount = 32
        project.sections[0].graph?.nodes[index].settings.tempo = .local(99.9)
        let plan = try XCTUnwrap(ArrangementCompiler.compile(project).occurrences.first?.signalPlan)
        let streams = plan.midiPerformances.values.flatMap { $0 }.sorted { $0.startSeconds < $1.startSeconds }
        XCTAssertEqual(streams.count, 32)
        let (_, _, clock) = try ArrangementCompiler.context(project: project, use: project.active.uses[0])
        let stream = streams[25]
        XCTAssertLessThan(abs(clock.seconds(at: stream.notes[0].beat) - stream.startSeconds), 1e-9)
        let tracks = try await SectionGraphRenderer.render(plan, project: project, root: nil, clock: clock,
                                                          tail: 0.1, applyOutputGain: false)
        XCTAssertGreaterThan(try XCTUnwrap(tracks[project.tracks[0].id]).peak, 0)
    }

    func testLegacyAndCenterSameFrameQueueLimitRejectOverflow() throws {
        let note = Note(beat: 0, length: 0.1, pitch: 69)
        let boundary = Array(repeating: note, count: 2048)
        let excessive = Array(repeating: note, count: 2049)
        let shortClock = try clock()
        XCTAssertNoThrow(try ProductionInstrument.synth(boundary, patch: patch(), clock: shortClock, tail: 0))
        XCTAssertThrowsError(try ProductionInstrument.synth(excessive, patch: patch(), clock: shortClock, tail: 0))
        XCTAssertNoThrow(try render(boundary, [stream("center-limit", notes: boundary, initial: state())]))
        XCTAssertThrowsError(try render(excessive, [stream("center-over", notes: excessive, initial: state())]))
    }


    func testPitchBendBounceArchiveSaveLoadAndRestorePreserveSourceAndPCM() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-pitch-bounce-\(newID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var project = Project(); project.global.tempo = 120
        let trackID = project.addTrack(name: "CPU bend archive")
        let useID = project.addSection(name: "bounce", at: Point(), bars: 1)
        project.tracks[0].instrument = .synthesizer(.pad); project.tracks[0].instrument.synth = patch()
        let expression = MIDIPitchBendSequence(initialValue: 12288, initialRange: .init(semitones: 24), events: [
            .init(beat: 1, kind: .value(8192)), .init(beat: 2, kind: .value(0))])
        project.sections[0].lanes[0].notes = [Note(beat: 0, length: 3, pitch: 69, velocity: 100)]
        project.sections[0].lanes[0].pitchBend = expression; project.schemaVersion = 5
        project = try SectionGraphMigration.migrate(project)
        let sourceNotes = project.sections[0].lanes[0].notes
        let sourceGraph = try XCTUnwrap(SectionGraphEditing.effective(section: project.sections[0], use: project.active.uses[0]))
        func renderProject(_ p: Project, root: URL?, preOutput: Bool = false) async throws -> PCM {
            let occurrence = try XCTUnwrap(ArrangementCompiler.compile(p).occurrences.first)
            let plan = try XCTUnwrap(occurrence.signalPlan)
            let (_, _, clock) = try ArrangementCompiler.context(project: p, use: p.active.uses[0])
            let outputs = try await SectionGraphRenderer.render(plan, project: p, root: root, clock: clock,
                tail: 0.25, applyOutputGain: !preOutput)
            return try XCTUnwrap(outputs[trackID])
        }
        let original = try await renderProject(project, root: nil)
        let preOutput = try await renderProject(project, root: nil, preOutput: true)
        XCTAssertGreaterThan(original.peak, 0)
        let wav = directory.appendingPathComponent("rendered.wav")
        try preOutput.writeWAV(wav)
        let (_, _, clock) = try ArrangementCompiler.context(project: project, use: project.active.uses[0])
        let nodeID = try BounceEditing.apply(asset: Asset(name: "bend archive", path: wav.path,
            duration: preOutput.duration, sampleRate: PCM.rate), trackID: trackID, useID: useID,
            bodySeconds: clock.seconds, tailSeconds: 0.25, in: &project)
        XCTAssertEqual(project.sections[0].lanes[0].pitchBend, expression)
        XCTAssertEqual(project.sections[0].lanes[0].notes, sourceNotes)
        let package = directory.appendingPathComponent("saved.circlr")
        _ = try ProjectStore.save(project, to: package, mediaRoot: nil)
        let loaded = try ProjectStore.load(package)
        project = loaded.project
        let bounced = try await renderProject(project, root: loaded.root)
        XCTAssertEqual(bounced.count, original.count)
        let difference = max(zip(bounced.left, original.left).map { abs($0 - $1) }.max() ?? 1,
                             zip(bounced.right, original.right).map { abs($0 - $1) }.max() ?? 1)
        XCTAssertLessThanOrEqual(difference, 4 / Float(8_388_608), "24-bit bounce quantization only")
        let archivedGraph = try XCTUnwrap(SectionGraphEditing.effective(section: project.sections[0], use: project.active.uses[0]))
        let archived = try XCTUnwrap(archivedGraph.nodes.first { $0.id == nodeID })
        XCTAssertNotNil(archived.bounce)
        XCTAssertEqual(project.sections[0].lanes[0].pitchBend, expression)
        try BounceEditing.restore(nodeID: nodeID, useID: useID, in: &project)
        let restoredGraph = try XCTUnwrap(SectionGraphEditing.effective(section: project.sections[0], use: project.active.uses[0]))
        let retained = try XCTUnwrap(restoredGraph.nodes.first { $0.id == nodeID })
        XCTAssertTrue(retained.muted); XCTAssertNil(retained.bounce)
        XCTAssertEqual(restoredGraph.edges.sorted { $0.id < $1.id }, sourceGraph.edges.sorted { $0.id < $1.id })
        XCTAssertEqual(project.sections[0].lanes[0].pitchBend, expression)
        XCTAssertEqual(project.sections[0].lanes[0].notes, sourceNotes)
        let restored = try await renderProject(project, root: loaded.root)
        assertExact(original, restored)
        let originalWAV = directory.appendingPathComponent("before.wav")
        let restoredWAV = directory.appendingPathComponent("restored.wav")
        try original.writeWAV(originalWAV); try restored.writeWAV(restoredWAV)
        XCTAssertEqual(try Data(contentsOf: originalWAV), try Data(contentsOf: restoredWAV))
    }

}
