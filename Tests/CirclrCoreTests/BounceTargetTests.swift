import XCTest
@testable import CirclrCore

final class BounceTargetTests:XCTestCase {
    func fixture()throws->Project {
        var p=Project();_=p.addTrack(name:"패드");_=p.addSection(name:"후렴",at:Point(),bars:4)
        p.sections[0].lanes[0].notes=[Note(beat:0,pitch:60)]
        return try SectionGraphMigration.migrate(p)
    }
    func testTargetReadsOutputAndPreservesProject()throws {
        let p=try fixture(),before=p
        let t=try BounceEditing.target(trackID:p.tracks[0].id,useID:p.active.uses[0].id,in:p)
        XCTAssertFalse(t.inputs.isEmpty);XCTAssertTrue(t.inputs.allSatisfy{$0.to==t.outputNodeID});XCTAssertEqual(p,before)
    }
    func testRejectsMissingTrackUseAndDisconnectedOutput()throws {
        var p=try fixture();let use=p.active.uses[0].id,track=p.tracks[0].id
        XCTAssertThrowsError(try BounceEditing.target(trackID:"missing",useID:use,in:p))
        XCTAssertThrowsError(try BounceEditing.target(trackID:track,useID:"missing",in:p))
        let target=try BounceEditing.target(trackID:track,useID:use,in:p)
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        graph.edges.removeAll{$0.to==target.outputNodeID}
        try SectionGraphEditing.set(graph,useID:use,original:false,in:&p)
        XCTAssertThrowsError(try BounceEditing.target(trackID:track,useID:use,in:p))
        let before=p
        XCTAssertThrowsError(try BounceEditing.apply(asset:Asset(name:"render",path:"/qa.wav",duration:1,sampleRate:48000),trackID:track,useID:use,bodySeconds:1,tailSeconds:0,in:&p))
        XCTAssertEqual(p,before)
    }
    func testExplicitArrangementIgnoresActiveSelection()throws {
        var p=try fixture();let arrangement=p.active.id,use=p.active.uses[0].id,track=p.tracks[0].id
        let expected=try BounceEditing.target(trackID:track,useID:use,in:p)
        let other=Arrangement(name:"다른 안");p.arrangements.append(other);p.activeArrangementID=other.id
        XCTAssertEqual(try BounceEditing.target(trackID:track,useID:use,arrangementID:arrangement,in:p),expected)
        XCTAssertThrowsError(try BounceEditing.target(trackID:track,useID:use,in:p))
    }
    func testDuplicateOutputsAreRejected()throws {
        var p=try fixture();let use=p.active.uses[0].id,track=p.tracks[0].id
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        var duplicate=try XCTUnwrap(graph.nodes.first{if case .output(let id)=$0.content{return id==track};return false})
        duplicate.id=newID();graph.nodes.append(duplicate)
        p.sections[0].graph=graph
        XCTAssertThrowsError(try BounceEditing.target(trackID:track,useID:use,in:p))
    }
}
