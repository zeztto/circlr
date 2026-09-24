import XCTest
@testable import CirclrCore

final class CanvasLabelLayoutTests:XCTestCase {
    let viewport=CGRect(x:24,y:78,width:400,height:240)

    func testNavigationObstacleAvoidsControlWithoutTruncatingCanvas() throws {
        let console=CGRect(x:24,y:519.5,width:675,height:122)
        let navigation=CGRect(x:543,y:475,width:164,height:36).insetBy(dx:-8,dy:-8)
        let viewport=CanvasWorkspaceGeometry.viewport(width:723,height:751,console:console)
        XCTAssertEqual(viewport.maxY,505.5)
        let center=CGPoint(x:507.312,y:102.203)
        let label=CanvasLabelRequest(id:.signal("06"),anchor:center,
            size:CGSize(width:192,height:36),radius:44.286,allowsViewportAdjustment:true,avoidsOwnRing:true)
        let placement=try XCTUnwrap(CanvasLabelLayout.place([label],within:viewport,avoiding:[navigation]).first)
        XCTAssertFalse(placement.rect.intersects(navigation))
        XCTAssertFalse(CanvasLabelLayout.obscuresRing(placement.rect,center:center,radius:44.286))
    }
    func testPortraitSongSectionsKeepEightLabelsAroundNavigation() {
        // Screen-space geometry from the 720x900 f0r h3r native failure.
        let anchors:[CGPoint]=[
            .init(x:361.5,y:291.75),.init(x:361.5,y:163.3214),.init(x:472.7224,y:227.5357),
            .init(x:472.7224,y:355.9643),.init(x:239.0207,y:253.1142),.init(x:297.2857,y:402.9724),
            .init(x:507.3122,y:102.2029),.init(x:598.5587,y:323.2535)
        ]
        let widths:[Double]=[80,132,168,115,185,183,192,140]
        let viewport=CGRect(x:24,y:78,width:672,height:427.5)
        let navigation=CGRect(x:543,y:475,width:164,height:36).insetBy(dx:-8,dy:-8)
        let requests=anchors.enumerated().map { index,center in
            CanvasLabelRequest(id:.signal("\(index)"),anchor:center,
                size:CGSize(width:widths[index],height:index==0 ? 54:36),
                radius:index==0 ? 62:44.286,expanded:index==0,priority:index==0 ? 100:70,
                allowsViewportAdjustment:true,avoidsOwnRing:true)
        }
        let circles=requests.map{CanvasLabelCircle(id:$0.id,center:$0.anchor,radius:$0.radius)}
        let labels=CanvasLabelLayout.place(requests,within:viewport,avoiding:[navigation],circles:circles)
        XCTAssertEqual(labels.count,8)
        for label in labels {
            XCTAssertFalse(label.rect.intersects(navigation))
            let circle=circles.first{$0.id==label.id}!
            XCTAssertFalse(CanvasLabelLayout.obscuresRing(label.rect,center:circle.center,radius:circle.radius))
        }
        var compact=requests
        compact[6].size=CGSize(width:132,height:74)
        let compactLabels=CanvasLabelLayout.place(compact,within:viewport,avoiding:[navigation],circles:circles)
        XCTAssertEqual(compactLabels.count,8)
        let finalChorus=compactLabels.first{$0.id == compact[6].id}!
        XCTAssertLessThan(hypot(finalChorus.rect.midX-anchors[6].x,finalChorus.rect.midY-anchors[6].y),160)
    }

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
    func testLongTimelineNameMovesOutsideOwnRingWithoutLosingLabel() throws {
        let center=CGPoint(x:340,y:300),radius=55.0
        let viewport=CGRect(x:24,y:78,width:672,height:600)
        let label=CanvasLabelRequest(id:.section(arrangementID:"song",useID:"chorus"),anchor:center,
            size:CGSize(width:190,height:38),radius:radius,allowsViewportAdjustment:true,avoidsOwnRing:true)
        let placement=try XCTUnwrap(CanvasLabelLayout.place([label],within:viewport,
            circles:[CanvasLabelCircle(id:label.id,center:center,radius:radius)]).first)
        XCTAssertTrue(viewport.contains(placement.rect))
        XCTAssertFalse(CanvasLabelLayout.obscuresRing(placement.rect,center:center,radius:radius))
        XCTAssertNotEqual(placement.rect.midX,center.x)
        XCTAssertEqual(placement.rect.width,190)
    }
    func testShortNameCanStayFullyInsideLargeTimelineRing() throws {
        let center=CGPoint(x:220,y:190),radius=100.0
        let label=CanvasLabelRequest(id:.signal("orbit"),anchor:center,
            size:CGSize(width:70,height:24),radius:radius,avoidsOwnRing:true)
        let placement=try XCTUnwrap(CanvasLabelLayout.place([label],within:viewport).first)
        XCTAssertEqual(placement.rect.midX,center.x)
        XCTAssertEqual(placement.rect.midY,center.y)
        XCTAssertFalse(CanvasLabelLayout.obscuresRing(placement.rect,center:center,radius:radius))
    }
    func testTimelineLabelProtectsInnerBarTicks() {
        let center=CGPoint(x:220,y:190),radius=100.0
        // The visible bar marks extend seven points inward from the orbit.
        let label=CGRect(x:center.x-66,y:center.y-66,width:132,height:132)
        XCTAssertFalse(CanvasLabelLayout.obscuresRing(label,center:center,radius:radius,clearance:4))
        XCTAssertTrue(CanvasLabelLayout.obscuresRing(label,center:center,radius:radius))
    }
    func testTimelineLabelDoesNotCoverRingWhenOutsideCandidatesAreBlocked() {
        let center=CGPoint(x:174,y:188),radius=55.0
        let narrow=CGRect(x:24,y:78,width:300,height:220)
        let label=CanvasLabelRequest(id:.signal("orbit"),anchor:center,
            size:CGSize(width:180,height:38),radius:radius,allowsViewportAdjustment:true,avoidsOwnRing:true)
        let blocked=[CGRect(x:24,y:78,width:300,height:72),CGRect(x:24,y:220,width:300,height:78)]
        XCTAssertTrue(CanvasLabelLayout.place([label],within:narrow,avoiding:blocked).isEmpty)
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
