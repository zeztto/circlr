import XCTest
@testable import CirclrCore

final class SectionGraphReachabilityTests:XCTestCase {
    func fixture()throws->Project {
        var p=Project();_ = p.addTrack(name:"첫 트랙");_ = p.addTrack(name:"둘째 트랙")
        _ = p.addSection(name:"섹션",at:Point(),bars:1);p.enableAlbum()
        p=try SectionGraphMigration.migrate(p)
        var graph=SectionGraph()
        func node(_ id:ID,_ content:MusicCircleContent) {
            var node=MusicCircle(name:id,content:content);node.id=id;graph.nodes.append(node)
        }
        for i in 0..<2 {
            let number=String(i+1)
            node("midi"+number,.midi(laneID:p.sections[0].lanes[i].id))
            node("instrument"+number,.instrument(trackID:p.tracks[i].id))
            node("effect"+number,.effect(Effect(.gain)))
            node("output"+number,.output(trackID:p.tracks[i].id))
            graph.edges.append(MusicConnection(from:"midi"+number,to:"instrument"+number,signal:.midi))
            graph.edges.append(MusicConnection(from:"instrument"+number,to:"effect"+number,signal:.audio))
            var input=MusicConnection(from:"effect"+number,to:"router",signal:.audio)
            input.toPortID=AudioRouter.inputs[i]
            var output=MusicConnection(from:"router",to:"output"+number,signal:.audio)
            output.fromPortID=AudioRouter.outputs[i]
            graph.edges += [input,output]
        }
        node("router",.router(AudioRouter()))
        p.sections[0].graph=graph;try ProjectStore.validateStructure(p)
        return p
    }
    func graph(_ p:Project)throws->SectionGraph {try XCTUnwrap(p.sections[0].graph)}
    func names(_ route:StudioTrackRoute)->Set<String> {Set(route.destinations.map(\.name))}
    func assess(_ p:Project,selected:ID)->BounceMembership {
        BounceAssessment.make(trackID:p.tracks[0].id,useID:p.active.uses[0].id,selectedNodeID:selected,in:p).membership
    }
    func testIndependentBusesAgreeAcrossNavigationMembershipAndRepeatedUses()throws {
        var p=try fixture()
        _ = try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point(800,0))
        let before=p,g=try graph(p),index=try SectionGraphReachability(graph:g)
        for number in 1...2 {
            for prefix in ["midi","instrument","effect"] {
                let id=prefix+String(number),expected:Set<ID>=[p.tracks[number-1].id]
                XCTAssertEqual(index.outputTracks(from:id),expected)
                XCTAssertEqual(StudioNavigation.outputTracks(from:id,graph:g),expected)
            }
        }
        XCTAssertEqual(index.outputTracks(from:"router"),Set(p.tracks.map(\.id)))
        XCTAssertEqual(assess(p,selected:"effect1"),.mainPath)
        XCTAssertEqual(assess(p,selected:"effect2"),.outsidePath)
        let routes=try StudioNavigation.build(p)
        XCTAssertEqual(routes.count,2)
        for route in routes {
            XCTAssertTrue(names(route.tracks[0]).contains("effect1"));XCTAssertFalse(names(route.tracks[0]).contains("effect2"))
            XCTAssertTrue(names(route.tracks[1]).contains("effect2"));XCTAssertFalse(names(route.tracks[1]).contains("effect1"))
            for track in route.tracks {XCTAssertTrue(track.destinations.allSatisfy(\.connected))}
        }
        XCTAssertNotEqual(routes[0].tracks[0].destinations[0].id,routes[1].tracks[0].destinations[0].id)
        XCTAssertEqual(p,before)
    }
    func testCrossRoutingAndFanOutComposeAcrossTwoRouters()throws {
        var p=try fixture(),g=try graph(p)
        var second=MusicCircle(name:"second",content:.router(AudioRouter()));second.id="second"
        g.nodes.append(second)
        for i in g.edges.indices where g.edges[i].from=="router" {
            let original=g.edges[i].to
            g.edges[i].to="second"
            g.edges[i].toPortID=original=="output1" ? AudioRouter.input2:AudioRouter.input1
        }
        for i in 0..<2 {
            var edge=MusicConnection(from:"second",to:"output"+String(i+1),signal:.audio)
            edge.fromPortID=AudioRouter.outputs[i];g.edges.append(edge)
        }
        var index=try SectionGraphReachability(graph:g)
        XCTAssertEqual(index.outputTracks(from:"effect1"),[p.tracks[1].id])
        XCTAssertEqual(index.outputTracks(from:"effect2"),[p.tracks[0].id])
        let secondIndex=try XCTUnwrap(g.nodes.firstIndex{$0.id=="second"})
        g.nodes[secondIndex].content = .router(AudioRouter(routes:[
            .init(input:AudioRouter.input1,output:AudioRouter.output1),
            .init(input:AudioRouter.input2,output:AudioRouter.output1),
            .init(input:AudioRouter.input2,output:AudioRouter.output2)]))
        index=try SectionGraphReachability(graph:g)
        XCTAssertEqual(index.outputTracks(from:"effect1"),Set(p.tracks.map(\.id)))
        XCTAssertEqual(index.outputTracks(from:"effect2"),[p.tracks[0].id])
        p.sections[0].graph=g
        let routes=try StudioNavigation.build(p)
        XCTAssertTrue(routes[0].tracks.allSatisfy{names($0).contains("effect1")})
        XCTAssertFalse(names(routes[0].tracks[1]).contains("effect2"))
    }
    func testZeroGainsMuteAndEmptyRouterRoutesKeepStructuralSemantics()throws {
        var p=try fixture(),g=try graph(p)
        let routerIndex=try XCTUnwrap(g.nodes.firstIndex{$0.id=="router"})
        g.nodes[routerIndex].content = .router(AudioRouter(routes:[.init(input:AudioRouter.input1,output:AudioRouter.output1,gain:0)]))
        for i in g.nodes.indices {g.nodes[i].muted=true;g.nodes[i].gain=0}
        for i in g.edges.indices where g.edges[i].signal == .audio {g.edges[i].gain=0}
        p.sections[0].graph=g;let before=p
        let index=try SectionGraphReachability(graph:g)
        XCTAssertEqual(index.outputTracks(from:"midi1"),[p.tracks[0].id])
        XCTAssertEqual(index.outputTracks(from:"effect2"),[])
        let routes=try StudioNavigation.build(p)
        let owned=routes[0].tracks[1].destinations
        for id in ["midi2","instrument2"] {
            XCTAssertFalse(try XCTUnwrap(owned.first{$0.name==id}).connected)
        }
        XCTAssertFalse(names(routes[0].tracks[1]).contains("effect2"))
        XCTAssertEqual(assess(p,selected:"midi1"),.mainPath);XCTAssertEqual(p,before)
        g.nodes[routerIndex].content = .router(AudioRouter(routes:[]))
        XCTAssertEqual(try SectionGraphReachability(graph:g).outputTracks(from:"effect1"),[])
    }
    func testSidechainOnlyAndMainPathsRemainDistinct()throws {
        var p=try fixture(),g=try graph(p)
        var compressor=MusicCircle(name:"compressor",content:.effect(Effect(.compressor)));compressor.id="compressor"
        g.nodes.append(compressor)
        g.edges.removeAll{$0.from=="effect2"}
        for i in g.edges.indices where g.edges[i].to=="output1" {g.edges[i].to="compressor"}
        g.edges.append(MusicConnection(from:"compressor",to:"output1",signal:.audio))
        var detector=MusicConnection(from:"effect2",to:"compressor",signal:.audio);detector.sidechain=true
        g.edges.append(detector);p.sections[0].graph=g
        var index=try SectionGraphReachability(graph:g)
        XCTAssertTrue(index.reachesSidechainOutput("output1",from:"midi2"))
        XCTAssertFalse(index.reachesMainOutput("output1",from:"midi2"))
        XCTAssertEqual(index.outputTracks(from:"effect2"),[])
        XCTAssertEqual(assess(p,selected:"effect2"),.sidechainOnly)
        XCTAssertFalse(names(try StudioNavigation.build(p)[0].tracks[0]).contains("effect2"))
        g.edges.append(MusicConnection(from:"effect2",to:"compressor",signal:.audio));p.sections[0].graph=g
        index=try SectionGraphReachability(graph:g)
        XCTAssertTrue(index.reachesSidechainOutput("output1",from:"effect2"))
        XCTAssertTrue(index.reachesMainOutput("output1",from:"effect2"))
        XCTAssertEqual(assess(p,selected:"effect2"),.mainPath)
        XCTAssertTrue(names(try StudioNavigation.build(p)[0].tracks[0]).contains("effect2"))
    }
    func testInvalidGraphFailsClosedWithoutDictionaryTrap()throws {
        let p=try fixture();var g=try graph(p)
        g.nodes.append(g.nodes[0])
        XCTAssertThrowsError(try SectionGraphReachability(graph:g))
        XCTAssertEqual(StudioNavigation.outputTracks(from:"midi1",graph:g),[])
    }
}
