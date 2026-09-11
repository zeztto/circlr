import XCTest
@testable import CirclrCore

final class MIDIPitchBendImportTests:XCTestCase {
    private func fixture(bars:Int=2)throws->Project {
        var p=Project();_=p.addTrack(name:"원본");_=p.addSection(name:"A",at:Point(),bars:bars)
        return try SectionGraphMigration.migrate(p)
    }
    private func part(_ expression:MIDIPitchBendSequence?=nil,length:Double=1,drums:Bool=false)->MIDIImportPart {
        .init(name:"연주",notes:[Note(beat:0,length:length,pitch:60)],drums:drums,pitchBend:expression)
    }
    private func importedLane(_ p:Project,id:ID)throws->Lane {
        try XCTUnwrap(ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0]).first{$0.id==id})
    }
    func testOffsetPreservesSeedsSameBeatOrderAndLateEventsWithoutChangingOtherUse()throws {
        var p=try fixture();_=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point())
        let before=p
        let expression=MIDIPitchBendSequence(channel:3,initialValue:10000,initialRange:.init(semitones:12,cents:50),events:[
            .init(beat:0,kind:.value(12000)),.init(beat:0,kind:.range(.init(semitones:7))),.init(beat:5,kind:.value(8192))])
        let ids=try MIDIImportEditing.apply([part(expression)],useID:p.active.uses[0].id,extendSection:false,atBeat:2,in:&p)
        let lane=try importedLane(p,id:ids[0]);var shifted=expression
        shifted.events=expression.events.map{.init(beat:$0.beat+2,kind:$0.kind)}
        XCTAssertEqual(lane.pitchBend,shifted);XCTAssertEqual(lane.notes[0].beat,2)
        XCTAssertEqual(p.schemaVersion,5);XCTAssertEqual(p.sections,before.sections)
        XCTAssertEqual(p.active.uses[1],before.active.uses[1])
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
    }
    func testExactEndRequiresExtensionButNotesAloneAndNearEndDoNot()throws {
        let base=try fixture(bars:1)
        for end in [Double(4).nextDown,4.0] {
            let parts=[part(.init(events:[.init(beat:end,kind:.value(10000))]))]
            var p=base
            if end==4 {
                XCTAssertThrowsError(try MIDITempoImport.preview(parts,useID:p.active.uses[0].id,extendSection:false,tempoPolicy:.keepCurrent,in:p))
                XCTAssertThrowsError(try MIDIImportEditing.apply(parts,useID:p.active.uses[0].id,extendSection:false,in:&p));XCTAssertEqual(p,base)
            }
            let preview=try MIDITempoImport.preview(parts,useID:p.active.uses[0].id,extendSection:true,tempoPolicy:.keepCurrent,in:p)
            let ids=try MIDIImportEditing.apply(parts,useID:p.active.uses[0].id,extendSection:true,in:&p)
            XCTAssertEqual(preview.bars,end==4 ? 2:1)
            XCTAssertEqual(try importedLane(p,id:ids[0]).pitchBend?.events.last?.beat,end)
            XCTAssertEqual(try ArrangementCompiler.context(project:p,use:p.active.uses[0]).2.beats,Double(preview.bars*4))
        }
        var plain=base
        _=try MIDIImportEditing.apply([part(length:4)],useID:plain.active.uses[0].id,extendSection:false,in:&plain)
        XCTAssertNil(plain.active.uses[0].barsOverride);XCTAssertEqual(plain.schemaVersion,base.schemaVersion)
    }
    func testFileTempoRegionIncludesLateExpressionAndRestoresAfterIt()throws {
        var p=try fixture()
        let parts=[part(.init(events:[.init(beat:4,kind:.value(8192))]))]
        let map=MIDIImportTempoMap(initialBPM:120,changes:[.init(beat:2,bpm:60)])
        let preview=try MIDITempoImport.preview(parts,useID:p.active.uses[0].id,extendSection:false,tempoMap:map,in:p)
        XCTAssertEqual(preview.noteEndBeat,1);XCTAssertEqual(preview.lastExpressionBeat,4);XCTAssertEqual(preview.endBeat,4)
        XCTAssertEqual(preview.regionSeconds,3);XCTAssertEqual(preview.sectionSeconds,5)
        _=try MIDIImportEditing.apply(parts,useID:p.active.uses[0].id,extendSection:false,tempoPolicy:.applyFile,tempoMap:map,in:&p)
        let clock=try ArrangementCompiler.context(project:p,use:p.active.uses[0]).2
        XCTAssertEqual(clock.bpm(at:3),60);XCTAssertEqual(clock.bpm(at:4),120);XCTAssertEqual(clock.seconds,preview.sectionSeconds)
    }
    func testInvalidExpressionDrumsAndShiftOverflowAreAtomic()throws {
        let base=try fixture()
        let cases:[MIDIImportPart]=[
            part(.init(channel:16)),part(.init(events:[.init(beat:1,kind:.value(16384))])),
            part(.init(events:[.init(beat:2,kind:.value(0)),.init(beat:1,kind:.value(0))])),
            part(.init(events:[.init(beat:.infinity,kind:.value(0))])),
            part(.init(),drums:true),part(.init(events:[.init(beat:131072,kind:.value(0))]))]
        for invalid in cases {
            var p=base
            XCTAssertThrowsError(try MIDITempoImport.preview([invalid],useID:p.active.uses[0].id,extendSection:true,atBeat:1,tempoPolicy:.keepCurrent,in:p))
            XCTAssertThrowsError(try MIDIImportEditing.apply([part(),invalid],useID:p.active.uses[0].id,extendSection:true,atBeat:1,in:&p));XCTAssertEqual(p,base)
        }
        var omitted=base
        _=try MIDIImportEditing.apply([part(drums:true)],useID:omitted.active.uses[0].id,extendSection:false,in:&omitted)
        XCTAssertEqual(omitted.schemaVersion,base.schemaVersion)
        for policy in MIDIImportExpressionPolicy.allCases {XCTAssertEqual(try JSONDecoder().decode(MIDIImportExpressionPolicy.self,from:JSONEncoder().encode(policy)),policy)}
    }
    func testMaximumSectionAndAggregateEventBudgetRejectAtomically()throws {
        var base=try fixture(bars:1024);base.sections[0].settings.meter = .local(Meter(32,1))
        let boundary=[part(.init(events:[.init(beat:131072,kind:.value(0))]))]
        var p=base
        XCTAssertThrowsError(try MIDITempoImport.preview(boundary,useID:p.active.uses[0].id,extendSection:true,tempoPolicy:.keepCurrent,in:p))
        XCTAssertThrowsError(try MIDIImportEditing.apply(boundary,useID:p.active.uses[0].id,extendSection:true,in:&p));XCTAssertEqual(p,base)
        let expression=MIDIPitchBendSequence(events:Array(repeating:.init(beat:0,kind:.value(8192)),count:100000))
        let tooMany=Array(repeating:part(expression),count:11)
        XCTAssertThrowsError(try MIDITempoImport.preview(tooMany,useID:p.active.uses[0].id,extendSection:false,tempoPolicy:.keepCurrent,in:p))
        XCTAssertThrowsError(try MIDIImportEditing.apply(tooMany,useID:p.active.uses[0].id,extendSection:false,in:&p));XCTAssertEqual(p,base)
    }
}
