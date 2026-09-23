import XCTest
@testable import CirclrCore

final class CirclePortPresentationTests: XCTestCase {
    func testRouterOverviewAndSinglePortSelectionPreserveAllEightChoices() throws {
        let ports = CirclePort.ports(for:.router(AudioRouter()))
        func handles(selected: String?) throws -> [CirclePortHandle] {
            try ports.flatMap { port in
                try CirclePortPresentation.octants(for:port,radius:100,engaged:true,expanded:port.id == selected,connected:[port.defaultOctant]).map { octant in
                    .init(endpoint:.init(node:.signal("router"),portID:port.id),octant:octant,
                          point:try CirclePortGeometry.anchor(center:Point(400,400),radius:100,port:port,octant:octant))
                }
            }
        }
        XCTAssertEqual(try handles(selected:nil).count,4)
        for port in ports {
            let visible = try handles(selected:port.id)
            XCTAssertEqual(visible.count,11)
            XCTAssertEqual(Set(visible.filter{$0.endpoint.portID == port.id}.map(\.octant)),Set(PortOctant.allCases))
            for handle in visible { XCTAssertEqual(CirclePortGeometry.hit(handle.point,visibleHandles:visible),handle) }
        }
        let hidden = try CirclePortGeometry.anchor(center:Point(400,400),radius:100,port:ports[0],octant:.north)
        XCTAssertNil(CirclePortGeometry.hit(hidden,visibleHandles:try handles(selected:nil)))
    }

    func testExistingNonDefaultConnectionsAndTinyOverviewDefaults() throws {
        let port = CirclePort.ports(for:.effect(Effect(.compressor))).first{$0.isSidechain}!
        XCTAssertEqual(CirclePortPresentation.octants(for:port,radius:60,engaged:false,expanded:false,connected:[.north,.southeast]),[.north,.southeast])
        XCTAssertEqual(CirclePortPresentation.octants(for:port,radius:60,engaged:true,expanded:true,connected:[.north]),[.north,.west])
        for radius in [Double.nan,Double.infinity,0] {
            XCTAssertTrue(CirclePortPresentation.octants(for:port,radius:radius,engaged:true,expanded:true,connected:Set(PortOctant.allCases)).isEmpty)
            XCTAssertTrue(CirclePortPresentation.octants(for:port,radius:radius,engaged:true,expanded:true,connected:[],selected:true).isEmpty)
        }
        for radius in [44.0,45.0] {
            XCTAssertTrue(CirclePortPresentation.octants(for:port,radius:radius,engaged:false,expanded:false,connected:Set(PortOctant.allCases)).isEmpty)
            XCTAssertEqual(CirclePortPresentation.octants(for:port,radius:radius,engaged:true,expanded:true,connected:Set(PortOctant.allCases)),[port.defaultOctant])
            XCTAssertEqual(CirclePortPresentation.octants(for:port,radius:radius,engaged:true,expanded:true,connected:[.north],selected:true),[port.defaultOctant])
        }
        XCTAssertEqual(CirclePortPresentation.octants(for:port,radius:46,engaged:true,expanded:true,connected:[.north],selected:true),[.north,port.defaultOctant].sorted{$0.rawValue<$1.rawValue})
        for port in CirclePort.flowPorts + CirclePort.ports(for:.instrument(trackID:"synth")) {
            XCTAssertEqual(CirclePortPresentation.octants(for:port,radius:100,engaged:true,expanded:false,connected:[]),[port.defaultOctant])
        }
    }

