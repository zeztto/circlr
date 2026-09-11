import XCTest
@testable import CirclrCore

final class OrbitTests: XCTestCase {
    func fixture() throws -> Project {
        var p=Project();_ = p.addTrack(name:"신스")
        let a=p.addSection(name:"Verse",at:Point(100,50),bars:2)
        let b=p.addSection(name:"Chorus",at:Point(450,80),bars:3)
        p.arrangements[0].uses[0].isEnd=false
        p.arrangements[0].uses[0].repeatCount=2
        p.arrangements[0].edges=[FlowEdge(from:a,to:b)]
        p.sections[0].lanes[0].notes=[Note(beat:0,length:1,pitch:60)]
        p.sections[1].settings.tempo = .local(90)
        p.sections[1].meterChanges=[MeterChange(bar:1,meter:Meter(3,4))]
        p.enableAlbum();return try SectionGraphMigration.migrate(p)
    }
    func testDefaultOrbitUsesActualExecutionAcrossRepeatsAndLocalClocks() throws {
        let p=try fixture(),scene=try HierarchySceneBuilder.build(p),plan=try ArrangementCompiler.compile(p)
        XCTAssertTrue(p.usesOrbits)
        let song=try XCTUnwrap(scene.node(.composition(p.album!.children[0])))
        XCTAssertEqual(song.timeline?.duration,plan.duration)
        XCTAssertEqual(scene.node(.album)?.timeline?.duration,try AlbumCompiler.executionPlan(p).duration)
        for use in p.active.uses {
            let node=try XCTUnwrap(scene.node(.section(arrangementID:p.activeArrangementID,useID:use.id))),orbit=try XCTUnwrap(node.orbit)
            XCTAssertEqual(orbit.intervals,plan.occurrences.filter{$0.use.id==use.id}.map{OrbitInterval($0.start,$0.end)})
            let attachment=try XCTUnwrap(scene.orbitAnchor(for:node.id))
            let offset=Point(attachment.x-song.center.x,attachment.y-song.center.y)
            XCTAssertEqual(OrbitTimeline.phase(offset),orbit.anchor/plan.duration,accuracy:1e-9)
            XCTAssertEqual(hypot(offset.x,offset.y),orbit.radius,accuracy:1e-9)
        }
        XCTAssertTrue(scene.nodes.allSatisfy { $0.scale == 1 })
        XCTAssertEqual(song.radius,200)
    }
    func testTempoMapTicksAndRoundTripUseSecondsRatherThanUniformBars() throws {
        let clock=try MusicClock(bars:3,context:MusicContext(),meterChanges:[MeterChange(bar:1,meter:Meter(3,4))],tempoChanges:[TempoChange(beat:4,bpm:60)])
        let orbit=OrbitTimeline(clock:clock)
        XCTAssertEqual(orbit.ticks.map(\.seconds),[0,2,5])
        XCTAssertEqual(orbit.duration,8)
        for beat in [0.0,0.25,4,6,9.5] {let seconds=clock.seconds(at:beat);XCTAssertEqual(orbit.seconds(at:orbit.point(at:seconds,radius:100)),seconds,accuracy:1e-9)}
        XCTAssertEqual(OrbitTimeline.phaseDelta(from:0.99,to:0.01),0.02,accuracy:1e-9)
        XCTAssertEqual(OrbitTimeline.phaseDelta(from:0.01,to:0.99),-0.02,accuracy:1e-9)
    }
    func testMusicStartChangesSchedulerAndGroupingKeepsItsMusicalOwner() throws {
        var p=try fixture();let use=p.active.uses[0],ai=p.activeArrangementID
        let source=CircleAddress.music(arrangementID:ai,useID:use.id,nodeID:"midi:\(p.sections[0].lanes[0].id)")
        let before=p
        try OrbitEditing.setStart(source,seconds:1.125,in:&p)
        let scene=try HierarchySceneBuilder.build(p),node=try XCTUnwrap(scene.node(source))
        XCTAssertEqual(node.music?.startBeat,2.25)
        let scheduled=try ArrangementCompiler.compile(p).occurrences[0].signalPlan!.midi[node.music!.id]!
        XCTAssertEqual(scheduled.first?.beat,2.25)
        let other=try XCTUnwrap(scene.nodes.first{$0.parent==node.parent && $0.music?.content.input != nil})
        let group=try HierarchyEditing.group([source,other.id],name:"그룹",in:&p)
        let grouped=try XCTUnwrap(HierarchySceneBuilder.build(p).node(source))
        XCTAssertEqual(grouped.parent,group);XCTAssertEqual(grouped.orbit,node.orbit)
        XCTAssertEqual(grouped.center.x,node.center.x,accuracy:1e-9);XCTAssertEqual(grouped.center.y,node.center.y,accuracy:1e-9)
        let restored=try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p))
        XCTAssertEqual(restored,p)
        let invalid=p;XCTAssertThrowsError(try OrbitEditing.setStart(other.id,seconds:1,in:&p));XCTAssertEqual(p,invalid)
        XCTAssertNotEqual(before,p)
    }
    func testAudioNaturalRepeatsAndLocalTempoMatchRendererBoundaries() throws {
        let clock=try MusicClock(bars:4,context:MusicContext())
        var node=MusicCircle(name:"오디오",content:.audio(laneID:"lane",clipID:"clip"))
        node.startBeat=2;node.repeatCount=3
        var clip=AudioClip(assetID:"asset",duration:1.5)
        clip.beat=1;clip.followsTempo=false
        XCTAssertEqual(OrbitTiming.intervals(node:node,context:MusicContext(),clock:clock,clips:[clip]),[OrbitInterval(1.5,3),OrbitInterval(3,4.5),OrbitInterval(4.5,6)])
        node.lengthBeats=4;node.settings.tempo = .local(60)
        var context=MusicContext();context.tempo=60
        XCTAssertEqual(OrbitTiming.intervals(node:node,context:context,clock:clock,clips:[clip]),[OrbitInterval(2,3.5),OrbitInterval(6,7.5)])
    }
    func testReorderAndRejectedBranchAreAtomic() throws {
        var p=try fixture();let a=p.active.uses[0].id,b=p.active.uses[1].id,ai=p.activeArrangementID
        let before=try ArrangementCompiler.compile(p).duration
        try OrbitEditing.reorderSection(.section(arrangementID:ai,useID:b),before:a,in:&p)
        XCTAssertEqual(p.active.startID,b);XCTAssertEqual(try ArrangementCompiler.compile(p).duration,before)
        p.arrangements[0].edges.append(FlowEdge(from:b,to:a));let bad=p
        XCTAssertThrowsError(try OrbitEditing.reorderSection(.section(arrangementID:ai,useID:a),before:b,in:&p));XCTAssertEqual(p,bad)
    }
    func testOverlapInsertAndUnscheduledSectionsKeepCompilerTime() throws {
        for mode in [TransitionMode.overlap,.insert] {
            var p=try fixture();p.arrangements[0].edges[0].transition.mode=mode
            p.arrangements[0].edges[0].transition.anchor = .seconds;p.arrangements[0].edges[0].transition.length=1
            let unused=p.addSection(name:"보관 섹션",at:Point(),bars:1);p=try SectionGraphMigration.migrate(p)
            let plan=try ArrangementCompiler.compile(p),scene=try HierarchySceneBuilder.build(p)
            let use=p.active.uses[1],node=try XCTUnwrap(scene.node(.section(arrangementID:p.activeArrangementID,useID:use.id)))
            XCTAssertEqual(node.orbit?.anchor,plan.occurrences.last?.start)
            XCTAssertNil(scene.node(.section(arrangementID:p.activeArrangementID,useID:unused))?.orbit)
            XCTAssertEqual(node.orbit?.timeline.duration,plan.duration)
        }
    }
    func testInheritedMusicClockKeepsPartialBarsAndMeterChanges() throws {
        let parent=try MusicClock(bars:3,context:MusicContext(),meterChanges:[MeterChange(bar:1,meter:Meter(3,4))],tempoChanges:[TempoChange(beat:4,bpm:60)])
        let clock=try MusicClock(parent:parent,start:2,length:6,context:MusicContext(),inheritTempo:true,inheritMeter:true)
        XCTAssertEqual(clock.barStarts,[0,2,5,6]);XCTAssertEqual(clock.meters.map(\.numerator),[4,3,3])
        XCTAssertEqual(clock.seconds,parent.seconds(at:8)-parent.seconds(at:2),accuracy:1e-9)
    }
    func testReorderNeverSilentlyDropsAnAudibleTransition() throws {
        var p=try fixture();p.arrangements[0].edges[0].transition.length=0.5
        let before=p
        XCTAssertThrowsError(try OrbitEditing.reorderSection(.section(arrangementID:p.activeArrangementID,useID:p.active.uses[0].id),before:nil,in:&p))
        XCTAssertEqual(p,before)
    }
    func testEmptyNewSongDoesNotRemoveExistingAlbumTime() throws {
        var p=try fixture();let before=try AlbumCompiler.executionPlan(p).duration
        let new=try AlbumEditing.add(name:"다음 곡",kind:.song,in:&p)
        let scene=try HierarchySceneBuilder.build(p)
        XCTAssertEqual(scene.node(.album)?.timeline?.duration,before)
        XCTAssertEqual(scene.node(.composition(new))?.timeline?.duration,0)
        XCTAssertNil(scene.node(.composition(new))?.orbit)
        XCTAssertNotNil(scene.node(.composition(p.album!.children[0]))?.orbit)
    }
}
