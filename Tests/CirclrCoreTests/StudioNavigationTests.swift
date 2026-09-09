import CoreGraphics
import XCTest
@testable import CirclrCore

final class StudioNavigationTests:XCTestCase {
    func fixture()throws->Project {try HierarchyEditingTests().fixture()}
    func testRoutesPreserveRepeatedUseIdentityAndPayload()throws {
        var p=try fixture()
        _=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point(300,0))
        let before=p,routes=try StudioNavigation.build(p)
        XCTAssertEqual(routes.count,2);XCTAssertNotEqual(routes[0].id,routes[1].id)
        XCTAssertEqual(routes[0].tracks.count,2)
        for route in routes {for track in route.tracks {
            XCTAssertTrue(track.destinations.contains{$0.role=="MIDI" && $0.connected})
            XCTAssertTrue(track.destinations.contains{$0.role=="악기" && $0.connected})
            XCTAssertTrue(track.destinations.contains{$0.role=="출력" && $0.connected})
        }}
        XCTAssertEqual(p,before)
    }
    func testSharedFXUsesAudibleOutputsExcludingSidechain()throws {
        var p=try fixture()
        var g=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let fx=MusicCircle(name:"공유 리버브",content:.effect(Effect(.reverb)))
        let compressor=MusicCircle(name:"덕킹",content:.effect(Effect(.compressor)))
        g.nodes += [fx,compressor]
        let outputs=g.nodes.filter{if case .output=$0.content{return true};return false}
        for output in outputs {try SectionGraphEditing.connect(from:fx.id,to:output.id,in:&g)}
        try SectionGraphEditing.connect(from:compressor.id,to:outputs[1].id,in:&g)
        let firstInstrument=try XCTUnwrap(g.nodes.first{if case .instrument(let id)=$0.content{return id==p.tracks[0].id};return false})
        try SectionGraphEditing.connect(from:firstInstrument.id,to:compressor.id,sidechain:true,in:&g)
        try SectionGraphEditing.set(g,useID:p.active.uses[0].id,original:false,in:&p)
        XCTAssertEqual(StudioNavigation.outputTracks(from:fx.id,graph:g),Set(p.tracks.map(\.id)))
        XCTAssertEqual(StudioNavigation.outputTracks(from:firstInstrument.id,graph:g),[p.tracks[0].id])
        let routes=try StudioNavigation.build(p)
        XCTAssertEqual(routes[0].tracks.filter{$0.destinations.contains{$0.name==fx.name}}.count,2)
        XCTAssertFalse(routes[0].tracks[0].destinations.contains{$0.name==compressor.name})
        XCTAssertTrue(routes[0].tracks[1].destinations.contains{$0.name==compressor.name})
    }
    func testRevealOpensOnlyContainingGroupsWithoutChangingMusic()throws {
        var p=try fixture()
        let routes=try StudioNavigation.build(p),target=try XCTUnwrap(routes[0].tracks[0].destinations.first{$0.role=="MIDI"})
        let instrument=try XCTUnwrap(routes[0].tracks[0].destinations.first{$0.role=="악기"})
        let group=try HierarchyEditing.group([target.id,instrument.id],name:"접힌 연주",in:&p)
        guard case .group(let scope,let id)=group else{return XCTFail()}
        try HierarchyEditing.editLayout(scope,in:&p){layout in layout.groups[layout.groups.firstIndex{$0.id==id}!].collapsed=true}
        let before=try AlbumCompiler.executionPlan(p),original=p
        XCTAssertNil(try HierarchySceneBuilder.build(p).node(target.id))
        XCTAssertTrue(try StudioNavigation.build(p)[0].tracks[0].destinations.contains{$0.id==target.id})
        let scene=try StudioNavigation.scene(revealing:target.id,in:p)
        XCTAssertNotNil(scene.node(target.id))
        XCTAssertEqual(p,original)
        XCTAssertEqual(try AlbumCompiler.executionPlan(p).occurrences[0].signalPlan?.midi,before.occurrences[0].signalPlan?.midi)
        XCTAssertNotNil(try StudioNavigation.scene(revealing:target.id,in:p).node(target.id))
        XCTAssertThrowsError(try StudioNavigation.scene(revealing:.music(arrangementID:p.activeArrangementID,useID:p.active.uses[0].id,nodeID:"missing"),in:p));XCTAssertEqual(p,original)
    }
    func testDisconnectedSourceRemainsDiscoverable()throws {
        var p=try fixture();var g=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let midi=try XCTUnwrap(g.nodes.first{if case .midi=$0.content{return true};return false})
        g.edges.removeAll{$0.from==midi.id}
        try SectionGraphEditing.set(g,useID:p.active.uses[0].id,original:false,in:&p)
        let target=try XCTUnwrap(try StudioNavigation.build(p)[0].tracks[0].destinations.first{$0.name==midi.name})
        XCTAssertFalse(target.connected)
    }
    func testDenseLabelsDoNotOverlapAndPriorityKeepsSelected() {
        let bounds=CGRect(x:0,y:0,width:1024,height:768),obstacle=CGRect(x:0,y:0,width:1024,height:80)
        let requests=(0..<15).map{CanvasLabelRequest(id:.signal("\($0)"),anchor:CGPoint(x:500,y:130+Double($0)*14),size:CGSize(width:150,height:30),radius:3,priority:$0==14 ? 100:0)}
        let placements=CanvasLabelLayout.place(requests,within:bounds,avoiding:[obstacle])
        XCTAssertEqual(placements.first?.id,.signal("14"));XCTAssertGreaterThan(placements.count,8)
        for (i,label) in placements.enumerated() {
            XCTAssertTrue(bounds.contains(label.rect));XCTAssertFalse(obstacle.intersects(label.rect))
            for other in placements.dropFirst(i+1) {XCTAssertFalse(label.rect.intersects(other.rect))}
        }
    }
    func testEditorFitsSmallAndLargeWindowsWithConsole() {
        for size in [CGSize(width:1024,height:673),CGSize(width:1440,height:809)] {
            for console in [nil,CGRect(x:20,y:size.height-220,width:700,height:202)] as [CGRect?] {
                let viewport=CanvasWorkspaceGeometry.viewport(width:size.width,height:size.height,console:console)
                let editor=CanvasWorkspaceGeometry.editor(center:CGPoint(x:10,y:10),radius:460,within:viewport)
                XCTAssertTrue(viewport.contains(editor));XCTAssertGreaterThan(editor.width,700);XCTAssertGreaterThan(editor.height,340)
                if let console {XCTAssertFalse(console.intersects(editor))}
            }
        }
    }
}
