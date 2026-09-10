import XCTest
@testable import CirclrCore
@testable import CirclrAudio

/// Export/parser interoperability and offline CPU PCM; never opens an output device.
final class MIDIPitchBendExportRoundTripTests: XCTestCase {
    private func lane(_ sequence: MIDIPitchBendSequence?, pitch: Int = 69) -> Lane {
        var lane = Lane(trackID: newID())
        lane.notes = [Note(beat: 0.25, length: 3, pitch: pitch, velocity: 100)]
        lane.pitchBend = sequence
        return lane
    }
    private func read(_ sources: [(String, Lane)], changes: [TempoChange] = []) throws -> ImportedMIDI {
        try MIDIImport.read(MIDIFile.encode(sources: sources, tempo: 120, meter: Meter(), tempoChanges: changes))
    }
    private func stateEqual(_ original: MIDIPitchBendSequence, _ imported: MIDIPitchBendSequence,
                            ticks: [Int], file: StaticString = #filePath, line: UInt = #line) throws {
        var quantized = original
        quantized.events = original.events.map { .init(beat: ($0.beat * 960).rounded() / 960, kind: $0.kind) }
        for tick in ticks {
            XCTAssertEqual(try quantized.state(atBeat: Double(tick) / 960),
                           try imported.state(atBeat: Double(tick) / 960),
                           "tick \(tick)", file: file, line: line)
        }
    }

    func testInitialSeedRangeOnlyAndRawWheelStatesRoundTripSemantically() throws {
        let sequences: [MIDIPitchBendSequence] = [
            .init(channel: 4, initialValue: 0, initialRange: .init(semitones: 12, cents: 127)),
            .init(channel: 4, initialRange: .init(semitones: 7, cents: 50), events: [
                .init(beat: 1, kind: .range(.init(semitones: 24, cents: 1)))]),
            .init(channel: 4, events: [.init(beat: 0.5, kind: .value(0)),
                .init(beat: 1, kind: .value(8192)), .init(beat: 2, kind: .value(16383))])
        ]
        for sequence in sequences {
            let document = try read([("표현", lane(sequence))])
            let track = try XCTUnwrap(document.tracks.first)
            let recovered = try XCTUnwrap(track.pitchBend)
            try stateEqual(sequence, recovered, ticks: [0, 479, 480, 959, 960, 1919, 1920, 3000])
            XCTAssertTrue(document.issues(selectedIDs: [track.id]).isEmpty)
            XCTAssertEqual(try document.importParts(selectedIDs: [track.id]).first?.pitchBend, recovered)
        }
    }

    func testSameTickOrderAnd960PPQQuantizationKeepFinalState() throws {
        let sequence = MIDIPitchBendSequence(initialValue: 12288, events: [
            .init(beat: 0.5001, kind: .value(0)),
            .init(beat: 0.5002, kind: .range(.init(semitones: 12, cents: 50))),
            .init(beat: 0.5003, kind: .value(16383)),
            .init(beat: 1, kind: .value(8192)),
            .init(beat: 1, kind: .range(.init(semitones: 3, cents: 127))),
            .init(beat: 1, kind: .value(12288))])
        let document = try read([("tick order", lane(sequence))])
        let recovered = try XCTUnwrap(document.tracks.first?.pitchBend)
        try stateEqual(sequence, recovered, ticks: [0, 479, 480, 481, 959, 960, 961])
        XCTAssertEqual(try recovered.state(atBeat: 0.5).rawValue, 16383)
        XCTAssertEqual(try recovered.state(atBeat: 1).range, .init(semitones: 3, cents: 127))
    }

    func testSameSourceChannelIsRemappedWithoutCrossTalkAndNilLaneGetsCenterSeed() throws {
        let down = MIDIPitchBendSequence(channel: 3, initialValue: 0, initialRange: .init(semitones: 12))
        let up = MIDIPitchBendSequence(channel: 3, initialValue: 12288, initialRange: .init(semitones: 24))
        let document = try read([("down", lane(down, pitch: 60)), ("up", lane(up, pitch: 64)), ("plain", lane(nil, pitch: 67))])
        XCTAssertEqual(document.tracks.count, 3)
        XCTAssertEqual(Set(document.tracks.map(\.channel)).count, 3)
        XCTAssertFalse(document.tracks.contains { $0.channel == 9 })
        for (pitch, expected) in [(60, down), (64, up), (67, MIDIPitchBendSequence())] {
            let track = try XCTUnwrap(document.tracks.first { $0.notes.first?.pitch == pitch })
            let recovered = try XCTUnwrap(track.pitchBend)
            try stateEqual(expected, recovered, ticks: [0, 240, 960, 3000])
            XCTAssertEqual(recovered.channel, track.channel)
        }
    }

