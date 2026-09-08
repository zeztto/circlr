import XCTest
import CirclrCore
@testable import CirclrAudio

final class CirclePortAudioTests:XCTestCase {
    func testExposedGroupPortsCollapseUndoAndReloadPreservePCM()async throws {
        var p=Project();_=p.addTrack(name:"그룹 신스");p.global.tempo=240
        _=p.addSection(name:"검증",at:Point(),bars:1)
        p.sections[0].lanes[0].notes=[Note(beat:0,length:2,pitch:60,velocity:110)]
        p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        let graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let instrument=graph.nodes.first{if case .instrument=$0.content{return true};return false}!
        let midi=graph.nodes.first{if case .midi=$0.content{return true};return false}!
        func address(_ id:ID)->CircleAddress {.music(arrangementID:p.active.id,useID:p.active.uses[0].id,nodeID:id)}
        let baseline=try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0)
        XCTAssertGreaterThan(baseline.mix.peak,0.001)
        let group=try HierarchyEditing.group([address(instrument.id),address(midi.id)],name:"신스",in:&p)
        let before=p,target=CirclePortEndpoint(node:address(instrument.id),portID:CirclePort.audioOutput)
        _=try GroupPortEditing.set(group:group,target:target,name:"신스 출력",projectID:p.id,expectedMusicRevision:p.musicRevision,expectedLayoutRevision:0,in:&p)
        guard case .group(let parent,let id)=group else{return XCTFail()}
        try HierarchyEditing.editLayout(parent,in:&p){layout in layout.groups[layout.groups.firstIndex{$0.id==id}!].collapsed=true}
        let collapsed=try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0)
        XCTAssertEqual(collapsed.mix.left,baseline.mix.left);XCTAssertEqual(collapsed.mix.right,baseline.mix.right)
        let package=FileManager.default.temporaryDirectory.appendingPathComponent("group-pcm-\(newID()).circlr")
        defer{try? FileManager.default.removeItem(at:package)}
        _=try ProjectStore.save(p,to:package,mediaRoot:nil);let loaded=try ProjectStore.load(package)
        let restored=try CircleHistory.restore(before,layoutOnly:true,current:loaded.project)
        XCTAssertEqual(restored.musicRevision,p.musicRevision);XCTAssertNil(restored.portLayout?.bindings)
        let reopened=try await ArrangementRenderer.render(project:restored,root:loaded.root,plan:ArrangementCompiler.compile(restored),tailSeconds:0)
        XCTAssertEqual(reopened.mix.left,baseline.mix.left);XCTAssertEqual(reopened.mix.right,baseline.mix.right)
    }
    func testAllDirectionChangesAndEmbeddedProjectPreserveRenderedPCM()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-port-pcm-\(newID())")
        defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var pcm=PCM(frames:48_000)
        for i in 0..<pcm.count {pcm.left[i]=Float(sin(Double(i)*2*Double.pi*220/PCM.rate))*0.15;pcm.right[i]=Float(cos(Double(i)*2*Double.pi*330/PCM.rate))*0.1}
        let url=root.appendingPathComponent("source.wav");try pcm.writeWAV(url)
        var p=Project();_=p.addTrack(name:"오디오");p.global.tempo=240
        let useID=p.addSection(name:"기록된 연주",at:Point(),bars:1)
        let asset=Asset(name:"통제된 입력",path:url.path,duration:1,sampleRate:PCM.rate);p.assets=[asset]
        var clip=AudioClip(assetID:asset.id,duration:1);clip.preservesTail=true;p.sections[0].lanes[0].audio=[clip]
        p=try SectionGraphMigration.migrate(p);p.enableAlbum()
        let (_,_,clock)=try ArrangementCompiler.context(project:p,use:p.active.uses[0])
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let source=graph.nodes.first{if case .audio=$0.content{return true};return false}!
        let output=graph.nodes.first{if case .output=$0.content{return true};return false}!
        let compressor=MusicCircle(name:"검출 분리",content:.effect(Effect(.compressor,amount:0.5)))
        graph.nodes.append(compressor);graph.edges.removeAll{$0.to==output.id}
        try SectionGraphEditing.connect(from:source.id,to:compressor.id,in:&graph)
        try SectionGraphEditing.connect(from:source.id,to:compressor.id,sidechain:true,in:&graph)
        try SectionGraphEditing.connect(from:compressor.id,to:output.id,in:&graph)
        try SectionGraphEditing.set(graph,useID:useID,original:false,in:&p)
        let baseline=try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0)
        XCTAssertGreaterThan(baseline.mix.rms,0.01)
        let before=p,connections=try CirclePortCatalog.connections(in:p)
        XCTAssertTrue(connections.contains{$0.sidechain});XCTAssertTrue(connections.contains{$0.to.portID==CirclePort.audioInput})
        for direction in PortOctant.allCases {
            let moves=connections.map{PlacedCircleConnection(id:$0.id,placement:.init(from:direction,to:PortOctant(rawValue:(direction.rawValue+4)%8)!))}
            _=try CirclePortLayoutEditing.apply(moves,projectID:p.id,expectedMusicRevision:p.musicRevision,expectedLayoutRevision:p.portLayout?.revision ?? 0,in:&p)
            let rendered=try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0)
            XCTAssertEqual(rendered.mix.left,baseline.mix.left);XCTAssertEqual(rendered.mix.right,baseline.mix.right)
            var music=p;music.portLayout=nil;XCTAssertEqual(music,before)
            XCTAssertEqual(rendered.plan.duration,clock.seconds)
        }
        let package=root.appendingPathComponent("ports.circlr")
        let saved=try ProjectStore.save(p,to:package,mediaRoot:nil),loaded=try ProjectStore.load(package)
        XCTAssertEqual(loaded.project,saved)
        let reopened=try await ArrangementRenderer.render(project:loaded.project,root:loaded.root,plan:ArrangementCompiler.compile(loaded.project),tailSeconds:0)
        XCTAssertEqual(reopened.mix.left,baseline.mix.left);XCTAssertEqual(reopened.mix.right,baseline.mix.right)
    }
}
