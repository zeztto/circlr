import XCTest
@testable import CirclrCore

final class MIDIEditingTests:XCTestCase {
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