    func testTinyFocusedRouterPortsStayDistinctAndHittable() throws {
        let ports = CirclePort.ports(for:.router(AudioRouter()))
        let selected = ports[2]
        let handles = try ports.flatMap { port in
            try CirclePortPresentation.octants(for:port,radius:44,engaged:true,expanded:port.id == selected.id,
                                               connected:Set(PortOctant.allCases),selected:port.id == selected.id).map { octant in
                CirclePortHandle(endpoint:.init(node:.signal("router"),portID:port.id),octant:octant,
                                 point:try CirclePortGeometry.anchor(center:Point(350,260),radius:44,port:port,octant:octant))
            }
        }
        XCTAssertEqual(handles.count,ports.count)
        XCTAssertEqual(Set(handles.map(\.endpoint.portID)),Set(ports.map(\.id)))
        XCTAssertTrue(handles.allSatisfy { handle in
            ports.first(where: { $0.id == handle.endpoint.portID })?.defaultOctant == handle.octant
        })
        for handle in handles {
            XCTAssertEqual(CirclePortGeometry.hit(handle.point,visibleHandles:handles),handle)
        }
        XCTAssertEqual(CirclePortPresentation.octants(for:selected,radius:44,engaged:false,expanded:false,connected:[],selected:true),[selected.defaultOctant])
        for port in ports {
            XCTAssertEqual(CirclePortPresentation.octants(for:port,radius:100,engaged:true,expanded:port.id == selected.id,
                                                          connected:[port.defaultOctant],selected:port.id == selected.id).count,
                           port.id == selected.id ? 8:1)
        }
    }

    func testTinyRouterMovesCoveredOutputControlsOutsideReadableLabel() throws {
        let center = Point(300,240), radius = 44.0
        let request = CanvasLabelRequest(id:.signal("router"),anchor:CGPoint(x:center.x,y:center.y),
                                         size:CGSize(width:120,height:36),radius:radius,priority:100)
        let label = try XCTUnwrap(CanvasLabelLayout.place([request],within:CGRect(x:0,y:0,width:700,height:480)).first?.rect)
        XCTAssertEqual(label.minX,center.x+radius+9)
        let ports = CirclePort.ports(for:.router(AudioRouter()))
        var handles:[CirclePortHandle] = []
        for port in ports {
            let original = try CirclePortGeometry.anchor(center:center,radius:radius,port:port,octant:port.defaultOctant)
            if port.direction == .output { XCTAssertTrue(label.contains(CGPoint(x:original.x,y:original.y))) }
            let choice = try XCTUnwrap(CirclePortPresentation.overviewAnchor(for:port,center:center,radius:radius) { point in
                !label.insetBy(dx:-10,dy:-10).contains(CGPoint(x:point.x,y:point.y)) &&
                    !handles.contains(where: { hypot($0.point.x-point.x,$0.point.y-point.y) <= CirclePortGeometry.hitRadius*2 })
            })
            let handle = CirclePortHandle(endpoint:.init(node:.signal("router"),portID:port.id),octant:choice.octant,point:choice.point)
            XCTAssertFalse(label.insetBy(dx:-10,dy:-10).contains(CGPoint(x:handle.point.x,y:handle.point.y)))
            XCTAssertEqual(CirclePortGeometry.hit(handle.point,visibleHandles:handles+[handle]),handle)
            handles.append(handle)
        }
        XCTAssertEqual(handles.count,4)
        XCTAssertEqual(Set(handles.map(\.endpoint.portID)),Set(ports.map(\.id)))
        XCTAssertTrue(handles.filter { $0.endpoint.portID.hasPrefix("out.") }.allSatisfy { $0.octant != .east })
        for handle in handles { XCTAssertEqual(CirclePortGeometry.hit(handle.point,visibleHandles:handles),handle) }
    }

