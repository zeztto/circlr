import XCTest
import CirclrCore
@testable import CirclrAudio

final class SynthQualityTests:XCTestCase {
    func testEngineThreeParametersRoundTripAndRejectUnsupportedLegacyVoices() throws {
        for voice in SynthVoice.allCases {
            var patch=SynthPatch(voice);patch.character=0.83;patch.motion=0.72
            let restored=try JSONDecoder().decode(SynthPatch.self,from:JSONEncoder().encode(patch))
            XCTAssertEqual(patch,restored);try restored.validate()
            if voice.rawValue>=6 {patch.engineVersion=2;XCTAssertThrowsError(try patch.validate())}
        }
        var p=SynthPatch();p.motion = .nan;XCTAssertThrowsError(try p.validate())
        p=SynthPatch();p.character=1.01;XCTAssertThrowsError(try p.validate())
    }
    func testLegacyEnginesIgnoreNewControlsAndNewEngineChangesTimbre() throws {
        for version in [1,2] {
            var patch=SynthPatch(.pad);patch.engineVersion=version
            let before=try render(patch)
            patch.character=0;patch.motion=1
            XCTAssertEqual(before.left,try render(patch).left)
        }
        var patch=SynthPatch(.electricPiano);patch.character=0
        let dark=try render(patch);patch.character=1
        XCTAssertNotEqual(dark.left,try render(patch).left)
        patch=SynthPatch(.strings);patch.motion=0
        let still=try render(patch);patch.motion=1
        XCTAssertNotEqual(still.right,try render(patch).right)
        // Voice identity includes articulation, not just one spectral roughness number.
        func sustainRatio(_ voice:SynthVoice)throws->Double {
            let pcm=try render(SynthPatch(voice))
            return pcm.slice(36000..<45000).rms/pcm.slice(4000..<12000).rms
        }
        XCTAssertGreaterThan(try sustainRatio(.organ),0.75)
        XCTAssertLessThan(try sustainRatio(.keys),0.5)
        XCTAssertGreaterThan(try sustainRatio(.electricPiano),try sustainRatio(.keys)*1.3)
        let strings=try render(SynthPatch(.strings))
        XCTAssertGreaterThan(strings.slice(16000..<24000).rms,strings.slice(0..<4000).rms*3)
    }
    func testQueueOverflowReleasesAndEngineCanPlayAgain() throws {
        let engine=try SynthEngine(SynthPatch(.strings))
        func block()->PCM {
            var out=PCM(frames:48000)
            out.left.withUnsafeMutableBufferPointer {l in out.right.withUnsafeMutableBufferPointer {r in engine.render(left:l.baseAddress!,right:r.baseAddress!,frames:48000)}}
            return out
        }
        engine.note(57,velocity:100,on:true);XCTAssertGreaterThan(block().peak,0.01)
        for _ in 0..<2200 {engine.note(57,velocity:0,on:false)}
        _=block();XCTAssertEqual(block().peak,0)
        engine.note(61,velocity:100,on:true);XCTAssertGreaterThan(block().peak,0.01)
    }
    func testBassHarmonicBodyDoesNotCancelItsFundamental() throws {
        var patch=SynthPatch(.bass);patch.cutoff=12000;patch.character=0;patch.sustain=0.7
        let pure=try render(patch,pitch:45).slice(12000..<30000)
        patch.character=1
        let rich=try render(patch,pitch:45).slice(12000..<30000)
        // Increasing the pulse contribution must not cancel the sine body.
        XCTAssertGreaterThan(rich.rms,pure.rms*0.8)
    }
    func testEnsembleIsAdditiveAndBlockIndependentForEveryVoice() throws {
        for voice in SynthVoice.allCases {
            func run(_ block:Int,_ initial:Float)throws->PCM {
                let engine=try SynthEngine(SynthPatch(voice));engine.note(57,velocity:105,on:true)
                var p=PCM(frames:2400);p.left=Array(repeating:initial,count:p.count);p.right=p.left
                var cursor=0
                while cursor<p.count {
                    let n=min(block,p.count-cursor)
                    p.left.withUnsafeMutableBufferPointer {l in p.right.withUnsafeMutableBufferPointer {r in engine.render(left:l.baseAddress!+cursor,right:r.baseAddress!+cursor,frames:UInt32(n))}}
                    cursor+=n
                };return p
            }
            let a=try run(37,0),b=try run(1024,0),added=try run(127,0.1)
            XCTAssertEqual(a.left,b.left);XCTAssertEqual(a.right,b.right)
            for i in a.left.indices {XCTAssertEqual(added.left[i],a.left[i]+0.1,accuracy:0.0000001)}
        }
        XCTAssertLessThanOrEqual(ArrangementRenderer.preparationByteLimit,2_147_483_648)
        XCTAssertLessThanOrEqual(ArrangementRenderer.preparationByteLimit,Double(ProcessInfo.processInfo.physicalMemory)/4)
    }
    func render(_ patch:SynthPatch,pitch:Int=57,velocity:Int=100) throws -> PCM {
        var c=MusicContext();c.tempo=120
        return try ProductionInstrument.synth([Note(beat:0,length:2,pitch:pitch,velocity:velocity)],patch:patch,clock:MusicClock(bars:1,context:c),tail:1)
    }
    func testLegacyPatchDecodingAndRoundTripPreserveEngine() throws {
        let data=Data(#"{"voice":1,"cutoff":900,"attack":0.004,"decay":0.18,"sustain":0.5,"release":0.08,"detune":3}"#.utf8)
        let legacy=try JSONDecoder().decode(SynthPatch.self,from:data)
        XCTAssertEqual(legacy.engineVersion,1)
        let restored=try JSONDecoder().decode(SynthPatch.self,from:JSONEncoder().encode(legacy))
        XCTAssertEqual(try render(legacy).left,try render(restored).left)
        XCTAssertEqual(SynthPatch(.bass).engineVersion,3)
        XCTAssertNotEqual(try render(legacy).left,try render(SynthPatch(.bass)).left)
    }
    func testBassMonoAndKeysVelocityChangeSpectrum() throws {
        let bass=try render(SynthPatch(.bass),pitch:33)
        XCTAssertEqual(bass.left,bass.right)
        var patch=SynthPatch(.keys);patch.cutoff=16000
        let soft=try render(patch,velocity:45),hard=try render(patch,velocity:120)
        func roughness(_ p:PCM)->Double {
            let a=p.slice(300..<9000);return zip(a.left.dropFirst(),a.left).reduce(0.0){$0+pow(Double($1.0-$1.1),2)}/Double(a.count)/pow(a.rms,2)
        }
        XCTAssertGreaterThan(hard.rms,soft.rms*2)
        XCTAssertGreaterThan(roughness(hard),roughness(soft)*1.15)
    }
    func testBlockSizeIndependentPolyphonyAndStealingRemainFinite() throws {
        func run(_ block:Int) throws -> PCM {
            let engine=try SynthEngine(SynthPatch(.supersaw));var p=PCM(frames:9600)
            for pitch in 40..<110 {engine.note(pitch,velocity:100,on:true)}
            var i=0
            while i<p.count {
                let n=min(block,p.count-i)
                p.left.withUnsafeMutableBufferPointer {l in p.right.withUnsafeMutableBufferPointer {r in engine.render(left:l.baseAddress!+i,right:r.baseAddress!+i,frames:UInt32(n))}}
                i+=n
            };return p
        }
        let a=try run(64),b=try run(1024)
        XCTAssertEqual(a.left,b.left);XCTAssertEqual(a.right,b.right)
        XCTAssertTrue(a.left.allSatisfy(\.isFinite));XCTAssertLessThan(a.peak,8)
    }
    func testAllVoicesAcrossKeyboardAndExtremePatchAreFiniteAndRelease() throws {
        for voice in SynthVoice.allCases {
            for pitch in [0,36,84,127] {
                var patch=SynthPatch(voice);patch.resonance=0.9;patch.filterEnvelope=4;patch.cutoff=20000;patch.release=0.1
                let p=try render(patch,pitch:pitch)
                XCTAssertTrue(p.left.allSatisfy(\.isFinite));XCTAssertLessThan(p.peak,1)
                XCTAssertEqual(p.slice(70000..<p.count).peak,0)
            }
        }
    }
    func testLongEffectChainReleasesBuffersAfterFanoutConsumers() async throws {
        var p=Project();let track=p.addTrack(name:"신스");p.global.tempo=240
        _=p.addSection(name:"메모리",at:Point(),bars:1)
        p.sections[0].lanes[0].notes=[Note(beat:0,length:1,pitch:60)]
        p=try SectionGraphMigration.migrate(p)
        var graph=try XCTUnwrap(p.sections[0].graph)
        let output=try XCTUnwrap(graph.nodes.first{if case .output=$0.content{return true};return false})
        let incoming=try XCTUnwrap(graph.edges.first{$0.to==output.id})
        graph.edges.removeAll{$0.id==incoming.id};var previous=incoming.from
        for _ in 0..<80 {let node=MusicCircle(name:"Gain",content:.effect(Effect(.gain,amount:1)));graph.nodes.append(node);graph.edges.append(MusicConnection(from:previous,to:node.id,signal:.audio));previous=node.id}
        graph.edges.append(MusicConnection(from:previous,to:output.id,signal:.audio));p.sections[0].graph=graph
        let use=p.active.uses[0],(_,context,clock)=try ArrangementCompiler.context(project:p,use:use)
        let plan=try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:p.sections[0],use:use,context:context,clock:clock))
        XCTAssertLessThan(SectionGraphRenderer.workingBufferCount(plan),14)
        let rendered=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0)
        XCTAssertGreaterThan(try XCTUnwrap(rendered[track]).peak,0.01)
    }
    func testReverbImpulseIsStereoDenseAndDecaysWithLegacyPreserved() throws {
        var input=PCM(frames:240000);input.left[0]=1;input.right[0]=1
        let effect=Effect(.reverb,amount:0.45,secondary:0.4)
        let p=try NativeDSP.process(input,effect:effect)
        XCTAssertEqual(p.left[0],1);XCTAssertEqual(p.slice(1..<864).peak,0)
        XCTAssertNotEqual(p.left,p.right)
        XCTAssertGreaterThan(p.slice(12000..<24000).rms,p.slice(192000..<240000).rms*20)
        XCTAssertGreaterThan(p.slice(12000..<24000).left.filter{abs($0)>1e-7}.count,11000)
        let legacy=try JSONDecoder().decode(Effect.self,from:Data(#"{"kind":"reverb","amount":0.45,"secondary":0.4}"#.utf8))
        XCTAssertNil(legacy.renderVersion);XCTAssertNotEqual(try NativeDSP.process(input,effect:legacy).left,p.left)
    }
}
