import XCTest
@testable import CirclrCore
@testable import CirclrAudio

/// Authored SMF bytes and CPU synthesis only; no sound bank, AU or audio device.
final class MIDIPitchBendImportTests: XCTestCase {
    private func vlq(_ value: Int) -> [UInt8] {
        var n = value, bytes = [UInt8(value & 127)]
        while n > 127 { n >>= 7; bytes.insert(UInt8(n & 127) | 128, at: 0) }
        return bytes
    }
    private func event(_ delta: Int, _ bytes: [UInt8]) -> [UInt8] { vlq(delta) + bytes }
    private func event(_ bytes: [UInt8]) -> [UInt8] { event(0, bytes) }
    private func smf(_ tracks: [[UInt8]]) -> Data {
        var result = Array("MThd".utf8) + [0, 0, 0, 6, 0, 1, 0, UInt8(tracks.count), 1, 224]
        for track in tracks {
            let body = track + [0, 255, 47, 0], n = body.count
            result += Array("MTrk".utf8) + [UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)] + body
        }
        return Data(result)
    }
    private func noteTrack(_ channel: UInt8 = 0, start: Int = 0, duration: Int = 960) -> [UInt8] {
        event(start, [0x90 | channel, 69, 100]) + event(duration, [0x80 | channel, 69, 0])
    }
    private func track(_ document: ImportedMIDI, channel: Int = 0) throws -> ImportedMIDITrack {
        try XCTUnwrap(document.tracks.first { $0.channel == channel })
    }

    func testControllerOnlyTrackRunningStatusAndLeadingRestPreserveRawEndpoints() throws {
        let controllers = event([0xff, 0x51, 3, 7, 0xa1, 0x20])
            + event([0xe0, 0, 0]) + event(240, [0, 64]) + event(240, [127, 127])
        let notes = event([0xc0, 81]) + noteTrack(start: 480)
        let document = try MIDIImport.read(smf([controllers, notes]))
        let imported = try track(document), sequence = try XCTUnwrap(imported.pitchBend)
        XCTAssertEqual(sequence.initialValue, 8192)
        XCTAssertEqual(sequence.initialRange, .init(semitones: 2))
        XCTAssertEqual(try sequence.state(atBeat: 0).rawValue, 0)
        XCTAssertEqual(try sequence.state(atBeat: 0.5).rawValue, 8192)
        XCTAssertEqual(try sequence.state(atBeat: 1).rawValue, 16383)
        XCTAssertEqual(imported.notes.count, 1)
        XCTAssertEqual(imported.notes[0].beat, 1)
        XCTAssertEqual(imported.notes[0].length, 2)
        XCTAssertEqual(imported.notes[0].pitch, 69)
        XCTAssertEqual(document.tempo, 120)
        XCTAssertEqual(document.ignoredPerformanceEvents, 1, "Program change retains its pre-existing ignored-event accounting")
        XCTAssertEqual(try document.importParts(selectedIDs: [imported.id]).first?.pitchBend, sequence)
        XCTAssertNil(try document.importParts(selectedIDs: [imported.id], expressionPolicy: .omit).first?.pitchBend)
    }

    func testSameTickTrackAndEventOrderRPNByteRangeAndNullSelection() throws {
        let controllers = event([0xb0, 101, 0]) + event([0xb0, 100, 0])
            + event([0xb0, 6, 12]) + event([0xb0, 38, 127]) + event([0xe0, 0, 0])
        let laterTrack = event([0xe0, 127, 127]) + event([0xe0, 0, 96])
            + event([0xb0, 101, 127]) + event([0xb0, 100, 127])
            + event([0xb0, 6, 99]) + noteTrack()
        let document = try MIDIImport.read(smf([controllers, laterTrack]))
        let imported = try track(document), sequence = try XCTUnwrap(imported.pitchBend)
        let state = try sequence.state(atBeat: 0)
        XCTAssertEqual(state.rawValue, 12288, "Last event of the later raw track wins at the same tick")
        XCTAssertEqual(state.range, .init(semitones: 12, cents: 127))
        XCTAssertEqual(state.range.totalSemitones, 13.27, accuracy: 1e-12)
        XCTAssertTrue(document.issues(selectedIDs: [imported.id]).isEmpty)
        XCTAssertEqual(document.ignoredPerformanceEvents, 0)
    }

    func testUnsupportedChannelExpressionBlocksOnlySelectedChannelAndOmitPreservesNotes() throws {
        let cases: [([UInt8], String)] = [
            (event([0xb1, 101, 0]) + event([0xb1, 100, 1]) + event([0xb1, 6, 3]), "rpn_unsupported"),
            (event([0xb1, 99, 0]) + event([0xb1, 98, 1]) + event([0xb1, 6, 3]), "nrpn_unsupported"),
            (event([0xb1, 101, 0]) + event([0xb1, 100, 0]) + event([0xb1, 96, 0]), "rpn_increment_unsupported"),
            (event([0xb1, 101, 0]) + event([0xb1, 100, 0]) + event([0xb1, 97, 0]), "rpn_increment_unsupported"),
            (event([0xb1, 121, 1]), "controller_reset_unsupported")
        ]
        for (controllers, code) in cases {
            let document = try MIDIImport.read(smf([controllers, noteTrack(), noteTrack(1)]))
            let clean = try track(document), blocked = try track(document, channel: 1)
            XCTAssertTrue(document.issues(selectedIDs: [clean.id]).isEmpty, code)
            XCTAssertNoThrow(try document.importParts(selectedIDs: [clean.id]), code)
            XCTAssertTrue(document.issues(selectedIDs: [blocked.id]).contains { $0.code == code && $0.channel == 1 }, code)
            XCTAssertThrowsError(try document.importParts(selectedIDs: [blocked.id]), code)
            let omitted = try XCTUnwrap(document.importParts(selectedIDs: [blocked.id], expressionPolicy: .omit).first)
            XCTAssertEqual(omitted.notes, blocked.notes, code)
            XCTAssertNil(omitted.pitchBend, code)
        }
    }

    func testSysExAndMPEAreGlobalBlockersWithExplicitNotesOnlyEscape() throws {
        let cases: [([UInt8], String)] = [
            (event([0xf0, 5, 0x7e, 0x7f, 9, 1, 0xf7]), "sysex_unsupported"),
            (event([0xb1, 101, 0]) + event([0xb1, 100, 6]) + event([0xb1, 6, 2]), "mpe_unsupported")
        ]
        for (controllers, code) in cases {
            let document = try MIDIImport.read(smf([controllers, noteTrack()]))
            let selected = try track(document)
            XCTAssertTrue(document.issues(selectedIDs: [selected.id]).contains { $0.code == code && $0.channel == nil })
            XCTAssertThrowsError(try document.importParts(selectedIDs: [selected.id]))
            XCTAssertEqual(try document.importParts(selectedIDs: [selected.id], expressionPolicy: .omit).first?.notes, selected.notes)
        }
    }

    func testDrumCenterExpressionRequiresOmitButResetOnlyDrumsStayNotesOnly() throws {
        let bent = try MIDIImport.read(smf([event([0xe9, 0, 64]) + noteTrack(9)]))
        let drum = try track(bent, channel: 9)
        XCTAssertNotNil(drum.pitchBend)
        XCTAssertTrue(bent.issues(selectedIDs: [drum.id]).contains { $0.code == "drum_backend_unsupported" })
        XCTAssertThrowsError(try bent.importParts(selectedIDs: [drum.id]))
        let omitted = try XCTUnwrap(bent.importParts(selectedIDs: [drum.id], expressionPolicy: .omit).first)
        XCTAssertTrue(omitted.drums); XCTAssertNil(omitted.pitchBend)
        let reset = try MIDIImport.read(smf([event([0xb9, 121, 0]) + noteTrack(9)]))
        let resetDrum = try track(reset, channel: 9)
        XCTAssertNil(resetDrum.pitchBend)
        XCTAssertTrue(try XCTUnwrap(reset.importParts(selectedIDs: [resetDrum.id]).first).drums)
    }

    func testResetCentersWheelRetainsRangeAndClearsRPNAndNRPNSelection() throws {
        let controllers = event([0xb0, 101, 0]) + event([0xb0, 100, 0])
            + event([0xb0, 6, 12]) + event([0xb0, 38, 50]) + event([0xe0, 0, 0])
            + event(240, [0xb0, 121, 0]) + event([0xb0, 6, 99])
            + event(240, [0xe0, 0, 96])
        let document = try MIDIImport.read(smf([controllers, noteTrack()]))
        let imported = try track(document), sequence = try XCTUnwrap(imported.pitchBend)
        XCTAssertEqual(try sequence.state(atBeat: 0).rawValue, 0)
        XCTAssertEqual(try sequence.state(atBeat: 0.5).rawValue, 8192)
        XCTAssertEqual(try sequence.state(atBeat: 1).rawValue, 12288)
        XCTAssertEqual(try sequence.state(atBeat: 1).range, .init(semitones: 12, cents: 50))
        XCTAssertTrue(document.issues(selectedIDs: [imported.id]).isEmpty)
        let resetNRPN = event([0xb0, 99, 0]) + event([0xb0, 98, 1])
            + event([0xb0, 121, 0]) + event([0xb0, 6, 10]) + event([0xe0, 0, 96])
        let second = try MIDIImport.read(smf([resetNRPN, noteTrack()]))
        let secondTrack = try track(second)
        XCTAssertTrue(second.issues(selectedIDs: [secondTrack.id]).isEmpty)
        XCTAssertEqual(try XCTUnwrap(secondTrack.pitchBend).state(atBeat: 0).range, .init())
    }

    func testImportedExpressionAtBeatOneCompilesAndRendersUnderBothTempoPolicies() async throws {
        let tempo = event([0xff, 0x51, 3, 7, 0xa1, 0x20])
            + event(480, [0xff, 0x51, 3, 15, 0x42, 0x40])
        let controls = event([0xb0, 101, 0]) + event([0xb0, 100, 0])
            + event([0xb0, 6, 12]) + event([0xe0, 0, 0]) + event(960, [0xe0, 0, 64])
        let document = try MIDIImport.read(smf([tempo, controls, noteTrack(start: 480)]))
        let imported = try track(document)
        let parts = try document.importParts(selectedIDs: [imported.id])
        for policy: MIDIImportTempoPolicy in [.keepCurrent, .applyFile] {
            var project = Project(); project.global.tempo = 90
            _ = project.addTrack(name: "silent CPU base")
            _ = project.addSection(name: "import expression", at: Point(), bars: 2)
            project.tracks[0].instrument = .synthesizer(.pad)
            project = try SectionGraphMigration.migrate(project)
            let useID = project.active.uses[0].id
            let ids = try MIDIImportEditing.apply(parts, useID: useID, extendSection: false, atBeat: 1,
                tempoPolicy: policy, tempoMap: .init(initialBPM: try XCTUnwrap(document.tempo), changes: Array(document.tempoChanges.dropFirst())), in: &project)
            let lane = try XCTUnwrap(project.active.uses[0].addedLanes.first { ids.contains($0.id) })
            let trackIndex = try XCTUnwrap(project.tracks.firstIndex { $0.id == lane.trackID })
            project.tracks[trackIndex].instrument = .synthesizer(.pad)
            XCTAssertEqual(lane.notes[0].beat, 2)
            XCTAssertEqual(lane.notes[0].length, 2)
            XCTAssertEqual(try XCTUnwrap(lane.pitchBend).events.map(\.beat), try XCTUnwrap(imported.pitchBend).events.map { $0.beat + 1 })
            let plan = try XCTUnwrap(ArrangementCompiler.compile(project).occurrences.first?.signalPlan)
            let streams = plan.midiPerformances.values.flatMap { $0 }
            let stream = try XCTUnwrap(streams.first { $0.notes.contains { $0.pitch == 69 } })
            let (_, _, clock) = try ArrangementCompiler.context(project: project, use: project.active.uses[0])
            let onset = policy == .keepCurrent ? 4.0 / 3 : 7.0 / 6
            XCTAssertEqual(clock.seconds(at: stream.notes[0].beat), onset, accuracy: 1e-10)
            let outputs = try await SectionGraphRenderer.render(plan, project: project, root: nil, clock: clock, tail: 0.1, applyOutputGain: false)
            let pcm = try XCTUnwrap(outputs[lane.trackID])
            XCTAssertGreaterThan(pcm.peak, 0)
            XCTAssertTrue(pcm.left.allSatisfy(\.isFinite))
            XCTAssertTrue(pcm.left.prefix(Int((onset - 0.01) * PCM.rate)).allSatisfy { $0 == 0 })
            var plain = lane; plain.pitchBend = nil
            try ProjectEditing.setLane(plain, for: useID, original: false, in: &project)
            let plainPlan = try XCTUnwrap(ArrangementCompiler.compile(project).occurrences.first?.signalPlan)
            let plainOutputs = try await SectionGraphRenderer.render(plainPlan, project: project, root: nil, clock: clock, tail: 0.1, applyOutputGain: false)
            XCTAssertNotEqual(pcm.left, try XCTUnwrap(plainOutputs[lane.trackID]).left)
        }
    }
}
