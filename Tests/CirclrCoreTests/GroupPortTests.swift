import XCTest
@testable import CirclrCore

final class GroupPortTests:XCTestCase {
    func fixture()throws->(Project,CircleAddress,CirclePortEndpoint,CirclePortEndpoint) {
        var p=Project();_=p.addTrack(name:"신스");_=p.addSection(name:"벌스",at:Point(),bars:1)
        p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let instrument=graph.nodes.first{if case .instrument=$0.content{return true};return false}!
        let router=MusicCircle(name:"라우터",content:.router(AudioRouter()));graph.nodes.append(router)
        try SectionGraphEditing.set(graph,useID:p.active.uses[0].id,original:false,in:&p)
        let a=CircleAddress.music(arrangementID:p.active.id,useID:p.active.uses[0].id,nodeID:instrument.id)
        let b=CircleAddress.music(arrangementID:p.active.id,useID:p.active.uses[0].id,nodeID:router.id)
        let group=try HierarchyEditing.group([a,b],name:"음색 그룹",in:&p)
        return (p,group,.init(node:a,portID:CirclePort.audioOutput),.init(node:b,portID:AudioRouter.output2))
    }
    func expose(_ target:CirclePortEndpoint,group:CircleAddress,name:String="신스 출력",id:String?=nil,in p:inout Project)throws->String {
        try GroupPortEditing.set(group:group,target:target,name:name,id:id,projectID:p.id,
                                 expectedMusicRevision:p.musicRevision,expectedLayoutRevision:p.portLayout?.revision ?? 0,in:&p)
    }
    func remove(_ id:String,group:CircleAddress,in p:inout Project)throws {
        try GroupPortEditing.remove(group:group,portID:id,projectID:p.id,expectedMusicRevision:p.musicRevision,
                                    expectedLayoutRevision:p.portLayout?.revision ?? 0,in:&p)
    }
    func testExplicitAliasKeepsRealDirectionSignalAndSeparateGeometry()throws {
        var (p,group,a,b)=try fixture();let before=p
        let one=try expose(a,group:group,in:&p),two=try expose(b,group:group,name:"두 번째 출력",in:&p)
        let ports=try CirclePortCatalog.ports(at:group,in:p)
        XCTAssertEqual(ports.map(\.id),[one,two]);XCTAssertEqual(ports.map(\.bindingTarget),[a,b])
        XCTAssertTrue(ports.allSatisfy{$0.direction == .output && $0.signal == .audio && $0.policy == .broadcast})
        XCTAssertEqual(try GroupPortEditing.resolve(.init(node:group,portID:two),in:p),b)
        for octant in PortOctant.allCases {
            let x=try CirclePortGeometry.anchor(center:Point(),radius:100,port:ports[0],octant:octant)
            let y=try CirclePortGeometry.anchor(center:Point(),radius:100,port:ports[1],octant:octant)
            XCTAssertEqual(hypot(x.x-y.x,x.y-y.y),44,accuracy:1e-8)
        }
        var stripped=p;stripped.portLayout=nil;XCTAssertEqual(stripped,before)
        XCTAssertTrue(try XCTUnwrap(HierarchySceneBuilder.build(p).node(group)).providesOutput)
    }
    func testAlbumMovementSectionAndSoundGroupsResolveWithinTheirOwners()throws {
        var (p,_,_,_)=try fixture()
        let song=try XCTUnwrap(p.album?.children.first)
        var container=Composition(name:"악장 묶음");container.children=[song]
        p.album?.compositions.append(container);p.album?.children=[container.id]
        let signal=try XCTUnwrap(p.signal.nodes.first { CirclePort.ports(for:$0).contains{$0.direction == .output} })
        let scopes:[(CircleAddress,CircleAddress,String)]=[
            (.album,.composition(container.id),CirclePort.flowOutput),
            (.composition(container.id),.composition(song),CirclePort.flowOutput),
            (.composition(song),.section(arrangementID:p.active.id,useID:p.active.uses[0].id),CirclePort.flowOutput),
            (.sound,.signal(signal.id),CirclePort.audioOutput)]
        for (parent,member,portID) in scopes {
            let group=CanvasGroup(name:"경계",members:[try XCTUnwrap(HierarchyEditing.memberID(member))])
            try HierarchyEditing.editLayout(parent,in:&p){$0.groups.append(group)}
            let address=CircleAddress.group(parent:parent,id:group.id)
            let endpoint=CirclePortEndpoint(node:member,portID:portID),before=p
            let id=try expose(endpoint,group:address,in:&p)
            XCTAssertEqual(try GroupPortEditing.members(of:address,in:p),[member])
            XCTAssertEqual(try GroupPortEditing.resolve(.init(node:address,portID:id),in:p),endpoint)
            let ports=try AgentPortEditing.snapshot(at:address,in:p).ports
            XCTAssertEqual(ports.count,1);XCTAssertEqual(ports.first?.bindingTarget,endpoint)
            var stripped=p;stripped.portLayout=before.portLayout;XCTAssertEqual(stripped,before)
            try ProjectStore.validateStructure(p)
        }
    }
    func testRenameDuplicateRemoveAndLayoutUndoPreserveMusicAndIdentity()throws {
        var (p,group,target,other)=try fixture()
        let id=try expose(target,group:group,in:&p),before=p
        XCTAssertEqual(try expose(target,group:group,name:"중복 이름",in:&p),id);XCTAssertEqual(p,before)
        XCTAssertThrowsError(try expose(other,group:group,id:id,in:&p));XCTAssertEqual(p,before)
        XCTAssertEqual(try expose(target,group:group,name:"넓은 신스",id:id,in:&p),id)
        XCTAssertEqual(p.portLayout?.revision,2);XCTAssertEqual(p.musicRevision,before.musicRevision)
        let renamed=p
        try remove(id,group:group,in:&p)
        XCTAssertEqual(try CirclePortCatalog.connections(in:p),try CirclePortCatalog.connections(in:before))
        XCTAssertTrue(try CirclePortCatalog.ports(at:group,in:p).isEmpty)
        XCTAssertThrowsError(try GroupPortEditing.resolve(.init(node:group,portID:id),in:p))
        p.name="새 음악 이름";p.musicRevision+=1
        let restored=try CircleHistory.restore(renamed,layoutOnly:true,current:p)
        XCTAssertEqual(restored.name,p.name);XCTAssertEqual(restored.musicRevision,p.musicRevision)
        XCTAssertEqual(restored.portLayout?.bindings,renamed.portLayout?.bindings)
        XCTAssertEqual(restored.portLayout?.revision,4)
    }
    func testCollapsedSceneProjectsOnlyExplicitAliasWithoutChangingLogicalCable()throws {
        var (p,group,target,_)=try fixture();let id=try expose(target,group:group,in:&p)
        let connection=try XCTUnwrap(CirclePortCatalog.connections(in:p).first{$0.from==target})
        let before=p
        guard case .group(let parent,let groupID)=group else {return XCTFail()}
        try HierarchyEditing.editLayout(parent,in:&p){layout in layout.groups[layout.groups.firstIndex{$0.id==groupID}!].collapsed=true}
        let scene=try HierarchySceneBuilder.build(p),edge=try XCTUnwrap(scene.edges.first{$0.connectionID==connection.id})
        XCTAssertNil(scene.node(target.node));XCTAssertEqual(edge.from,group);XCTAssertEqual(edge.fromPortID,id)
        XCTAssertEqual(edge.connectionID?.from,target.node);XCTAssertEqual(try CirclePortCatalog.connections(in:p),try CirclePortCatalog.connections(in:before))
        let snapshot=try AgentPortEditing.snapshot(at:group,in:p)
        XCTAssertEqual(snapshot.connections.map(\.connection),[connection]);XCTAssertEqual(snapshot.bindings?.count,1)
        try remove(id,group:group,in:&p)
        let unbound=try XCTUnwrap(HierarchySceneBuilder.build(p).edges.first{$0.connectionID==connection.id})
        XCTAssertEqual(unbound.fromPortID,target.portID);XCTAssertTrue(try CirclePortCatalog.ports(at:group,in:p).isEmpty)
    }
    func testAliasReverseConnectionAndPlacementGestureUseActualRouterBus()throws {
        var (p,group,_,target)=try fixture();let id=try expose(target,group:group,in:&p)
        let output=try XCTUnwrap(CirclePortCatalog.connections(in:p).first{if case .music=$0.to.node{return $0.to.portID==CirclePort.audioInput};return false}).to
        let alias=CirclePortEndpoint(node:group,portID:id)
        let edge=try CircleConnectionEditing.connect(output,alias,firstOctant:.northwest,secondOctant:.northeast,in:&p)
        let connection=try XCTUnwrap(CirclePortCatalog.connections(in:p).first{$0.id==edge})
        XCTAssertEqual(connection.from,target);XCTAssertEqual(connection.to,output)
        XCTAssertEqual(p.portLayout?.placement(for:edge),.init(from:.northeast,to:.northwest))
        let before=p
        let gesture=try CircleCableGesture(id:edge,direction:.output,mode:.placement,project:p)
        _=try gesture.apply(to:alias,octant:.south,in:&p)
        XCTAssertEqual(p.musicRevision,before.musicRevision);XCTAssertEqual(p.portLayout?.placement(for:edge).from,.south)
        let stale=try CircleCableGesture(id:edge,direction:.output,mode:.reconnect,project:p)
        try remove(id,group:group,in:&p)
        XCTAssertThrowsError(try stale.apply(to:alias,octant:.east,in:&p))
        XCTAssertEqual(try CirclePortCatalog.connections(in:p),try CirclePortCatalog.connections(in:before))
    }
    func testBindingsDoNotLeakIntoReusedUseAndMissingTargetsStayUnresolved()throws {
        var (p,group,target,_)=try fixture();let id=try expose(target,group:group,in:&p)
        var use=p.active.uses[0];use.id=newID();p.arrangements[p.activeIndex].uses.append(use)
        guard case .group(_,let groupID)=group else{return XCTFail()}
        let other=CircleAddress.group(parent:.section(arrangementID:p.active.id,useID:use.id),id:groupID)
        XCTAssertTrue(try CirclePortCatalog.ports(at:other,in:p).isEmpty)
        XCTAssertThrowsError(try GroupPortEditing.resolve(.init(node:other,portID:id),in:p))
        guard case .music(_,_,let nodeID)=target.node else{return XCTFail()}
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        graph.nodes.removeAll{$0.id==nodeID};graph.edges.removeAll{$0.from==nodeID || $0.to==nodeID}
        try SectionGraphEditing.set(graph,useID:p.active.uses[0].id,original:false,in:&p)
        XCTAssertTrue(try CirclePortCatalog.ports(at:group,in:p).isEmpty)
        XCTAssertEqual(GroupPortEditing.bindings(at:group,in:p).map(\.id),[id])
        try ProjectStore.validateStructure(p)
        XCTAssertThrowsError(try GroupPortEditing.resolve(.init(node:group,portID:id),in:p))
    }
    func testStaleInvalidAndMalformedBindingsFailAtomically()throws {
        var (p,group,target,_)=try fixture();let original=p
        for mismatch in 0..<3 {
            XCTAssertThrowsError(try GroupPortEditing.set(group:group,target:target,name:"출력",projectID:mismatch==0 ? "stale":p.id,
                expectedMusicRevision:p.musicRevision+(mismatch==1 ? 1:0),expectedLayoutRevision:mismatch==2 ? 1:0,in:&p))
            XCTAssertEqual(p,original)
        }
        XCTAssertThrowsError(try expose(target,group:group,name:"  ",in:&p));XCTAssertEqual(p,original)
        var bad=target;bad.portID="missing";XCTAssertThrowsError(try expose(bad,group:group,in:&p))
        bad.node = .signal(p.signal.nodes[0].id);XCTAssertThrowsError(try expose(bad,group:group,in:&p))
        let id=try expose(target,group:group,in:&p)
        var layout=p.portLayout!;layout.bindings!.append(layout.bindings![0]);XCTAssertThrowsError(try layout.validate())
        layout=p.portLayout!;layout.bindings![0].group = .group(parent:.music(arrangementID:"a",useID:"u",nodeID:"n"),id:"g")
        XCTAssertThrowsError(try layout.validate())
        XCTAssertEqual(try GroupPortEditing.resolve(.init(node:group,portID:id),in:p),target)
    }
    func testAgentWireMetadataCommandsAndLegacySaveRestore()throws {
        var (p,group,target,_)=try fixture()
        var r=AgentRequest(method:"set_group_port");r.projectID=p.id;r.expectedRevision=p.musicRevision
        var args=AgentArguments();args.node=group;args.target=target;args.name="まとめ";args.expectedLayoutRevision=0;r.arguments=args
        r=try JSONDecoder().decode(AgentRequest.self,from:JSONEncoder().encode(r))
        let edited=try AgentPortEditing.apply(r,to:p);XCTAssertNotNil(edited.portID);p=edited.project
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("group-port-\(newID()).circlr")
        defer{try? FileManager.default.removeItem(at:url)}
        let saved=try ProjectStore.save(p,to:url,mediaRoot:nil),loaded=try ProjectStore.load(url)
        XCTAssertEqual(saved,loaded.project);XCTAssertEqual(loaded.project.musicRevision,r.expectedRevision)
        let legacy=try JSONDecoder().decode(CirclePortLayout.self,from:Data(#"{"revision":0,"connections":[]}"#.utf8))
        XCTAssertNil(legacy.bindings)
        r.method="remove_group_port";r.arguments?.target=nil;r.arguments?.portID=edited.portID;r.arguments?.expectedLayoutRevision=p.portLayout!.revision
        let removed=try AgentPortEditing.apply(r,to:p);XCTAssertNil(removed.project.portLayout?.bindings)
        XCTAssertEqual(removed.project.musicRevision,p.musicRevision)
    }
    func testSidechainAliasRetainsDetectorRoleAndRejectsMIDIMismatch()throws {
        var (p,group,a,_)=try fixture()
        let compressor=MusicCircle(name:"컴프레서",content:.effect(Effect(.compressor)))
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        graph.nodes.append(compressor)
        guard case .group(_,let groupID)=group else{return XCTFail()}
        graph.layout.groups[graph.layout.groups.firstIndex{$0.id==groupID}!].members.append(compressor.id)
        try SectionGraphEditing.set(graph,useID:p.active.uses[0].id,original:false,in:&p)
        let target=CirclePortEndpoint(node:.music(arrangementID:p.active.id,useID:p.active.uses[0].id,nodeID:compressor.id),portID:CirclePort.sidechainInput)
        let id=try expose(target,group:group,name:"덕킹 입력",in:&p),alias=CirclePortEndpoint(node:group,portID:id)
        let port=try XCTUnwrap(CirclePortCatalog.ports(at:group,in:p).first)
        XCTAssertTrue(port.isSidechain);XCTAssertEqual(port.direction,.input);XCTAssertEqual(port.policy,.audioSum)
        XCTAssertTrue(try CirclePortCatalog.normalize(alias,a,in:p).sidechain)
        let midi=graph.nodes.first{if case .midi=$0.content{return true};return false}!
        let wrong=CirclePortEndpoint(node:.music(arrangementID:p.active.id,useID:p.active.uses[0].id,nodeID:midi.id),portID:CirclePort.midiOutput)
        XCTAssertThrowsError(try CirclePortCatalog.normalize(alias,wrong,in:p))
    }
}