    func testAllFifteenMelodicChannelsRemainIsolatedAndReserveDrumChannel() throws {
        let sources = (0..<15).map { index in
            ("source \(index)", lane(.init(channel: 0, initialValue: 7000 + index * 100), pitch: 48 + index))
        }
        let document = try read(sources)
        XCTAssertEqual(document.tracks.count, 15)
        XCTAssertEqual(Set(document.tracks.map(\.channel)), Set((0..<16).filter { $0 != 9 }))
        for index in 0..<15 {
            let track = try XCTUnwrap(document.tracks.first { $0.notes.first?.pitch == 48 + index })
            XCTAssertEqual(try XCTUnwrap(track.pitchBend).state(atBeat: 0).rawValue, 7000 + index * 100)
        }
    }

    func testLegacyNilExportStaysByteExactAndTempoConductorRoundTrips() throws {
        let plain = lane(nil)
        XCTAssertEqual(try MIDIFile.encode(sources: [("plain", plain)], tempo: 120, meter: Meter()),
                       try MIDIFile.encode(lanes: [("plain", plain.notes)], tempo: 120, meter: Meter()))
        let nilDocument = try read([("plain", plain)])
        XCTAssertNil(nilDocument.tracks.first?.pitchBend)
        let expression = lane(.init(initialValue: 0))
        let document = try read([("tempo", expression)], changes: [.init(beat: 1, bpm: 60), .init(beat: 2.5, bpm: 150)])
        XCTAssertNil(document.tempoImportIssue)
        XCTAssertEqual(document.tempo, 120)
        XCTAssertEqual(document.tempoChanges.map(\.beat), [0, 1, 2.5])
        XCTAssertEqual(document.tempoChanges.map(\.bpm), [120, 60, 150])
        let map = MIDIImportTempoMap(initialBPM: try XCTUnwrap(document.tempo), changes: Array(document.tempoChanges.dropFirst()))
        XCTAssertNoThrow(try map.validate())
    }

    private func pcm(_ notes: [Note], sequence: MIDIPitchBendSequence) throws -> PCM {
        var context = MusicContext(); context.tempo = 120
        let clock = try MusicClock(bars: 1, context: context)
        var patch = SynthPatch(.pad); patch.engineVersion = 3
        patch.motion = 0; patch.detune = 0; patch.stereoWidth = 0
        // Coalesce same-tick RPN data bytes to the held state used at that sample.
        let beats = Set(sequence.events.map(\.beat).filter { $0 > 0 }).sorted()
        let events = try beats.map { MIDITimedPitchBendState(seconds: clock.seconds(at: $0), state: try sequence.state(atBeat: $0)) }
        let stream = MIDIPerformanceStream(id: "roundtrip", sourceNodeID: "source", sourceChannel: sequence.channel,
            notes: notes, startSeconds: 0, endSeconds: clock.seconds,
            initialPitchBend: try sequence.state(atBeat: 0), pitchBendStates: events)
        return try ProductionInstrument.synth(notes, patch: patch, clock: clock, tail: 0.25, performances: [stream])
    }

    func testTickExactExportImportProducesIdenticalCPUSynthPCM() throws {
        let sequence = MIDIPitchBendSequence(channel: 6, initialValue: 0, initialRange: .init(semitones: 12), events: [
            .init(beat: 0.5, kind: .range(.init(semitones: 24, cents: 50))),
            .init(beat: 0.5, kind: .value(12288)), .init(beat: 1, kind: .value(8192)),
            .init(beat: 2, kind: .value(16383))])
        let source = lane(sequence)
        let document = try read([("CPU", source)])
        let imported = try XCTUnwrap(document.tracks.first)
        let recovered = try XCTUnwrap(imported.pitchBend)
        let before = try pcm(source.notes, sequence: sequence)
        let after = try pcm(imported.notes, sequence: recovered)
        XCTAssertGreaterThan(before.peak, 0)
        XCTAssertEqual(before.left, after.left)
        XCTAssertEqual(before.right, after.right)
    }
}
