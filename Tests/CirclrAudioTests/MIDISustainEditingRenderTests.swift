import XCTest
@testable import CirclrCore
@testable import CirclrAudio

/// Direct edits, compilation and CPU synthesis. No player, AU, or audio device.
final class MIDISustainEditingRenderTests:XCTestCase {
    func fixture()throws->Project {
        var p=Project();_=p.addTrack(name:"페달");_=p.addTrack(name:"독립 음");_=p.addSection(name:"벌스",at:Point(),bars:1)
        for i in p.tracks.indices {
            p.tracks[i].instrument = .synthesizer(.pad)
            p.tracks[i].instrument.synth!.attack=0.005;p.tracks[i].instrument.synth!.release=0.06;p.tracks[i].instrument.synth!.motion=0
            p.sections[0].lanes[i].notes=[.init(beat:0,length:0.5,pitch:i==0 ? 60:67,velocity:100)]
        }
        p.sections[0].lanes[0].pitchBend = .init(channel:3,initialValue:10240)
        p.schemaVersion=7;p=try SectionGraphMigration.migrate(p)
        return p
    }
    func edit(_ kind:String,p:Project,index:Int?=nil,beat:Double?=nil,raw:Int?=nil,original:Bool=false)throws->Project {
        var change=AgentSustainChange(kind:kind);change.index=index;change.beat=beat;change.rawValue=raw
        var op=AgentOperation("edit_sustain");op.arrangementID=p.activeArrangementID;op.useID=p.active.uses[0].id
        op.laneID=p.sections[0].lanes[0].id;op.original=original;op.sustainChange=change
        var request=AgentRequest(method:"apply");request.projectID=p.id;request.expectedRevision=p.musicRevision
        var arguments=AgentArguments();arguments.operations=[op];request.arguments=arguments
        return try AgentProjectEditing.apply(request,to:p)
    }
    func outputs(_ p:Project,useID:ID?=nil)async throws->[ID:PCM] {
        let use=try XCTUnwrap(p.active.uses.first{useID==nil || $0.id==useID})
        let (section,context,clock)=try ArrangementCompiler.context(project:p,use:use,arrangementID:p.activeArrangementID)
        let compiled=try SectionGraphCompiler.compile(project:p,section:section,use:use,context:context,clock:clock)
        let plan=try XCTUnwrap(compiled)
        return try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0.15)
    }
    func lane(_ p:Project)throws->Lane {
        let use=p.active.uses[0]
        return try XCTUnwrap(ArrangementCompiler.effectiveLanes(section:p.sections[0],use:use).first)
    }
    func testInsertUpdateOffAndClearChangeSoundWithoutChangingKeysOrPairedBend()async throws {
        let original=try fixture(),dry=try await outputs(original),track=original.tracks[0].id,other=original.tracks[1].id
        var down=try edit("insert",p:original,beat:0,raw:127)
        down=try edit("insert",p:down,beat:2,raw:0)
        let held=try await outputs(down),heldLane=try lane(down)
        XCTAssertEqual(heldLane.notes,original.sections[0].lanes[0].notes)
        XCTAssertEqual(heldLane.pitchBend,original.sections[0].lanes[0].pitchBend)
        XCTAssertEqual(heldLane.sustain?.channel,3)
        let heldPCM=try XCTUnwrap(held[track]),dryPCM=try XCTUnwrap(dry[track])
        XCTAssertNotEqual(heldPCM.left,dryPCM.left)
        let late=24000..<42000
        XCTAssertGreaterThan(heldPCM.left[late].reduce(0){$0+abs($1)},dryPCM.left[late].reduce(0){$0+abs($1)}+1)
        XCTAssertEqual(held[other]?.left,dry[other]?.left);XCTAssertEqual(held[other]?.right,dry[other]?.right)
        let off=try edit("update",p:down,index:0,beat:0,raw:63),offPCM=try await outputs(off)
        XCTAssertEqual(offPCM[track]?.left,dryPCM.left);XCTAssertEqual(offPCM[track]?.right,dryPCM.right)
        let restored=try edit("clear",p:down),restoredPCM=try await outputs(restored)
        XCTAssertNil(try lane(restored).sustain)
        XCTAssertEqual(restoredPCM[track]?.left,dryPCM.left);XCTAssertEqual(restoredPCM[track]?.right,dryPCM.right)
    }
    func testPedalReleaseBeatEditFollowsTempoMapAndRestoresExactPCM()async throws {
        var p=try fixture();p.sections[0].tempoChanges=[.init(beat:1,bpm:60)]
        p=try edit("insert",p:p,beat:0,raw:127);p=try edit("insert",p:p,beat:2,raw:0)
        let before=p,baseline=try await outputs(p),track=p.tracks[0].id
        let later=try edit("update",p:p,index:1,beat:3,raw:0),laterPCM=try await outputs(later)
        // At 120→60 BPM after beat1, pedal-up beat2 is 1.5s; beat3 is 2.5s.
        let a=try XCTUnwrap(baseline[track]),b=try XCTUnwrap(laterPCM[track])
        XCTAssertEqual(Array(a.left[..<72000]),Array(b.left[..<72000]))
        XCTAssertNotEqual(Array(a.left[96000..<108000]),Array(b.left[96000..<108000]))
        let restored=try edit("update",p:later,index:1,beat:2,raw:0),restoredPCM=try await outputs(restored)
        XCTAssertEqual(restoredPCM[track]?.left,a.left);XCTAssertEqual(restoredPCM[track]?.right,a.right)
        XCTAssertEqual(try lane(restored),try lane(before))
    }
    func testUseOverrideDoesNotChangeAnotherUseOfSameSource()async throws {
        var p=try fixture();let first=p.active.uses[0].id
        let second=try ProjectEditing.reuse(first,in:&p,at:Point(300,0))
        let baseline=try await outputs(p,useID:second)
        var changed=try edit("insert",p:p,beat:0,raw:127)
        changed=try edit("insert",p:changed,beat:2,raw:0)
        let other=try await outputs(changed,useID:second)
        for track in p.tracks {XCTAssertEqual(other[track.id]?.left,baseline[track.id]?.left);XCTAssertEqual(other[track.id]?.right,baseline[track.id]?.right)}
        XCTAssertEqual(changed.sections,p.sections)
        XCTAssertEqual(changed.active.uses[1],p.active.uses[1])
    }
}
