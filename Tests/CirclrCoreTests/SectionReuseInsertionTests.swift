import XCTest
@testable import CirclrCore

final class SectionReuseInsertionTests:XCTestCase {
    func fixture()throws->(Project,ID,ID,ID) {
        var p=Project();_ = p.addTrack(name:"신스")
        let a=p.addSection(name:"A",at:Point(),bars:2)
        let b=p.addSection(name:"B",at:Point(1000,0),bars:2)
        try ProjectEditing.connect(from:a,to:b,in:&p)
        p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        return (p,p.activeArrangementID,a,b)
    }
    func testReusedOccurrencePreservesSharedSourceRepeatsOverridesAndOutgoingTransition()throws {
        var (p,arr,a,b)=try fixture()
        p.arrangements[0].uses[0].repeatCount=2
        p.arrangements[0].uses[0].barsOverride=1
        p.arrangements[0].uses[0].gain=0.7
        p.arrangements[0].edges[0].transition.length=0.25
        let edge=p.active.edges[0]
        p.arrangements[0].chosenEdges[a]=edge.id
        let before=p,source=p.active.uses[0]
        let id=try SectionInsertion.reuseAfter(arrangementID:arr,afterUseID:a,at:Point(500,650),in:&p)
        let copied=try XCTUnwrap(p.active.uses.first{$0.id==id})
        var expected=source;expected.id=id;expected.name="A 재사용"
        XCTAssertEqual(copied,expected)
        XCTAssertEqual(p.sections,before.sections)
        var expectedEdge=edge;expectedEdge.from=id
        XCTAssertEqual(p.active.edges.first{$0.id==edge.id},expectedEdge)
        XCTAssertNil(p.active.chosenEdges[a]);XCTAssertEqual(p.active.chosenEdges[id],edge.id)
        XCTAssertEqual(p.active.edges.first{$0.from==a}?.transition,Transition())
        XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences.map{$0.use.id},[a,a,id,id,b])
        let data=try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:data),p)
    }
    func testTerminalAndSingleSectionKeepStartAndTransferEnd()throws {
        var (p,arr,a,b)=try fixture()
        let id=try SectionInsertion.reuseAfter(arrangementID:arr,afterUseID:b,at:Point(2000,0),in:&p)
        XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences.map{$0.use.id},[a,b,id])
        XCTAssertEqual(p.active.startID,a)
        XCTAssertFalse(p.active.uses.first{$0.id==b}!.isEnd)
        XCTAssertTrue(p.active.uses.first{$0.id==id}!.isEnd)
        var single=Project();let first=single.addSection(name:"독주",at:Point(),bars:1)
        let next=try SectionInsertion.reuseAfter(arrangementID:single.activeArrangementID,afterUseID:first,at:Point(1000,0),in:&single)
        XCTAssertEqual(try ArrangementCompiler.compile(single).occurrences.map{$0.use.id},[first,next])
    }
    func testBranchAndInvalidCoordinatesDoNotMutate()throws {
        var (p,arr,a,_)=try fixture()
        let c=p.addSection(name:"분기",at:Point(),bars:1)
        p.arrangements[0].edges.append(FlowEdge(from:a,to:c))
        let before=p
        XCTAssertThrowsError(try SectionInsertion.reuseAfter(arrangementID:arr,afterUseID:a,at:Point(),in:&p))
        XCTAssertEqual(p,before)
        XCTAssertThrowsError(try SectionInsertion.reuseAfter(arrangementID:arr,afterUseID:a,at:Point(.nan,0),in:&p))
        XCTAssertEqual(p,before)
    }
    func testInvalidTransitionAndLoopFailWithoutPublishingCandidate()throws {
        let (base,arr,a,b)=try fixture()
        var invalid=base
        invalid.arrangements[0].edges[0].transition.length = -1
        var loop=base
        loop.arrangements[0].edges.append(FlowEdge(from:b,to:a))
        loop.arrangements[0].uses[1].isEnd=false
        for original in [invalid,loop] {
            var project=original
            XCTAssertThrowsError(try SectionInsertion.reuseAfter(arrangementID:arr,afterUseID:a,at:Point(500,650),in:&project))
            XCTAssertEqual(project,original)
        }
    }
    func testOtherArrangementsAndSourcesAreUnchanged()throws {
        var (p,arr,a,_)=try fixture()
        ProjectEditing.duplicateArrangement(in:&p,name:"다른 편곡")
        let other=p.active,sections=p.sections
        _=try SectionInsertion.reuseAfter(arrangementID:arr,afterUseID:a,at:Point(500,650),in:&p)
        XCTAssertEqual(p.active,other);XCTAssertEqual(p.sections,sections)
    }
}
