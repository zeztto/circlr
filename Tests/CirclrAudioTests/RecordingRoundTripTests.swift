import XCTest
import AVFAudio
import CirclrCore
@testable import CirclrAudio

final class RecordingRoundTripTests:XCTestCase {
    func testTakeFinalizationPreservesRouterGroupAndLayoutUndo()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("take-ports-\(newID())")
        defer{try? FileManager.default.removeItem(at:root)}
        var input=PCM(frames:48_000)
        for i in 0..<input.count {input.left[i]=Float(i%127)/2048;input.right[i] = -Float(i%89)/2048}
        let url=root.appendingPathComponent("controlled.wav");try input.writeWAV(url)
        var p=Project();p.global.tempo=240;let track=p.addTrack(name:"통합 녹음");p.tracks[0].gain=1
        let use=p.addSection(name:"한 마디",at:Point(),bars:1);p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        let ai=p.active.id,clock=try MusicClock(bars:1,context:p.global)
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let output=try XCTUnwrap(graph.nodes.first{if case .output=$0.content{return true};return false})
        let midi=try XCTUnwrap(graph.nodes.first{if case .midi=$0.content{return true};return false})
        let incoming=try XCTUnwrap(graph.edges.first{$0.to==output.id})
        let router=MusicCircle(name:"테이크 라우터",content:.router(AudioRouter()));graph.nodes.append(router)
        graph.edges.removeAll{$0.id==incoming.id}
        var routerInput=MusicConnection(from:incoming.from,to:router.id,signal:.audio)
        routerInput.fromPortID=CirclePort.audioOutput;routerInput.toPortID=AudioRouter.input1
        var routerOutput=MusicConnection(from:router.id,to:output.id,signal:.audio)
        routerOutput.fromPortID=AudioRouter.output1;routerOutput.toPortID=CirclePort.audioInput
        graph.edges.append(contentsOf:[routerInput,routerOutput])
        try SectionGraphEditing.set(graph,useID:use,original:false,in:&p)
        let address=CircleAddress.music(arrangementID:ai,useID:use,nodeID:router.id)
        let group=try HierarchyEditing.group([address,.music(arrangementID:ai,useID:use,nodeID:midi.id)],name:"녹음 경계",in:&p)
        let alias=try GroupPortEditing.set(group:group,target:.init(node:address,portID:AudioRouter.output1),name:"녹음 출력",projectID:p.id,expectedMusicRevision:p.musicRevision,expectedLayoutRevision:0,in:&p)
        let original=p,bindings=p.portLayout?.bindings,connections=try CirclePortCatalog.connections(in:p).filter{$0.from.node==address || $0.to.node==address}
        let asset=Asset(name:"통제된 입력",path:url.path,duration:1,sampleRate:PCM.rate)
        _=try AudioTakeEditing.save(asset:asset,projectID:p.id,arrangementID:ai,useID:use,trackID:track,laneID:p.sections[0].lanes[0].id,clock:clock,in:&p)
        XCTAssertEqual(p.portLayout?.bindings,bindings)
        XCTAssertEqual(try CirclePortCatalog.connections(in:p).filter{$0.from.node==address || $0.to.node==address},connections)
        XCTAssertEqual(try GroupPortEditing.resolve(.init(node:group,portID:alias),in:p),.init(node:address,portID:AudioRouter.output1))
        let takeProject=p,rendered=try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0)
        XCTAssertGreaterThan(rendered.mix.peak,0.01)
        try CirclePortLayoutEditing.apply([.init(id:connections[0].id,placement:.init(from:.north,to:.south))],projectID:p.id,expectedMusicRevision:p.musicRevision,expectedLayoutRevision:p.portLayout!.revision,in:&p)
        let restored=try CircleHistory.restore(original,layoutOnly:true,current:p)
        XCTAssertEqual(restored.takes,takeProject.takes);XCTAssertEqual(restored.assets,takeProject.assets)
        XCTAssertEqual(restored.portLayout?.bindings,bindings)
        let package=root.appendingPathComponent("take.circlr")
        _=try ProjectStore.save(restored,to:package,mediaRoot:nil);let loaded=try ProjectStore.load(package)
        let final=try await ArrangementRenderer.render(project:loaded.project,root:loaded.root,plan:ArrangementCompiler.compile(loaded.project),tailSeconds:0)
        XCTAssertEqual(final.mix.left,rendered.mix.left);XCTAssertEqual(final.mix.right,rendered.mix.right)
    }
    /// Controlled callback PCM only; this never opens a microphone or an output device.
    func testCapturedCAFBecomesPortableTakeAndRenderedBounce()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-recording-roundtrip-\(newID())")
        defer{try? FileManager.default.removeItem(at:root)}
        var source=PCM(frames:96_000)
        for i in 0..<source.count {
            source.left[i]=Float(i%127+1)/1024
            source.right[i] = -Float(i%89+1)/1024
        }
        let control=try CaptureControl(),buffer=try source.buffer()
        let writer=try TakeWriter(url:root.appendingPathComponent("captured.caf"),format:buffer.format)
        control.limit(frames:UInt64(source.count));control.append(buffer,to:writer,channels:2)
        control.disable();control.waitForCallbacks();try writer.finish()
        let file=try AVAudioFile(forReading:writer.url)
        XCTAssertEqual(file.length,96_000)
        XCTAssertEqual(file.processingFormat.sampleRate,48_000)
        XCTAssertEqual(file.processingFormat.channelCount,2)
        let readback=try PCM.read(writer.url)
        XCTAssertEqual(readback.left,source.left);XCTAssertEqual(readback.right,source.right)

        var project=Project();let trackID=project.addTrack(name:"녹음 트랙")
        project.tracks[0].gain=1
        let useID=project.addSection(name:"녹음 구간",at:Point(),bars:1)
        project=try SectionGraphMigration.migrate(project)
        let clock=try MusicClock(bars:1,context:project.global)
        let asset=Asset(name:"입력 원본",path:writer.url.path,duration:Double(file.length)/file.processingFormat.sampleRate,sampleRate:file.processingFormat.sampleRate)
        let takeID=try AudioTakeEditing.save(asset:asset,projectID:project.id,arrangementID:project.active.id,useID:useID,trackID:trackID,laneID:project.sections[0].lanes[0].id,clock:clock,in:&project)
        XCTAssertEqual(project.takes?.map(\.id),[takeID])
        let rendered=try await ArrangementRenderer.render(project:project,root:nil,plan:ArrangementCompiler.compile(project),tailSeconds:0)
        XCTAssertEqual(rendered.mix.left,source.left);XCTAssertEqual(rendered.mix.right,source.right)

        let package=root.appendingPathComponent("captured.circlr")
        let saved=try ProjectStore.save(project,to:package,mediaRoot:nil)
        let reopened=try ProjectStore.load(package)
        XCTAssertEqual(reopened.project,saved)
        let embedded=try ProjectStore.assetURL(saved.assets[0],root:package)
        XCTAssertEqual(try ProjectStore.checksum(embedded),try ProjectStore.checksum(writer.url))
        // Rendering must use embedded media after the original capture is no longer present.
        try FileManager.default.removeItem(at:writer.url)
        let portable=try await ArrangementRenderer.render(project:reopened.project,root:reopened.root,plan:ArrangementCompiler.compile(reopened.project),tailSeconds:0)
        XCTAssertEqual(portable.mix.left,source.left);XCTAssertEqual(portable.mix.right,source.right)

        let bounceURL=root.appendingPathComponent("take-bounce.wav")
        try portable.stems[trackID]!.writeWAV(bounceURL)
        var bounced=reopened.project
        let bounceAsset=Asset(name:"녹음 바운스",path:bounceURL.path,duration:clock.seconds,sampleRate:PCM.rate)
        let bounceID=try BounceEditing.apply(asset:bounceAsset,trackID:trackID,useID:useID,bodySeconds:clock.seconds,tailSeconds:0,in:&bounced)
        let after=try await ArrangementRenderer.render(project:bounced,root:reopened.root,plan:ArrangementCompiler.compile(bounced),tailSeconds:0)
        XCTAssertLessThanOrEqual(zip(after.mix.left,source.left).map{abs($0-$1)}.max()!,1.0/8_388_608)
        XCTAssertLessThanOrEqual(zip(after.mix.right,source.right).map{abs($0-$1)}.max()!,1.0/8_388_608)
        try BounceEditing.restore(nodeID:bounceID,useID:useID,in:&bounced)
        let restored=try await ArrangementRenderer.render(project:bounced,root:reopened.root,plan:ArrangementCompiler.compile(bounced),tailSeconds:0)
        XCTAssertEqual(restored.mix.left,source.left);XCTAssertEqual(restored.mix.right,source.right)
    }
}
