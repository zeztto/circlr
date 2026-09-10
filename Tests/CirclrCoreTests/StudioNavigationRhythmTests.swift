import XCTest
@testable import CirclrCore

final class StudioNavigationRhythmTests:XCTestCase {
    func fixture()throws->Project {
        var p=try HierarchyEditingTests().fixture()
        var pattern=RhythmPattern(name:"공유 패턴",trackID:p.tracks[0].id)
        let asset=Asset(name:"루프",path:"loop.wav",duration:4,sampleRate:48000)
        p.assets=[asset];pattern.audio=[AudioClip(assetID:asset.id,duration:1)]
        p.patterns=[pattern];p.global.rhythm=RhythmAssignment(pattern.id)
        return p
    }
    func address(_ kind:String,_ p:Project)->CircleAddress {
        .music(arrangementID:p.activeArrangementID,useID:p.active.uses[0].id,nodeID:"rhythm-\(kind):\(p.tracks[0].id)")
    }
    func testSharedSourcesHaveMediaRolesAndKeepTrackOwnershipWhenRerouted()throws {
        var p=try fixture()
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let midiID="rhythm-midi:\(p.tracks[0].id)",audioID="rhythm-audio:\(p.tracks[0].id)"
        graph.edges.removeAll{$0.from==midiID || $0.from==audioID}
        let otherOutput=try XCTUnwrap(graph.nodes.first{if case .output(let id)=$0.content{return id==p.tracks[1].id};return false})
        try SectionGraphEditing.connect(from:audioID,to:otherOutput.id,in:&graph)
        try SectionGraphEditing.set(graph,useID:p.active.uses[0].id,original:false,in:&p)
        let before=p,routes=try StudioNavigation.build(p)
        let owner=try XCTUnwrap(routes[0].tracks.first{$0.id==p.tracks[0].id})
        let midi=try XCTUnwrap(owner.destinations.first{$0.id==address("midi",p)})
        let audio=try XCTUnwrap(owner.destinations.first{$0.id==address("audio",p)})
        XCTAssertEqual(midi.role,"MIDI");XCTAssertEqual(audio.role,"오디오")
        XCTAssertTrue(midi.name.contains("공유 리듬"));XCTAssertTrue(audio.name.contains("공유 리듬"))
        XCTAssertFalse(midi.connected);XCTAssertFalse(audio.connected)
        XCTAssertFalse(routes[0].tracks.filter{$0.id != p.tracks[0].id}.flatMap(\.destinations).contains{$0.id==midi.id || $0.id==audio.id})
        XCTAssertNotNil(try StudioNavigation.scene(revealing:midi.id,in:p).node(midi.id))
        XCTAssertNotNil(try StudioNavigation.scene(revealing:audio.id,in:p).node(audio.id))
        XCTAssertEqual(p,before)
    }
    func testSharedSourcesRevealCollapsedGroupWithoutEditingPatternOrProject()throws {
        var p=try fixture();let midi=address("midi",p),audio=address("audio",p)
        let group=try HierarchyEditing.group([midi,audio],name:"공유 소스",in:&p)
        guard case .group(let scope,let id)=group else{return XCTFail()}
        try HierarchyEditing.editLayout(scope,in:&p){layout in layout.groups[layout.groups.firstIndex{$0.id==id}!].collapsed=true}
        let before=p
        XCTAssertNil(try HierarchySceneBuilder.build(p).node(audio))
        XCTAssertTrue(try StudioNavigation.build(p)[0].tracks[0].destinations.contains{$0.id==audio})
        XCTAssertEqual(try StudioNavigation.containingGroups(of:audio,in:p),[group])
        XCTAssertNotNil(try StudioNavigation.scene(revealing:audio,in:p).node(audio))
        XCTAssertEqual(p,before)
    }
    func testUnassignedAndEmptyAudioAreHiddenButAssignedEmptyMIDIIsEditable()throws {
        var p=try fixture();p.patterns[0].audio=[]
        let midi=address("midi",p),audio=address("audio",p)
        let destinations=try StudioNavigation.build(p).flatMap(\.tracks).flatMap(\.destinations)
        XCTAssertTrue(destinations.contains{$0.id==midi});XCTAssertFalse(destinations.contains{$0.id==audio})
        XCTAssertNotNil(try StudioNavigation.scene(revealing:midi,in:p).node(midi))
        p.global.rhythm=RhythmAssignment()
        XCTAssertFalse(try StudioNavigation.build(p).flatMap(\.tracks).flatMap(\.destinations).contains{$0.id==midi || $0.id==audio})
    }
    func testNodeLocalPatternOverridesInactiveParentButRequiresMatchingTrack()throws {
        var p=try fixture();p.global.rhythm=RhythmAssignment()
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        for index in graph.nodes.indices {
            switch graph.nodes[index].content {
            case .rhythmMIDI,.rhythmAudio:graph.nodes[index].settings.rhythm = .local(RhythmAssignment(p.patterns[0].id))
            default:break
            }
        }
        try SectionGraphEditing.set(graph,useID:p.active.uses[0].id,original:false,in:&p)
        let before=p,tracks=try StudioNavigation.build(p)[0].tracks
        let destinations=tracks.flatMap(\.destinations).filter{$0.name.contains("공유 리듬")}
        XCTAssertEqual(Set(destinations.map(\.id)),[address("midi",p),address("audio",p)])
        XCTAssertFalse(tracks.filter{$0.id != p.tracks[0].id}.flatMap(\.destinations).contains{$0.name.contains("공유 리듬")})
        for target in destinations {XCTAssertNotNil(try StudioNavigation.scene(revealing:target.id,in:p).node(target.id))}
        XCTAssertEqual(p,before)
    }
}
