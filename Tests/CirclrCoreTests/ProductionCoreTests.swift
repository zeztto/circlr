import XCTest
@testable import CirclrCore

final class ProductionCoreTests:XCTestCase {
    func testGeneratedPatternsFollowScaleMeterAndDuration() throws {
        var context=MusicContext();context.scale=Scale(root:6);context.meter=Meter(7,8)
        for pattern in MIDIPattern.allCases {
            let notes=try MIDIGenerator.notes(pattern:pattern,context:context,beats:10.5)
            XCTAssertFalse(notes.isEmpty)
            XCTAssertTrue(notes.allSatisfy{$0.beat>=0 && $0.beat+$0.length<=10.5 && $0.velocity>0})
            if pattern != .pulse {XCTAssertTrue(notes.allSatisfy{context.scale.contains($0.pitch)})}
            let same=try MIDIGenerator.notes(pattern:pattern,context:context,beats:10.5)
            XCTAssertEqual(notes.map(\.pitch),same.map(\.pitch));XCTAssertEqual(notes.map(\.beat),same.map(\.beat))
        }
    }
    func testMIDIHasValidHeaderTrackChunksAndRejectsInvalidNotes() throws {
        let data=try MIDIFile.encode(lanes:[("f0r h3r",[Note(beat:0,length:0.5,pitch:66,velocity:100),Note(beat:0.5,length:1,pitch:73,velocity:90)])],tempo:116,meter:Meter())
        XCTAssertEqual(Array(data.prefix(14)),Array("MThd".utf8)+[0,0,0,6,0,1,0,2,3,192])
        var cursor=14,tracks=0
        while cursor<data.count {XCTAssertEqual(String(data:data[cursor..<cursor+4],encoding:.ascii),"MTrk");let length=data[cursor+4..<cursor+8].reduce(0){$0*256+Int($1)};cursor+=8+length;tracks+=1}
        XCTAssertEqual(cursor,data.count);XCTAssertEqual(tracks,2)
        XCTAssertThrowsError(try MIDIFile.encode(lanes:[("bad",[Note(beat:0,pitch:150)])],tempo:120,meter:Meter()))
        XCTAssertThrowsError(try MIDIGenerator.notes(pattern:.chords,context:MusicContext(),beats:.infinity))
    }
    func testOldInstrumentDecodesWithoutNewSettings() throws {
        let old=Data(#"{"kind":"soundBank","program":81,"drums":false}"#.utf8)
        let value=try JSONDecoder().decode(Instrument.self,from:old)
        XCTAssertNil(value.synth);XCTAssertNil(value.sample);XCTAssertEqual(value.program,81)
    }
}
