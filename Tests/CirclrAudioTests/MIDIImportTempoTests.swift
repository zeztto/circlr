import XCTest
import CirclrCore
@testable import CirclrAudio

final class MIDIImportTempoTests:XCTestCase {
    private func vlq(_ value:Int)->[UInt8] {
        var value=value,bytes=[UInt8(value&127)];value >>= 7
        while value>0 {bytes.insert(UInt8(value&127)|128,at:0);value >>= 7}
        return bytes
    }
    private func tempo(_ delta:Int,_ micros:Int)->[UInt8] {
        vlq(delta)+[0xff,0x51,3,UInt8((micros>>16)&255),UInt8((micros>>8)&255),UInt8(micros&255)]
    }
    private func smf(_ tracks:[[UInt8]],format:Int=1)->Data {
        var bytes=Array("MThd".utf8)+[0,0,0,6,0,UInt8(format),0,UInt8(tracks.count),1,0xe0]
        for track in tracks {
            let body=track+[0,0xff,0x2f,0],n=body.count
            bytes+=Array("MTrk".utf8)+[UInt8((n>>24)&255),UInt8((n>>16)&255),UInt8((n>>8)&255),UInt8(n&255)]+body
        }
        return Data(bytes)
    }
    private var noteTrack:[UInt8] {[0,0x90,60,100]+vlq(480)+[0x80,60,0]}
    func testNoTempoAndDelayedTempoStartAtStandard120()throws {
        let empty=try MIDIImport.read(smf([noteTrack],format:0))
        XCTAssertNil(empty.tempoImportIssue)
        XCTAssertEqual(empty.tempoChanges,[TempoChange(beat:0,bpm:120)])
        let delayed=try MIDIImport.read(smf([tempo(960,1_000_000),noteTrack]))
        XCTAssertNil(delayed.tempoImportIssue)
        XCTAssertEqual(delayed.tempoChanges,[TempoChange(beat:0,bpm:120),TempoChange(beat:2,bpm:60)])
        XCTAssertEqual(delayed.tracks[0].notes[0].length,1,accuracy:1e-5)
        // The parser retains tempo-only events after the notes; selection policy trims later.
        XCTAssertGreaterThan(delayed.tempoChanges.last!.beat,delayed.beats)
    }
    func testFormatZeroSameBeatLastEventWinsAndRunningNotesSurvive()throws {
        let body=tempo(0,500000)+tempo(0,1000000)+[0,0x90,60,100,0,64,90]+vlq(480)+[0x80,60,0,0,64,0]
        let result=try MIDIImport.read(smf([body],format:0))
        XCTAssertNil(result.tempoImportIssue)
        XCTAssertEqual(result.tempoChanges,[TempoChange(beat:0,bpm:60)])
        XCTAssertEqual(result.tracks[0].notes.map(\.pitch),[60,64])
    }
    func testFormatOneConflictsUseFileTrackThenEventOrder()throws {
        let first=tempo(0,500000)+tempo(480,1000000)
        let second=tempo(0,750000)+tempo(480,400000)+tempo(0,600000)
        let changes=try MIDIImport.readTempoChanges(smf([first,second,noteTrack]))
        XCTAssertEqual(changes,[TempoChange(beat:0,bpm:80),TempoChange(beat:1,bpm:100)])
        let reordered=try MIDIImport.readTempoChanges(smf([second,first,noteTrack]))
        XCTAssertEqual(reordered,[TempoChange(beat:0,bpm:120),TempoChange(beat:1,bpm:60)])
    }
    func testUnsupportedFileTempoDoesNotBlockValidNotesOnlyImport()throws {
        let result=try MIDIImport.read(smf([tempo(0,50000),noteTrack])) // 1200 BPM is valid SMF, unsupported project tempo.
        XCTAssertEqual(result.tracks[0].notes[0].pitch,60)
        XCTAssertTrue(result.tempoChanges.isEmpty);XCTAssertNotNil(result.tempoImportIssue)
    }
    func testCancellationStopsNotesAndTempoParsingInsteadOfBecomingTempoIssue()async {
        let data=smf([tempo(0,500000),noteTrack])
        let task=Task {
            withUnsafeCurrentTask{$0?.cancel()}
            do {_=try MIDIImport.read(data);XCTFail("Cancelled note import must not succeed")}
            catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
            do {_=try MIDIImport.readTempoChanges(data);XCTFail("Cancelled tempo import must not succeed")}
            catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
        }
        await task.value
    }
    func testMalformedAndExcessiveTempoMetadataAreRejectedForFilePolicy()throws {
        for body in [[UInt8](arrayLiteral:0,0xff,0x51,2,1,2),tempo(0,0)] {
            XCTAssertThrowsError(try MIDIImport.readTempoChanges(smf([body,noteTrack])))
        }
        let excessive=Array(repeating:tempo(0,500000),count:4097).flatMap{$0}
        XCTAssertThrowsError(try MIDIImport.readTempoChanges(smf([excessive,noteTrack])))
        var truncated=smf([tempo(0,500000),noteTrack]);truncated.removeLast(2)
        XCTAssertThrowsError(try MIDIImport.readTempoChanges(truncated))
    }
}
