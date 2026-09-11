import XCTest
import CirclrCore
@testable import CirclrAudio

final class MIDIImportTests:XCTestCase {
    func testNativeSMFImportPreservesPolyphonyQuarterBeatsNamesAndTempo()throws {
        let notes=[Note(beat:0.125,length:0.75,pitch:60,velocity:83),Note(beat:0.125,length:1.25,pitch:64,velocity:111),Note(beat:4,length:0.25,pitch:67)]
        let data=try MIDIFile.encode(lanes:[("빛의 코드",notes),("베이스",[Note(beat:2,length:2,pitch:36,velocity:97)])],tempo:127,meter:Meter(7,8))
        let imported=try MIDIImport.read(data)
        XCTAssertEqual(imported.tracks.count,2);XCTAssertEqual(imported.tracks[0].name,"빛의 코드");XCTAssertEqual(imported.beats,4.25,accuracy:1e-5)
        XCTAssertEqual(try XCTUnwrap(imported.tempo),127,accuracy:0.001)
        XCTAssertEqual(imported.tracks[0].notes.map(\.pitch),notes.map(\.pitch));XCTAssertEqual(imported.tracks[0].notes.map(\.velocity),notes.map(\.velocity))
        for (a,b) in zip(imported.tracks[0].notes,notes) {XCTAssertEqual(a.beat,b.beat,accuracy:1.0/960);XCTAssertEqual(a.length,b.length,accuracy:1.0/960)}
    }
    func testBadEmptySMPTEAndFormatTwoFilesAreRejected()throws {
        XCTAssertThrowsError(try MIDIImport.read(Data("not midi".utf8)))
        let data=try MIDIFile.encode(lanes:[],tempo:120,meter:Meter())
        XCTAssertThrowsError(try MIDIImport.read(data))
        var smpte=data;smpte[12]=0xE7;XCTAssertThrowsError(try MIDIImport.read(smpte))
        var two=data;two[9]=2;XCTAssertThrowsError(try MIDIImport.read(two))
        var truncated=try MIDIFile.encode(lanes:[("keys",[Note(beat:0,length:1,pitch:60)])],tempo:120,meter:Meter());truncated.removeLast(12)
        XCTAssertThrowsError(try MIDIImport.read(truncated))
    }
    func testFormatZeroSplitsChannelsAndPreservesSustainController()throws {
        let body:[UInt8]=[0,0x99,36,111,0,0x90,60,100,0,0xB0,64,127,0x83,0x60,0x89,36,0,0,0x80,60,0,0,0xFF,0x2F,0]
        let data=Data(Array("MThd".utf8)+[0,0,0,6,0,0,0,1,1,0xE0]+Array("MTrk".utf8)+[0,0,0,UInt8(body.count)]+body)
        let imported=try MIDIImport.read(data)
        XCTAssertEqual(imported.tracks.map(\.channel),[0,9]);XCTAssertEqual(imported.tracks.map{$0.notes[0].pitch},[60,36]);XCTAssertEqual(imported.ignoredPerformanceEvents,0)
        let sustain=try XCTUnwrap(imported.tracks[0].sustain)
        XCTAssertEqual(sustain.channel,0);XCTAssertEqual(sustain.initialValue,0)
        XCTAssertEqual(sustain.events,[MIDISustainEvent(beat:0,rawValue:127)])
        XCTAssertNil(imported.tracks[1].sustain)
        XCTAssertEqual(imported.tracks[0].notes[0].length,1,accuracy:1e-5)
    }

}
