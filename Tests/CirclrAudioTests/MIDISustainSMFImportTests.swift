import XCTest
@testable import CirclrCore
@testable import CirclrAudio

final class MIDISustainSMFImportTests:XCTestCase {
    func vlq(_ value:Int)->[UInt8] {
        var n=value,out=[UInt8(value&127)]
        while n>127 {n >>= 7;out.insert(UInt8(n&127)|128,at:0)}
        return out
    }
    func event(_ delta:Int=0,_ bytes:[UInt8])->[UInt8] {vlq(delta)+bytes}
    func smf(_ tracks:[[UInt8]],format:UInt8=1)->Data {
        var result=Array("MThd".utf8)+[0,0,0,6,0,format,0,UInt8(tracks.count),1,224]
        for track in tracks {
            let body=track+[0,255,47,0],n=body.count
            result+=Array("MTrk".utf8)+[UInt8((n>>24)&255),UInt8((n>>16)&255),UInt8((n>>8)&255),UInt8(n&255)]+body
        }
        return Data(result)
    }
    func notes(_ channel:UInt8=0)->[UInt8] {event(480,[0x90|channel,60,100])+event(480,[0x80|channel,60,0])}
    func testFormatZeroRunningStatusRawThresholdAndNoteTailPreserved()throws {
        var bytes=event(0,[0xb0,64,63])+event(0,[64,64])+event(480,[0x90,60,100])
        bytes+=event(480,[0x80,60,0])+event(480,[0xb0,64,0])
        let document=try MIDIImport.read(smf([bytes],format:0)),track=try XCTUnwrap(document.tracks.first)
        let sustain=try XCTUnwrap(track.sustain)
        XCTAssertEqual(sustain.channel,0);XCTAssertEqual(sustain.initialValue,0)
        XCTAssertEqual(sustain.events.map(\.beat),[0,0,3]);XCTAssertEqual(sustain.events.map(\.rawValue),[63,64,0])
        XCTAssertEqual(track.notes.count,1);XCTAssertEqual(track.notes[0].beat,1);XCTAssertEqual(track.notes[0].length,1)
        XCTAssertEqual(document.ignoredPerformanceEvents,0);XCTAssertNil(track.pitchBend)
    }
    func testFormatOneControllerTracksMergeInStableFileOrder()throws {
        let first=event(0,[0xb2,64,127])+event(480,[64,0])
        let second=event(480,[0xb2,64,64])+event(0,[64,0])+event(0,[64,127])
        let document=try MIDIImport.read(smf([first,second,notes(2),notes(3)]))
        let selected=try XCTUnwrap(document.tracks.first{$0.channel==2}),sustain=try XCTUnwrap(selected.sustain)
        XCTAssertEqual(sustain.events.map(\.beat),[0,1,1,1,1]);XCTAssertEqual(sustain.events.map(\.rawValue),[127,0,64,0,127])
        XCTAssertNil(document.tracks.first{$0.channel==3}?.sustain)
        XCTAssertEqual(try document.importParts(selectedIDs:[selected.id]).first?.sustain,sustain)
        XCTAssertNil(try document.importParts(selectedIDs:[selected.id],expressionPolicy:.omit).first?.sustain)
    }
    func testResetBeforeAndAfterExplicitPedalAndBendRemainIndependent()throws {
        let control=event(0,[0xb0,121,0])+event(0,[0xe0,0,0])+event(0,[0xb0,64,127])+event(480,[121,0])
        let document=try MIDIImport.read(smf([control,notes()])),track=try XCTUnwrap(document.tracks.first)
        XCTAssertEqual(track.sustain?.events.map(\.rawValue),[0,127,0])
        XCTAssertEqual(track.sustain?.events.map(\.beat),[0,0,1])
        XCTAssertEqual(try track.pitchBend?.state(atBeat:0).rawValue,0)
        XCTAssertEqual(try track.pitchBend?.state(atBeat:1).rawValue,8192)
        XCTAssertEqual(document.ignoredPerformanceEvents,0)
        let omitted=try XCTUnwrap(document.importParts(selectedIDs:[track.id],expressionPolicy:.omit).first)
        XCTAssertNil(omitted.sustain);XCTAssertNil(omitted.pitchBend);XCTAssertEqual(omitted.notes,track.notes)
        let resetOnly=try MIDIImport.read(smf([event(0,[0xb9,121,0]),notes(9)]))
        let drum=try XCTUnwrap(resetOnly.tracks.first)
        XCTAssertNil(drum.sustain);XCTAssertNil(drum.pitchBend)
        XCTAssertTrue(resetOnly.issues(selectedIDs:[drum.id]).isEmpty)
    }
    func testPedalDrumAndNonzeroResetRequireExplicitOmit()throws {
        let document=try MIDIImport.read(smf([event(0,[0xb9,64,64]),notes(9)])),track=try XCTUnwrap(document.tracks.first)
        XCTAssertTrue(document.issues(selectedIDs:[track.id]).contains{$0.code=="drum_backend_unsupported"})
        XCTAssertThrowsError(try document.importParts(selectedIDs:[track.id]))
        XCTAssertNil(try document.importParts(selectedIDs:[track.id],expressionPolicy:.omit).first?.sustain)
        let bad=try MIDIImport.read(smf([event(0,[0xb0,121,1]),notes()])),id=try XCTUnwrap(bad.tracks.first?.id)
        XCTAssertTrue(bad.issues(selectedIDs:[id]).contains{$0.code=="controller_reset_unsupported"})
        XCTAssertThrowsError(try bad.importParts(selectedIDs:[id]))
    }
    func testMalformedRawControllerAndSustainCountLimitReject()throws {
        let malformed=smf([[0,0xb0,64]])
        XCTAssertThrowsError(try MIDIExpressionScan.read(malformed))
        var many=[UInt8]();many.reserveCapacity(400004)
        for _ in 0..<100001 {many += [0,0xb0,64,127]}
        XCTAssertThrowsError(try MIDIExpressionScan.read(smf([many])))
    }
}
