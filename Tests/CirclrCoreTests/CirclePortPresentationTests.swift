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

    func testExistingNonDefaultConnectionsRemainVisibleAndTinyCirclesCannotBeHit() throws {
        let port = CirclePort.ports(for:.effect(Effect(.compressor))).first{$0.isSidechain}!
        XCTAssertEqual(CirclePortPresentation.octants(for:port,radius:60,engaged:false,expanded:false,connected:[.north,.southeast]),[.north,.southeast])
        XCTAssertEqual(CirclePortPresentation.octants(for:port,radius:60,engaged:true,expanded:true,connected:[.north]),[.north,.west])
        for radius in [Double.nan,Double.infinity,0,45] {
            XCTAssertTrue(CirclePortPresentation.octants(for:port,radius:radius,engaged:true,expanded:true,connected:Set(PortOctant.allCases)).isEmpty)
        }
        for port in CirclePort.flowPorts + CirclePort.ports(for:.instrument(trackID:"synth")) {
            XCTAssertEqual(CirclePortPresentation.octants(for:port,radius:100,engaged:true,expanded:false,connected:[]),[port.defaultOctant])
        }
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
