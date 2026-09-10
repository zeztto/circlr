import XCTest
@testable import CirclrCore

final class MIDISustainImportExportTests: XCTestCase {
    private func fixture() throws -> Project {
        var p=Project();_=p.addTrack(name:"원본");_=p.addSection(name:"A",at:Point(),bars:2)
        return try SectionGraphMigration.migrate(p)
    }
    private func part(_ sustain:MIDISustainSequence?=nil,bend:MIDIPitchBendSequence?=nil,drums:Bool=false)->MIDIImportPart {
        .init(name:"페달 연주",notes:[.init(beat:0,length:1,pitch:60)],drums:drums,pitchBend:bend,sustain:sustain)
    }
    func testTypedImportPreservesRawSeedAndSameBeatOrderWithOffset() throws {
        var p=try fixture();_=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point())
        let before=p,sequence=MIDISustainSequence(channel:3,initialValue:100,events:[
            .init(beat:0,rawValue:127),.init(beat:0,rawValue:0),.init(beat:5,rawValue:63)])
        let ids=try MIDIImportEditing.apply([part(sequence,bend:.init(channel:3))],useID:p.active.uses[0].id,extendSection:false,atBeat:2,in:&p)
        let lane=try XCTUnwrap(ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0]).first{$0.id==ids[0]})
        var expected=sequence;for i in expected.events.indices {expected.events[i].beat+=2}
        XCTAssertEqual(lane.sustain,expected);XCTAssertEqual(lane.pitchBend?.channel,3)
        XCTAssertEqual(lane.notes[0].beat,2);XCTAssertEqual(p.schemaVersion,7)
        XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.active.uses[1],before.active.uses[1])
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
    }
    func testPedalAtExactEndRequiresExtensionAndTempoIncludesLateRelease() throws {
        var p=try fixture();let use=p.active.uses[0].id
        let parts=[part(.init(events:[.init(beat:0,rawValue:127),.init(beat:8,rawValue:0)]))]
        let before=p
        XCTAssertThrowsError(try MIDIImportEditing.apply(parts,useID:use,extendSection:false,in:&p));XCTAssertEqual(p,before)
        let map=MIDIImportTempoMap(initialBPM:120,changes:[.init(beat:2,bpm:60)])
        let preview=try MIDITempoImport.preview(parts,useID:use,extendSection:true,tempoMap:map,in:p)
        XCTAssertEqual(preview.noteEndBeat,1);XCTAssertEqual(preview.lastExpressionBeat,8);XCTAssertEqual(preview.bars,3)
        XCTAssertEqual(preview.regionSeconds,7)
        _=try MIDIImportEditing.apply(parts,useID:use,extendSection:true,tempoPolicy:.applyFile,tempoMap:map,in:&p)
        let clock=try ArrangementCompiler.context(project:p,use:p.active.uses[0]).2
        XCTAssertEqual(clock.bpm(at:7),60);XCTAssertEqual(clock.bpm(at:8),120)
        XCTAssertEqual(clock.seconds,preview.sectionSeconds)
    }
    func testInvalidAndConflictingControllersRejectWholeImport() throws {
        let base=try fixture()
        let invalid=[part(.init(channel:16)),part(.init(initialValue:128)),
                     part(.init(channel:1),bend:.init(channel:2)),part(.init(),drums:true),
                     part(.init(events:[.init(beat:131072,rawValue:0)]))]
        for item in invalid {
            var p=base
            XCTAssertThrowsError(try MIDIImportEditing.apply([part(),item],useID:p.active.uses[0].id,extendSection:true,atBeat:1,in:&p))
            XCTAssertEqual(p,base)
        }
    }
    func testCombinedExpressionBudgetIsEnforced() throws {
        let base=try fixture()
        let bend=MIDIPitchBendSequence(events:Array(repeating:.init(beat:0,kind:.value(8192)),count:100000))
        let pedal=MIDISustainSequence(events:Array(repeating:.init(beat:0,rawValue:0),count:100000))
        var p=base
        XCTAssertThrowsError(try MIDIImportEditing.apply(Array(repeating:part(pedal,bend:bend),count:6),useID:p.active.uses[0].id,extendSection:false,in:&p))
        XCTAssertEqual(p,base)
    }
    func testTypedExportRejectsEvenExplicitOffInsteadOfDiscardingRawData() throws {
        var lane=Lane(trackID:"track");lane.notes=[.init(beat:0,length:1,pitch:60)]
        let legacy=try MIDIFile.encode(lanes:[("연주",lane.notes)],tempo:120,meter:Meter())
        XCTAssertEqual(try MIDIFile.encode(sources:[("연주",lane)],tempo:120,meter:Meter()),legacy)
        for sequence in [MIDISustainSequence(),.init(initialValue:63),.init(initialValue:127),.init(events:[.init(beat:2,rawValue:0)])] {
            lane.sustain=sequence;let before=lane
            XCTAssertThrowsError(try MIDIFile.encode(sources:[("연주",lane)],tempo:120,meter:Meter())) { error in
                XCTAssertTrue(error.localizedDescription.contains("서스테인"))
            }
            XCTAssertThrowsError(try MIDIExpressionExport.encode(sources:[("연주",lane)],tempo:120,meter:Meter(),tempoChanges:[.init(beat:1,bpm:90)]))
            XCTAssertEqual(lane,before)
        }
    }
    func testProjectPackageSaveReopenAndTakeSummaryPreservePedal() throws {
        var p=try fixture();let use=p.active.uses[0].id
        var lane=p.sections[0].lanes[0];lane.notes=[.init(beat:0,length:1,pitch:60)]
        lane.sustain = .init(initialValue:127,events:[.init(beat:2,rawValue:0)])
        try ProjectEditing.setLane(lane,for:use,original:false,in:&p)
        var take=RecordedTake(useID:use,name:"페달 없는 같은 노트",lane:lane)
        take.targetLaneID=lane.id;take.arrangementID=p.activeArrangementID;take.lane.sustain=nil
        XCTAssertEqual(RecordedTakeSummary.make(take,arrangementID:p.activeArrangementID,useID:use,laneID:lane.id,in:p)?.matchesCurrentContent,false)
        let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".circlr")
        defer {try? FileManager.default.removeItem(at:path)}
        let saved=try ProjectStore.save(p,to:path,mediaRoot:nil)
        let loaded=try ProjectStore.load(path).project
        XCTAssertEqual(saved,loaded);XCTAssertEqual(loaded.schemaVersion,7)
        XCTAssertEqual(loaded.active.uses[0].laneOverrides[lane.id]?.sustain,lane.sustain)
        try ProjectEditing.activateTake(take,in:&p)
        XCTAssertEqual(RecordedTakeSummary.make(take,arrangementID:p.activeArrangementID,useID:use,laneID:lane.id,in:p)?.matchesCurrentContent,true)
    }

    func testSchemaSevenStillAllowsSongFormInsertion() throws {
        var (p,arr,_,last)=try SectionInsertionTests().fixture()
        p.sections[0].lanes[0].sustain = .init(initialValue:63)
        try MIDISustainStorage.promote(in:&p)
        let source=p.sections[0]
        _=try SectionInsertion.insert(arrangementID:arr,afterUseID:last,name:"후렴",bars:1,at:Point(),in:&p)
        XCTAssertEqual(p.schemaVersion,7);XCTAssertEqual(p.sections.first{$0.id==source.id},source)
        try ProjectStore.validateStructure(p)
    }

}
