import XCTest
@testable import CirclrCore

final class PlaybackFramingTests:XCTestCase {
    func fixture()throws->(HierarchyScene,CircleSceneNode) {
        var p=Project();p.circleLayout = .freeform
        _=p.addTrack(name:"신스");_=p.addTrack(name:"드럼");let use=p.addSection(name:"후렴",at:Point(),bars:8)
        p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        for (i,node) in graph.nodes.filter({if case .rhythmMIDI=$0.content{return false};if case .rhythmAudio=$0.content{return false};return true}).enumerated() {
            graph.layout.positions[node.id]=Point(Double(i%4)*240-360,Double(i/4)*240-120)
        }
        try SectionGraphEditing.set(graph,useID:use,original:false,in:&p)
        let scene=try HierarchySceneBuilder.build(p)
        return (scene,try XCTUnwrap(scene.node(.section(arrangementID:p.active.id,useID:use))))
    }
    func testContentsUseAvailableCanvasAcrossWindowAndConsoleSizes()throws {
        let (scene,section)=try fixture()
        for size in [CGSize(width:1440,height:801),CGSize(width:1024,height:641)] {
            for console in [nil,CGRect(x:20,y:size.height-220,width:700,height:202)] as [CGRect?] {
                let viewport=CanvasWorkspaceGeometry.viewport(width:size.width,height:size.height,console:console)
                let camera=try XCTUnwrap(PlaybackFraming.camera(for:section,in:scene,viewport:viewport))
                let old=HierarchyCamera().focused(on:section,width:size.width,height:viewport.height)
                XCTAssertGreaterThan(camera.zoom,old.zoom*1.4)
                for node in scene.children(of:section.id) {
                    let center=camera.screen(node.center),r=node.outerRadius*camera.zoom
                    let rect=CGRect(x:center.x-r,y:center.y-r,width:2*r,height:2*r)
                    XCTAssertTrue(viewport.contains(rect));XCTAssertGreaterThan(r,25)
                    if let console {XCTAssertFalse(console.intersects(rect))}
                }
            }
        }
    }
    func testSectionRepeatRingsDoNotShrinkItsEditableContents()throws {
        let (scene,section)=try fixture();var repeated=section;repeated.repeatCount=256
        let viewport=CGRect(x:24,y:78,width:1392,height:498)
        XCTAssertEqual(PlaybackFraming.camera(for:section,in:scene,viewport:viewport),PlaybackFraming.camera(for:repeated,in:scene,viewport:viewport))
    }
    func testEmptySectionFitsItsOwnOrbitAndInvalidViewportIsRejected()throws {
        let (_,section)=try fixture(),scene=HierarchyScene(nodes:[section],edges:[])
        let viewport=CGRect(x:24,y:78,width:976,height:420)
        let camera=try XCTUnwrap(PlaybackFraming.camera(for:section,in:scene,viewport:viewport))
        let center=camera.screen(section.center),r=section.outerRadius*camera.zoom
        XCTAssertTrue(viewport.contains(CGRect(x:center.x-r,y:center.y-r,width:r*2,height:r*2)))
        XCTAssertNil(PlaybackFraming.camera(for:section,in:scene,viewport:.zero))
        XCTAssertNil(PlaybackFraming.camera(for:section,in:scene,viewport:CGRect(x:0,y:0,width:Double.infinity,height:100)))
    }
    func testDenseLabelsAvoidOtherCirclesAndKeepSelectedLabel() {
        let circles=(0..<12).map{CanvasLabelCircle(id:.signal("\($0)"),center:CGPoint(x:220+Double($0%4)*90,y:160+Double($0/4)*90),radius:28)}
        let requests=circles.enumerated().map{i,c in CanvasLabelRequest(id:c.id,anchor:c.center,size:CGSize(width:110,height:30),radius:c.radius,priority:i==11 ? 100:0)}
        let viewport=CGRect(x:24,y:78,width:976,height:498)
        let placements=CanvasLabelLayout.place(requests,within:viewport,circles:circles)
        XCTAssertEqual(placements.first?.id,.signal("11"));XCTAssertGreaterThan(placements.count,6)
        for (i,label) in placements.enumerated() {
            XCTAssertTrue(viewport.contains(label.rect))
            for other in placements.dropFirst(i+1) {XCTAssertFalse(label.rect.intersects(other.rect))}
            for circle in circles where circle.id != label.id {XCTAssertFalse(circle.intersects(label.rect))}
        }
        XCTAssertEqual(placements.map(\.rect),CanvasLabelLayout.place(requests,within:viewport,circles:circles).map(\.rect))
    }
    func testCircleClearanceUsesTheDiskRatherThanItsBoundingSquare() {
        let circle=CanvasLabelCircle(id:.signal("x"),center:CGPoint(x:100,y:100),radius:40)
        XCTAssertFalse(circle.intersects(CGRect(x:136,y:136,width:20,height:20)))
        XCTAssertTrue(circle.intersects(CGRect(x:130,y:100,width:20,height:20)))
    }
    func testKeyboardSelectionRevealsOrbitEdgeWithOnlyNecessaryPan()throws {
        let (_,fixture)=try fixture()
        var node=fixture;node.center=Point(950,250);node.radius=80;node.scale=1
        let viewport=CGRect(x:24,y:78,width:976,height:498)
        let current=HierarchyCamera()
        let target=try XCTUnwrap(current.revealing(node,in:viewport))
        let center=target.screen(node.center),radius=node.outerRadius*target.zoom
        XCTAssertEqual(target.zoom,1)
        XCTAssertTrue(viewport.insetBy(dx:20,dy:20).contains(
            CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)))
        XCTAssertEqual(target.pan.y,0)
        XCTAssertNil(target.revealing(node,in:viewport))
    }
    func testKeyboardSelectionFitsLargeOrbitAboveConsole()throws {
        let (_,fixture)=try fixture()
        var node=fixture;node.center=Point(1200,1100);node.radius=700;node.scale=1
        let viewport=CanvasWorkspaceGeometry.viewport(width:1024,height:700,
            console:CGRect(x:20,y:440,width:600,height:220))
        let target=try XCTUnwrap(HierarchyCamera().revealing(node,in:viewport))
        let center=target.screen(node.center),radius=node.outerRadius*target.zoom
        XCTAssertLessThan(target.zoom,1)
        XCTAssertTrue(viewport.insetBy(dx:20,dy:20).contains(
            CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)))
        XCTAssertNil(HierarchyCamera().revealing(node,in:.zero))
    }
}
