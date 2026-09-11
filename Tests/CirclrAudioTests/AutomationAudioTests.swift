import XCTest
import CirclrCore
@testable import CirclrAudio

final class AutomationAudioTests:XCTestCase {
    func fixture(_ root:URL)throws->Project {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var pcm=PCM(frames:192000);for i in pcm.left.indices {pcm.left[i]=0.2;pcm.right[i]=0.1}
        let url=root.appendingPathComponent("constant.wav");try pcm.writeWAV(url)
        var p=Project();_=p.addTrack(name:"검증");_=p.addSection(name:"자동화",at:Point(),bars:2)
        let asset=Asset(name:"constant",path:url.path,duration:4,sampleRate:48000);p.assets=[asset]
        var clip=AudioClip(assetID:asset.id,duration:4);clip.preservesTail=true;p.sections[0].lanes[0].audio=[clip]
        return try SectionGraphMigration.migrate(p)
    }
    func render(_ p:Project,outputGain:Bool=true)async throws->[ID:PCM] {
        let u=p.active.uses[0],(s,c,k)=try ArrangementCompiler.context(project:p,use:u)
        return try await SectionGraphRenderer.render(try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:s,use:u,context:c,clock:k)),project:p,root:nil,clock:k,tail:0,applyOutputGain:outputGain)
    }
    func track(_ p:Project,outputGain:Bool=true)async throws->PCM {let rendered=try await render(p,outputGain:outputGain);return try XCTUnwrap(rendered[p.tracks[0].id])}
    func testGainPanDisabledAndSplitPCM()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-automation-\(newID())");defer{try? FileManager.default.removeItem(at:root)}
        var p=try fixture(root);let u=p.active.uses[0].id,n=p.sections[0].graph!.nodes.first{if case .audio=$0.content{return true};return false}!.id
        let dry=try await track(p)
        try AutomationEditing.set(parameter:.gain,points:[.init(beat:0,value:0),.init(beat:8,value:1)],nodeID:n,useID:u,in:&p)
        try AutomationEditing.set(parameter:.pan,points:[.init(beat:0,value:-1),.init(beat:8,value:1)],nodeID:n,useID:u,in:&p)
        let wet=try await track(p)
        XCTAssertEqual(wet.left[0],0);XCTAssertEqual(wet.right[0],0)
        XCTAssertEqual(wet.left[96000],dry.left[96000]*0.5,accuracy:1e-7);XCTAssertEqual(wet.right[96000],dry.right[96000]*0.5,accuracy:1e-7)
        XCTAssertLessThan(wet.left[190000],wet.right[190000])
        _=try AudioEditing.apply(.split(sourceOffset:1.317),nodeID:n,useID:u,in:&p)
        let split=try await track(p);XCTAssertEqual(split.left,wet.left);XCTAssertEqual(split.right,wet.right)
        for node in try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0])).nodes where node.automation != nil {
            for parameter in (node.automation ?? []).map(\.parameter) {try AutomationEditing.set(parameter:parameter,enabled:false,nodeID:node.id,useID:u,in:&p)}
        }
        let off=try await track(p);XCTAssertEqual(off.left,dry.left);XCTAssertEqual(off.right,dry.right)
    }
    func testBounceExcludesOutputAutomationUntilPlayback()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-automation-bounce-\(newID())");defer{try? FileManager.default.removeItem(at:root)}
        var p=try fixture(root);let u=p.active.uses[0].id,t=p.tracks[0].id,n=p.sections[0].graph!.nodes.first{if case .audio=$0.content{return true};return false}!.id,out=p.sections[0].graph!.nodes.first{if case .output=$0.content{return true};return false}!.id
        try AutomationEditing.set(parameter:.gain,points:[.init(beat:0,value:0.8)],nodeID:n,useID:u,in:&p)
        try AutomationEditing.set(parameter:.gain,points:[.init(beat:0,value:0.2),.init(beat:8,value:0.8)],nodeID:out,useID:u,in:&p)
        try AutomationEditing.set(parameter:.pan,points:[.init(beat:0,value:-0.7),.init(beat:8,value:0.7)],nodeID:out,useID:u,in:&p)
        let expected=try await track(p),baked=try await track(p,outputGain:false)
        XCTAssertEqual(baked.left[96000],0.16,accuracy:1e-6)
        let url=root.appendingPathComponent("bounce.wav");try baked.writeWAV(url)
        _=try BounceEditing.apply(asset:Asset(name:"bounce",path:url.path,duration:4,sampleRate:48000),trackID:t,useID:u,bodySeconds:4,tailSeconds:0,in:&p)
        let restored=try await track(p)
        XCTAssertLessThanOrEqual(zip(restored.left,expected.left).map{abs($0-$1)}.max() ?? 0,2e-7)
        XCTAssertLessThanOrEqual(zip(restored.right,expected.right).map{abs($0-$1)}.max() ?? 0,2e-7)
    }
}
