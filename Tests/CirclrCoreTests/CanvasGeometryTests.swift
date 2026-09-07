import XCTest
@testable import CirclrCore

final class CanvasGeometryTests: XCTestCase {
    func testZoomKeepsPointUnderCursor() {
        let camera = CanvasCamera(pan:Point(-319,87),zoom:0.73), cursor = Point(612,349)
        let before = camera.world(cursor), after = camera.zoomed(to:2.5,around:cursor).world(cursor)
        XCTAssertEqual(before.x,after.x,accuracy:1e-9); XCTAssertEqual(before.y,after.y,accuracy:1e-9)
    }
    func testPlainWheelDirectionsAndNaturalScrollNormalization() {
        let c=CanvasCamera(pan:Point(130,-45),zoom:1),cursor=Point(417,259)
        let up=c.wheelZoom(deltaY:3,precise:false,inverted:false,around:cursor)
        let down=c.wheelZoom(deltaY:-3,precise:false,inverted:false,around:cursor)
        XCTAssertGreaterThan(up.zoom,c.zoom);XCTAssertLessThan(down.zoom,c.zoom)
        XCTAssertEqual(c.wheelZoom(deltaY:-3,precise:false,inverted:true,around:cursor),up)
        XCTAssertEqual(up.world(cursor).x,c.world(cursor).x,accuracy:1e-9)
        XCTAssertEqual(up.world(cursor).y,c.world(cursor).y,accuracy:1e-9)
        XCTAssertEqual(up.wheelZoom(deltaY:-3,precise:false,inverted:false,around:cursor).zoom,1,accuracy:1e-9)
        let precise=c.wheelZoom(deltaY:3,precise:true,inverted:true,around:cursor)
        XCTAssertGreaterThan(precise.zoom,1);XCTAssertLessThan(precise.zoom,up.zoom)
    }
    func testWheelLimitsCannotOverflowOrCrossZoomBounds() {
        let c=CanvasCamera(),cursor=Point(30,80)
        XCTAssertEqual(c.wheelZoom(deltaY:.nan,precise:false,inverted:false,around:cursor),c)
        var large=c,small=c
        for _ in 0..<200 {
            large=large.wheelZoom(deltaY:1e12,precise:false,inverted:false,around:cursor)
            small=small.wheelZoom(deltaY:-1e12,precise:true,inverted:false,around:cursor)
        }
        XCTAssertEqual(large.zoom,2.5);XCTAssertEqual(small.zoom,0.25)
        XCTAssertEqual(large.world(cursor).x,c.world(cursor).x,accuracy:1e-9)
        XCTAssertEqual(small.world(cursor).y,c.world(cursor).y,accuracy:1e-9)
    }
    func testGroupDropPreservesRelativeSpacing() {
        let a = Point(11,29), b = Point(239,52), delta = Point(37.5,-8.1)
        let drop = CanvasCamera.droppedDelta(delta,anchor:a,spacing:24,snap:true)
        XCTAssertEqual(a.x+drop.x,48); XCTAssertEqual(a.y+drop.y,24)
        XCTAssertEqual((b.x+drop.x)-(a.x+drop.x),b.x-a.x)
        XCTAssertEqual((b.y+drop.y)-(a.y+drop.y),b.y-a.y)
        XCTAssertEqual(CanvasCamera.droppedDelta(delta,anchor:a,spacing:24,snap:false),delta)
    }
    func testFitCentersContentAndKeepsCircleMargins() {
        let c = CanvasCamera.fitting(points:[Point(-700,-200),Point(800,400)],width:1000,height:700)!
        XCTAssertEqual(c.screen(Point(50,100)),Point(500,350))
        XCTAssertGreaterThan(c.screen(Point(-810,-310)).x,-0.0001)
        XCTAssertLessThan(c.screen(Point(910,510)).x,1000.0001)
    }
    func testFocusReturnCameraIsExactAndAnimationCannotOvershoot() {
        let overview = CanvasCamera(pan:Point(171,-39),zoom:0.82), focus = CanvasCamera(pan:Point(-500,200),zoom:1.1)
        XCTAssertEqual(overview.interpolated(to:focus,progress:0),overview)
        XCTAssertEqual(focus.interpolated(to:overview,progress:1),overview)
        for i in 0...100 { let c = overview.interpolated(to:focus,progress:Double(i)/100); XCTAssertTrue((-500...171).contains(c.pan.x)); XCTAssertTrue((0.82...1.1).contains(c.zoom)) }
    }
}
