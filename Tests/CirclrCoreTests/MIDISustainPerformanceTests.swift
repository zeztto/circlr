import XCTest
@testable import CirclrCore

final class MIDISustainPerformanceTests:XCTestCase {
    func fixture()throws->Project {
        var p=Project();_=p.addTrack(name:"신스");_=p.addSection(name:"섹션",at:Point(),bars:4)
        p.sections[0].lanes[0].notes=[.init(beat:0,length:3,pitch:60),.init(beat:2,length:1,pitch:64)]
        p=try SectionGraphMigration.migrate(p);p.schemaVersion=7
        return p
    }
    var pedal:MIDISustainSequence {.init(channel:2,initialValue:64,events:[.init(beat:1,rawValue:0),.init(beat:1,rawValue:127),.init(beat:4,rawValue:0)])}
    func signal(_ p:Project)throws->SectionSignalPlan {
        let execution=try ArrangementCompiler.compile(p)
        return try XCTUnwrap(execution.occurrences.first?.signalPlan)
    }
    func testSustainOnlyKeepsNotesAndOrderedEqualTimeStates()throws {
        var p=try fixture();let before=try signal(p)
        p.sections[0].lanes[0].sustain=pedal
        let result=try signal(p),stream=try XCTUnwrap(result.midiPerformances.values.first?.first)
        XCTAssertEqual(result.midi,before.midi)
        XCTAssertEqual(stream.notes,result.midi[stream.sourceNodeID])
        XCTAssertEqual(stream.sourceChannel,2);XCTAssertEqual(stream.initialSustain.rawValue,64)
        XCTAssertEqual(stream.sustainStates.map(\.seconds),[0.5,0.5,2])
        XCTAssertEqual(stream.sustainStates.map(\.state.rawValue),[0,127,0])
        XCTAssertFalse(stream.hasPitchBendExpression)
        XCTAssertTrue(stream.pitchBendStates.isEmpty);XCTAssertEqual(stream.initialPitchBend.rawValue,8192)
        XCTAssertEqual(result.eventCount,before.eventCount+4)
    }
    func testCombinedExpressionUsesOneStreamAndRejectsChannelMismatch()throws {
        var p=try fixture();p.sections[0].lanes[0].sustain=pedal
        p.sections[0].lanes[0].pitchBend = .init(channel:2,events:[.init(beat:1,kind:.value(0))])
        let result=try signal(p),streams=result.midiPerformances.values.flatMap{$0}
        XCTAssertEqual(streams.count,1);XCTAssertTrue(streams[0].hasPitchBendExpression)
        XCTAssertEqual(streams.flatMap(\.notes),result.midi.values.flatMap{$0})
        XCTAssertEqual(streams[0].pitchBendStates.count,1);XCTAssertEqual(streams[0].sustainStates.count,3)
        p.sections[0].lanes[0].sustain=nil
        XCTAssertTrue(try XCTUnwrap(signal(p).midiPerformances.values.first?.first).hasPitchBendExpression)
        p.sections[0].lanes[0].sustain=pedal
        p.sections[0].lanes[0].pitchBend?.channel=3
        XCTAssertThrowsError(try signal(p))
    }
    func testLocalRepeatsHaveIndependentInitialPedalAndEndExclusiveStates()throws {
        var p=try fixture();p.sections[0].lanes[0].sustain=pedal
        let i=try XCTUnwrap(p.sections[0].graph?.nodes.firstIndex{if case .midi=$0.content{return true};return false})
        p.sections[0].graph?.nodes[i].startBeat=4;p.sections[0].graph?.nodes[i].lengthBeats=4
        p.sections[0].graph?.nodes[i].repeatCount=2;p.sections[0].graph?.nodes[i].settings.tempo = .local(60)
        let result=try signal(p),id=p.sections[0].graph!.nodes[i].id,streams=try XCTUnwrap(result.midiPerformances[id])
        XCTAssertEqual(streams.map(\.startSeconds),[2,6]);XCTAssertEqual(streams.map(\.endSeconds),[6,8])
        XCTAssertEqual(streams.map(\.initialSustain.rawValue),[64,64])
        XCTAssertEqual(streams[0].sustainStates.map(\.seconds),[3,3]);XCTAssertEqual(streams[1].sustainStates.map(\.seconds),[7,7])
        XCTAssertEqual(Set(streams.map(\.id)).count,2);XCTAssertEqual(streams.flatMap(\.notes),result.midi[id])
    }
    func testTempoOverrideAndSharedPatternOverlapKeepPedalClock()throws {
        var p=try fixture(),pattern=RhythmPattern(name:"공유",trackID:"")
        pattern.trackID=p.tracks[0].id;pattern.length=4;pattern.notes=[.init(beat:0.25,length:5,pitch:60)];pattern.sustain=pedal
        p.patterns=[pattern];p.global.rhythm=RhythmAssignment(pattern.id);p.global.beatGrid.swing=0.5
        p.sections[0].graph=nil;p=try SectionGraphMigration.migrate(p)
        p.arrangements[0].uses[0].tempoOverride = .init(initialBPM:120,changes:[.init(beat:2,bpm:60)])
        let result=try signal(p),id="rhythm-midi:\(p.tracks[0].id)",streams=try XCTUnwrap(result.midiPerformances[id])
        XCTAssertEqual(streams.count,4);XCTAssertEqual(streams[0].sustainStates.map(\.seconds),[0.5,0.5])
        XCTAssertEqual(streams[1].startSeconds,3);XCTAssertEqual(streams[1].sustainStates.map(\.seconds),[4,4])
        XCTAssertGreaterThan(streams[0].notes[0].beat+streams[0].notes[0].length,4)
        XCTAssertEqual(streams.flatMap(\.notes),result.midi[id])
        XCTAssertThrowsError(try SectionGraphCompiler.expandedPattern(pattern,length:16,grid:p.global.beatGrid))
    }
    func testLegacyMutedSchemaAndBudgetValidation()throws {
        var p=try fixture();p.sections[0].lanes[0].sustain=pedal
        p.schemaVersion=6;XCTAssertThrowsError(try signal(p));p.schemaVersion=7
        let i=try XCTUnwrap(p.sections[0].graph?.nodes.firstIndex{if case .midi=$0.content{return true};return false})
        p.sections[0].graph?.nodes[i].muted=true
        XCTAssertTrue(try signal(p).midiPerformances.values.flatMap{$0}.isEmpty)
        p.sections[0].graph?.nodes[i].muted=false
        p.sections[0].graph?.nodes[i].lengthBeats=1;p.sections[0].graph?.nodes[i].repeatCount=16
        p.sections[0].lanes[0].sustain = .init(events:Array(repeating:.init(beat:0,rawValue:127),count:100000))
        XCTAssertThrowsError(try signal(p))
        p.sections[0].lanes[0].sustain=pedal;p.sections[0].graph=nil
        XCTAssertThrowsError(try ArrangementCompiler.compile(p))
    }
}