    func testSelectedPortCameraKeepsAnchorOnScreenWithoutMovingNormalOverview() throws {
        let (_, fixture) = try PlaybackFramingTests().fixture()
        var node = fixture; node.center = Point(500,360); node.radius = 100; node.scale = 1; node.repeatCount = 1
        let port = CirclePort.ports(for:.router(AudioRouter()))[3]
        let viewport = CGRect(x:24,y:180,width:680,height:400)
        for radius in [44.0,45.0,46.0] {
            let zoom = radius/node.radius
            let current = HierarchyCamera(pan:Point(viewport.midX-node.center.x*zoom,viewport.midY-node.center.y*zoom),zoom:zoom)
            let target = CirclePortPresentation.cameraRevealingSelected(port,on:node,current:current,within:viewport) ?? current
            let center = target.screen(node.center)
            let anchor = try CirclePortGeometry.anchor(center:center,radius:node.outerRadius*target.zoom,port:port,octant:port.defaultOctant)
            XCTAssertTrue(viewport.contains(CGPoint(x:anchor.x,y:anchor.y)))
            if radius <= 45 { XCTAssertGreaterThanOrEqual(node.radius*target.zoom,62) }
            else { XCTAssertEqual(target,current) }
        }
        let current = HierarchyCamera(pan:Point(-1000,-700),zoom:0.46)
        let moved = try XCTUnwrap(CirclePortPresentation.cameraRevealingSelected(port,on:node,current:current,within:viewport))
        let center = moved.screen(node.center)
        let anchor = try CirclePortGeometry.anchor(center:center,radius:node.outerRadius*moved.zoom,port:port,octant:port.defaultOctant)
        XCTAssertTrue(viewport.contains(CGPoint(x:anchor.x,y:anchor.y)))
        XCTAssertEqual(moved.zoom,current.zoom)
        var exposed = port; exposed.bindingIndex = 10
        let normal = HierarchyCamera(pan:Point(viewport.midX-node.center.x*0.46,viewport.midY-node.center.y*0.46),zoom:0.46)
        let shifted = try XCTUnwrap(CirclePortPresentation.cameraRevealingSelected(exposed,on:node,current:normal,within:viewport))
        let shiftedCenter = shifted.screen(node.center)
        let farAnchor = try CirclePortGeometry.anchor(center:shiftedCenter,radius:node.outerRadius*shifted.zoom,
                                                       port:exposed,octant:exposed.defaultOctant)
        XCTAssertTrue(viewport.insetBy(dx:11,dy:11).contains(CGPoint(x:farAnchor.x,y:farAnchor.y)))
        XCTAssertEqual(shifted.zoom,normal.zoom)
    }

    func testRouterLabelsDoNotCoverPortsTimeHandlesOrEachOther() throws {
        let viewport = CGRect(x:24,y:78,width:650,height:470), center = Point(350,315)
        let ports = CirclePort.ports(for:.router(AudioRouter()))
        let requests = try ports.map { port -> PortLabelRequest in
            let p = try CirclePortGeometry.anchor(center:center,radius:90,port:port,octant:port.defaultOctant)
            return .init(endpoint:.init(node:.signal("router"),portID:port.id),anchor:CGPoint(x:p.x,y:p.y),size:CGSize(width:42,height:19),octant:port.defaultOctant)
        }
        let obstacles = requests.map { CGRect(x:$0.anchor.x-10,y:$0.anchor.y-10,width:20,height:20) } + [CGRect(x:300,y:200,width:80,height:35),CGRect(x:170,y:310,width:28,height:28)]
        let labels = CirclePortPresentation.labels(requests,within:viewport,avoiding:obstacles)
        XCTAssertEqual(labels.count,4)
        for (index,label) in labels.enumerated() {
            XCTAssertTrue(viewport.contains(label.rect))
            XCTAssertFalse(obstacles.contains{$0.intersects(label.rect)})
            XCTAssertFalse(labels.dropFirst(index+1).contains{$0.rect.intersects(label.rect)})
        }
        XCTAssertEqual(labels.map(\.rect),CirclePortPresentation.labels(requests,within:viewport,avoiding:obstacles).map(\.rect))
    }

    func testActiveLabelWinsDuplicateAndCoveredViewportHidesText() {
        let endpoint = CirclePortEndpoint(node:.signal("a"),portID:CirclePort.audioInput)
        let old = PortLabelRequest(endpoint:endpoint,anchor:CGPoint(x:100,y:100),size:CGSize(width:42,height:19),octant:.west)
        let active = PortLabelRequest(endpoint:endpoint,anchor:CGPoint(x:400,y:200),size:CGSize(width:42,height:19),octant:.east,priority:10)
        let viewport = CGRect(x:0,y:0,width:600,height:400)
        let placed = CirclePortPresentation.labels([old,active],within:viewport,avoiding:[])
        XCTAssertEqual(placed.count,1); XCTAssertGreaterThan(placed[0].rect.minX,400)
        XCTAssertTrue(CirclePortPresentation.labels([old,active],within:viewport,avoiding:[viewport]).isEmpty)
        var invalid = active; invalid.size.width = .infinity
        XCTAssertTrue(CirclePortPresentation.labels([invalid],within:viewport,avoiding:[]).isEmpty)
    }
}
