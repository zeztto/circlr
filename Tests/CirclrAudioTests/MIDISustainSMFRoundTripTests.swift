import XCTest
@testable import CirclrCore
@testable import CirclrAudio

/// SMF parsing and offline native synth only; no Audio Unit helper or audio device.
final class MIDISustainSMFRoundTripTests: XCTestCase {
    private func event(_ delta: Int, _ bytes: [UInt8]) -> [UInt8] {
        var n = delta, encoded = [UInt8(delta & 127)]
        while n > 127 { n >>= 7; encoded.insert(UInt8(n & 127) | 128, at: 0) }
        return encoded + bytes
    }
    private func smf(_ tracks: [[UInt8]]) -> Data {
        var bytes = Array("MThd".utf8) + [0,0,0,6,0,1,0,UInt8(tracks.count),1,224]
        for track in tracks {
            let body = track + [0,255,47,0], count = body.count
            bytes += Array("MTrk".utf8) + [UInt8((count >> 24) & 255),UInt8((count >> 16) & 255),UInt8((count >> 8) & 255),UInt8(count & 255)] + body
        }
        return Data(bytes)
    }
    private func authored() -> Data {
        let tempo = event(0,[255,81,3,7,161,32]) + event(480,[255,81,3,15,66,64])
        var a = event(0,[0xb2,64,63]) + event(0,[0xb2,64,64])
        a += event(0,[0xe2,0,96]) + event(0,[0x92,60,91])
        a += event(240,[0x82,60,0])
        a += event(240,[0xb2,64,127]) + event(0,[0xb2,64,0]) + event(0,[0xb2,64,127])
        a += event(960,[0xb2,121,0])
        var b = event(0,[0xb5,64,127]) + event(0,[0x95,67,83])
        b += event(480,[0x85,67,0]) + event(960,[0xb5,121,0])
        return smf([tempo,a,b])
    }
    private func sources(_ document: ImportedMIDI) -> [(String,Lane)] {
        document.tracks.map { track in
            var lane = Lane(trackID: track.id)
            lane.notes = track.notes; lane.pitchBend = track.pitchBend; lane.sustain = track.sustain
            return (track.name,lane)
        }
    }
    private func roundTrip(_ document: ImportedMIDI) throws -> ImportedMIDI {
        try MIDIImport.read(MIDIFile.encode(sources:sources(document),tempo:document.tempo ?? 120,
            meter:Meter(),tempoChanges:document.tempoChanges.filter{$0.beat > 0},sustainEndBeat:3))
    }
    func testTwoChannelsRawOrderResetAndKeyLengthsSurviveSMFRoundTrip() throws {
        let before = try MIDIImport.read(authored()), after = try roundTrip(before)
        XCTAssertEqual(Set(before.tracks.map(\.channel)),[2,5])
        XCTAssertEqual(Set(after.tracks.map(\.channel)),[2,5])
        XCTAssertTrue(after.expressionIssues.isEmpty)
        for channel in [2,5] {
            let source = try XCTUnwrap(before.tracks.first{$0.channel == channel})
            let result = try XCTUnwrap(after.tracks.first{$0.channel == channel})
            let pedal = try XCTUnwrap(source.sustain), exported = try XCTUnwrap(result.sustain)
            XCTAssertEqual(exported.channel,pedal.channel)
            // Export emits an explicit seed and terminal release, without deleting raw events.
            XCTAssertEqual(exported.events.map(\.rawValue),[pedal.initialValue] + pedal.events.map(\.rawValue) + [0])
            XCTAssertEqual(exported.events.map(\.beat),[0] + pedal.events.map(\.beat) + [3])
            XCTAssertEqual(source.notes.count,1); XCTAssertEqual(result.notes.count,1)
            XCTAssertEqual(result.notes[0].beat,source.notes[0].beat)
            XCTAssertEqual(result.notes[0].length,source.notes[0].length)
            XCTAssertEqual(result.notes[0].pitch,source.notes[0].pitch)
            XCTAssertEqual(result.notes[0].velocity,source.notes[0].velocity)
        }
        let a = try XCTUnwrap(after.tracks.first{$0.channel == 2})
        XCTAssertEqual(a.sustain?.events.filter{$0.beat == 1}.map(\.rawValue),[127,0,127])
        XCTAssertEqual(a.notes[0].length,0.5,"Pedal must not be baked into key duration")
        XCTAssertEqual(try a.pitchBend?.state(atBeat:0).rawValue,12288)
        XCTAssertEqual(try a.pitchBend?.state(atBeat:3).rawValue,8192,"CC121 reset survives as explicit state")
        XCTAssertEqual(after.tempoChanges,before.tempoChanges)
    }
    private func render(_ document: ImportedMIDI) async throws -> [PCM] {
        var project = Project()
        _ = project.addSection(name:"연주",at:Point(),bars:2)
        project = try SectionGraphMigration.migrate(project)
        let parts = try document.importParts(selectedIDs:Set(document.tracks.map(\.id)))
        _ = try MIDIImportEditing.apply(parts,useID:project.active.uses[0].id,extendSection:false,
            tempoPolicy:.applyFile,tempoMap:.init(initialBPM:document.tempo ?? 120,
                changes:document.tempoChanges.filter{$0.beat > 0}),in:&project)
        for index in project.tracks.indices {
            project.tracks[index].instrument = .synthesizer(.pad)
            project.tracks[index].instrument.synth!.release = 0.1
            project.tracks[index].instrument.synth!.motion = 0
        }
        let use = project.active.uses[0], context = try ArrangementCompiler.context(project:project,use:use)
        let plan = try XCTUnwrap(SectionGraphCompiler.compile(project:project,section:context.0,use:use,context:context.1,clock:context.2))
        let outputs = try await SectionGraphRenderer.render(plan,project:project,root:nil,clock:context.2,tail:0.25)
        return try project.tracks.map{try XCTUnwrap(outputs[$0.id])}
    }
    func testReadExportReadTypedImportCompileKeepsMixedBendPedalTempoPCM() async throws {
        let document = try MIDIImport.read(authored()), restored = try roundTrip(document)
        let before = try await render(document), after = try await render(restored)
        XCTAssertEqual(before.count,2); XCTAssertEqual(after.count,before.count)
        for (a,b) in zip(before,after) {
            XCTAssertGreaterThan(a.peak,0)
            XCTAssertEqual(a.left,b.left); XCTAssertEqual(a.right,b.right)
        }
    }
    func testNotesOnlyExportRemainsLegacyBytesAndImportsWithoutPedal() throws {
        var lane = Lane(trackID:"plain")
        lane.notes = [.init(beat:0.5,length:0.25,pitch:72,velocity:89)]
        let legacy = try MIDIFile.encode(lanes:[("노트",lane.notes)],tempo:120,meter:Meter())
        XCTAssertEqual(try MIDIFile.encode(sources:[("노트",lane)],tempo:120,meter:Meter()),legacy)
        let document = try MIDIImport.read(legacy), track = try XCTUnwrap(document.tracks.first)
        XCTAssertNil(track.sustain); XCTAssertNil(track.pitchBend)
        XCTAssertEqual(track.notes[0].beat,0.5); XCTAssertEqual(track.notes[0].length,0.25)
    }
}
