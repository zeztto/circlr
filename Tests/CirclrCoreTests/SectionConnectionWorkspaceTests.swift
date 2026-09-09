import XCTest
@testable import CirclrCore

final class SectionConnectionWorkspaceTests:XCTestCase {
    func fixture()throws->Project {
        var p=try AlbumTests().legacySong()
        _=p.addSection(name:"도시의 밤",at:Point(),bars:2)
        _=p.addSection(name:"도시의 밤",at:Point(),bars:2)
        _=p.addSection(name:"긴 섹션 · Nordic 夜の街",at:Point(),bars:2)
        p.enableAlbum();return p
    }
    func id(_ p:Project,_ edge:FlowEdge)->CircleConnectionID {
        .init(edgeID:edge.id,from:.section(arrangementID:p.active.id,useID:edge.from),to:.section(arrangementID:p.active.id,useID:edge.to))
    }
    func testSectionNamesIncludeOrdinalAndOwnerScopeWithoutChangingEndpoints()throws {
        let p=try fixture(),before=p
        let items=p.active.uses.map{use in ConnectionTargetSearch.choice(.init(node:.section(arrangementID:p.active.id,useID:use.id),portID:CirclePort.flowInput),name:"ignored",port:"IN 재생 경로",in:p)}
        XCTAssertEqual(items.map(\.ordinal),[1,2,3,4]);XCTAssertEqual(items[1].title,"#2 · 도시의 밤")
        XCTAssertTrue(items[1].detail.contains(p.album!.compositions[0].name))
        XCTAssertTrue(items[1].detail.contains(p.active.name));XCTAssertEqual(p,before)
        XCTAssertEqual(ConnectionTargetSearch.search(items,query:"도시의 밤".decomposedStringWithCanonicalMapping).map(\.endpoint),[items[1].endpoint,items[2].endpoint])
        XCTAssertEqual(ConnectionTargetSearch.search(items,query:"#３").map(\.endpoint),[items[2].endpoint])
        XCTAssertEqual(ConnectionTargetSearch.search(items,query:"ＮＯＲＤＩＣ 夜").map(\.endpoint),[items[3].endpoint])
        XCTAssertTrue(ConnectionTargetSearch.search(items,query:"#2 Nordic").isEmpty)
        XCTAssertTrue(ConnectionTargetSearch.search(items,query:"#0").isEmpty)
        XCTAssertTrue(ConnectionTargetSearch.search(items,query:"#bad").isEmpty)
    }
    func testManySectionsUseExactOrdinalsAndGenericPortsKeepTheirLabels()throws {
        var p=try fixture();for i in 5...32 {_=p.addSection(name:"섹션 \(i)",at:Point(),bars:1)}
        let items=p.active.uses.map{ConnectionTargetSearch.choice(.init(node:.section(arrangementID:p.active.id,useID:$0.id),portID:CirclePort.flowInput),name:$0.name,port:"IN",in:p)}
        XCTAssertEqual(ConnectionTargetSearch.search(items,query:"#1").map(\.ordinal),[1])
        XCTAssertEqual(ConnectionTargetSearch.search(items,query:"#32").map(\.ordinal),[32])
        let ep=CirclePortEndpoint(node:.signal(p.signal.nodes[0].id),portID:CirclePort.audioOutput)
        let item=ConnectionTargetSearch.choice(ep,name:"저역 버스",port:"OUT 스테레오",in:p)
        XCTAssertEqual(item.endpoint,ep);XCTAssertEqual(item.title,"저역 버스");XCTAssertEqual(item.detail,"OUT 스테레오");XCTAssertNil(item.ordinal)
        XCTAssertEqual(ConnectionTargetSearch.search([item],query:"저역 OUT"),[item]);XCTAssertTrue(ConnectionTargetSearch.search([item],query:"#1").isEmpty)
    }
    func testSingleConnectionAutomaticallySelectedAndNoOpMatchesCompiler()throws {
        var p=try fixture();let a=p.active.uses[0].id,b=p.active.uses[1].id
        try ProjectEditing.connect(from:a,to:b,in:&p);let edge=p.active.edges.last!,key=id(p,edge),before=p
        XCTAssertNil(p.active.chosenEdges[a]);XCTAssertTrue(SectionFlowSelection.isSelected(key,in:p))
        XCTAssertFalse(try SectionFlowSelection.choose(key,in:&p));XCTAssertEqual(p,before)
        XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences.count,2)
    }
    func testBranchSelectionOnlyEditsOwnerAndCompilerFollowsChosenEdge()throws {
        var p=try fixture();let a=p.active.uses[0].id
        try ProjectEditing.connect(from:a,to:p.active.uses[1].id,in:&p)
        try ProjectEditing.connect(from:a,to:p.active.uses[2].id,in:&p)
        let edge=p.active.edges.last!,key=id(p,edge),ai=p.activeIndex
        p.arrangements[ai].edges[p.active.edges.count-1].transition.effect=Effect(.lowpass,amount:0.3)
        XCTAssertThrowsError(try ArrangementCompiler.compile(p))
        let first=p.activeArrangementID;ProjectEditing.duplicateArrangement(in:&p,name:"별도 편곡");let before=p
        XCTAssertTrue(try SectionFlowSelection.choose(key,in:&p))
        var expected=before;expected.arrangements[ai].chosenEdges[a]=edge.id;expected.arrangements[ai].uses[0].isEnd=false
        XCTAssertEqual(p,expected);XCTAssertEqual(p.activeArrangementID,before.activeArrangementID)
        XCTAssertTrue(SectionFlowSelection.isSelected(key,in:p))
        let plan=try ArrangementCompiler.compile(p,arrangementID:first)
        XCTAssertEqual(plan.occurrences.count,2);XCTAssertEqual(plan.occurrences.last?.use.id,edge.to)
        let after=p;XCTAssertFalse(try SectionFlowSelection.choose(key,in:&p));XCTAssertEqual(p,after)
    }
    func testEndSectionMustResumeExplicitlyEvenWhenChosenEdgeExists()throws {
        var p=try fixture();let a=p.active.uses[0].id
        try ProjectEditing.connect(from:a,to:p.active.uses[1].id,in:&p);let edge=p.active.edges[0],key=id(p,edge)
        p.arrangements[p.activeIndex].uses[0].isEnd=true;p.arrangements[p.activeIndex].chosenEdges[a]=edge.id
        XCTAssertFalse(SectionFlowSelection.isSelected(key,in:p));XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences.count,1)
        XCTAssertTrue(try SectionFlowSelection.choose(key,in:&p));XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences.count,2)
    }
    func testRemovedCrossArrangementAndWrongEndpointRejectAtomically()throws {
        var p=try fixture();try ProjectEditing.connect(from:p.active.uses[0].id,to:p.active.uses[1].id,in:&p)
        let key=id(p,p.active.edges[0]),before=p
        let bad=[CircleConnectionID(edgeID:"missing",from:key.from,to:key.to),
                 CircleConnectionID(edgeID:key.edgeID,from:key.from,to:.section(arrangementID:"other",useID:p.active.uses[1].id)),
                 CircleConnectionID(edgeID:key.edgeID,from:key.from,to:.section(arrangementID:p.active.id,useID:p.active.uses[2].id))]
        for value in bad {XCTAssertNil(SectionFlowSelection.edge(value,in:p));XCTAssertThrowsError(try SectionFlowSelection.choose(value,in:&p));XCTAssertEqual(p,before)}
        try CircleConnectionEditing.disconnect(key,in:&p);let removed=p
        XCTAssertThrowsError(try SectionFlowSelection.choose(key,in:&p));XCTAssertEqual(p,removed)
    }
}
