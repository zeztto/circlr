import XCTest
@testable import CirclrCore

final class AudioImportEditingTests:XCTestCase {
    func fixture()throws->Project {
        var p=Project();_=p.addTrack(name:"기존 MIDI");_=p.addSection(name:"공유 구간",at:Point(),bars:4)
        p.sections[0].lanes[0].notes=[Note(beat:1,pitch:64)]
        p=try SectionGraphMigration.migrate(p)
        _=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point(200,0))
        p.circleLayout = .freeform
        p.signal.layout.positions[p.signal.nodes.first{$0.kind == .master}!.id]=Point(-400,720)
        return p
    }
    func assets()->[Asset] {(0..<2).map{Asset(name:"오디오 \($0)",path:"/owned/\($0).wav",duration:1,sampleRate:48000)}}
    func target(_ p:Project,track:ID?=nil,original:Bool=false)->AudioImportDestination {
        .section(arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:track,beat:2,position:Point(300,240),original:original)
    }
    func testBatchPreservesOtherUseNotesRoutesAndMasterPosition()throws {
        var p=try fixture()
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        graph.edges.removeFirst() // A deliberately disconnected MIDI source must stay disconnected.
        try SectionGraphEditing.set(graph,useID:p.active.uses[0].id,original:false,in:&p)
        let before=p,ids=try AudioImportEditing.apply(assets(),to:target(p),projectID:p.id,revision:p.musicRevision,in:&p)
        XCTAssertEqual(p.tracks.count,before.tracks.count+2);XCTAssertEqual(ids.count,2)
        XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.active.uses[1],before.active.uses[1])
        XCTAssertEqual(p.musicRevision,before.musicRevision)
        for (id,point) in before.signal.layout.positions {XCTAssertEqual(p.signal.layout.positions[id],point)}
        let after=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let oldNodes=Set(graph.nodes.map(\.id))
        XCTAssertEqual(after.edges.filter{oldNodes.contains($0.from)},graph.edges)
        XCTAssertEqual(after.layout.positions["audio:\(ids[0])"],Point(300,240))
        XCTAssertEqual(after.layout.positions["audio:\(ids[1])"],Point(520,240))
        let lanes=try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0])
        XCTAssertEqual(lanes.first{$0.trackID==before.tracks[0].id}?.notes,before.sections[0].lanes[0].notes)
        XCTAssertEqual(lanes.flatMap(\.audio).map(\.beat),[2,2])
    }
    func testSingleFileAtSectionCreatesTrackAfterPriorMIDISelection()throws {
        var p=try fixture();let before=p
        let selection=CircleAddress.section(arrangementID:p.active.id,useID:p.active.uses[0].id)
        let track=AudioImportPlacement.suggestedTrack(for:selection,selectedTrack:p.tracks[0].id)
        let ids=try AudioImportEditing.apply([assets()[0]],to:target(p,track:track),projectID:p.id,revision:p.musicRevision,in:&p)
        XCTAssertEqual(p.tracks.count,before.tracks.count+1)
        let lanes=try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0])
        XCTAssertEqual(lanes.first{$0.trackID==before.tracks[0].id}?.notes,before.sections[0].lanes[0].notes)
        XCTAssertTrue(lanes.first{$0.trackID==before.tracks[0].id}!.audio.isEmpty)
        XCTAssertEqual(lanes.first{$0.trackID==p.tracks.last!.id}?.audio.map(\.id),ids)
        XCTAssertEqual(p.active.uses[1],before.active.uses[1])
    }
    func testSingleFileUsesExistingTrackAndOrbitPositionDoesNotChangeTiming()throws {
        var p=try fixture();p.circleLayout = .orbit;let count=p.tracks.count
        let id=try AudioImportEditing.apply([assets()[0]],to:target(p,track:p.tracks[0].id),projectID:p.id,revision:p.musicRevision,in:&p)[0]
        XCTAssertEqual(p.tracks.count,count)
        let lane=try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0])[0]
        XCTAssertEqual(lane.notes.count,1);XCTAssertEqual(lane.audio[0].beat,2)
        let graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        XCTAssertNotEqual(graph.layout.positions["audio:\(id)"],Point(300,240))
    }
    func testInvalidBatchAndStaleDestinationLeaveProjectUnchanged()throws {
        var p=try fixture();let before=p;var bad=assets();bad[1].duration = .nan
        XCTAssertThrowsError(try AudioImportEditing.apply(bad,to:target(p),projectID:p.id,revision:p.musicRevision,in:&p));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try AudioImportEditing.apply(assets(),to:target(p),projectID:p.id,revision:p.musicRevision+1,in:&p));XCTAssertEqual(p,before)
        let missing=AudioImportDestination.section(arrangementID:p.active.id,useID:"deleted",trackID:nil,beat:0,position:nil,original:false)
        XCTAssertThrowsError(try AudioImportEditing.apply(assets(),to:missing,projectID:p.id,revision:p.musicRevision,in:&p));XCTAssertEqual(p,before)
        let invalidPosition=AudioImportDestination.section(arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:nil,beat:0,position:Point(.infinity,0),original:false)
        XCTAssertThrowsError(try AudioImportEditing.apply(assets(),to:invalidPosition,projectID:p.id,revision:p.musicRevision,in:&p));XCTAssertEqual(p,before)
    }
    func testExplicitInactiveArrangementAndPatternDestinations()throws {
        var p=try fixture();let ai=p.active.id,ui=p.active.uses[0].id
        let other=Arrangement(name:"다른 곡");p.arrangements.append(other);p.activeArrangementID=other.id
        _=try AudioImportEditing.apply(assets(),to:.section(arrangementID:ai,useID:ui,trackID:nil,beat:0,position:nil,original:false),projectID:p.id,revision:p.musicRevision,in:&p)
        XCTAssertEqual(p.activeArrangementID,other.id);XCTAssertEqual(p.active,other)
        var pattern=RhythmPattern(name:"드럼 루프",trackID:p.tracks[0].id);pattern.notes=[Note(beat:0,pitch:36)];p.patterns.append(pattern)
        _=try AudioImportEditing.apply(assets(),to:.pattern(id:pattern.id,beat:0),projectID:p.id,revision:p.musicRevision,in:&p)
        XCTAssertEqual(p.patterns[0].notes,pattern.notes);XCTAssertEqual(p.patterns[0].audio.count,2)
    }
}
