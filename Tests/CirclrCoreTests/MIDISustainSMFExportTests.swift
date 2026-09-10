import XCTest
@testable import CirclrCore

final class MIDISustainSMFExportTests: XCTestCase {
    private struct Message { let tick:Int; let status:UInt8; let data:[UInt8] }
    private func tracks(_ data:Data)throws->[[Message]] {
        let bytes=Array(data);var position=14,result:[[Message]]=[]
        func integer(_ at:Int)->Int {bytes[at..<at+4].reduce(0){$0*256+Int($1)}}
        while position<bytes.count {
            let size=integer(position+4);position+=8;let end=position+size
            var tick=0,messages:[Message]=[]
            func variable()->Int {var value=0;while true {let b=bytes[position];position+=1;value=value*128+Int(b&127);if b<128{return value}}}
            while position<end {
                tick+=variable();let status=bytes[position];position+=1
                if status==255 {position+=1;let length=variable();position+=length}
                else {let count=(status&240)==192 || (status&240)==208 ? 1:2
                    messages.append(.init(tick:tick,status:status,data:Array(bytes[position..<position+count])));position+=count}
            }
            result.append(messages)
        }
        return result
    }
    private func lane()->Lane {var lane=Lane(trackID:"track");lane.notes=[Note(beat:0,length:2,pitch:60)];return lane}
    private func encode(_ lanes:[Lane],end:Double?=nil)throws->Data {
        try MIDIFile.encode(sources:lanes.map{("연주",$0)},tempo:120,meter:Meter(),sustainEndBeat:end)
    }
    func testRawSeedSameTickOrderingAndTerminalUp()throws {
        var lane=lane();lane.sustain = .init(channel:3,initialValue:63,events:[.init(beat:0,rawValue:100),.init(beat:2,rawValue:0),.init(beat:2,rawValue:127)])
        let events=try tracks(encode([lane],end:2))[1]
        let pedals=events.filter{$0.status&240==176 && $0.data[0]==64}
        XCTAssertEqual(pedals.map{$0.data[1]},[63,100,0,127,0])
        XCTAssertEqual(pedals.map(\.tick),[0,0,1920,1920,1920])
        XCTAssertTrue(events.allSatisfy{$0.status&15==3})
        let last=events.filter{$0.tick==1920}
        XCTAssertEqual(last.first?.status,131)
        XCTAssertEqual(last.last?.data,[64,0])
    }
    func testMixedNilSourcesAreSeededAndChannelsIndependent()throws {
        var pedal=lane();pedal.sustain = .init(channel:9,initialValue:127)
        let plain=lane(),data=try tracks(encode([pedal,plain],end:2))
        let channels=data.dropFirst().map{Set($0.map{$0.status&15})}
        XCTAssertEqual(channels.count,2);XCTAssertTrue(channels.allSatisfy{$0.count==1 && !$0.contains(9)})
        XCTAssertNotEqual(channels[0],channels[1])
        XCTAssertEqual(data[2].filter{$0.status&240==176 && $0.data[0]==64}.map{$0.data[1]},[0,0])
    }
    func testMissingInvalidOrTooShortHorizonRejectsWithoutCropping()throws {
        var lane=lane();lane.sustain = .init(events:[.init(beat:2,rawValue:127)])
        let ends:[Double?] = [nil,0,-1,Double.nan,Double.infinity,131073,1.9]
        for end in ends {XCTAssertThrowsError(try encode([lane],end:end))}
        lane.notes=[];lane.sustain?.events=[.init(beat:2.01,rawValue:0)]
        XCTAssertThrowsError(try encode([lane],end:2))
        lane.sustain?.events=[];lane.pitchBend = .init(events:[.init(beat:2.01,kind:.value(8192))])
        XCTAssertThrowsError(try encode([lane],end:2))
        lane.pitchBend=nil;lane.notes=[Note(beat:1.9999,length:0.00001,pitch:60)]
        XCTAssertThrowsError(try encode([lane],end:2)) // Minimum one tick would cross endTick.
    }
    func testFifteenChannelsAndMatchingControllerChannelValidation()throws {
        var source=lane();source.sustain = .init(channel:0)
        XCTAssertNoThrow(try encode(Array(repeating:source,count:15),end:2))
        XCTAssertThrowsError(try encode(Array(repeating:source,count:16),end:2))
        source.pitchBend = .init(channel:1)
        XCTAssertThrowsError(try encode([source],end:2))
        source.pitchBend = .init(channel:0)
        XCTAssertNoThrow(try encode([source],end:2))
    }
    func testAllOffRawEventsAreStillExportedAndOverlapRejected()throws {
        var source=lane();source.sustain = .init(initialValue:1,events:[.init(beat:1,rawValue:63)])
        let events=try tracks(encode([source],end:2))[1]
        XCTAssertEqual(events.filter{$0.status&240==176 && $0.data[0]==64}.map{$0.data[1]},[1,63,0])
        source.notes.append(Note(beat:1,length:1,pitch:60))
        XCTAssertThrowsError(try encode([source],end:2))
    }
    func testPedalBudgetIncludesSeedAndTerminalWithoutCoalescing()throws {
        var source=lane()
        source.sustain = .init(events:Array(repeating:.init(beat:1,rawValue:63),count:99998))
        let messages=try tracks(encode([source],end:2))[1]
        let pedals=messages.filter{$0.status&240==176 && $0.data[0]==64}
        XCTAssertEqual(pedals.count,100000)
        XCTAssertEqual(pedals.filter{$0.tick==960 && $0.data[1]==63}.count,99998)
        source.sustain?.events.append(.init(beat:1,rawValue:63))
        XCTAssertThrowsError(try encode([source],end:2))
    }

    func testAbsentSustainKeepsLegacyBytesAndIgnoresOptionalHorizon()throws {
        var source=lane()
        let plain=try MIDIFile.encode(lanes:[("연주",source.notes)],tempo:120,meter:Meter())
        XCTAssertEqual(try encode([source]),plain);XCTAssertEqual(try encode([source],end:1),plain)
        source.pitchBend = .init(events:[.init(beat:1,kind:.value(12288))])
        let baseline=try MIDIExpressionExport.encode(sources:[("연주",source)],tempo:120,meter:Meter(),tempoChanges:[])
        XCTAssertEqual(try encode([source]),baseline);XCTAssertEqual(try encode([source],end:1),baseline)
        XCTAssertFalse(try tracks(baseline)[1].contains{$0.status&240==176 && $0.data[0]==64})
    }
}
