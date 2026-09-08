import XCTest
@testable import CirclrCore

final class CirclePortTests:XCTestCase {
    func fixture()throws->Project {
        var p=Project();_=p.addTrack(name:"신스");_=p.addSection(name:"벌스",at:Point(),bars:1);p.enableAlbum()
        return try SectionGraphMigration.migrate(p)
    }
    func move(_ moves:[PlacedCircleConnection],in p:inout Project)throws->Bool {
        try CirclePortLayoutEditing.apply(moves,projectID:p.id,expectedMusicRevision:p.musicRevision,expectedLayoutRevision:p.portLayout?.revision ?? 0,in:&p)
    }
    func testRealPortsAndReverseInputGestureUseStableSignalRoles()throws {
        var p=try fixture();let use=p.active.uses[0]
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:use))
        let midi=graph.nodes.first{if case .midi=$0.content{return true};return false}!
        let instrument=graph.nodes.first{if case .instrument=$0.content{return true};return false}!
        let compressor=MusicCircle(name:"컴프레서",content:.effect(Effect(.compressor)))
        graph.nodes.append(compressor);try SectionGraphEditing.set(graph,useID:use.id,original:false,in:&p)
        func endpoint(_ id:ID,_ port:String)->CirclePortEndpoint {.init(node:.music(arrangementID:p.active.id,useID:use.id,nodeID:id),portID:port)}
        let output=endpoint(midi.id,CirclePort.midiOutput),input=endpoint(instrument.id,CirclePort.midiInput)
        let reversed=try CirclePortCatalog.normalize(input,output,in:p)
        XCTAssertEqual(reversed.from,output);XCTAssertEqual(reversed.to,input);XCTAssertEqual(reversed.signal,.midi)
        XCTAssertEqual(CirclePort.ports(for:midi.content).map(\.id),[CirclePort.midiOutput])
        XCTAssertEqual(CirclePort.ports(for:instrument.content).map(\.id),[CirclePort.midiInput,CirclePort.audioOutput])
        let sidechain=try CirclePortCatalog.normalize(endpoint(compressor.id,CirclePort.sidechainInput),endpoint(instrument.id,CirclePort.audioOutput),in:p)
        XCTAssertTrue(sidechain.sidechain);XCTAssertEqual(sidechain.signal,.audio)
        XCTAssertThrowsError(try CirclePortCatalog.normalize(output,endpoint(compressor.id,CirclePort.audioInput),in:p))
        XCTAssertThrowsError(try CirclePortCatalog.normalize(input,input,in:p))
        XCTAssertThrowsError(try CirclePortCatalog.normalize(endpoint(instrument.id,"out.audio.bus2"),endpoint(compressor.id,CirclePort.audioInput),in:p))
        XCTAssertEqual(try CirclePortCatalog.ports(at:.album,in:p),[])
        XCTAssertEqual(try CirclePortCatalog.ports(at:.group(parent:.album,id:"visual"),in:p),[])
        var global=SignalNode(kind:.effect,name:"전역 컴프레서");global.effect=Effect(.compressor)
        XCTAssertEqual(CirclePort.ports(for:global).map(\.id),[CirclePort.audioInput,CirclePort.sidechainInput,CirclePort.audioOutput])
        global.effect=Effect(.audioUnit);XCTAssertFalse(CirclePort.ports(for:global).contains{$0.isSidechain})
        for node in try HierarchySceneBuilder.build(p).nodes {
            XCTAssertEqual(node.acceptsInput,node.ports.contains{$0.direction == .input})
            XCTAssertEqual(node.providesOutput,node.ports.contains{$0.direction == .output})
        }
    }
    func testEightDirectionsHaveSeparateMainSidechainAndOutputHits()throws {
        let ports=CirclePort.ports(for:.effect(Effect(.compressor))),center=Point(400,300)
        var handles:[CirclePortHandle]=[]
        for octant in PortOctant.allCases {
            for port in ports {
                let point=try CirclePortGeometry.anchor(center:center,radius:100,port:port,octant:octant)
                XCTAssertEqual(CirclePortGeometry.nearestOctant(to:point,center:center),octant)
                handles.append(.init(endpoint:.init(node:.signal("compressor"),portID:port.id),octant:octant,point:point))
            }
        }
        XCTAssertEqual(handles.count,24)
        for handle in handles {
            XCTAssertEqual(CirclePortGeometry.hit(handle.point,visibleHandles:handles),handle)
            XCTAssertNil(CirclePortGeometry.hit(handle.point,visibleHandles:handles.filter{$0 != handle}))
        }
        XCTAssertNil(CirclePortGeometry.hit(center,visibleHandles:handles))
        XCTAssertNil(CirclePortGeometry.hit(handles[0].point,visibleHandles:[]))
        XCTAssertNil(CirclePortGeometry.nearestOctant(to:center,center:center))
        XCTAssertNil(CirclePortGeometry.nearestOctant(to:Point(.nan,0),center:center))
        XCTAssertThrowsError(try CirclePortGeometry.anchor(center:center,radius:.infinity,port:ports[0],octant:.north))
        let right=try CirclePortGeometry.anchor(center:center,radius:100,port:ports[0],octant:.east)
        XCTAssertEqual(right.x,524,accuracy:1e-8);XCTAssertEqual(right.y,300,accuracy:1e-8)
    }
    func testEveryCurveUsesEndpointNormalsAndKeepsExactEndpoints()throws {
        for from in PortOctant.allCases {for to in PortOctant.allCases {
            let a=CirclePortHandle(endpoint:.init(node:.signal("a"),portID:CirclePort.audioOutput),octant:from,point:Point(100,150))
            let b=CirclePortHandle(endpoint:.init(node:.signal("b"),portID:CirclePort.audioInput),octant:to,point:Point(350,270))
            let curve=try CirclePortGeometry.curve(from:a,to:b),an=CirclePortGeometry.normal(from),bn=CirclePortGeometry.normal(to)
            XCTAssertEqual(try curve.point(at:0),a.point);XCTAssertEqual(try curve.point(at:1),b.point)
            XCTAssertGreaterThan((curve.control1.x-a.point.x)*an.x+(curve.control1.y-a.point.y)*an.y,0)
            XCTAssertGreaterThan((curve.control2.x-b.point.x)*bn.x+(curve.control2.y-b.point.y)*bn.y,0)
            XCTAssertThrowsError(try curve.point(at:.nan))
        }}
    }
    func testLegacyJSONAndAllPlacementsPreserveEveryMusicField()throws {
        var p=try fixture();let original=p,encoded=try JSONEncoder().encode(p)
        XCTAssertNil((try JSONSerialization.jsonObject(with:encoded) as! [String:Any])["portLayout"])
        XCTAssertNil(try JSONDecoder().decode(Project.self,from:encoded).portLayout)
        let connection=try XCTUnwrap(CirclePortCatalog.connections(in:p).first)
        XCTAssertFalse(try move([.init(id:connection.id,placement:.init())],in:&p));XCTAssertEqual(p,original)
        for octant in PortOctant.allCases {
            XCTAssertTrue(try move([.init(id:connection.id,placement:.init(from:octant,to:.north))],in:&p))
            XCTAssertEqual(p.portLayout?.placement(for:connection.id).from,octant)
            var music=p;music.portLayout=nil;XCTAssertEqual(music,original)
        }
        let before=p
        XCTAssertFalse(try move([.init(id:connection.id,placement:.init(from:.northwest,to:.north))],in:&p));XCTAssertEqual(p,before)
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
    }
    func testStaleOrPartiallyInvalidBatchCannotChangePlacement()throws {
        var p=try fixture();let edge=try XCTUnwrap(CirclePortCatalog.connections(in:p).first)
        let change=PlacedCircleConnection(id:edge.id,placement:.init(from:.north,to:.south)),before=p
        for (projectID,music,layout) in [("wrong",0,0),(p.id,1,0),(p.id,0,1)] {
            XCTAssertThrowsError(try CirclePortLayoutEditing.apply([change],projectID:projectID,expectedMusicRevision:music,expectedLayoutRevision:layout,in:&p));XCTAssertEqual(p,before)
        }
        var missing=change;missing.id.edgeID="missing"
        XCTAssertThrowsError(try move([change,missing],in:&p));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try move([change,change],in:&p));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try move([],in:&p));XCTAssertEqual(p,before)
    }
    func testLayoutUndoKeepsNewMusicAndUsesMonotonicLayoutRevision()throws {
        var p=try fixture();let edge=try XCTUnwrap(CirclePortCatalog.connections(in:p).first)
        _=try move([.init(id:edge.id,placement:.init(from:.north,to:.south))],in:&p);let saved=p.portLayout
        p.musicRevision+=1;p.sections[0].lanes[0].notes.append(Note(beat:0,pitch:60));let music=p
        XCTAssertTrue(try CirclePortLayoutEditing.restore(nil,projectID:p.id,expectedMusicRevision:p.musicRevision,expectedLayoutRevision:1,in:&p))
        XCTAssertEqual(p.portLayout?.revision,2);XCTAssertEqual(p.portLayout?.connections,[])
        XCTAssertEqual(p.musicRevision,music.musicRevision);XCTAssertEqual(p.sections,music.sections)
        XCTAssertTrue(try CirclePortLayoutEditing.restore(saved,projectID:p.id,expectedMusicRevision:p.musicRevision,expectedLayoutRevision:2,in:&p))
        XCTAssertEqual(p.portLayout?.revision,3);XCTAssertEqual(p.portLayout?.connections,saved?.connections)
        let before=p
        XCTAssertThrowsError(try CirclePortLayoutEditing.restore(nil,projectID:p.id,expectedMusicRevision:p.musicRevision,expectedLayoutRevision:1,in:&p));XCTAssertEqual(p,before)
    }
    func testSharedEdgeIDsStaySeparateAcrossUsesAndRejectCrossUseGesture()throws {
        var p=try fixture();let first=p.active.uses[0]
        _=try ProjectEditing.reuse(first.id,in:&p,at:Point(200,0))
        let second=p.active.uses[1],connections=try CirclePortCatalog.connections(in:p)
        let a=try XCTUnwrap(connections.first{if case .music(_,let id,_)=$0.from.node{return id==first.id};return false})
        let b=try XCTUnwrap(connections.first{if case .music(_,let id,_)=$0.from.node{return id==second.id && $0.id.edgeID==a.id.edgeID};return false})
        XCTAssertNotEqual(a.id,b.id)
        _=try move([.init(id:a.id,placement:.init(from:.south,to:.northeast))],in:&p)
        XCTAssertEqual(p.portLayout?.placement(for:b.id),CircleConnectionPlacement())
        XCTAssertThrowsError(try CirclePortCatalog.normalize(a.from,b.to,in:p))
    }
    func testCollapsedGroupKeepsLogicalEndpointsAndSaveReopenPlacement()throws {
        var p=try fixture();let use=p.active.uses[0]
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:use))
        let edge=graph.edges.first!,from=CircleAddress.music(arrangementID:p.active.id,useID:use.id,nodeID:edge.from),to=CircleAddress.music(arrangementID:p.active.id,useID:use.id,nodeID:edge.to)
        let id=CircleConnectionID(edgeID:edge.id,from:from,to:to),placement=CircleConnectionPlacement(from:.northwest,to:.southeast)
        _=try move([.init(id:id,placement:placement)],in:&p)
        var group=CanvasGroup(name:"연주 묶음",members:[edge.from]);group.collapsed=true;graph.layout.groups.append(group)
        try SectionGraphEditing.set(graph,useID:use.id,original:false,in:&p)
        let scene=try HierarchySceneBuilder.build(p),shown=try XCTUnwrap(scene.edges.first{$0.connectionID==id})
        XCTAssertEqual(shown.placement,placement);XCTAssertEqual(shown.to,to);XCTAssertNotEqual(shown.from,from)
        XCTAssertEqual(shown.connectionID?.from,from);XCTAssertEqual(scene.node(shown.from)?.ports,[])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-ports-\(newID()).circlr");defer{try? FileManager.default.removeItem(at:root)}
        let saved=try ProjectStore.save(p,to:root,mediaRoot:nil),reopened=try ProjectStore.load(root).project
        XCTAssertEqual(reopened,saved)
        XCTAssertEqual(try HierarchySceneBuilder.build(reopened).edges.first{$0.connectionID==id}?.placement,placement)
    }
    func testMalformedLayoutRejectedBeforeSceneDictionaryConstruction()throws {
        var p=try fixture(),layout=CirclePortLayout();let edge=try XCTUnwrap(CirclePortCatalog.connections(in:p).first)
        layout.connections=[.init(id:edge.id,placement:.init(from:.north,to:.south))];layout.connections.append(layout.connections[0]);p.portLayout=layout
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
        XCTAssertThrowsError(try HierarchySceneBuilder.build(p))
        XCTAssertThrowsError(try JSONDecoder().decode(PortOctant.self,from:Data("8".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(PortOctant.self,from:Data("-1".utf8)))
        layout.connections=[];layout.revision = -1;XCTAssertThrowsError(try layout.validate())
    }
    func testMoreThanEightBranchesKeepOneLogicalOutputAndIndependentPlacements()throws {
        var p=try fixture();let source=p.signal.nodes.first{$0.kind == .source}!
        for i in 0..<12 {
            let bus=SignalNode(kind:.bus,name:"버스 \(i+1)");p.signal.nodes.append(bus)
            var edge=SignalEdge(from:source.id,to:bus.id);edge.gain=Double(i+1)/12;p.signal.edges.append(edge)
        }
        let before=p,branches=try CirclePortCatalog.connections(in:p).filter{$0.from.node == .signal(source.id)}
        XCTAssertEqual(branches.count,13);XCTAssertEqual(Set(branches.map(\.from.portID)),[CirclePort.audioOutput])
        let moves=branches.enumerated().map{i,edge in PlacedCircleConnection(id:edge.id,placement:.init(from:PortOctant(rawValue:i%8)!,to:.north))}
        XCTAssertTrue(try move(moves,in:&p));XCTAssertEqual(p.portLayout?.connections.count,13)
        for change in moves {XCTAssertEqual(p.portLayout?.placement(for:change.id),change.placement)}
        var music=p;music.portLayout=nil;XCTAssertEqual(music,before)
    }
}
