import XCTest
@testable import CirclrCore

final class MIDIBatchInspectorTests:XCTestCase {
    func fixture()->Lane {
        var lane=Lane(trackID:"keys")
        lane.notes=[Note(beat:0,length:0.5,pitch:60,velocity:70),Note(beat:1,length:0.25,pitch:64,velocity:80),Note(beat:3,length:1,pitch:67,velocity:90)]
        lane.audio=[AudioClip(assetID:"preserved",duration:1)];return lane
    }
    func testRelativeVelocityPreservesDynamicsIDsAndUnselectedContent()throws {
        let lane=fixture(),ids=Set(lane.notes.prefix(2).map(\.id))
        let result=try MIDIEditing.apply(.velocityDelta(7),to:lane,ids:ids,beats:4)
        var expected=lane;expected.notes[0].velocity=77;expected.notes[1].velocity=87
        XCTAssertEqual(result,expected)
        XCTAssertEqual(try MIDIEditing.apply(.velocityDelta(-7),to:result,ids:ids,beats:4),lane)
    }
    func testLengthDeltaPreservesRelativeDurationsAndExactMinimum()throws {
        let lane=fixture(),ids=Set(lane.notes.prefix(2).map(\.id))
        let longer=try MIDIEditing.apply(.lengthDelta(0.5),to:lane,ids:ids,beats:4)
        var expected=lane;expected.notes[0].length=1;expected.notes[1].length=0.75
        XCTAssertEqual(longer,expected)
        let short=try MIDIEditing.apply(.lengthDelta(-0.21875),to:lane,ids:ids,beats:4)
        XCTAssertEqual(short.notes[0].length,0.28125);XCTAssertEqual(short.notes[1].length,0.03125)
        XCTAssertEqual(short.notes[2],lane.notes[2]);XCTAssertEqual(short.audio,lane.audio)
    }
    func testAnyInvalidResultRejectsWholeSelection()throws {
        let lane=fixture(),ids=Set(lane.notes.prefix(2).map(\.id)),before=lane
        for delta in [48,-70,Int.max,Int.min] {XCTAssertThrowsError(try MIDIEditing.apply(.velocityDelta(delta),to:lane,ids:ids,beats:4))}
        for delta in [-0.25,4,Double.nan,Double.infinity,-Double.infinity] {XCTAssertThrowsError(try MIDIEditing.apply(.lengthDelta(delta),to:lane,ids:ids,beats:4))}
        XCTAssertEqual(lane,before)
    }
    func testZeroIsNoOpIncludingExistingTailsOutsideShortenedCircle()throws {
        let lane=fixture(),ids=Set(lane.notes.map(\.id))
        XCTAssertEqual(try MIDIEditing.apply(.lengthDelta(0),to:lane,ids:ids,beats:1),lane)
        XCTAssertEqual(try MIDIEditing.apply(.velocityDelta(0),to:lane,ids:ids,beats:1),lane)
    }
    func testAgentRelativeEditsShareAtomicTransactionAndRejectMissingDelta()throws {
        let helper=AgentTests();var p=try helper.project(),lane=p.sections[0].lanes[0]
        lane.notes=fixture().notes;let use=p.active.uses[0].id
        try ProjectEditing.setLane(lane,for:use,original:false,in:&p)
        var length=AgentOperation("edit_notes");length.useID=use;length.laneID=lane.id;length.nodeID="midi:\(lane.id)";length.noteIDs=lane.notes.prefix(2).map(\.id);length.edit="length_delta";length.beatOffset=0.25
        var velocity=length;velocity.edit="velocity_delta";velocity.beatOffset=nil;velocity.velocityOffset=10
        let result=try AgentProjectEditing.apply(helper.request(p,[length,velocity]),to:p)
        let edited=try ArrangementCompiler.effectiveLanes(section:result.sections[0],use:result.active.uses[0])[0]
        var expected=lane;expected.notes[0].length=0.75;expected.notes[1].length=0.5;expected.notes[0].velocity=80;expected.notes[1].velocity=90
        XCTAssertEqual(edited,expected)
        velocity.velocityOffset=100
        XCTAssertThrowsError(try AgentProjectEditing.apply(helper.request(p,[length,velocity]),to:p))
        velocity.velocityOffset=nil
        XCTAssertThrowsError(try AgentProjectEditing.apply(helper.request(p,[velocity]),to:p))
        length.beatOffset=nil
        XCTAssertThrowsError(try AgentProjectEditing.apply(helper.request(p,[length]),to:p))
        XCTAssertEqual(try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0])[0],lane)
    }
    func testAgentZeroAndInvalidNodeKeepProjectUnchanged()throws {
        let helper=AgentTests();var p=try helper.project(),lane=p.sections[0].lanes[0];lane.notes=fixture().notes
        try ProjectEditing.setLane(lane,for:p.active.uses[0].id,original:false,in:&p)
        var op=AgentOperation("edit_notes");op.useID=p.active.uses[0].id;op.laneID=lane.id;op.noteIDs=lane.notes.map(\.id);op.edit="velocity_delta";op.velocityOffset=0
        XCTAssertEqual(try AgentProjectEditing.apply(helper.request(p,[op]),to:p),p)
        op.edit="length_delta";op.beatOffset=0
        XCTAssertEqual(try AgentProjectEditing.apply(helper.request(p,[op]),to:p),p)
        op.nodeID="missing"
        XCTAssertThrowsError(try AgentProjectEditing.apply(helper.request(p,[op]),to:p))
    }
}
