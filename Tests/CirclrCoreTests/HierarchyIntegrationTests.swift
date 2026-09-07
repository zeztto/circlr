import XCTest
@testable import CirclrCore

final class HierarchyIntegrationTests: XCTestCase {
    func fixture() throws -> Project {
        var p=Project();let track=p.addTrack(name:"건반");_=p.addSection(name:"벌스",at:Point(),bars:2)
        p.sections[0].lanes.append(Lane(trackID:track))
        p.sections[0].lanes[0].notes=[Note(beat:0,pitch:48)]
        p.sections[0].lanes[1].notes=[Note(beat:1,pitch:60)]
        p.enableAlbum();return try SectionGraphMigration.migrate(p)
    }
    func testGlobalSignalSceneUsesRealNodesEdgesAndMovesIndependently() throws {
        var p=try fixture();var fx=SignalNode(kind:.effect,name:"앨범 Delay");fx.effect=Effect(.delay,amount:0.25,secondary:0.3)
        let source=p.signal.nodes.first{$0.kind == .source}!,master=p.signal.nodes.first{$0.kind == .master}!
        p.signal.nodes.append(fx);p.signal.layout.positions[fx.id]=Point(340,0)
        p.signal.edges=[SignalEdge(from:source.id,to:fx.id),SignalEdge(from:fx.id,to:master.id)]
        let before=try HierarchySceneBuilder.build(p),node=try XCTUnwrap(before.node(.signal(fx.id)))
        XCTAssertEqual(node.signal?.effect,fx.effect);XCTAssertEqual(node.parent,.sound)
        XCTAssertTrue(node.acceptsInput);XCTAssertTrue(node.providesOutput)
        XCTAssertFalse(before.node(.signal(source.id))!.acceptsInput)
        XCTAssertFalse(before.node(.signal(master.id))!.providesOutput)
        XCTAssertEqual(before.edges.filter{$0.id.hasPrefix("signal:")}.count,2)
        try HierarchyEditing.move(.signal(fx.id),to:Point(420,90),in:&p)
        XCTAssertEqual(p.signal.layout.positions[fx.id],Point(420,90))
        XCTAssertEqual(p.signal.edges.count,2)
        let soundPosition=try HierarchyEditing.position(.sound,in:p),beforeMove=try HierarchySceneBuilder.build(p)
        try HierarchyEditing.move(.sound,to:Point(soundPosition.x+100,soundPosition.y+50),in:&p)
        let afterMove=try HierarchySceneBuilder.build(p)
        XCTAssertEqual(afterMove.node(.signal(fx.id))!.center.x-beforeMove.node(.signal(fx.id))!.center.x,30,accuracy:1e-8)
        XCTAssertEqual(afterMove.node(.signal(fx.id))!.center.y-beforeMove.node(.signal(fx.id))!.center.y,15,accuracy:1e-8)
        _=try SignalValidator.sorted(p.signal,tracks:p.tracks)
    }
    func testRecordedTakeTargetsExactLaneAcrossActiveArrangements() throws {
        var p=try fixture();let target=p.sections[0].lanes[1],original=p.sections[0].lanes[0]
        var take=RecordedTake(useID:p.active.uses[0].id,name:"테이크",lane:Lane(trackID:target.trackID))
        take.lane.notes=[Note(beat:0.5,pitch:72)];take.targetLaneID=target.id;take.arrangementID=p.activeArrangementID
        _=try AlbumEditing.add(name:"두 번째 곡",kind:.song,in:&p)
        let active=p.activeArrangementID
        try ProjectEditing.activateTake(take,in:&p)
        XCTAssertEqual(p.activeArrangementID,active)
        let use=p.arrangements.first{$0.id==take.arrangementID}!.uses[0]
        let lanes=try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:use)
        XCTAssertEqual(lanes.first{$0.id==target.id}!.notes,take.lane.notes)
        XCTAssertEqual(lanes.first{$0.id==original.id}!.notes,original.notes)
        let before=p;take.targetLaneID="deleted"
        XCTAssertThrowsError(try ProjectEditing.activateTake(take,in:&p));XCTAssertEqual(p,before)
    }
    func testPartialBarRecordingClockUsesOwnTempoAndExactBoundary() throws {
        var context=MusicContext();context.tempo=90
        let clock=try MusicClock(beats:5.5,context:context,tempoChanges:[TempoChange(beat:4,bpm:120)])
        XCTAssertEqual(clock.beats,5.5);XCTAssertEqual(clock.seconds,4*60/90+1.5*60/120,accuracy:1e-10)
        XCTAssertEqual(clock.beat(atSeconds:clock.seconds),5.5,accuracy:1e-10)
        XCTAssertThrowsError(try MusicClock(beats:.infinity,context:context))
    }
    func testViewportRoundTripAndInvalidCameraFallback() throws {
        var p=try fixture();let address=CircleAddress.music(arrangementID:p.activeArrangementID,useID:p.active.uses[0].id,nodeID:"midi:\(p.sections[0].lanes[0].id)")
        let saved=HierarchyViewport(camera:HierarchyCamera(pan:Point(-200,500),zoom:81),width:1200,height:800,selection:address)
        p.hierarchyView=saved
        let loaded=try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p))
        XCTAssertEqual(loaded.hierarchyView,saved)
        XCTAssertEqual(saved.restored(width:1000,height:700),HierarchyCamera(pan:Point(-300,450),zoom:81))
        var invalid=saved;invalid.camera.zoom=0;XCTAssertNil(invalid.restored(width:1000,height:700))
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(p)) as! [String:Any];legacy.removeValue(forKey:"hierarchyView")
        XCTAssertNil(try JSONDecoder().decode(Project.self,from:JSONSerialization.data(withJSONObject:legacy)).hierarchyView)
    }
}
