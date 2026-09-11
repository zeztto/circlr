import XCTest
@testable import CirclrCore
@testable import CirclrAudio

final class MIDISustainBounceTests: XCTestCase {
    private func fixture() throws -> Project {
        var p=Project();_=p.addTrack(name:"페달 신스");_=p.addSection(name:"연주",at:Point(),bars:1)
        p.tracks[0].instrument = .synthesizer(.pad)
        p.tracks[0].instrument.synth!.engineVersion=2
        p.tracks[0].instrument.synth!.release=0.15
        p.sections[0].lanes[0].notes=[.init(beat:0,length:0.5,pitch:60,velocity:90)]
        p=try SectionGraphMigration.migrate(p)
        var lane=p.sections[0].lanes[0]
        lane.sustain = .init(events:[.init(beat:0,rawValue:127),.init(beat:3,rawValue:0)])
        try ProjectEditing.setLane(lane,for:p.active.uses[0].id,original:true,in:&p)
        return p
    }
    private func render(_ p:Project,root:URL?=nil) async throws -> PCM {
        let use=p.active.uses[0],tuple=try ArrangementCompiler.context(project:p,use:use)
        let plan=try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:tuple.0,use:use,context:tuple.1,clock:tuple.2))
        let outputs=try await SectionGraphRenderer.render(plan,project:p,root:root,clock:tuple.2,tail:0.25)
        return try XCTUnwrap(outputs[p.tracks[0].id])
    }
    func testCompileBounceSaveReopenRestoreKeepsPedalAndAudio() async throws {
        var p=try fixture();let original=p,use=p.active.uses[0].id,track=p.tracks[0].id
        let pcm=try await render(p)
        XCTAssertEqual(p,original);XCTAssertGreaterThan(pcm.peak,0.001);XCTAssertLessThan(pcm.peak,1)
        // Independent authored held key, not a transformed copy of compiled events.
        var held=original;held.sections[0].lanes[0].sustain=nil;held.sections[0].lanes[0].notes[0].length=3
        let reference=try await render(held)
        XCTAssertEqual(pcm.left,reference.left);XCTAssertEqual(pcm.right,reference.right)
        var dry=original;dry.sections[0].lanes[0].sustain=nil
        let released=try await render(dry)
        XCTAssertNotEqual(pcm.left,released.left)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let wav=directory.appendingPathComponent("sustain.wav");try pcm.writeWAV(wav)
        let asset=Asset(name:"페달 바운스",path:wav.path,duration:pcm.duration,sampleRate:PCM.rate)
        let id=try BounceEditing.apply(asset:asset,trackID:track,useID:use,bodySeconds:2,tailSeconds:0.25,in:&p)
        XCTAssertEqual(p.sections[0].lanes[0],original.sections[0].lanes[0])
        let package=directory.appendingPathComponent("song.circlr")
        let saved=try ProjectStore.save(p,to:package,mediaRoot:nil)
        let loaded=try ProjectStore.load(package)
        XCTAssertEqual(loaded.project,saved)
        let cached=try await render(loaded.project,root:loaded.root)
        XCTAssertEqual(cached.count,pcm.count)
        for (actual,expected) in [(cached.left,pcm.left),(cached.right,pcm.right)] {
            let maxError=zip(actual,expected).map{abs($0-$1)}.max() ?? 0
            XCTAssertLessThanOrEqual(maxError,2.0/8_388_608)
        }
        var restored=loaded.project
        try BounceEditing.restore(nodeID:id,useID:use,in:&restored)
        XCTAssertEqual(restored.sections[0].lanes[0],original.sections[0].lanes[0])
        XCTAssertEqual(restored.assets.count,1)
        let rerendered=try await render(restored,root:loaded.root)
        XCTAssertEqual(rerendered.left,pcm.left);XCTAssertEqual(rerendered.right,pcm.right)
    }
    func testArrangementRepeatUsesIsolatedPedalRenders() async throws {
        var p=try fixture();p.arrangements[0].uses[0].repeatCount=2
        let plan=try ArrangementCompiler.compile(p)
        XCTAssertEqual(plan.occurrences.count,2)
        let prepared=try await ArrangementRenderer.render(project:p,root:nil,plan:plan,tailSeconds:0.25,includeStems:true)
        XCTAssertTrue(prepared.mix.left.allSatisfy(\.isFinite));XCTAssertGreaterThan(prepared.peak,0.001)
        XCTAssertEqual(prepared.stems.count,1)
        var held=p;held.sections[0].lanes[0].sustain=nil;held.sections[0].lanes[0].notes[0].length=3
        let reference=try await ArrangementRenderer.render(project:held,root:nil,plan:ArrangementCompiler.compile(held),tailSeconds:0.25,includeStems:true)
        XCTAssertEqual(prepared.mix.left,reference.mix.left);XCTAssertEqual(prepared.mix.right,reference.mix.right)
    }
}
