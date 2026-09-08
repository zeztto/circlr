import XCTest
@testable import CirclrCore

final class AudioEditingTests:XCTestCase {
    func fixture()throws->Project {
        var p=Project();_=p.addTrack(name:"오디오");_=p.addSection(name:"편집",at:Point(),bars:4)
        let asset=Asset(name:"원본",path:"source.wav",duration:4,sampleRate:48000);p.assets=[asset]
        var clip=AudioClip(assetID:asset.id,duration:2,beat:1);clip.sourceStart=0.25
        p.sections[0].lanes[0].audio=[clip]
        return try SectionGraphMigration.migrate(p)
    }
    func audio(_ p:Project)throws->(SectionGraph,[AudioClip]) {
        let u=p.active.uses[0],s=p.sections[0]
        return (try XCTUnwrap(SectionGraphEditing.effective(section:s,use:u)),try ArrangementCompiler.effectiveLanes(section:s,use:u)[0].audio)
    }
    func testSplitPreservesSourceFadeRoutingAndSharedUse()throws {
        var p=try fixture();let use=p.active.uses[0].id
        _=try ProjectEditing.reuse(use,in:&p,at:Point(100,0))
        var graph=try audio(p).0;let index=try XCTUnwrap(graph.nodes.firstIndex{if case .audio=$0.content{return true};return false})
        graph.nodes[index].gain=0.7;graph.nodes[index].repeatCount=3
        let id=graph.nodes[index].id,original=p.sections[0]
        let sidechain=MusicCircle(name:"검증 compressor",content:.effect(Effect(.compressor)))
        graph.nodes.append(sidechain)
        var edge=MusicConnection(from:id,to:sidechain.id,signal:.audio);edge.sidechain=true;edge.gain=0.4;graph.edges.append(edge)
        try SectionGraphEditing.set(graph,useID:use,original:false,in:&p)
        let right=try XCTUnwrap(AudioEditing.apply(.split(sourceOffset:0.75),nodeID:id,useID:use,in:&p))
        let (next,clips)=try audio(p)
        XCTAssertEqual(clips.count,2);XCTAssertEqual(clips.map(\.duration),[0.75,1.25]);XCTAssertEqual(clips.map(\.sourceStart),[0.25,1])
        XCTAssertEqual(clips[1].beat,2.5);XCTAssertEqual(clips[0].renderWindow,clips[1].renderWindow)
        XCTAssertEqual(clips[0].loopSourceDuration,2);XCTAssertEqual(clips[0].fadeOut,0)
        XCTAssertEqual(next.nodes.first{$0.id==right}?.repeatCount,3);XCTAssertEqual(next.nodes.first{$0.id==right}?.gain,0.7)
        XCTAssertEqual(next.edges.filter{$0.from==right}.map(\.to),graph.edges.filter{$0.from==id}.map(\.to))
        XCTAssertEqual(next.edges.filter{$0.from==right}.map(\.gain),graph.edges.filter{$0.from==id}.map(\.gain))
        XCTAssertEqual(next.edges.filter{$0.from==right}.map(\.sidechain),graph.edges.filter{$0.from==id}.map(\.sidechain))
        XCTAssertEqual(p.sections[0],original);XCTAssertTrue(p.active.uses[1].laneOverrides.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
    }
    func testEditingSharedClipOnlyChangesSelectedNodeAndInvalidBatchIsAtomic()throws {
        var p=try fixture();var graph=try audio(p).0
        let n=try XCTUnwrap(graph.nodes.first{if case .audio=$0.content{return true};return false})
        var alias=n;alias.id=newID();graph.nodes.append(alias)
        try SectionGraphEditing.set(graph,useID:p.active.uses[0].id,original:false,in:&p)
        let before=p,use=p.active.uses[0].id
        XCTAssertThrowsError(try AudioEditing.apply(.split(sourceOffset:0),nodeID:n.id,useID:use,in:&p));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try AudioEditing.apply(.fade(input:2,output:1),nodeID:n.id,useID:use,in:&p));XCTAssertEqual(p,before)
        _=try AudioEditing.apply(.split(sourceOffset:1),nodeID:n.id,useID:use,in:&p)
        let (next,clips)=try audio(p)
        XCTAssertEqual(clips.count,3);XCTAssertEqual(next.nodes.first{$0.id==alias.id},alias)
        XCTAssertEqual(clips[0],try audio(before).1[0])
    }
    func testBounceSplitFamilyRestoresAllPiecesWithoutDiscardingOriginals()throws {
        var p=try fixture();let use=p.active.uses[0].id
        let asset=Asset(name:"bounce",path:"bounce.wav",duration:4,sampleRate:48000)
        let bounced=try BounceEditing.apply(asset:asset,trackID:p.tracks[0].id,useID:use,bodySeconds:3,tailSeconds:1,in:&p)
        let right=try XCTUnwrap(AudioEditing.apply(.split(sourceOffset:1),nodeID:bounced,useID:use,in:&p))
        try BounceEditing.restore(nodeID:right,useID:use,in:&p)
        let graph=try audio(p).0
        for id in [bounced,right] {XCTAssertEqual(graph.nodes.first{$0.id==id}?.muted,true);XCTAssertFalse(graph.edges.contains{$0.from==id})}
    }
    func testDuplicateFreshIdentityFadeAndDeletePreserveOtherMusic()throws {
        var p=try fixture();let use=p.active.uses[0].id,n=try XCTUnwrap(audio(p).0.nodes.first{if case .audio=$0.content{return true};return false})
        _=try AudioEditing.apply(.fade(input:0.4,output:0.7),nodeID:n.id,useID:use,in:&p)
        let copy=try XCTUnwrap(AudioEditing.apply(.duplicate(beatOffset:nil),nodeID:n.id,useID:use,in:&p))
        let clips=try audio(p).1;XCTAssertEqual(clips.map(\.beat),[1,5]);XCTAssertNotEqual(clips[0].id,clips[1].id);XCTAssertEqual(clips[1].fadeOut,0.7)
        _=try AudioEditing.apply(.delete,nodeID:copy,useID:use,in:&p)
        XCTAssertEqual(try audio(p).1,[clips[0]])
    }
    func testAgentAudioEditsShareCommandAndRejectInvalidBatch()throws {
        let p=try fixture(),node=try XCTUnwrap(audio(p).0.nodes.first{if case .audio=$0.content{return true};return false})
        var op=AgentOperation("edit_audio");op.useID=p.active.uses[0].id;op.nodeID=node.id;op.edit="split";op.sourceOffset=0.5
        var args=AgentArguments();args.operations=[op]
        var request=AgentRequest(method:"apply",id:"audio-qa");request.projectID=p.id;request.expectedRevision=p.musicRevision;request.arguments=args
        let result=try AgentProjectEditing.apply(request,to:p);XCTAssertEqual(try audio(result).1.count,2)
        var bad=op;bad.nodeID="missing";request.arguments?.operations=[op,bad]
        XCTAssertThrowsError(try AgentProjectEditing.apply(request,to:p));XCTAssertEqual(try audio(p).1.count,1)
        request.arguments?.operations=[op];request.expectedRevision = -1
        XCTAssertThrowsError(try AgentProjectEditing.apply(request,to:p))
    }
    func testFragmentDuplicateStartsAtItsActualEndWithoutExtraLoopGap()throws {
        var p=try fixture();let use=p.active.uses[0].id,node=try XCTUnwrap(audio(p).0.nodes.first{if case .audio=$0.content{return true};return false})
        let right=try XCTUnwrap(AudioEditing.apply(.split(sourceOffset:0.75),nodeID:node.id,useID:use,in:&p))
        _=try AudioEditing.apply(.duplicate(beatOffset:nil),nodeID:right,useID:use,in:&p)
        let clips=try audio(p).1;XCTAssertEqual(clips.last?.beat,5)
        XCTAssertEqual(clips.last?.duration,1.25);XCTAssertEqual(clips.last?.loopSourceDuration,2)
    }
    func testReplacementSeparatesSharedClipAndPreservesGraphAndOtherUse()throws {
        var p=try fixture();let use=p.active.uses[0].id
        _=try ProjectEditing.reuse(use,in:&p,at:Point(100,0))
        var graph=try audio(p).0
        let node=try XCTUnwrap(graph.nodes.first{if case .audio=$0.content{return true};return false})
        var alias=node;alias.id=newID();graph.nodes.append(alias)
        try SectionGraphEditing.set(graph,useID:use,original:false,in:&p)
        let before=p,source=try audio(p).1[0]
        var replacement=source;replacement.sourceStart=0.5;replacement.duration=1.5;replacement.gain=0.5;replacement.followsTempo=true;replacement.sourceBPM=90
        XCTAssertEqual(try AudioEditing.apply(.replace(replacement),nodeID:node.id,useID:use,in:&p),node.id)
        let (after,clips)=try audio(p)
        XCTAssertEqual(clips.count,2);XCTAssertEqual(clips[0],source)
        replacement.id=clips[1].id;XCTAssertEqual(clips[1],replacement);XCTAssertNotEqual(replacement.id,source.id)
        var expected=graph
        let i=try XCTUnwrap(expected.nodes.firstIndex{$0.id==node.id})
        if case .audio(let laneID,_)=node.content{expected.nodes[i].content = .audio(laneID:laneID,clipID:replacement.id)}
        XCTAssertEqual(after,expected);XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.active.uses[1],before.active.uses[1])
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
    }
    func testReplacementRejectsInvalidIdentityAndValuesAtomicallyAndNoopDoesNotDetach()throws {
        var p=try fixture(),graph=try audio(p).0
        let node=try XCTUnwrap(graph.nodes.first{if case .audio=$0.content{return true};return false})
        var alias=node;alias.id=newID();graph.nodes.append(alias)
        let use=p.active.uses[0].id
        try SectionGraphEditing.set(graph,useID:use,original:false,in:&p)
        let before=p,source=try audio(p).1[0]
        _=try AudioEditing.apply(.replace(source),nodeID:node.id,useID:use,in:&p);XCTAssertEqual(p,before)
        let invalid:[(inout AudioClip)->Void]=[
            {$0.id=newID()},{$0.assetID=newID()},{$0.sourceStart = -1},{$0.duration=10},{$0.gain=5},{$0.sourceBPM=0},{$0.fadeIn=2;$0.fadeOut=1}
        ]
        for edit in invalid {
            var value=source;edit(&value)
            XCTAssertThrowsError(try AudioEditing.apply(.replace(value),nodeID:node.id,useID:use,in:&p));XCTAssertEqual(p,before)
        }
    }
}
