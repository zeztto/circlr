import XCTest
@testable import CirclrCore

final class AudioRouterEditingTests:XCTestCase {
    func fixture()throws->(Project,AudioRouterTarget,ID) {
        var (p,g,_,_,r)=try AudioRouterTests().fixture()
        let index=try XCTUnwrap(g.nodes.firstIndex{$0.id==r.id})
        g.nodes[index].content = .router(AudioRouter(routes:[
            .init(input:AudioRouter.input2,output:AudioRouter.output2,gain:0.333333),
            .init(input:AudioRouter.input1,output:AudioRouter.output1,gain:1),
            .init(input:AudioRouter.input2,output:AudioRouter.output1,gain:0)]))
        let first=p.active.uses[0].id
        try SectionGraphEditing.set(g,useID:first,original:true,in:&p)
        let second=try ProjectEditing.reuse(first,in:&p,at:Point(1000,0))
        return (p,.init(address:.music(arrangementID:p.active.id,useID:first,nodeID:r.id),original:false),second)
    }
    func testGainEditsPreserveRouteOrderAndOnlyTheChosenUse()throws {
        var (p,target,second)=try fixture();let before=p
        let baseline=try AudioRouterEditing.snapshot(target,in:p)
        try AudioRouterEditing.setGain(target,input:AudioRouter.input2,output:AudioRouter.output2,gain:0.6,expectedGain:0.333333,in:&p)
        var expected=baseline;expected.routes[0].gain=0.6
        XCTAssertEqual(try AudioRouterEditing.snapshot(target,in:p),expected)
        XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.tracks,before.tracks);XCTAssertEqual(p.album,before.album)
        XCTAssertEqual(p.active.uses.first{$0.id==second},before.active.uses.first{$0.id==second})
        XCTAssertEqual(p.musicRevision,before.musicRevision)
        try AudioRouterEditing.setGain(target,input:AudioRouter.input1,output:AudioRouter.output2,gain:0.4,in:&p)
        expected.routes.append(.init(input:AudioRouter.input1,output:AudioRouter.output2,gain:0.4))
        XCTAssertEqual(try AudioRouterEditing.snapshot(target,in:p),expected)
        try AudioRouterEditing.setGain(target,input:AudioRouter.input1,output:AudioRouter.output1,gain:0,in:&p)
        expected.routes.remove(at:1)
        XCTAssertEqual(try AudioRouterEditing.snapshot(target,in:p),expected)
    }
    func testSameGainExplicitZeroAndSamePresetAreCompleteNoops()throws {
        var (p,target,_)=try fixture();let before=p
        for route in try AudioRouterEditing.snapshot(target,in:p).routes {
            try AudioRouterEditing.setGain(target,input:route.input,output:route.output,gain:route.gain,expectedGain:route.gain,in:&p)
            XCTAssertEqual(p,before)
        }
        try AudioRouterEditing.setGain(target,input:AudioRouter.input1,output:AudioRouter.output2,gain:0,in:&p)
        let current=try AudioRouterEditing.snapshot(target,in:p)
        try AudioRouterEditing.replace(target,router:current,expected:current,in:&p)
        XCTAssertEqual(p,before)
    }
    func testSharedOriginalDoesNotCopyUnrelatedUseOverrides()throws {
        var (p,target,_)=try fixture()
        let use=p.active.uses[0],section=try XCTUnwrap(p.sections.first{$0.id==use.sectionID})
        var edited=try XCTUnwrap(SectionGraphEditing.effective(section:section,use:use))
        let unrelated=try XCTUnwrap(edited.nodes.firstIndex{if case .mix=$0.content{return true};return false})
        edited.nodes[unrelated].gain=0.37
        try SectionGraphEditing.set(edited,useID:use.id,original:false,in:&p)
        let before=p,original=AudioRouterTarget(address:target.address,original:true)
        let preset=AudioRouter(routes:[.init(input:AudioRouter.input1,output:AudioRouter.output2)])
        try AudioRouterEditing.replace(original,router:preset,in:&p)
        var expected=before
        let routerIndex=try XCTUnwrap(expected.sections[0].graph?.nodes.firstIndex{if case .router=$0.content{return true};return false})
        expected.sections[0].graph!.nodes[routerIndex].content = .router(preset)
        XCTAssertEqual(p,expected)
        XCTAssertNotEqual(p.sections[0].graph!.nodes[unrelated].gain,0.37)
    }
    func testInvalidAndStaleChangesAreAtomic()throws {
        var (p,target,_)=try fixture();let before=p
        for gain in [-0.1,4.1,Double.nan,.infinity] {
            XCTAssertThrowsError(try AudioRouterEditing.setGain(target,input:AudioRouter.input1,output:AudioRouter.output1,gain:gain,in:&p));XCTAssertEqual(p,before)
        }
        XCTAssertThrowsError(try AudioRouterEditing.setGain(target,input:"missing",output:AudioRouter.output1,gain:1,in:&p))
        XCTAssertThrowsError(try AudioRouterEditing.setGain(target,input:AudioRouter.input1,output:AudioRouter.output1,gain:0.5,expectedGain:0.7,in:&p))
        XCTAssertThrowsError(try AudioRouterEditing.replace(target,router:AudioRouter(),expected:AudioRouter(routes:[]),in:&p))
        let duplicate=AudioRouter(routes:[.init(input:AudioRouter.input1,output:AudioRouter.output1),.init(input:AudioRouter.input1,output:AudioRouter.output1)])
        XCTAssertThrowsError(try AudioRouterEditing.replace(target,router:duplicate,in:&p))
        XCTAssertEqual(p,before)
    }
    func testWrongTargetAndAddedOnlyOriginalAreRejected()throws {
        var (p,target,_)=try fixture();let before=p
        guard case .music(let arrangement,let use,let router)=target.address else{return XCTFail()}
        let other=Arrangement(name:"다른 편곡");p.arrangements.append(other)
        for address in [CircleAddress.music(arrangementID:other.id,useID:use,nodeID:router),
                        .music(arrangementID:arrangement,useID:"missing",nodeID:router),
                        .music(arrangementID:arrangement,useID:use,nodeID:"missing"),.album] {
            let current=p,wrong=AudioRouterTarget(address:address,original:false)
            XCTAssertThrowsError(try AudioRouterEditing.snapshot(wrong,in:p))
            XCTAssertThrowsError(try AudioRouterEditing.replace(wrong,router:AudioRouter(),in:&p));XCTAssertEqual(p,current)
        }
        p=before
        var graph=try XCTUnwrap(p.sections[0].graph)
        let added=MusicCircle(name:"이번 사용만",content:.router(AudioRouter()))
        graph.nodes.append(added);try SectionGraphEditing.set(graph,useID:use,original:false,in:&p)
        let current=p,addedTarget=AudioRouterTarget(address:.music(arrangementID:arrangement,useID:use,nodeID:added.id),original:true)
        XCTAssertThrowsError(try AudioRouterEditing.replace(addedTarget,router:AudioRouter(routes:[]),in:&p));XCTAssertEqual(p,current)
    }
    func testFullGraphValidationPreventsPartialCommit()throws {
        var (p,target,second)=try fixture()
        var graph=try XCTUnwrap(p.sections[0].graph)
        let bad=MusicCircle(name:"손상된 use",content:.instrument(trackID:"missing-track"))
        graph.nodes.append(bad)
        let patch=SectionGraphEdits.difference(original:p.sections[0].graph!,edited:graph)
        let secondIndex=try XCTUnwrap(p.active.uses.firstIndex{$0.id==second})
        p.arrangements[p.activeIndex].uses[secondIndex].graphEdits=patch
        let before=p,original=AudioRouterTarget(address:target.address,original:true)
        XCTAssertThrowsError(try AudioRouterEditing.replace(original,router:AudioRouter(routes:[]),in:&p))
        XCTAssertEqual(p,before)
    }
}
