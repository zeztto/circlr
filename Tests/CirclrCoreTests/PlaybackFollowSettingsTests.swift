import XCTest
@testable import CirclrCore

final class PlaybackFollowSettingsTests: XCTestCase {
    func fixture() throws -> (HierarchyScene, CircleAddress, CircleAddress) {
        var project=Project();_=project.addTrack(name:"Synth")
        let first=project.addSection(name:"Verse",at:Point(),bars:4)
        let second=project.addSection(name:"Chorus",at:Point(400,0),bars:4)
        project.enableAlbum();project=try SectionGraphMigration.migrate(project)
        return (try HierarchySceneBuilder.build(project),.section(arrangementID:project.active.id,useID:first),.section(arrangementID:project.active.id,useID:second))
    }
    func testDefaultsAndCodablePin() throws {
        let defaults=PlaybackFollowSettings()
        XCTAssertEqual(defaults.target,.section);XCTAssertEqual(defaults.framing,.fit);XCTAssertEqual(defaults.transition,.subtle)
        let setting=PlaybackFollowSettings(target:.pinned,framing:.keepZoom,transition:.emphasized,pinned:.group(parent:.section(arrangementID:"a",useID:"u"),id:"g"))
        XCTAssertEqual(try JSONDecoder().decode(PlaybackFollowSettings.self,from:JSONEncoder().encode(setting)),setting)
    }
    func testCurrentUseAndSongResolution() throws {
        let (scene,first,second)=try fixture()
        XCTAssertEqual(PlaybackFollowResolver.resolve(.init(),currentSection:second,activeCircles:[],in:scene),.target(second))
        let song=try XCTUnwrap(scene.path(to:first).last(where:{$0.role == .song}))
        for section in [first,second] {
            XCTAssertEqual(PlaybackFollowResolver.resolve(.init(target:.song),currentSection:section,activeCircles:[],in:scene),.target(song.id))
        }
        XCTAssertEqual(PlaybackFollowResolver.resolve(.init(),currentSection:nil,activeCircles:[],in:scene),.inactive)
    }
    func testPinnedMissingInactiveAndParticipatingAreDistinct() throws {
        let (scene,first,second)=try fixture()
        let node=try XCTUnwrap(scene.children(of:first).first)
        let pin=PlaybackFollowSettings(target:.pinned,pinned:node.id)
        XCTAssertEqual(PlaybackFollowResolver.resolve(pin,currentSection:second,activeCircles:[],in:scene),.inactive)
        XCTAssertEqual(PlaybackFollowResolver.resolve(pin,currentSection:second,activeCircles:[node.id],in:scene),.target(node.id))
        XCTAssertEqual(PlaybackFollowResolver.resolve(.init(target:.pinned,pinned:first),currentSection:first,activeCircles:[node.id],in:scene),.target(first))
        XCTAssertEqual(PlaybackFollowResolver.resolve(.init(target:.pinned,pinned:.signal("deleted")),currentSection:first,activeCircles:[node.id],in:scene),.missingPinnedTarget)
        XCTAssertEqual(PlaybackFollowResolver.resolve(.init(target:.pinned),currentSection:first,activeCircles:[],in:scene),.missingPinnedTarget)
    }
    func testKeepZoomUsesStableContentCenterAndRejectsInvalidZoom() throws {
        let (scene,section,_)=try fixture(),viewport=CGRect(x:10,y:30,width:1100,height:700)
        let fitted=try XCTUnwrap(PlaybackFollowResolver.camera(for:section,settings:.init(),current:.init(),scene:scene,viewport:viewport))
        let keep=try XCTUnwrap(PlaybackFollowResolver.camera(for:section,settings:.init(framing:.keepZoom),current:.init(zoom:0.75),scene:scene,viewport:viewport))
        XCTAssertEqual(keep.zoom,0.75)
        XCTAssertEqual((viewport.midX-keep.pan.x)/keep.zoom,(viewport.midX-fitted.pan.x)/fitted.zoom,accuracy:1e-8)
        XCTAssertNil(PlaybackFollowResolver.camera(for:section,settings:.init(framing:.keepZoom),current:.init(zoom:.nan),scene:scene,viewport:viewport))
    }
    func testTransitionEndpointsBoundsAndFrameRateIndependence() {
        let a=HierarchyCamera(pan:Point(20,40),zoom:2),b=HierarchyCamera(pan:Point(-100000,500),zoom:4)
        let curve=PlaybackFollowCameraCurve(start:a,destination:b,viewport:CGRect(x:0,y:0,width:1000,height:700),transition:.emphasized,changesSection:true)
        XCTAssertEqual(curve.camera(at:0),a);XCTAssertEqual(curve.camera(at:100),b)
        XCTAssertEqual(curve.camera(at:curve.duration/2).zoom,1.6,accuracy:1e-8)
        for step in 0...1000 {let value=curve.camera(at:Double(step)*curve.duration/1000);XCTAssertGreaterThanOrEqual(value.zoom,1.6-1e-8);XCTAssertLessThanOrEqual(value.zoom,4+1e-8)}
        XCTAssertEqual(curve.camera(at:0.3),curve.camera(at:9.0/30))
        XCTAssertEqual(curve.camera(at:.nan),a)
        // Interrupt/re-target from the visible frame: no stale starting-camera jump.
        let visible=curve.camera(at:0.25)
        let next=PlaybackFollowCameraCurve(start:visible,destination:a,viewport:.zero,transition:.subtle,changesSection:true)
        XCTAssertEqual(next.camera(at:0),visible)
    }
    func testNoExcursionForLoopOtherTargetsOffShortSectionsAndReducedMotion() {
        let a=HierarchyCamera(zoom:2),b=HierarchyCamera(pan:Point(100,200),zoom:2),viewport=CGRect(x:0,y:0,width:1000,height:700)
        for (mode,changed,remaining) in [(PlaybackFollowTransition.off,true,nil),(.subtle,false,nil),(.emphasized,true,0.2)] as [(PlaybackFollowTransition,Bool,Double?)] {
            let curve=PlaybackFollowCameraCurve(start:a,destination:b,viewport:viewport,transition:mode,changesSection:changed,remainingSectionSeconds:remaining)
            XCTAssertEqual(curve.camera(at:curve.duration/2).zoom,2,accuracy:1e-8)
        }
        let reduced=PlaybackFollowCameraCurve(start:a,destination:b,viewport:viewport,transition:.emphasized,changesSection:true,reduceMotion:true)
        XCTAssertEqual(reduced.duration,0);XCTAssertEqual(reduced.camera(at:0),b)
        let same=PlaybackFollowCameraCurve(start:a,destination:a,viewport:viewport,transition:.emphasized,changesSection:true)
        XCTAssertEqual(same.duration,0)
    }
}
