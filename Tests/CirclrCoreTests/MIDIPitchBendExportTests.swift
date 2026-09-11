import XCTest
@testable import CirclrCore

final class MIDIPitchBendExportTests:XCTestCase {
    func source(_ channel:Int?=nil)->Lane {
        var lane=Lane(trackID:"track");lane.notes=[.init(beat:0,length:1,pitch:60)]
        if let channel {lane.pitchBend = .init(channel:channel,initialValue:0)}
        return lane
    }
    func testLegacySourceExportMatchesExistingNotesBytes()throws {
        let lane=source()
        XCTAssertEqual(try MIDIFile.encode(sources:[("연주",lane)],tempo:120,meter:Meter()),
                       try MIDIFile.encode(lanes:[("연주",lane.notes)],tempo:120,meter:Meter()))
    }
    func testExpressionIncludingCenterAndSharedSourcesExportsWithoutMutation()throws {
        var ordinary=source(),expressive=source(0)
        ordinary.id="plain";expressive.id="bend"
        for sequence in [MIDIPitchBendSequence(),.init(initialValue:0),.init(events:[.init(beat:1,kind:.range(.init(semitones:12)))])] {
            expressive.pitchBend=sequence
            let before=expressive
            let data=try MIDIFile.encode(sources:[("원본",ordinary),("표현",expressive)],tempo:120,meter:Meter())
            XCTAssertEqual(data.prefix(4),Data("MThd".utf8));XCTAssertEqual(expressive,before)
        }
        var pattern=RhythmPattern(name:"공유",trackID:"track");pattern.pitchBend = .init(initialValue:0)
        var lane=Lane(trackID:pattern.trackID);lane.pitchBend=pattern.pitchBend
        XCTAssertNoThrow(try MIDIFile.encode(sources:[(pattern.name,lane)],tempo:120,meter:Meter()))
    }
    func testMelodicChannelCapacityAndSamePitchOverlapBoundaries()throws {
        let fifteen=(0..<15).map{("source\($0)",source(0))}
        XCTAssertNoThrow(try MIDIFile.encode(sources:fifteen,tempo:120,meter:Meter()))
        XCTAssertThrowsError(try MIDIFile.encode(sources:fifteen+[("extra",source())],tempo:120,meter:Meter()))
        var lane=source(0);lane.notes.append(.init(beat:0.5,length:1,pitch:60))
        XCTAssertThrowsError(try MIDIFile.encode(sources:[("중첩",lane)],tempo:120,meter:Meter())) {error in
            XCTAssertTrue(error.localizedDescription.contains("pitch 60"))
        }
        lane.notes[1].beat=1
        XCTAssertNoThrow(try MIDIFile.encode(sources:[("경계",lane)],tempo:120,meter:Meter()))
        lane.notes=[.init(beat:0,length:0.0001,pitch:60),.init(beat:0.0002,length:0.0001,pitch:60)]
        XCTAssertThrowsError(try MIDIFile.encode(sources:[("tick 충돌",lane)],tempo:120,meter:Meter()))
        lane=source();lane.notes.append(.init(beat:0.5,length:1,pitch:60))
        XCTAssertEqual(try MIDIFile.encode(sources:[("원래",lane)],tempo:120,meter:Meter()),try MIDIFile.encode(lanes:[("원래",lane.notes)],tempo:120,meter:Meter()))
    }
    func testInvalidExpressionTempoAndEventExpansionFailAtomically()throws {
        var lane=source(0);lane.pitchBend?.initialValue = -1
        XCTAssertThrowsError(try MIDIFile.encode(sources:[("오류",lane)],tempo:120,meter:Meter()))
        lane=source(0)
        for map in [[TempoChange(beat:.nan,bpm:120)], [.init(beat:1,bpm:1)], [.init(beat:2,bpm:120),.init(beat:1,bpm:90)]] {
            XCTAssertThrowsError(try MIDIFile.encode(sources:[("오류",lane)],tempo:120,meter:Meter(),tempoChanges:map))
        }
        lane.pitchBend?.events=Array(repeating:.init(beat:0,kind:.range(.init())),count:50000)
        let before=lane
        XCTAssertThrowsError(try MIDIFile.encode(sources:[("많음",lane)],tempo:120,meter:Meter()))
        XCTAssertEqual(lane,before)
    }
    func testTypedTempoMapIsEncodedWithoutRequiringExpression()throws {
        let lane=source()
        let legacy=try MIDIFile.encode(sources:[("연주",lane)],tempo:120,meter:Meter())
        let mapped=try MIDIFile.encode(sources:[("연주",lane)],tempo:120,meter:Meter(),tempoChanges:[.init(beat:0.5,bpm:60)])
        XCTAssertNotEqual(mapped,legacy)
        XCTAssertEqual(mapped.prefix(4),Data("MThd".utf8))
    }
    func testLongKoreanTitleStopsAtValidUTF8Boundary()throws {
        let name=String(repeating:"한",count:400),lane=source(0)
        let data=[UInt8](try MIDIFile.encode(sources:[(name,lane)],tempo:120,meter:Meter()))
        // Track-name FF03 metadata is followed by a VLQ byte length.
        let marker=try XCTUnwrap(data.indices.dropLast().first {data[$0]==0xff && data[$0+1]==0x03})
        var index=marker+2,length=0
        while true {
            let byte=data[index];index+=1;length=(length<<7)|Int(byte&127)
            if byte&128==0 {break}
        }
        XCTAssertLessThanOrEqual(length,1024)
        XCTAssertEqual(length,1023)
        let title=String(bytes:data[index..<index+length],encoding:.utf8)
        XCTAssertEqual(title,String(repeating:"한",count:341))
    }

}
