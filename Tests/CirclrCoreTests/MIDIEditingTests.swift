import XCTest
@testable import CirclrCore

final class MIDIEditingTests:XCTestCase {
    func testImportOffsetPreservesRestsNotesOtherUseRoutingAndPlacement()throws {
        var p=try AudioImportEditingTests().fixture()
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        graph.edges.removeFirst()
        try SectionGraphEditing.set(graph,useID:p.active.uses[0].id,original:false,in:&p)
        let before=p
        let notes=[Note(beat:0.5,length:0.75,pitch:60,velocity:81),Note(beat:2.25,length:1,pitch:67,velocity:105)]
        let parts=[MIDIImportPart(name:"쉼표 있는 신스",notes:notes),MIDIImportPart(name:"드럼",notes:notes,drums:true)]
        let ids=try MIDIImportEditing.apply(parts,useID:p.active.uses[0].id,extendSection:false,atBeat:4.25,position:Point(300,240),in:&p)
        XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.active.uses[1],before.active.uses[1]);XCTAssertEqual(p.musicRevision,before.musicRevision)
        for (id,point) in before.signal.layout.positions {XCTAssertEqual(p.signal.layout.positions[id],point)}
        let after=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let oldNodes=Set(graph.nodes.map(\.id))
        XCTAssertEqual(after.edges.filter{oldNodes.contains($0.from)},graph.edges)
        XCTAssertEqual(after.layout.positions["midi:\(ids[0])"],Point(300,240));XCTAssertEqual(after.layout.positions["midi:\(ids[1])"],Point(520,240))
        let lanes=try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0])
        for id in ids {
            let imported=try XCTUnwrap(lanes.first{$0.id==id})
            XCTAssertEqual(imported.notes.map(\.beat),[4.75,6.5]);XCTAssertEqual(imported.notes.map(\.length),notes.map(\.length))
            XCTAssertEqual(imported.notes.map(\.pitch),notes.map(\.pitch));XCTAssertEqual(imported.notes.map(\.velocity),notes.map(\.velocity))
            XCTAssertTrue(Set(imported.notes.map(\.id)).isDisjoint(with:notes.map(\.id)))
        }
        XCTAssertTrue(p.tracks.last!.instrument.drums)
    }
    func testOffsetExtendsOnlyTargetUsingChangedMeterAndOrbitTiming()throws {
        var p=try AudioImportEditingTests().fixture();p.circleLayout = .orbit
        p.sections[0].bars=2;p.global.meter=Meter(6,8)
        p.sections[0].meterChanges=[MeterChange(bar:1,meter:Meter(5,8))]
        let before=p,part=MIDIImportPart(name:"변박",notes:[Note(beat:0.25,length:2,pitch:60)])
        let id=try MIDIImportEditing.apply([part],useID:p.active.uses[0].id,extendSection:true,atBeat:5,position:Point(300,240),in:&p)[0]
        XCTAssertEqual(p.active.uses[0].barsOverride,3);XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.active.uses[1],before.active.uses[1])
        let clock=try ArrangementCompiler.context(project:p,use:p.active.uses[0]).2
        XCTAssertEqual(clock.beats,8)
        let graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        XCTAssertNotEqual(graph.layout.positions["midi:\(id)"],Point(300,240))
        let compiled=try ArrangementCompiler.compile(p)
        XCTAssertEqual(compiled.occurrences[0].lanes.first{$0.id==id}?.notes.first?.beat,5.25)
    }
    func testInvalidOffsetAndNonExtendingImportAreAtomic()throws {
        var p=try AudioImportEditingTests().fixture();let before=p
        let part=MIDIImportPart(name:"코드",notes:[Note(beat:0,length:2,pitch:60)])
        for offset in [-1,16,Double.nan,Double.infinity] {
            XCTAssertThrowsError(try MIDIImportEditing.apply([part],useID:p.active.uses[0].id,extendSection:true,atBeat:offset,in:&p));XCTAssertEqual(p,before)
        }
        XCTAssertThrowsError(try MIDIImportEditing.apply([part],useID:p.active.uses[0].id,extendSection:false,atBeat:15,in:&p));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try MIDIImportEditing.apply([part],useID:p.active.uses[0].id,extendSection:true,position:Point(.nan,0),in:&p));XCTAssertEqual(p,before)
    }
    func testImportAddsPlayableCirclesExtendsOnlyThisUseAndIsAtomic()throws {
        var p=Project();let oldTrack=p.addTrack(name:"기존");let use=p.addSection(name:"한 마디",at:Point(),bars:1);p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        let before=p,part=MIDIImportPart(name:"가져온 코드",notes:[Note(beat:3.5,length:2,pitch:60)])
        XCTAssertThrowsError(try MIDIImportEditing.apply([part],useID:use,extendSection:false,in:&p));XCTAssertEqual(p,before)
        let ids=try MIDIImportEditing.apply([part],useID:use,extendSection:true,in:&p)
        XCTAssertEqual(p.active.uses[0].barsOverride,2);XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.tracks.first{$0.id==oldTrack},before.tracks[0])
        let plan=try ArrangementCompiler.compile(p),lanes=plan.occurrences[0].lanes
        XCTAssertEqual(plan.occurrences[0].clock.beats,8)
        XCTAssertEqual(lanes.first{$0.id==ids[0]}?.notes.map(\.pitch),[60]);XCTAssertNotEqual(lanes.first{$0.id==ids[0]}?.notes[0].id,part.notes[0].id)
        XCTAssertTrue(plan.occurrences[0].signalPlan!.midi.values.contains{$0.contains{$0.pitch==60}})
    }
    func fixture()->Lane {var lane=Lane(trackID:"keys");lane.notes=[Note(beat:0.13,length:0.6,pitch:60,velocity:91),Note(beat:0.38,length:0.2,pitch:64,velocity:87),Note(beat:3,length:1,pitch:67)];lane.audio=[AudioClip(assetID:"a",duration:1)];return lane}
    func testQuantizeStrengthKeepsIDsLengthVelocityAndUntouchedNotes()throws {
        let lane=fixture(),ids=Set(lane.notes.prefix(2).map(\.id))
        let n=try MIDIEditing.apply(.quantize(subdivisions:4,strength:0.5),to:lane,ids:ids,beats:4)
        XCTAssertEqual(n.notes[0].beat,0.19,accuracy:1e-10);XCTAssertEqual(n.notes[1].beat,0.44,accuracy:1e-10)
        XCTAssertEqual(n.notes.map(\.id),lane.notes.map(\.id));XCTAssertEqual(n.notes.map(\.length),lane.notes.map(\.length));XCTAssertEqual(n.notes.map(\.velocity),lane.notes.map(\.velocity));XCTAssertEqual(n.notes[2],lane.notes[2]);XCTAssertEqual(n.audio,lane.audio)
        XCTAssertEqual(try MIDIEditing.apply(.quantize(subdivisions:3,strength:0),to:lane,ids:ids,beats:4),lane)
    }
    func testTransposeAndMovePreserveIntervalsAndRejectPartialClamping()throws {
        let lane=fixture(),ids=Set(lane.notes.prefix(2).map(\.id))
        let n=try MIDIEditing.apply(.transpose(12),to:lane,ids:ids,beats:4)
        XCTAssertEqual(n.notes.map(\.pitch),[72,76,67])
        let moved=try MIDIEditing.apply(.move(2),to:n,ids:ids,beats:4)
        XCTAssertEqual(moved.notes[0].beat,2.13,accuracy:1e-9);XCTAssertEqual(moved.notes[1].beat,2.38,accuracy:1e-9)
        XCTAssertThrowsError(try MIDIEditing.apply(.transpose(65),to:lane,ids:ids,beats:4))
        XCTAssertThrowsError(try MIDIEditing.apply(.move(-0.2),to:lane,ids:ids,beats:4))
        XCTAssertThrowsError(try MIDIEditing.apply(.move(4),to:lane,ids:ids,beats:4))
    }
    func testDuplicateAndDeleteKeepOriginalsAndAudio()throws {
        let lane=fixture(),ids=Set(lane.notes.prefix(2).map(\.id))
        let copied=try MIDIEditing.apply(.duplicate(1),to:lane,ids:ids,beats:4)
        XCTAssertEqual(Array(copied.notes.prefix(3)),lane.notes);XCTAssertEqual(Set(copied.notes.map(\.id)).count,5)
        XCTAssertEqual(copied.notes[3].beat,1.13,accuracy:1e-9);XCTAssertEqual(copied.notes[3].velocity,91)
        let deleted=try MIDIEditing.apply(.delete,to:lane,ids:ids,beats:4)
        XCTAssertEqual(deleted.notes,[lane.notes[2]]);XCTAssertEqual(deleted.audio,lane.audio)
        XCTAssertThrowsError(try MIDIEditing.apply(.velocity(128),to:lane,ids:ids,beats:4))
        XCTAssertThrowsError(try MIDIEditing.apply(.delete,to:lane,ids:["missing"],beats:4))
        XCTAssertThrowsError(try MIDIEditing.apply(.quantize(subdivisions:5,strength:1),to:lane,ids:ids,beats:4))
    }
}
