import XCTest
import CirclrCore
@testable import CirclrAudio

final class ProductionTests:XCTestCase {
    func testEverySynthVoiceProducesFiniteStereoAndReleases() throws {
        var context=MusicContext();context.tempo=240
        let clock=try MusicClock(bars:1,context:context)
        for voice in SynthVoice.allCases {
            var patch=SynthPatch(voice);patch.release=0.2
            let pcm=try ProductionInstrument.synth([Note(beat:1,length:1,pitch:60,velocity:100)],patch:patch,clock:clock,tail:0.3)
            XCTAssertEqual(pcm.slice(0..<12000).peak,0)
            XCTAssertGreaterThan(pcm.peak,0.01)
            XCTAssertLessThan(pcm.peak,0.5)
            XCTAssertEqual(pcm.slice(40000..<pcm.count).peak,0)
            XCTAssertTrue(pcm.left.allSatisfy(\.isFinite))
            if voice != .keys && voice != .bass {XCTAssertNotEqual(pcm.left,pcm.right)}
        }
    }
    func testSamplerTranspositionVelocityAndGate() throws {
        var context=MusicContext();context.tempo=120;let clock=try MusicClock(bars:1,context:context)
        var source=PCM(frames:48000);for i in 0..<source.count {source.left[i]=Float(sin(Double(i)*2*Double.pi*220/48000)*0.3);source.right[i]=source.left[i]}
        let pcm=try ProductionInstrument.sampler([Note(beat:0,length:0.25,pitch:72,velocity:64)],source:source,settings:SampleInstrument(assetID:"test",oneShot:true),clock:clock,tail:0)
        XCTAssertGreaterThan(pcm.slice(1000..<12000).rms,0.09)
        XCTAssertEqual(pcm.slice(24000..<pcm.count).peak,0)
        let gated=try ProductionInstrument.sampler([Note(beat:0,length:0.25,pitch:60,velocity:127)],source:source,settings:SampleInstrument(assetID:"test",oneShot:false),clock:clock,tail:0)
        XCTAssertEqual(gated.slice(6000..<gated.count).peak,0)
    }
    func testBounceKeepsEffectOutputTailAndRestorableRouting() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-bounce-\(newID())")
        defer{try? FileManager.default.removeItem(at:root)}
        var p=Project();let track=p.addTrack(name:"신스");p.tracks[0].instrument = .synthesizer(.pluck)
        p.global.tempo=240;let useID=p.addSection(name:"후렴",at:Point(),bars:1)
        p.sections[0].lanes[0].notes=[Note(beat:3.5,length:0.5,pitch:66,velocity:90)]
        p.arrangements[0].uses[0].effects=[Effect(.delay,amount:0.25,secondary:0.6)]
        p=try SectionGraphMigration.migrate(p)
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let oi=try XCTUnwrap(graph.nodes.firstIndex{if case .output=$0.content{return true};return false});graph.nodes[oi].gain=0.6
        try SectionGraphEditing.set(graph,useID:useID,original:false,in:&p)
        let original=p
        let (_,context,clock)=try ArrangementCompiler.context(project:p,use:p.active.uses[0])
        let plan=try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:p.sections[0],use:p.active.uses[0],context:context,clock:clock))
        let full=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:2)
        let preGain=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:2,applyOutputGain:false)
        let audio=try XCTUnwrap(preGain[track]),url=root.appendingPathComponent("bounce.wav");try audio.writeWAV(url)
        let id=try BounceEditing.apply(asset:Asset(name:"바운스",path:url.path,duration:audio.duration,sampleRate:PCM.rate),trackID:track,useID:useID,bodySeconds:clock.seconds,tailSeconds:2,in:&p)
        let afterPlan=try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:p.sections[0],use:p.active.uses[0],context:context,clock:clock))
        let after=try await SectionGraphRenderer.render(afterPlan,project:p,root:nil,clock:clock,tail:2)
        let expected=try XCTUnwrap(full[track]),actual=try XCTUnwrap(after[track])
        // Engine 2 pluck has a quieter release; the tail must remain well above 24-bit noise.
        XCTAssertGreaterThan(actual.slice(48000..<actual.count).rms,0.0001)
        XCTAssertLessThan(zip(expected.left,actual.left).map{abs($0-$1)}.max() ?? 1,0.000001)
        XCTAssertEqual(p.sections[0].lanes[0].notes,original.sections[0].lanes[0].notes)
        let saved=try ProjectStore.save(p,to:root.appendingPathComponent("song.circlr"),mediaRoot:nil)
        XCTAssertNotNil(try SectionGraphEditing.effective(section:saved.sections[0],use:saved.active.uses[0])?.nodes.first{$0.id==id}?.bounce)
        try BounceEditing.restore(nodeID:id,useID:useID,in:&p)
        let restored=try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:p.sections[0],use:p.active.uses[0],context:context,clock:clock))
        let restoredAudio=try await SectionGraphRenderer.render(restored,project:p,root:nil,clock:clock,tail:2)
        XCTAssertEqual(restoredAudio[track]?.left,expected.left)
    }
}
