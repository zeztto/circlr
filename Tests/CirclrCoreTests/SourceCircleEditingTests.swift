import XCTest
@testable import CirclrCore

final class SourceCircleEditingTests:XCTestCase {
    func audioProject()throws->Project {
        var p=Project();_=p.addSection(name:"오디오 구간",at:Point(),bars:4);p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        let asset=Asset(name:"패드.wav",path:"/owned/pad.wav",duration:2,sampleRate:48000)
        _=try AudioImportEditing.apply([asset],to:.section(arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:nil,beat:0,position:nil,original:false),projectID:p.id,revision:p.musicRevision,in:&p)
        return p
    }
    func graph(_ p:Project)throws->SectionGraph {try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))}
    func lane(_ p:Project)throws->Lane {try XCTUnwrap(ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0]).first)}
    func testAudioOnlyCreatesThreeVisibleCirclesAndNavigationOpensAudio()throws {
        let p=try audioProject(),g=try graph(p)
        XCTAssertEqual(g.nodes.count,4);XCTAssertEqual(g.edges.count,3)
        XCTAssertFalse(g.nodes.contains{switch $0.content {case .midi,.instrument,.rhythmMIDI:return true;default:return false}})
        let routes=try StudioNavigation.build(p),track=try XCTUnwrap(routes.first?.tracks.first)
        XCTAssertEqual(track.destinations.map(\.role),["오디오","믹스","출력"])
        XCTAssertTrue(track.destinations.allSatisfy(\.connected))
        let scene=try HierarchySceneBuilder.build(p)
        XCTAssertEqual(scene.nodes.filter{if case .music=$0.id{return true};return false}.count,3)
    }
    func testFirstMIDINoteMaterializesPlayablePathWithoutMovingOrReconnectingAudio()throws {
        var p=try audioProject(),l=try lane(p),g=try graph(p)
        let audio=try XCTUnwrap(g.nodes.first{if case .audio=$0.content{return true};return false})
        g.edges.removeAll{$0.from==audio.id}
        try SectionGraphEditing.set(g,useID:p.active.uses[0].id,original:false,in:&p)
        l.notes=[Note(beat:0,pitch:60)]
        try ProjectEditing.setLane(l,for:p.active.uses[0].id,original:false,in:&p)
        let after=try graph(p),midi="midi:\(l.id)"
        XCTAssertTrue(after.nodes.contains{$0.id==midi})
        XCTAssertEqual(StudioNavigation.outputTracks(from:midi,graph:after),Set([l.trackID]))
        XCTAssertFalse(after.edges.contains{$0.from==audio.id})
        for (id,position) in g.layout.positions {XCTAssertEqual(after.layout.positions[id],position)}
        let positions=after.layout.positions.sorted{$0.key<$1.key}
        for i in positions.indices {for j in positions.indices where j>i {
            XCTAssertGreaterThanOrEqual(hypot(positions[i].value.x-positions[j].value.x,positions[i].value.y-positions[j].value.y),180)
        }}
    }
    func testFurtherAudioEditsDoNotCreateMIDIOrResurrectDeletedSource()throws {
        var p=try audioProject(),l=try lane(p)
        var clip=l.audio[0];clip.id=newID();clip.beat=4;l.audio.append(clip)
        try ProjectEditing.setLane(l,for:p.active.uses[0].id,original:false,in:&p)
        XCTAssertEqual(try graph(p).nodes.count,5)
        l.notes=[Note(beat:0,pitch:60)]
        try ProjectEditing.setLane(l,for:p.active.uses[0].id,original:false,in:&p)
        var g=try graph(p);SectionGraphEditing.remove(["midi:\(l.id)"],from:&g)
        try SectionGraphEditing.set(g,useID:p.active.uses[0].id,original:false,in:&p)
        clip.id=newID();clip.beat=8;l.audio.append(clip)
        try ProjectEditing.setLane(l,for:p.active.uses[0].id,original:false,in:&p)
        XCTAssertFalse(try graph(p).nodes.contains{$0.id=="midi:\(l.id)"})
        let existing=try graph(p);l.audio[0].gain=0.5
        try ProjectEditing.setLane(l,for:p.active.uses[0].id,original:false,in:&p)
        XCTAssertEqual(try graph(p),existing)
    }
    func testEmptyMIDICreationAndExplicitRhythmAreAvailableAndIdempotent()throws {
        var p=try audioProject();let master=try XCTUnwrap(p.signal.nodes.first{$0.kind == .master})
        p.signal.layout.positions[master.id]=Point(-320,900)
        let track=p.addTrack(name:"빈 MIDI"),l=Lane(trackID:track)
        try ProjectEditing.setLane(l,for:p.active.uses[0].id,original:false,in:&p)
        XCTAssertEqual(p.signal.layout.positions[master.id],Point(-320,900))
        XCTAssertTrue(try graph(p).nodes.contains{$0.id=="midi:\(l.id)"})
        let audioTrack=try lane(p).trackID,before=try graph(p)
        let id=try SourceCircleEditing.ensureRhythmMIDI(trackID:audioTrack,useID:p.active.uses[0].id,in:&p)
        XCTAssertEqual(StudioNavigation.outputTracks(from:id,graph:try graph(p)),Set([audioTrack]))
        for edge in before.edges {XCTAssertTrue(try graph(p).edges.contains(edge))}
        let once=p;_=try SourceCircleEditing.ensureRhythmMIDI(trackID:audioTrack,useID:p.active.uses[0].id,in:&p)
        XCTAssertEqual(p,once)
        XCTAssertThrowsError(try SourceCircleEditing.ensureRhythmMIDI(trackID:"missing",useID:p.active.uses[0].id,in:&p));XCTAssertEqual(p,once)
    }
    func testOutputEffectPreservesFanInGainsAndOtherOutput()throws {
        var p=try audioProject(),g=try graph(p)
        let output=try XCTUnwrap(g.nodes.first{if case .output=$0.content{return true};return false})
        let other=MusicCircle(name:"다른 출력",content:.output(trackID:p.tracks[0].id));g.nodes.append(other)
        let audio=try XCTUnwrap(g.nodes.first{if case .audio=$0.content{return true};return false})
        var direct=MusicConnection(from:audio.id,to:output.id,signal:.audio);direct.gain=0.4;direct.toPortID=CirclePort.audioInput;g.edges.append(direct)
        let otherEdge=MusicConnection(from:audio.id,to:other.id,signal:.audio);g.edges.append(otherEdge)
        let before=g,incoming=g.edges.filter{$0.to==output.id},fx=MusicCircle(name:"트랙 필터",content:.effect(Effect(.lowpass,amount:0.5)))
        try SectionGraphEditing.insertEffectBeforeOutput(fx,before:output.id,in:&g)
        XCTAssertEqual(g.edges.filter{$0.to==output.id}.map(\.from),[fx.id])
        for edge in incoming {let changed=try XCTUnwrap(g.edges.first{$0.id==edge.id});XCTAssertEqual(changed.to,fx.id);XCTAssertEqual(changed.from,edge.from);XCTAssertEqual(changed.gain,edge.gain)}
        XCTAssertTrue(g.edges.contains(otherEdge));_=try SectionGraphValidator.sorted(g)
        let valid=g
        XCTAssertThrowsError(try SectionGraphEditing.insertEffectBeforeOutput(fx,before:audio.id,in:&g));XCTAssertEqual(g,valid)
        try SectionGraphEditing.set(before,useID:p.active.uses[0].id,original:false,in:&p)
        let unchanged=p;try SectionGraphEditing.set(g,useID:p.active.uses[0].id,original:false,in:&p)
        XCTAssertEqual(p.sections,unchanged.sections)
    }
}
