import XCTest
@testable import CirclrCore

final class MusicGraphEditingTests:XCTestCase {
    func fixture()throws->(Project,MusicGraphTarget,ID) {
        var p=Project();_ = p.addTrack(name:"악기")
        let first=p.addSection(name:"공유 섹션",at:Point(),bars:1);p.enableAlbum()
        p=try SectionGraphMigration.migrate(p)
        var graph=try XCTUnwrap(p.sections[0].graph)
        var effect=MusicCircle(name:"원본 이펙트",content:.effect(Effect(.delay,amount:0.3,secondary:0.7)))
        effect.gain=0.8;graph.nodes.append(effect)
        let output=try XCTUnwrap(graph.nodes.first{if case .output=$0.content{return true};return false})
        for i in graph.edges.indices where graph.edges[i].to==output.id {graph.edges[i].to=effect.id}
        graph.edges.append(MusicConnection(from:effect.id,to:output.id,signal:.audio))
        try SectionGraphEditing.set(graph,useID:first,original:true,in:&p)
        let second=try ProjectEditing.reuse(first,in:&p,at:Point(1000,0))
        var useGraph=graph
        let index=try XCTUnwrap(useGraph.nodes.firstIndex{$0.id==effect.id})
        useGraph.nodes[index].name="A 이름";useGraph.nodes[index].gain=0.2
        useGraph.nodes[index].content = .effect(Effect(.delay,amount:0.9,secondary:0.1))
        useGraph.layout.positions[effect.id]=Point(777,333)
        useGraph.edges[0].gain=0.25
        let added=MusicCircle(name:"A 추가",content:.effect(Effect(.gain)))
        useGraph.nodes.append(added);useGraph.edges.append(MusicConnection(from:effect.id,to:added.id,signal:.audio))
        try SectionGraphEditing.set(useGraph,useID:first,original:false,in:&p)
        return (p,.init(address:.music(arrangementID:p.active.id,useID:first,nodeID:effect.id),original:true),second)
    }
    func testOriginalNameAndGainEditPreservesUseOverridesAddedNodesAndEdges()throws {
        var (p,target,second)=try fixture();let before=p
        let baseline=try MusicGraphEditing.snapshot(target,in:p)
        var edited=baseline
        let node=try MusicGraphEditing.node(target,in:p),index=try XCTUnwrap(edited.nodes.firstIndex{$0.id==node.id})
        edited.nodes[index].name="새 원본 이름";edited.nodes[index].gain=0.6
        try MusicGraphEditing.replace(target,graph:edited,expected:baseline,in:&p)
        var expected=before;expected.sections[0].graph=edited
        XCTAssertEqual(p,expected)
        XCTAssertEqual(p.active.uses,before.active.uses)
        let local=try MusicGraphEditing.node(.init(address:target.address,original:false),in:p)
        XCTAssertEqual(local.name,"A 이름");XCTAssertEqual(local.gain,0.2)
        let inherited=try MusicGraphEditing.node(.init(address:.music(arrangementID:p.active.id,useID:second,nodeID:node.id),original:false),in:p)
        XCTAssertEqual(inherited.name,"새 원본 이름");XCTAssertEqual(inherited.gain,0.6)
        XCTAssertEqual(inherited.content,node.content)
    }
    func testSingleEffectFieldUsesOriginalBaselineNotEffectiveComposite()throws {
        var (p,target,_)=try fixture();let before=p
        let baseline=try MusicGraphEditing.snapshot(target,in:p),node=try MusicGraphEditing.node(target,in:p)
        guard case .effect(var effect)=node.content else{return XCTFail()}
        XCTAssertEqual(effect.secondary,0.7);effect.amount=0.4
        var edited=baseline
        let index=try XCTUnwrap(edited.nodes.firstIndex{$0.id==node.id})
        edited.nodes[index].content = .effect(effect)
        try MusicGraphEditing.replace(target,graph:edited,expected:baseline,in:&p)
        var expected=before;expected.sections[0].graph=edited
        XCTAssertEqual(p,expected)
        guard case .effect(let result)=try MusicGraphEditing.node(target,in:p).content else{return XCTFail()}
        XCTAssertEqual(result.amount,0.4);XCTAssertEqual(result.secondary,0.7)
    }
    func testSectionScopeUsesEffectiveGraphWithoutTouchingSharedOriginal()throws {
        var (p,music,_)=try fixture();let before=p
        guard case .music(let arrangement,let use,_)=music.address else{return XCTFail()}
        let target=MusicGraphTarget(address:.section(arrangementID:arrangement,useID:use),original:false)
        let baseline=try MusicGraphEditing.snapshot(target,in:p)
        XCTAssertGreaterThan(baseline.nodes.count,p.sections[0].graph!.nodes.count)
        var edited=baseline;edited.layout.pan=Point(23,42)
        try MusicGraphEditing.replace(target,graph:edited,expected:baseline,in:&p)
        XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.active.uses[1],before.active.uses[1])
        XCTAssertEqual(try MusicGraphEditing.snapshot(target,in:p),edited)
        XCTAssertThrowsError(try MusicGraphEditing.node(target,in:p))
    }
    func testStaleNoopAndInvalidGraphDoNotPartiallyCommit()throws {
        var (p,target,_)=try fixture();let before=p
        let baseline=try MusicGraphEditing.snapshot(target,in:p)
        try MusicGraphEditing.replace(target,graph:baseline,expected:baseline,in:&p);XCTAssertEqual(p,before)
        var stale=baseline;stale.layout.pan.x+=1
        XCTAssertThrowsError(try MusicGraphEditing.replace(target,graph:baseline,expected:stale,in:&p));XCTAssertEqual(p,before)
        var invalid=baseline;invalid.nodes.append(invalid.nodes[0])
        XCTAssertThrowsError(try MusicGraphEditing.replace(target,graph:invalid,expected:baseline,in:&p));XCTAssertEqual(p,before)
    }
    func testUseOnlyOriginalAndMissingGraphAreExplicitAtomicErrors()throws {
        var (p,target,_)=try fixture();let before=p
        guard case .music(let arrangement,let use,_)=target.address else{return XCTFail()}
        let added=try XCTUnwrap(p.active.uses[0].graphEdits?.addedNodes.first)
        let originalAdded=MusicGraphTarget(address:.music(arrangementID:arrangement,useID:use,nodeID:added.id),original:true)
        XCTAssertThrowsError(try MusicGraphEditing.node(originalAdded,in:p))
        XCTAssertThrowsError(try MusicGraphEditing.replace(originalAdded,graph:p.sections[0].graph!,expected:p.sections[0].graph!,in:&p))
        XCTAssertEqual(p,before)
        p.sections[0].graph=nil;p.arrangements[p.activeIndex].uses[0].graphEdits=nil
        let missing=p
        for original in [true,false] {
            let section=MusicGraphTarget(address:.section(arrangementID:arrangement,useID:use),original:original)
            XCTAssertThrowsError(try MusicGraphEditing.snapshot(section,in:p))
            XCTAssertThrowsError(try MusicGraphEditing.replace(section,graph:SectionGraph(),expected:SectionGraph(),in:&p))
            XCTAssertEqual(p,missing)
        }
    }
    func testWrongAndAmbiguousScopesAreRejected()throws {
        let (base,target,_)=try fixture()
        guard case .music(let arrangement,let use,let node)=target.address else{return XCTFail()}
        for address in [CircleAddress.album,.music(arrangementID:"foreign",useID:use,nodeID:node),.music(arrangementID:arrangement,useID:"missing",nodeID:node)] {
            XCTAssertThrowsError(try MusicGraphEditing.snapshot(.init(address:address,original:true),in:base))
        }
        var duplicateUse=base;duplicateUse.arrangements[0].uses.append(duplicateUse.arrangements[0].uses[0])
        var duplicateSection=base;duplicateSection.sections.append(duplicateSection.sections[0])
        var duplicateArrangement=base;duplicateArrangement.arrangements.append(duplicateArrangement.arrangements[0])
        for invalid in [duplicateUse,duplicateSection,duplicateArrangement] {
            XCTAssertThrowsError(try MusicGraphEditing.snapshot(target,in:invalid))
        }
    }
}
