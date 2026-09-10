import XCTest
@testable import CirclrCore
@testable import CirclrAudio

final class SynthCutoffAutomationTests:XCTestCase {
    private func plans(_ points:[AutomationPoint],clock:MusicClock,enabled:Bool=true)throws->[AutomationPlan] {
        var node=MusicCircle(name:"신스",content:.instrument(trackID:"synth"))
        node.automation=[AutomationLane(parameter:.synthCutoff,points:points,enabled:enabled)]
        var context=MusicContext();context.tempo=120
        return try AutomationCompiler.compile(node,context:context,clock:clock)
    }
    func testCompiledHzLinearHoldAndTailUseExactSampleTime()throws {
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(bars:1,context:context)
        var cursor=try SynthCutoffCursor(plans([.init(beat:1,value:400),.init(beat:3,value:6400)],clock:clock))
        XCTAssertEqual(cursor.value(at:0),400)
        XCTAssertEqual(cursor.value(at:1),3400,accuracy:1e-10)
        XCTAssertEqual(cursor.value(at:clock.seconds+2),6400)
        cursor=try SynthCutoffCursor(plans([.init(beat:0,value:400,shape:.hold),.init(beat:1,value:6400)],clock:clock))
        XCTAssertEqual(cursor.value(at:0.5-1/PCM.rate),400)
        XCTAssertEqual(cursor.value(at:0.5),6400)
        XCTAssertEqual(cursor.value(at:clock.seconds+1),6400)
    }
    func testConstantAndDisabledPlansPreserveFixedPatchPCMForEveryEngine()throws {
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(bars:1,context:context)
        let notes=[Note(beat:0,length:1.75,pitch:60,velocity:100),Note(beat:0.25,length:2,pitch:67,velocity:85)]
        for version in [1,2,3] {
            var patch=SynthPatch(.pad);patch.engineVersion=version;patch.cutoff=400
            let fixed=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.5)
            let constant=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.5,
                automation:plans([.init(beat:0,value:400)],clock:clock))
            let disabled=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.5,
                automation:plans([.init(beat:0,value:12000)],clock:clock,enabled:false))
            XCTAssertEqual(fixed.left,constant.left,"engine \(version)");XCTAssertEqual(fixed.right,constant.right)
            XCTAssertEqual(fixed.left,disabled.left);XCTAssertEqual(fixed.right,disabled.right)
        }
    }
    func testCutoffIsNotAppliedAsPostPCMFilterAndRejectsInvalidSpans()throws {
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(bars:1,context:context)
        let cutoff=try plans([.init(beat:0,value:400),.init(beat:4,value:6400)],clock:clock)
        var pcm=PCM(frames:64);pcm.left=Array(repeating:0.25,count:64);pcm.right=Array(repeating:-0.5,count:64)
        let dry=pcm;try AutomationDSP.apply(cutoff,to:&pcm)
        XCTAssertEqual(pcm.left,dry.left);XCTAssertEqual(pcm.right,dry.right)
        XCTAssertThrowsError(try SynthCutoffCursor(cutoff+cutoff))
        var invalid=cutoff;invalid[0].spans[0].from = .nan
        XCTAssertThrowsError(try SynthCutoffCursor(invalid))
    }
    func testSectionSweepFollowsParentTempoChangeThroughInstrumentRender()async throws {
        var project=Project();project.global.tempo=120
        _=project.addTrack(name:"템포 필터");_=project.addSection(name:"템포 변화",at:Point(),bars:1)
        project.tracks[0].instrument = .synthesizer(.pad)
        project.tracks[0].instrument.synth?.cutoff=12000
        project.sections[0].tempoChanges=[TempoChange(beat:2,bpm:60)]
        project.sections[0].lanes[0].notes=[Note(beat:0,length:4,pitch:60,velocity:100)]
        project=try SectionGraphMigration.migrate(project)
        let useID=project.active.uses[0].id
        let instrument=try XCTUnwrap(project.sections[0].graph?.nodes.first{if case .instrument=$0.content{return true};return false})
        XCTAssertEqual(instrument.startBeat,0);XCTAssertNil(instrument.lengthBeats);XCTAssertEqual(instrument.repeatCount,1)
        try AutomationEditing.set(parameter:.synthCutoff,points:[.init(beat:0,value:400),.init(beat:4,value:6400)],
                                  nodeID:instrument.id,useID:useID,in:&project)
        let before=project,use=project.active.uses[0]
        let (section,context,clock)=try ArrangementCompiler.context(project:project,use:use)
        XCTAssertEqual(clock.seconds(at:2),1,accuracy:1e-12);XCTAssertEqual(clock.seconds,3,accuracy:1e-12)
        let plan=try XCTUnwrap(SectionGraphCompiler.compile(project:project,section:section,use:use,context:context,clock:clock))
        let tracks=try await SectionGraphRenderer.render(plan,project:project,root:nil,clock:clock,tail:0.4)
        let actual=try XCTUnwrap(tracks[project.tracks[0].id])
        // Independent expected seconds: 0–2 beats take 1 second, the next 2 take 2 seconds.
        // These spans are constructed from that contract, not copied from the compiled plan.
        let expectedPlan=AutomationPlan(parameter:.synthCutoff,spans:[
            AutomationSpan(start:0,end:1,from:400,to:3400,shape:.linear),
            AutomationSpan(start:1,end:3,from:3400,to:6400,shape:.linear)])
        let notes=project.sections[0].lanes[0].notes,patch=try XCTUnwrap(project.tracks[0].instrument.synth)
        let expected=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.4,automation:[expectedPlan])
        XCTAssertEqual(actual.left,expected.left);XCTAssertEqual(actual.right,expected.right)
        var cursor=try SynthCutoffCursor(plan.automation[instrument.id] ?? [])
        XCTAssertEqual(cursor.value(at:1),3400,accuracy:1e-10)
        XCTAssertEqual(cursor.value(at:2),4900,accuracy:1e-10)
        XCTAssertEqual(cursor.value(at:3.3),6400,accuracy:1e-10)
        // Ignoring the tempo change would finish the sweep at 2 seconds instead of 3.
        let wrongClockPlan=AutomationPlan(parameter:.synthCutoff,spans:[
            AutomationSpan(start:0,end:2,from:400,to:6400,shape:.linear),
            AutomationSpan(start:2,end:3,from:6400,to:6400,shape:.hold)])
        let wrong=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0.4,automation:[wrongClockPlan])
        XCTAssertNotEqual(Array(actual.left[48000..<144000]),Array(wrong.left[48000..<144000]))
        XCTAssertEqual(project,before)
    }
    func testSectionInstrumentConsumesCutoffBeforeGainAndPreservesProject()async throws {
        var project=Project();_=project.addTrack(name:"내장 신스");_=project.addSection(name:"필터",at:Point(),bars:1)
        project.tracks[0].instrument = .synthesizer(.pad)
        project.tracks[0].instrument.synth?.cutoff=12000
        project.sections[0].lanes[0].notes=[Note(beat:0,length:3,pitch:60,velocity:100)]
        project=try SectionGraphMigration.migrate(project)
        let useID=project.active.uses[0].id
        let instrument=try XCTUnwrap(project.sections[0].graph?.nodes.first{if case .instrument=$0.content{return true};return false})
        func render(_ p:Project)async throws->PCM {
            let use=p.active.uses[0],(section,context,clock)=try ArrangementCompiler.context(project:p,use:use)
            let plan=try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:section,use:use,context:context,clock:clock))
            let tracks=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0.25)
            return try XCTUnwrap(tracks[p.tracks[0].id])
        }
        let bright=try await render(project)
        var fixedDark=project;fixedDark.tracks[0].instrument.synth?.cutoff=400
        let expectedDark=try await render(fixedDark)
        try AutomationEditing.set(parameter:.synthCutoff,points:[.init(beat:0,value:400)],nodeID:instrument.id,useID:useID,in:&project)
        let before=project,dark=try await render(project)
        XCTAssertEqual(project,before);XCTAssertNotEqual(dark.left,bright.left)
        XCTAssertEqual(dark.left,expectedDark.left);XCTAssertEqual(dark.right,expectedDark.right)
        try AutomationEditing.set(parameter:.gain,points:[.init(beat:0,value:0.5)],nodeID:instrument.id,useID:useID,in:&project)
        let attenuated=try await render(project)
        XCTAssertEqual(attenuated.left,dark.left.map{$0*0.5});XCTAssertEqual(attenuated.right,dark.right.map{$0*0.5})
        try AutomationEditing.set(parameter:.synthCutoff,enabled:false,nodeID:instrument.id,useID:useID,in:&project)
        try AutomationEditing.set(parameter:.gain,enabled:false,nodeID:instrument.id,useID:useID,in:&project)
        let restored=try await render(project)
        XCTAssertEqual(restored.left,bright.left);XCTAssertEqual(restored.right,bright.right)
    }
}
