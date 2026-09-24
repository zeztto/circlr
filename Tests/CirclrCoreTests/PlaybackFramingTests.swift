import XCTest
@testable import CirclrCore

final class PlaybackFramingTests:XCTestCase {
    func testDemoSongFitAvoidsConsoleWithoutShrinkingBelowTopBand() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project=try JSONDecoder().decode(Project.self,from:Data(contentsOf:root.appendingPathComponent("Resources/Demos/f0r-h3r.circlr/manifest.json")))
        let scene=try HierarchySceneBuilder.build(project)
        let song=try XCTUnwrap(scene.nodes.first{$0.role == .song})
        let viewport=CanvasWorkspaceGeometry.viewport(width:1440,height:900)
        let console=CGRect(x:20,y:704,width:820,height:180)
        let upper=CanvasWorkspaceGeometry.viewport(width:1440,height:900,console:console)
        let old=try XCTUnwrap(PlaybackFraming.camera(for:song,in:scene,viewport:upper))
        let new=try XCTUnwrap(PlaybackFraming.camera(for:song,in:scene,viewport:viewport,avoiding:console))
        XCTAssertGreaterThanOrEqual(new.zoom+1e-8,old.zoom)
        for circle in CanvasWorkspaceGeometry.contextCircles(song.id,in:scene) {
            let p=new.screen(Point(circle.center.x,circle.center.y)),r=circle.radius*new.zoom
            let rect=CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)
            XCTAssertFalse(rect.intersects(console.insetBy(dx:-13.99,dy:-13.99)))
        }
    }
    func testActualDemoSoundOrbitRevealsItsFullNearbySignalChain()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project=try JSONDecoder().decode(Project.self,from:Data(contentsOf:root.appendingPathComponent("Resources/Demos/f0r-h3r.circlr/manifest.json")))
        let scene=try HierarchySceneBuilder.build(project),sound=try XCTUnwrap(scene.node(.sound))
        let children=scene.immediateSatellites(of:.sound)
        XCTAssertEqual(children.count,18)
        let viewport=CanvasWorkspaceGeometry.viewport(width:1659,height:1387)
        let usable=viewport.insetBy(dx:20,dy:20)
        let zoom=0.52
        let current=HierarchyCamera(pan:Point(viewport.midX-sound.center.x*zoom,
                                               900-sound.center.y*zoom),zoom:zoom)
        let orbitCenter=current.screen(sound.center),orbitRadius=sound.outerRadius*zoom
        XCTAssertTrue(usable.contains(CGRect(x:orbitCenter.x-orbitRadius,y:orbitCenter.y-orbitRadius,
                                             width:orbitRadius*2,height:orbitRadius*2)))
        XCTAssertTrue(children.contains { child in
            current.screen(child.center).y+child.outerRadius*zoom>usable.maxY
        })
        let target=try XCTUnwrap(current.revealing(sound,including:children,in:viewport))
        XCTAssertLessThanOrEqual(target.zoom,current.zoom)
        for node in [sound]+children {
            let center=target.screen(node.center),radius=node.outerRadius*target.zoom
            XCTAssertGreaterThanOrEqual(center.x-radius,usable.minX-1e-8,node.title)
            XCTAssertLessThanOrEqual(center.x+radius,usable.maxX+1e-8,node.title)
            XCTAssertGreaterThanOrEqual(center.y-radius,usable.minY-1e-8,node.title)
            XCTAssertLessThanOrEqual(center.y+radius,usable.maxY+1e-8,node.title)
        }
        var remote=try XCTUnwrap(children.first)
        remote.id = .signal("manually-remote")
        remote.center=Point(sound.center.x,sound.center.y+12_000)
        XCTAssertEqual(current.revealing(sound,including:children+[remote],in:viewport),target)
    }
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
    func testFollowFitKeepsSectionCirclesOutOfConsoleAtWideAndPortraitWidths() throws {
        let (scene,section)=try fixture()
        let circles=CanvasWorkspaceGeometry.contextCircles(section.id,in:scene)
        XCTAssertFalse(circles.isEmpty)
        for width in [700.0,1440.0] {
            for consoleHeight in [40.0,180.0] {
                let viewport=CanvasWorkspaceGeometry.viewport(width:width,height:900)
                let console=CGRect(x:20,y:900-consoleHeight-16,
                                   width:min(820,width-40),height:consoleHeight)
                let camera=try XCTUnwrap(PlaybackFraming.camera(for:section,in:scene,
                    viewport:viewport,avoiding:console))
                let follow=try XCTUnwrap(PlaybackFollowResolver.camera(for:section.id,
                    settings:PlaybackFollowSettings(target:.section),current:HierarchyCamera(),
                    scene:scene,viewport:viewport,avoiding:console))
                XCTAssertEqual(camera,follow)
                for circle in circles {
                    let p=camera.screen(Point(circle.center.x,circle.center.y)),r=circle.radius*camera.zoom
                    let frame=CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)
                    XCTAssertTrue(viewport.insetBy(dx:0.01,dy:0.01).contains(frame))
                    XCTAssertFalse(frame.intersects(console.insetBy(dx:-13.99,dy:-13.99)))
                }
            }
        }
    }
    func testKeepZoomPreservesScaleWhenSafeAndFallsBackWhenConsoleBlocksIt() throws {
        let (scene,section)=try fixture()
        let viewport=CanvasWorkspaceGeometry.viewport(width:1440,height:900)
        let console=CGRect(x:20,y:704,width:820,height:180)
        let settings=PlaybackFollowSettings(target:.section,framing:.keepZoom)
        let fit=try XCTUnwrap(PlaybackFraming.camera(for:section,in:scene,viewport:viewport,
            avoiding:console))
        let safe=try XCTUnwrap(PlaybackFollowResolver.camera(for:section.id,settings:settings,
            current:HierarchyCamera(zoom:fit.zoom*0.8),scene:scene,viewport:viewport,avoiding:console))
        XCTAssertEqual(safe.zoom,fit.zoom*0.8,accuracy:1e-8)
        let reduced=try XCTUnwrap(PlaybackFollowResolver.camera(for:section.id,settings:settings,
            current:HierarchyCamera(zoom:fit.zoom*1.8),scene:scene,viewport:viewport,avoiding:console))
        XCTAssertLessThan(reduced.zoom,fit.zoom*1.8)
        XCTAssertEqual(reduced.zoom,fit.zoom,accuracy:1e-6)
        for camera in [safe,reduced] {
            for circle in CanvasWorkspaceGeometry.contextCircles(section.id,in:scene) {
                let p=camera.screen(Point(circle.center.x,circle.center.y)),r=circle.radius*camera.zoom
                let frame=CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)
                XCTAssertTrue(viewport.insetBy(dx:0.01,dy:0.01).contains(frame))
                XCTAssertFalse(frame.intersects(console.insetBy(dx:-13.99,dy:-13.99)))
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
    func testKeyboardSelectionIncludesPartlyVisibleSatelliteBelowOrbit()throws {
        let (_,fixture)=try fixture()
        var orbit=fixture;orbit.center=Point(500,330);orbit.radius=100;orbit.scale=1;orbit.repeatCount=1
        var satellite=fixture;satellite.id = .signal("visible-satellite")
        satellite.parent=orbit.id;satellite.center=Point(500,550)
        satellite.radius=45;satellite.scale=1;satellite.repeatCount=1
        var remote=satellite;remote.id = .signal("remote-satellite");remote.center=Point(500,5000)
        let viewport=CGRect(x:24,y:78,width:976,height:498),current=HierarchyCamera()
        XCTAssertNil(current.revealing(orbit,in:viewport))
        XCTAssertNil(current.revealing(orbit,including:[remote],in:viewport))
        let target=try XCTUnwrap(current.revealing(orbit,including:[satellite,remote],in:viewport))
        let usable=viewport.insetBy(dx:20,dy:20)
        XCTAssertEqual(target.zoom,current.zoom)
        XCTAssertEqual(target.pan.x,0)
        XCTAssertLessThan(target.pan.y,0)
        for node in [orbit,satellite] {
            let center=target.screen(node.center),radius=node.outerRadius*target.zoom
            XCTAssertTrue(usable.contains(CGRect(x:center.x-radius,y:center.y-radius,
                                                width:radius*2,height:radius*2)))
        }
        XCTAssertNil(target.revealing(orbit,including:[satellite],in:viewport))
    }
    func testKeyboardSelectionFitsOrbitAndVisibleSatelliteWithoutZoomingIn()throws {
        let (_,fixture)=try fixture()
        var orbit=fixture;orbit.center=Point(500,300);orbit.radius=190;orbit.scale=1;orbit.repeatCount=1
        var satellite=fixture;satellite.id = .signal("lower-satellite")
        satellite.parent=orbit.id;satellite.center=Point(500,545)
        satellite.radius=90;satellite.scale=1;satellite.repeatCount=1
        let viewport=CGRect(x:24,y:78,width:976,height:498),current=HierarchyCamera()
        let target=try XCTUnwrap(current.revealing(orbit,including:[satellite],in:viewport))
        XCTAssertLessThan(target.zoom,current.zoom)
        let usable=viewport.insetBy(dx:20,dy:20)
        for node in [orbit,satellite] {
            let center=target.screen(node.center),radius=node.outerRadius*target.zoom
            XCTAssertGreaterThanOrEqual(center.y-radius,usable.minY-1e-8)
            XCTAssertLessThanOrEqual(center.y+radius,usable.maxY+1e-8)
        }
        XCTAssertNil(target.revealing(orbit,including:[satellite],in:viewport))
    }
    func testOffscreenOrbitRevealsSatelliteVisibleAfterInitialPan()throws {
        let (_,fixture)=try fixture()
        var orbit=fixture;orbit.center=Point(1200,800);orbit.radius=100;orbit.scale=1;orbit.repeatCount=1
        var satellite=fixture;satellite.id = .signal("following-satellite")
        satellite.parent=orbit.id;satellite.center=Point(1200,920)
        satellite.radius=45;satellite.scale=1;satellite.repeatCount=1
        let viewport=CGRect(x:24,y:78,width:976,height:498),current=HierarchyCamera()
        let orbitOnly=try XCTUnwrap(current.revealing(orbit,in:viewport))
        let onlyCenter=orbitOnly.screen(satellite.center)
        XCTAssertGreaterThan(onlyCenter.y+satellite.outerRadius*orbitOnly.zoom,
                             viewport.insetBy(dx:20,dy:20).maxY)
        let target=try XCTUnwrap(current.revealing(orbit,including:[satellite],in:viewport))
        let usable=viewport.insetBy(dx:20,dy:20)
        for node in [orbit,satellite] {
            let center=target.screen(node.center),radius=node.outerRadius*target.zoom
            XCTAssertTrue(usable.contains(CGRect(x:center.x-radius,y:center.y-radius,
                                                width:radius*2,height:radius*2)))
        }
    }
    func testImmediateSatellitesExpandVisualGroupsOnly()throws {
        let (_,fixture)=try fixture()
        var orbit=fixture;orbit.childCount=2
        var expanded=fixture;expanded.id = .group(parent:orbit.id,id:"expanded")
        expanded.parent=orbit.id;expanded.role = .group;expanded.childCount=1
        var child=fixture;child.id = .signal("group-member");child.parent=expanded.id
        var collapsed=fixture;collapsed.id = .group(parent:orbit.id,id:"collapsed")
        collapsed.parent=orbit.id;collapsed.role = .group;collapsed.childCount=0
        let scene=HierarchyScene(nodes:[orbit,expanded,child,collapsed],edges:[],isOrbit:true)
        XCTAssertEqual(Set(scene.immediateSatellites(of:orbit.id).map(\.id)),Set([child.id,collapsed.id]))
    }
    func testCollapsedProjectGroupIsOneVisibleSatelliteWithoutHiddenMembers()throws {
        let helper=HierarchyEditingTests()
        var project=try helper.fixture();project.circleLayout = .orbit
        let members=helper.addresses(project)
        let address=try HierarchyEditing.group(members,name:"접힘 테스트",in:&project)
        guard case .group(let parent,let id)=address else {return XCTFail("그룹 주소가 아닙니다")}
        let expanded=try HierarchySceneBuilder.build(project)
        XCTAssertTrue(members.isSubset(of:Set(expanded.immediateSatellites(of:parent).map(\.id))))
        try HierarchyEditing.editLayout(parent,in:&project) { layout in
            guard let index=layout.groups.firstIndex(where:{$0.id == id}) else {return}
            layout.groups[index].collapsed=true
        }
        let collapsed=try HierarchySceneBuilder.build(project)
        let group=try XCTUnwrap(collapsed.node(address))
        XCTAssertEqual(group.childCount,0)
        XCTAssertTrue(collapsed.children(of:address).isEmpty)
        XCTAssertTrue(collapsed.immediateSatellites(of:parent).contains(where:{$0.id == address}))
        XCTAssertTrue(members.isDisjoint(with:Set(collapsed.immediateSatellites(of:parent).map(\.id))))
    }
}
