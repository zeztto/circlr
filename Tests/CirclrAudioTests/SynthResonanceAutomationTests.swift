import XCTest
@testable import CirclrCore
@testable import CirclrAudio

final class SynthResonanceAutomationTests:XCTestCase {
    func plan(_ from:Double,_ to:Double,seconds:Double=1)->AutomationPlan {
        .init(parameter:.synthResonance,spans:[.init(start:0,end:seconds,from:from,to:to,shape:.linear)])
    }
    func testNilDisabledAndConstantPreservePatchAndCutoffOnlyPCM()throws {
        let clock=try MusicClock(beats:2,context:MusicContext()),notes=[Note(beat:0,length:1.5,pitch:60)]
        for version in [2,3] {
            var patch=SynthPatch(.pad);patch.engineVersion=version;patch.resonance=0.37
            let base=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.2)
            let constant=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.2,automation:[plan(0.37,0.37)])
            XCTAssertEqual(base.left,constant.left);XCTAssertEqual(base.right,constant.right)
            var node=MusicCircle(name:"신스",content:.instrument(trackID:"track"))
            node.automation=[.init(parameter:.synthResonance,points:[.init(beat:0,value:0.9)],enabled:false)]
            let disabled=try AutomationCompiler.compile(node,context:MusicContext(),clock:clock)
            let off=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.2,automation:disabled)
            XCTAssertEqual(base.left,off.left);XCTAssertEqual(base.right,off.right)
            // Direct old API and new optional buffers on identical voice pools.
            let a=try SynthEngine(patch),b=try SynthEngine(patch)
            a.note(60,velocity:90,on:true);b.note(60,velocity:90,on:true)
            var al=[Float](repeating:0,count:257),ar=al,bl=al,br=al
            let cutoff=(0..<257).map{400+Double($0)*20}
            cutoff.withUnsafeBufferPointer { c in
                a.render(left:&al,right:&ar,cutoffHz:c.baseAddress!,frames:257)
                b.render(left:&bl,right:&br,cutoffHz:c.baseAddress,resonance:nil,frames:257)
            }
            XCTAssertEqual(al,bl);XCTAssertEqual(ar,br)
        }
    }
    func testConcurrentCutoffBendAndResonanceIsBlockIndependent()throws {
        let clock=try MusicClock(beats:2,context:MusicContext()),notes=[Note(beat:0,length:1.25,pitch:60)]
        let stream=MIDIPerformanceStream(id:"s",sourceNodeID:"node",sourceChannel:0,notes:notes,startSeconds:0,endSeconds:1,initialPitchBend:.init(rawValue:8192,range:.init()),pitchBendStates:[.init(seconds:0.25,state:.init(rawValue:0,range:.init()))])
        let cutoff=AutomationPlan(parameter:.synthCutoff,spans:[.init(start:0,end:1,from:250,to:2000,shape:.linear)])
        for version in [2,3] {
            var patch=SynthPatch(.pad);patch.engineVersion=version;patch.cutoff=1000;patch.release=0.4
            let plans=[cutoff,plan(0,0.9)]
            let base=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.3,automation:plans,performances:[stream],blockSize:31)
            for block in [64,257] {
                let actual=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.3,automation:plans,performances:[stream],blockSize:block)
                XCTAssertEqual(base.left,actual.left);XCTAssertEqual(base.right,actual.right)
            }
            let dry=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.3,automation:[cutoff],performances:[stream],blockSize:31)
            XCTAssertNotEqual(base.left,dry.left)
            XCTAssertTrue(base.left.allSatisfy(\.isFinite));XCTAssertTrue(base.right.allSatisfy(\.isFinite))
            XCTAssertGreaterThan(base.left.map{abs($0)}.max() ?? 0,0)
        }
    }
    func testCursorTailInvalidAndEngineOneAreExplicit()throws {
        var cursor=try SynthResonanceCursor([plan(0,0.9)])
        XCTAssertEqual(cursor.value(at:0.5),0.45,accuracy:1e-12)
        XCTAssertEqual(cursor.value(at:2),0.9)
        for bad in [-0.01,0.91,Double.nan,Double.infinity] {XCTAssertThrowsError(try SynthResonanceCursor([plan(bad,0.9)]))}
        XCTAssertThrowsError(try SynthResonanceCursor([plan(0,0.9),plan(0,0.9)]))
        var patch=SynthPatch(.pad);patch.engineVersion=1
        let clock=try MusicClock(beats:1,context:MusicContext())
        XCTAssertThrowsError(try ProductionInstrument.synth([Note(beat:0,pitch:60)],patch:patch,clock:clock,tail:0,automation:[plan(0,0.9)]))
        var pcm=PCM(frames:20);pcm.left=Array(repeating:0.1,count:20);pcm.right=pcm.left
        let before=pcm;try AutomationDSP.apply([plan(0,0.9)],to:&pcm)
        XCTAssertEqual(before.left,pcm.left);XCTAssertEqual(before.right,pcm.right)
    }
    func testCompiledSourceClockAndTailMatchIndependentSeconds()async throws {
        var p=Project();_=p.addTrack(name:"신스");_=p.addSection(name:"필터",at:Point(),bars:1)
        p.tracks[0].instrument = .synthesizer(.pad)
        p.sections[0].tempoChanges=[.init(beat:2,bpm:60)]
        p.sections[0].lanes[0].notes=[.init(beat:0,length:4,pitch:60)]
        p=try SectionGraphMigration.migrate(p)
        let instrument=try XCTUnwrap(p.sections[0].graph?.nodes.first{if case .instrument=$0.content{return true};return false})
        try AutomationEditing.set(parameter:.synthResonance,points:[.init(beat:0,value:0),.init(beat:4,value:0.9)],nodeID:instrument.id,useID:p.active.uses[0].id,in:&p)
        let before=p,tuple=try ArrangementCompiler.context(project:p,use:p.active.uses[0])
        let signal=try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:tuple.0,use:p.active.uses[0],context:tuple.1,clock:tuple.2))
        let rendered=try await SectionGraphRenderer.render(signal,project:p,root:nil,clock:tuple.2,tail:0.3)
        let actual=try XCTUnwrap(rendered[p.tracks[0].id])
        let expectedPlan=AutomationPlan(parameter:.synthResonance,spans:[.init(start:0,end:1,from:0,to:0.45,shape:.linear),.init(start:1,end:3,from:0.45,to:0.9,shape:.linear)])
        let expected=try ProductionInstrument.synth(p.sections[0].lanes[0].notes,patch:p.tracks[0].instrument.synth!,clock:tuple.2,tail:0.3,automation:[expectedPlan])
        XCTAssertEqual(actual.left,expected.left);XCTAssertEqual(actual.right,expected.right)
        XCTAssertEqual(p,before)
        var cursor=try SynthResonanceCursor(signal.automation[instrument.id] ?? [])
        XCTAssertEqual(cursor.value(at:2),0.675,accuracy:1e-12);XCTAssertEqual(cursor.value(at:3.3),0.9)
    }
    func testDirectUnsupportedBackendsRejectBeforeAudioOrAssetAccess()async throws {
        let clock=try MusicClock(beats:1,context:MusicContext()),notes=[Note(beat:0,pitch:60)]
        for kind in [Instrument.Kind.sampler,.audioUnit,.soundBank,.synthesizer] {
            var instrument=Instrument();instrument.kind=kind
            if kind == .synthesizer {var patch=SynthPatch(.pad);patch.engineVersion=1;instrument.synth=patch}
            do {
                _ = try await ProductionInstrument.render(notes,instrument:instrument,project:Project(),root:nil,clock:clock,tail:0,automation:[plan(0,0.9)])
                XCTFail("Unsupported backend unexpectedly rendered")
            } catch {XCTAssertTrue(error.localizedDescription.lowercased().contains("resonance"))}
        }
    }
    func testCInvalidResonanceSamplesUsePatchWithoutResettingVoices()throws {
        for version in [2,3] {
            var patch=SynthPatch(.pad);patch.engineVersion=version;patch.resonance=0.43
            let a=try SynthEngine(patch),b=try SynthEngine(patch)
            a.note(60,velocity:90,on:true);b.note(60,velocity:90,on:true)
            for value in [Double.nan,Double.infinity,-0.1,0.91,patch.resonance] {
                var al=[Float](repeating:0,count:64),ar=al,bl=al,br=al
                let values=[Double](repeating:value,count:64)
                a.render(left:&al,right:&ar,frames:64)
                values.withUnsafeBufferPointer { v in b.render(left:&bl,right:&br,cutoffHz:nil,resonance:v.baseAddress,frames:64) }
                XCTAssertEqual(al,bl);XCTAssertEqual(ar,br)
            }
        }
    }

}
