import XCTest
import CirclrCore
@testable import CirclrAudio

final class OutputLevelAudioTests:XCTestCase {
    func fixture(_ root:URL)throws->(Project,ID) {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var pcm=PCM(frames:96000);for i in pcm.left.indices{pcm.left[i]=0.2;pcm.right[i]=0.1}
        let file=root.appendingPathComponent("controlled.wav");try pcm.writeWAV(file)
        var p=Project();_=p.addTrack(name:"오디오");_=p.addSection(name:"첫 사용",at:Point(),bars:1)
        let asset=Asset(name:"controlled",path:file.path,duration:2,sampleRate:48000);p.assets=[asset]
        p.sections[0].lanes[0].audio=[AudioClip(assetID:asset.id,duration:2)]
        p=try SectionGraphMigration.migrate(p)
        var other=p.active.uses[0];other.id=newID();other.name="두 번째 사용";p.arrangements[0].uses.append(other)
        let output=p.sections[0].graph!.nodes.first{if case .output=$0.content{return true};return false}!.id
        return (p,output)
    }
    func render(_ p:Project,_ index:Int)async throws->PCM {
        let plan=try ArrangementCompiler.compile(p,onlyUseID:p.active.uses[index].id)
        return try await ArrangementRenderer.render(project:p,root:nil,plan:plan,tailSeconds:0,includeStems:false).mix
    }
    func testCircleAndTrackLevelAreAppliedOnceAtTheirIntendedScope()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-level-\(newID())");defer{try? FileManager.default.removeItem(at:root)}
        var (p,output)=try fixture(root);let use=p.active.uses[0].id
        let first=try await render(p,0),second=try await render(p,1)
        XCTAssertGreaterThan(first.rms,0.01)
        let target=LevelTarget.circle(.music(arrangementID:p.activeArrangementID,useID:use,nodeID:output),original:false)
        try LevelEditing.set(target,gain:try XCTUnwrap(GainScale.parse("-6")),in:&p)
        let local=try await render(p,0),other=try await render(p,1)
        XCTAssertEqual(local.rms/first.rms,pow(10,-6.0/20),accuracy:1e-6)
        XCTAssertEqual(other.left,second.left);XCTAssertEqual(other.right,second.right)
        try LevelEditing.set(.track(p.tracks[0].id),gain:p.tracks[0].gain*0.5,in:&p)
        let globalFirst=try await render(p,0),globalOther=try await render(p,1)
        XCTAssertEqual(globalFirst.rms/local.rms,0.5,accuracy:1e-6);XCTAssertEqual(globalOther.rms/second.rms,0.5,accuracy:1e-6)
        try LevelEditing.set(target,muted:true,in:&p)
        let mutedFirst=try await render(p,0),audibleOther=try await render(p,1)
        XCTAssertEqual(mutedFirst.peak,0);XCTAssertEqual(audibleOther.left,globalOther.left)
        try LevelEditing.set(.track(p.tracks[0].id),muted:true,in:&p)
        let mutedOther=try await render(p,1);XCTAssertEqual(mutedOther.peak,0)
    }
    func testBounceDoesNotBakeOutputLevelAgain()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-level-bounce-\(newID())");defer{try? FileManager.default.removeItem(at:root)}
        var (p,output)=try fixture(root);let use=p.active.uses[0]
        let target=LevelTarget.circle(.music(arrangementID:p.activeArrangementID,useID:use.id,nodeID:output),original:false)
        try LevelEditing.set(target,gain:0.25,in:&p)
        let (section,context,clock)=try ArrangementCompiler.context(project:p,use:p.active.uses[0])
        let plan=try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:section,use:p.active.uses[0],context:context,clock:clock))
        let normal=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0)
        let baked=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0,applyOutputGain:false)
        let track=p.tracks[0].id
        let a=try XCTUnwrap(normal[track]),b=try XCTUnwrap(baked[track])
        XCTAssertEqual(a.rms/b.rms,0.25,accuracy:1e-6)
    }
}
