import XCTest
@testable import CirclrCore

final class SectionInsertionTests:XCTestCase {
    func fixture()throws->(Project,ID,ID,ID) {
        var p=Project();_ = p.addTrack(name:"건반")
        let a=p.addSection(name:"A",at:Point(),bars:1)
        let b=p.addSection(name:"B",at:Point(1000,0),bars:2)
        try ProjectEditing.connect(from:a,to:b,in:&p)
        p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        return (p,p.activeArrangementID,a,b)
    }
    func testMiddleInsertionCompilesInOrderAndPreservesUnrelatedData()throws {
        var (p,arr,a,b)=try fixture()
        let edge=p.active.edges[0]
        p.arrangements[p.activeIndex].chosenEdges[a]=edge.id
        p.circleColors=[.section(arrangementID:arr,useID:a):CircleColor.Preset.mint.color]
        let other=try AlbumEditing.add(name:"다른 곡",kind:.song,in:&p)
        p.activeArrangementID=try XCTUnwrap(p.album?.composition(other)?.selectedArrangementID)
        let before=p
        let id=try SectionInsertion.insert(arrangementID:arr,afterUseID:a,name:" 새 섹션 ",bars:3,at:Point(500,40),in:&p)
        let target=try XCTUnwrap(p.arrangements.first{$0.id==arr}),use=try XCTUnwrap(target.uses.first{$0.id==id})
        let section=try XCTUnwrap(p.sections.first{$0.id==use.sectionID})
        XCTAssertEqual(section.name,"새 섹션");XCTAssertEqual(section.bars,3)
        XCTAssertEqual(section.lanes.map(\.trackID),p.tracks.map(\.id));XCTAssertNotNil(section.graph)
        XCTAssertEqual(try ArrangementCompiler.compile(p,arrangementID:arr).occurrences.map{ $0.use.id },[a,id,b])
        var expected=before;expected.sections.append(section)
        let ai=try XCTUnwrap(expected.arrangements.firstIndex{$0.id==arr})
        expected.arrangements[ai].uses.insert(use,at:1)
        expected.arrangements[ai].layout.positions[id]=Point(500,40)
        expected.arrangements[ai].edges[0].to=id
        expected.arrangements[ai].edges.append(try XCTUnwrap(target.edges.first{$0.from==id}))
        XCTAssertEqual(p,expected)
        XCTAssertFalse(use.isEnd);XCTAssertEqual(target.startID,a)
        XCTAssertEqual(target.chosenEdges[a],edge.id)
    }
    func testTerminalInsertionTransfersEndAndUndoRedoRestoresDocument()throws {
        var (p,arr,a,b)=try fixture();let before=p
        let id=try SectionInsertion.insert(arrangementID:arr,afterUseID:b,name:"끝",bars:1,at:Point(2000,0),in:&p)
        XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences.map{$0.use.id},[a,b,id])
        XCTAssertFalse(try XCTUnwrap(p.active.uses.first{$0.id==b}).isEnd)
        XCTAssertTrue(try XCTUnwrap(p.active.uses.first{$0.id==id}).isEnd)
        p.musicRevision+=1
        let undone=try CircleHistory.restore(before,layoutOnly:false,current:p)
        var expected=before;expected.musicRevision=p.musicRevision+1
        XCTAssertEqual(undone,expected)
        let redo=try CircleHistory.restore(p,layoutOnly:false,current:undone)
        expected=p;expected.musicRevision=undone.musicRevision+1
        XCTAssertEqual(redo,expected)
    }
    func testBranchLoopLatentEndAndTransitionFailAtomically()throws {
        let (base,arr,a,b)=try fixture()
        var branch=base;let c=branch.addSection(name:"분기",at:Point(),bars:1)
        branch.arrangements[branch.activeIndex].edges.append(FlowEdge(from:a,to:c))
        var loop=base;loop.arrangements[0].edges.append(FlowEdge(from:b,to:a));loop.arrangements[0].uses[1].isEnd=false
        var latent=base;latent.arrangements[0].uses[0].isEnd=true
        var transition=base;transition.arrangements[0].edges[0].transition.length=1
        var hiddenTransition=base;hiddenTransition.arrangements[0].edges[0].transition.effect.amount=0.5
        for (original,issue) in [(branch,SectionInsertionIssue.ambiguousBranch),(loop,.loop),(latent,.invalidStructure),(transition,.transition),(hiddenTransition,.transition)] {
            var p=original
            XCTAssertEqual(SectionInsertion.assess(arrangementID:arr,afterUseID:a,in:p).issue,issue)
            XCTAssertThrowsError(try SectionInsertion.insert(arrangementID:arr,afterUseID:a,name:"새",bars:1,at:Point(),in:&p))
            XCTAssertEqual(p,original)
        }
    }
    func testInputValidationAndForeignUseLeaveEverythingUnchanged()throws {
        var (p,arr,a,_)=try fixture();let before=p
        for name in ["", " \n\t",String(repeating:"가",count:121)] {
            XCTAssertThrowsError(try SectionInsertion.insert(arrangementID:arr,afterUseID:a,name:name,bars:1,at:Point(),in:&p));XCTAssertEqual(p,before)
        }
        for bars in [0,4097] {
            XCTAssertThrowsError(try SectionInsertion.insert(arrangementID:arr,afterUseID:a,name:"새",bars:bars,at:Point(),in:&p));XCTAssertEqual(p,before)
        }
        for point in [Point(.nan,0),Point(0,.infinity),Point(1e7,0)] {
            XCTAssertThrowsError(try SectionInsertion.insert(arrangementID:arr,afterUseID:a,name:"새",bars:1,at:point,in:&p));XCTAssertEqual(p,before)
        }
        XCTAssertEqual(SectionInsertion.assess(arrangementID:"foreign",afterUseID:a,in:p).issue,.missingArrangement)
        XCTAssertEqual(SectionInsertion.assess(arrangementID:arr,afterUseID:"foreign",in:p).issue,.missingSection)
    }
    func testFalseEndWithoutSuccessorMatchesCompilerRejection()throws {
        var p=Project();_ = p.addTrack(name:"건반")
        let a=p.addSection(name:"A",at:Point(),bars:1)
        p.arrangements[p.activeIndex].uses[0].isEnd=false
        let before=p
        XCTAssertThrowsError(try ArrangementCompiler.compile(p))
        XCTAssertEqual(SectionInsertion.assess(arrangementID:p.activeArrangementID,afterUseID:a,in:p).issue,.invalidStructure)
        XCTAssertThrowsError(try SectionInsertion.insert(arrangementID:p.activeArrangementID,afterUseID:a,name:"새",bars:1,at:Point(),in:&p))
        XCTAssertEqual(p,before)
    }
    func testLegacySectionsRemainUnmigratedWhileNewSectionHasGraph()throws {
        var p=Project();_ = p.addTrack(name:"건반")
        let a=p.addSection(name:"원본",at:Point(),bars:1),old=p.sections
        let id=try SectionInsertion.insert(arrangementID:p.activeArrangementID,afterUseID:a,name:"새",bars:1,at:Point(1000,0),in:&p)
        XCTAssertEqual(Array(p.sections.dropLast()),old)
        XCTAssertNotNil(p.sections.last?.graph)
        XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences.map{$0.use.id},[a,id])
    }
    func testAgentInsertionUsesExplicitTargetAndInvalidBatchIsAtomic()throws {
        var (p,arr,a,_)=try fixture();let other=try AlbumEditing.add(name:"다른 곡",kind:.song,in:&p)
        p.activeArrangementID=try XCTUnwrap(p.album?.composition(other)?.selectedArrangementID)
        var insert=AgentOperation("insert_section");insert.arrangementID=arr;insert.useID=a;insert.name="API";insert.bars=2;insert.at=Point(500,0)
        func request(_ operations:[AgentOperation])->AgentRequest {
            var r=AgentRequest(method:"apply");r.projectID=p.id;r.expectedRevision=p.musicRevision
            var args=AgentArguments();args.operations=operations;r.arguments=args;return r
        }
        let transport=try JSONDecoder().decode(AgentRequest.self,from:JSONEncoder().encode(request([insert])))
        let result=try AgentProjectEditing.apply(transport,to:p)
        XCTAssertEqual(result.activeArrangementID,p.activeArrangementID);XCTAssertEqual(result.album,p.album)
        XCTAssertEqual(result.sections.count,p.sections.count+1)
        var invalid=insert;invalid.at=nil
        XCTAssertThrowsError(try AgentProjectEditing.apply(request([insert,invalid]),to:p))
        invalid=insert;invalid.arrangementID=nil
        XCTAssertThrowsError(try AgentProjectEditing.apply(request([invalid]),to:p))
        invalid=insert;invalid.useID=p.active.uses.first?.id ?? "foreign"
        XCTAssertThrowsError(try AgentProjectEditing.apply(request([insert,invalid]),to:p))
        var stale=request([insert]);stale.expectedRevision=p.musicRevision+1
        XCTAssertThrowsError(try AgentProjectEditing.apply(stale,to:p))
    }
}
