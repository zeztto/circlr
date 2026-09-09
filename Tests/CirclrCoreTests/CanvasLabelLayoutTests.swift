import XCTest
@testable import CirclrCore

final class CanvasLabelLayoutTests:XCTestCase {
    let viewport=CGRect(x:24,y:78,width:400,height:240)

    func request(_ anchor:CGPoint,adjust:Bool=true)->CanvasLabelRequest {
        CanvasLabelRequest(id:.signal("selected"),anchor:anchor,size:CGSize(width:400,height:84),radius:30,priority:100,allowsViewportAdjustment:adjust)
    }
    func testPrimaryLabelCanMoveInsideEachViewportCorner() {
        for anchor in [CGPoint(x:30,y:84),CGPoint(x:418,y:84),CGPoint(x:30,y:312),CGPoint(x:418,y:312)] {
            XCTAssertTrue(CanvasLabelLayout.place([request(anchor,adjust:false)],within:viewport).isEmpty)
            let placed=CanvasLabelLayout.place([request(anchor)],within:viewport)
            XCTAssertEqual(placed.count,1)
            XCTAssertTrue(viewport.contains(placed[0].rect))
            XCTAssertEqual(placed[0].rect.size,CGSize(width:400,height:84))
            XCTAssertEqual(placed[0].anchor,anchor)
        }
    }
    func testNormalCandidateWinsBeforeAnyViewportAdjustment() {
        var value=request(CGPoint(x:220,y:190));value.size=CGSize(width:150,height:48);value.radius=80
        let adjusted=CanvasLabelLayout.place([value],within:viewport)
        value.allowsViewportAdjustment=false
        XCTAssertEqual(adjusted.map(\.rect),CanvasLabelLayout.place([value],within:viewport).map(\.rect))
        XCTAssertEqual(adjusted.first?.rect.midX,220)
        XCTAssertEqual(adjusted.first?.rect.midY,190)
    }
    func testAdjustedLabelStillAvoidsToolsTimeHandlesAndOtherCircles() {
        let value=request(CGPoint(x:30,y:84)),tools=CGRect(x:24,y:78,width:400,height:40)
        let time=CGRect(x:270,y:280,width:36,height:36)
        let other=CanvasLabelCircle(id:.signal("other"),center:CGPoint(x:280,y:100),radius:20)
        let placed=CanvasLabelLayout.place([value],within:viewport,avoiding:[tools,time],circles:[other])
        XCTAssertEqual(placed.count,1)
        for label in placed {
            XCTAssertFalse(tools.intersects(label.rect));XCTAssertFalse(time.intersects(label.rect))
            XCTAssertFalse(other.intersects(label.rect));XCTAssertTrue(viewport.contains(label.rect))
        }
        XCTAssertTrue(CanvasLabelLayout.place([value],within:viewport,avoiding:[viewport]).isEmpty)
        let covering=CanvasLabelCircle(id:.signal("other"),center:CGPoint(x:220,y:190),radius:500)
        XCTAssertTrue(CanvasLabelLayout.place([value],within:viewport,circles:[covering]).isEmpty)
    }
    func testOffscreenCenterRetainsLabelOnlyWhileItsCircleTouchesViewport() {
        XCTAssertEqual(CanvasLabelLayout.place([request(CGPoint(x:8,y:84))],within:viewport).count,1)
        XCTAssertTrue(CanvasLabelLayout.place([request(CGPoint(x:-400,y:84))],within:viewport).isEmpty)
    }
    func testOversizeLabelIsOmittedWithoutShrinkingOrCoveringControls() {
        var value=request(CGPoint(x:30,y:84));value.size.width=401
        XCTAssertTrue(CanvasLabelLayout.place([value],within:viewport).isEmpty)
        value.size=CGSize(width:200,height:241)
        XCTAssertTrue(CanvasLabelLayout.place([value],within:viewport).isEmpty)
    }
    func testSelectedPriorityAndStableOrderStillAvoidEveryOtherLabel() {
        let primary=request(CGPoint(x:30,y:84))
        let neighbors:[CanvasLabelRequest]=(0..<8).map{index in
            let anchor=CGPoint(x:Double(70+(index%4)*80),y:Double(190+(index/4)*80))
            return CanvasLabelRequest(id:.signal("\(index)"),anchor:anchor,size:CGSize(width:70,height:32),radius:20)
        }
        let requests=neighbors+[primary],placed=CanvasLabelLayout.place(requests,within:viewport)
        XCTAssertEqual(placed.first?.id,primary.id);XCTAssertGreaterThan(placed.count,3)
        for (index,label) in placed.enumerated() {
            XCTAssertTrue(viewport.contains(label.rect))
            for other in placed.dropFirst(index+1) {XCTAssertFalse(label.rect.intersects(other.rect))}
        }
        XCTAssertEqual(placed.map(\.id),CanvasLabelLayout.place(requests,within:viewport).map(\.id))
        XCTAssertEqual(placed.map(\.rect),CanvasLabelLayout.place(requests,within:viewport).map(\.rect))
    }
    func testNonFiniteGeometryDoesNotEscapeIntoPlacements() {
        let value=request(CGPoint(x:30,y:84))
        for invalid in [CGRect.zero,CGRect(x:0,y:0,width:Double.infinity,height:200),CGRect(x:Double.nan,y:0,width:400,height:200)] {
            XCTAssertTrue(CanvasLabelLayout.place([value],within:invalid).isEmpty)
        }
        var invalid=value;invalid.radius = .infinity
        XCTAssertTrue(CanvasLabelLayout.place([invalid],within:viewport).isEmpty)
        invalid=value;invalid.anchor.x = .nan
        XCTAssertTrue(CanvasLabelLayout.place([invalid],within:viewport).isEmpty)
    }
    func testDenseNativeSectionCanUseFreePerimeterWithoutMovingCircles() {
        let viewport=CGRect(x:24,y:78,width:976,height:370.5)
        let points=[CGPoint(x:269.9167,y:360.0833),CGPoint(x:274.7583,y:263.25),CGPoint(x:618.5167,y:166.4167),
                    CGPoint(x:618.5167,y:360.0833),CGPoint(x:537.525,y:360.0833),CGPoint(x:642.725,y:263.25),
                    CGPoint(x:754.0833,y:156.7333),CGPoint(x:754.0833,y:263.25),CGPoint(x:754.0833,y:369.7667)]
        var circles=points.enumerated().map{CanvasLabelCircle(id:.signal("\($0.offset)"),center:$0.element,radius:38.7333)}
        circles.append(CanvasLabelCircle(id:.signal("group"),center:CGPoint(x:357.0667,y:214.8333),radius:48.4167))
        let selected=CanvasLabelRequest(id:.signal("selected"),anchor:CGPoint(x:405.4833,y:360.0833),size:CGSize(width:320,height:84),radius:38.7333,priority:100,allowsViewportAdjustment:true)
        let placed=CanvasLabelLayout.place([selected],within:viewport,circles:circles)
        XCTAssertEqual(placed.count,1)
        XCTAssertTrue(viewport.contains(placed[0].rect))
        for circle in circles {XCTAssertFalse(circle.intersects(placed[0].rect))}
    }
}
