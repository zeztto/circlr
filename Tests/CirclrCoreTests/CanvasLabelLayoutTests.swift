import XCTest
@testable import CirclrCore

final class CanvasLabelLayoutTests:XCTestCase {
    let viewport=CGRect(x:24,y:78,width:400,height:240)

    func testConsoleFitUsesLowerRightOnlyWhenThereIsRoomAndPreservesEveryCircle() throws {
        let circles=[CanvasLabelCircle(id:.signal("left"),center:CGPoint(x:300,y:300),radius:70),
                     CanvasLabelCircle(id:.signal("right"),center:CGPoint(x:900,y:600),radius:70)]
        for width in [700.0,1440.0] {
            for consoleHeight in [40.0,180.0] {
                let full=CanvasWorkspaceGeometry.viewport(width:width,height:900)
                let console=CGRect(x:20,y:900-consoleHeight-16,width:min(820,width-40),height:consoleHeight)
                let old=CanvasWorkspaceGeometry.viewport(width:width,height:900,console:console)
                let camera=try XCTUnwrap(CanvasWorkspaceGeometry.fittingCamera(circles:circles,within:full,
                    avoiding:console,marginX:50,marginY:40))
                for circle in circles {
                    let point=camera.screen(Point(circle.center.x,circle.center.y)),r=circle.radius*camera.zoom
                    let frame=CGRect(x:point.x-r,y:point.y-r,width:r*2,height:r*2)
                    XCTAssertTrue(full.insetBy(dx:49.99,dy:39.99).contains(frame),"\(width) × \(consoleHeight): \(circle.id)")
                    XCTAssertFalse(frame.intersects(console.insetBy(dx:-13.99,dy:-13.99)),"\(width) × \(consoleHeight): \(circle.id)")
                }
                if width == 700 {
                    XCTAssertGreaterThanOrEqual(old.maxY,console.minY-14)
                    XCTAssertLessThan(camera.zoom,1.3)
                } else if consoleHeight == 180 {
                    let upper=try XCTUnwrap(CanvasWorkspaceGeometry.fittingCamera(circles:circles,within:old,
                        marginX:50,marginY:40))
                    XCTAssertGreaterThan(camera.zoom,upper.zoom*1.1)
                    let right=camera.screen(Point(900,600))
                    XCTAssertGreaterThan(right.y+70*camera.zoom,old.maxY)
                    XCTAssertGreaterThan(right.x-70*camera.zoom,console.maxX)
                }
            }
        }
    }
    func testConsoleLabelCanOccupyOnlyTheFreeLowerRightAndRemainHittable() throws {
        let full=CanvasWorkspaceGeometry.viewport(width:1440,height:900)
        let console=CGRect(x:20,y:704,width:820,height:180)
        let anchor=CGPoint(x:1060,y:740)
        let request=CanvasLabelRequest(id:.signal("right"),anchor:anchor,
            size:CGSize(width:170,height:36),radius:46,allowsViewportAdjustment:true)
        let label=try XCTUnwrap(CanvasLabelLayout.place([request],within:full,
            avoiding:[console.insetBy(dx:-14,dy:-14)]).first)
        XCTAssertGreaterThan(label.rect.minY,console.minY)
        XCTAssertTrue(full.contains(label.rect))
        XCTAssertFalse(label.rect.intersects(console.insetBy(dx:-14,dy:-14)))
        XCTAssertTrue(label.rect.contains(CGPoint(x:label.rect.midX,y:label.rect.midY)))
    }
    func testInteractiveRegionAndKeyboardVisibilityRespectActualConsoleFootprint() {
        for width in [700.0,1440.0] {
            let viewport=CanvasWorkspaceGeometry.viewport(width:width,height:900)
            let console=CGRect(x:20,y:704,width:min(820,width-40),height:180)
            XCTAssertFalse(CanvasWorkspaceGeometry.containsInteractivePoint(CGPoint(x:100,y:740),within:viewport,avoiding:console))
            XCTAssertTrue(CanvasWorkspaceGeometry.containsInteractivePoint(CGPoint(x:100,y:500),within:viewport,avoiding:console))
            if width == 1440 {
                let point=CGPoint(x:1050,y:740)
                XCTAssertTrue(CanvasWorkspaceGeometry.containsInteractivePoint(point,within:viewport,avoiding:console))
                let circle=CanvasLabelCircle(id:.signal("selected"),center:point,radius:48)
                XCTAssertTrue(CanvasWorkspaceGeometry.circlesVisible([circle],through:HierarchyCamera(),
                    within:viewport,avoiding:console))
                XCTAssertFalse(CanvasWorkspaceGeometry.circlesVisible([circle],through:HierarchyCamera(),
                    within:viewport,avoiding:CGRect(x:820,y:690,width:300,height:200)))
            } else {
                XCTAssertFalse(CanvasWorkspaceGeometry.containsInteractivePoint(CGPoint(x:650,y:740),within:viewport,avoiding:console))
            }
        }
    }
    func testDenseSceneUsesBoundedConservativeFit() throws {
        let viewport=CanvasWorkspaceGeometry.viewport(width:1440,height:900)
        let console=CGRect(x:20,y:704,width:820,height:180)
        let circles=(0..<300).map { index in
            CanvasLabelCircle(id:.signal("\(index)"),center:CGPoint(x:Double(index%20)*60,y:Double(index/20)*60),radius:18)
        }
        let started=ProcessInfo.processInfo.systemUptime
        let camera=try XCTUnwrap(CanvasWorkspaceGeometry.fittingCamera(circles:circles,within:viewport,avoiding:console))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-started,0.5)
        for circle in circles {
            let p=camera.screen(Point(circle.center.x,circle.center.y)),r=circle.radius*camera.zoom
            let rect=CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)
            XCTAssertFalse(rect.intersects(console.insetBy(dx:-13.99,dy:-13.99)))
        }
    }
    func testCableWithVisibleEndpointsButHiddenCurveIsRevealed() {
        let viewport=CanvasWorkspaceGeometry.viewport(width:1440,height:900)
        let console=CGRect(x:20,y:704,width:820,height:180)
        let clear=CirclePortCurve(from:Point(1000,720),control1:Point(1050,680),
                                  control2:Point(1150,680),to:Point(1200,720))
        XCTAssertTrue(CanvasWorkspaceGeometry.curveVisible(clear,within:viewport,avoiding:console))
        let straight=CirclePortCurve(from:Point(1000,720),control1:Point(1050,720),
                                     control2:Point(1150,720),to:Point(1200,720))
        XCTAssertTrue(CanvasWorkspaceGeometry.curveVisible(straight,within:viewport,avoiding:console))
        let hidden=CirclePortCurve(from:Point(1000,720),control1:Point(800,750),
                                   control2:Point(1000,750),to:Point(1200,720))
        XCTAssertTrue(viewport.contains(CGPoint(x:hidden.from.x,y:hidden.from.y)))
        XCTAssertTrue(viewport.contains(CGPoint(x:hidden.to.x,y:hidden.to.y)))
        XCTAssertFalse(CanvasWorkspaceGeometry.curveVisible(hidden,within:viewport,avoiding:console))
        let offscreen=CirclePortCurve(from:Point(1000,720),control1:Point(1050,900),
                                      control2:Point(1150,900),to:Point(1200,720))
        XCTAssertFalse(CanvasWorkspaceGeometry.curveVisible(offscreen,within:viewport,avoiding:console))
        let upper=CanvasWorkspaceGeometry.viewport(width:1440,height:900,console:console)
        let hiddenMiddle=CirclePortCurve(from:Point(300,500),control1:Point(380,780),
                                         control2:Point(520,780),to:Point(600,500))
        XCTAssertTrue(upper.insetBy(dx:70,dy:70).contains(CGPoint(x:hiddenMiddle.from.x,y:hiddenMiddle.from.y)))
        XCTAssertTrue(upper.insetBy(dx:70,dy:70).contains(CGPoint(x:hiddenMiddle.to.x,y:hiddenMiddle.to.y)))
        XCTAssertFalse(CanvasWorkspaceGeometry.curveVisible(hiddenMiddle,within:viewport,avoiding:console))
        XCTAssertFalse(CanvasWorkspaceGeometry.curveVisible(hiddenMiddle,within:upper,margin:70))
    }

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
