import XCTest
@testable import CirclrCore
@testable import CirclrAudio

final class MIDIPitchBendGuardTests:XCTestCase {
    private func fixture(expression:Bool=true)throws->Project {
        var p=Project();_=p.addTrack(name:"피치 연주");_=p.addSection(name:"A",at:Point(),bars:1)
        p.tracks[0].instrument = .synthesizer(.keys)
        p.sections[0].lanes[0].notes=[Note(beat:0,length:1,pitch:60,velocity:100)]
        if expression {p.schemaVersion=5;p.sections[0].lanes[0].pitchBend=MIDIPitchBendSequence()}
        return try SectionGraphMigration.migrate(p)
    }
    private func signal(_ p:Project)throws->(SectionSignalPlan,MusicClock) {
        let use=p.active.uses[0],(section,context,clock)=try ArrangementCompiler.context(project:p,use:use)
        return (try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:section,use:use,context:context,clock:clock)),clock)
    }
    func testExplicitCenterStreamFailsBeforeInstrumentOrHelperRender()async throws {
        var p=try fixture();let (plan,clock)=try signal(p)
        XCTAssertFalse(plan.midiPerformances.values.flatMap{$0}.isEmpty)
        // No valid plugin exists. The expression failure must precede plugin/worker preparation.
        p.tracks[0].instrument.kind = .audioUnit;p.tracks[0].instrument.plugin=nil
        do {_=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0);XCTFail("Expression must not be dropped")}
        catch {XCTAssertTrue(error.localizedDescription.contains("피치 벤드"),error.localizedDescription)}
    }
    func testMutedDisconnectedAndZeroGainPathsDoNotBlockStoredExpression()throws {
        var p=try fixture();let (plan,_)=try signal(p)
        p.tracks[0].instrument.kind = .audioUnit;p.tracks[0].instrument.plugin=nil
        let source=try XCTUnwrap(plan.midiPerformances.first?.key)
        let instrument=try XCTUnwrap(plan.orderedNodes.firstIndex{if case .instrument=$0.content{return true};return false})
        for variant in 0..<4 {
            var changed=plan
            if variant==0 {let i=try XCTUnwrap(changed.orderedNodes.firstIndex{$0.id==source});changed.orderedNodes[i].muted=true}
            if variant==1 {changed.orderedNodes[instrument].muted=true}
            if variant==2 {changed.connections.removeAll{$0.from.nodeID==source}}
            if variant==3 {changed.orderedNodes[instrument].gain=0}
            XCTAssertNoThrow(try SectionGraphRenderer.validatePitchBendSupport(changed,project:p))
        }
    }
    func testRouterUnusedPortAndZeroRouteStaySilentButActiveRouteRejects()async throws {
        var p=try fixture(),graph=try XCTUnwrap(p.sections[0].graph)
        p.tracks[0].instrument.kind = .audioUnit;p.tracks[0].instrument.plugin=nil
        let instrument=try XCTUnwrap(graph.nodes.first{if case .instrument=$0.content{return true};return false})
        let output=try XCTUnwrap(graph.nodes.first{if case .output=$0.content{return true};return false})
        graph.edges.removeAll{$0.signal == .audio}
        let router=MusicCircle(name:"분리 bus",content:.router(AudioRouter()))
        graph.nodes.append(router)
        try SectionGraphEditing.connect(from:instrument.id,to:router.id,toPortID:AudioRouter.input2,in:&graph)
        try SectionGraphEditing.connect(from:router.id,to:output.id,fromPortID:AudioRouter.output1,in:&graph)
        let routerIndex=try XCTUnwrap(graph.nodes.firstIndex{$0.id==router.id})
        for variant in 0..<3 {
            // Variant 0: expression reaches IN 2, but only OUT 1 is connected.
            // Variant 1: IN 2 -> OUT 1 exists with zero gain. Variant 2 makes it audible.
            if variant>0 {graph.nodes[routerIndex].content = .router(AudioRouter(routes:[
                .init(input:AudioRouter.input2,output:AudioRouter.output1,gain:variant==1 ? 0:1)]))}
            p.sections[0].graph=graph
            let (plan,clock)=try signal(p)
            XCTAssertFalse(plan.midiPerformances.values.flatMap{$0}.isEmpty)
            XCTAssertTrue(plan.connections.contains{$0.from.nodeID==instrument.id && $0.to.nodeID==router.id})
            if variant<2 {
                XCTAssertNoThrow(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p))
                let rendered=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0)
                XCTAssertEqual(try XCTUnwrap(rendered[p.tracks[0].id]).peak,0)
            } else {
                XCTAssertThrowsError(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p))
                do {_=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0);XCTFail("Active expression route must reject")}
                catch {XCTAssertTrue(error.localizedDescription.contains("피치 벤드"),error.localizedDescription)}
            }
        }
    }
    func testPreOutputBounceStillRejectsWhenOnlyDestinationIsMuted()throws {
        var p=try fixture();var (plan,_)=try signal(p)
        p.tracks[0].instrument.kind = .soundBank
        p.tracks[0].muted=true;p.tracks[0].gain=0
        let output=try XCTUnwrap(plan.orderedNodes.firstIndex{if case .output=$0.content{return true};return false})
        plan.orderedNodes[output].muted=true;plan.orderedNodes[output].gain=0
        XCTAssertNoThrow(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p))
        XCTAssertThrowsError(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p,applyOutputGain:false))
    }
    func testDirectSectionReturnsPreTrackAudioSoTrackMuteDoesNotBypassGuard()throws {
        var p=try fixture();let (plan,_)=try signal(p)
        p.tracks[0].instrument.kind = .sampler
        p.tracks[0].muted=true;p.tracks[0].gain=0
        XCTAssertThrowsError(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p))
    }
    func testDisconnectedExpressionProducesOnlySilentMixAndExportedStems()async throws {
        var p=try fixture();p.signal.edges=[]
        let prepared=try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0,includeStems:true)
        XCTAssertEqual(prepared.mix.peak,0)
        XCTAssertEqual(prepared.stems.count,p.tracks.count)
        XCTAssertTrue(prepared.stems.values.allSatisfy{$0.peak==0})
        p=try fixture();p.tracks[0].muted=true
        let muted=try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0,includeStems:true)
        XCTAssertEqual(muted.mix.peak,0);XCTAssertTrue(muted.stems.values.allSatisfy{$0.peak==0})
    }
    func testWholeArrangementPreflightRejectsLegacyLaneAndHonorsMute()async throws {
        let p=try fixture();var plan=try ArrangementCompiler.compile(p)
        plan.occurrences[0].signalPlan=nil
        XCTAssertThrowsError(try ArrangementRenderer.validatePitchBendSupport(project:p,plan:plan))
        var rejected=p;rejected.tracks[0].instrument.kind = .audioUnit;rejected.tracks[0].instrument.plugin=nil
        do {_=try await ArrangementRenderer.render(project:rejected,root:nil,plan:plan,tailSeconds:0);XCTFail("Must reject before AU")}
        catch {XCTAssertTrue(error.localizedDescription.contains("피치 벤드"),error.localizedDescription)}
        var muted=p;muted.tracks[0].muted=true
        XCTAssertNoThrow(try ArrangementRenderer.validatePitchBendSupport(project:muted,plan:plan))
        var detached=p;detached.signal.edges=[]
        XCTAssertNoThrow(try ArrangementRenderer.validatePitchBendSupport(project:detached,plan:plan))
        plan.occurrences[0].use.gain=0
        XCTAssertNoThrow(try ArrangementRenderer.validatePitchBendSupport(project:p,plan:plan))
    }
    func testOnlySelectedLegacyAndTransitionPatternsAreGuarded()throws {
        var p=try fixture(expression:false)
        var pattern=RhythmPattern(name:"표현 리듬",trackID:p.tracks[0].id)
        pattern.notes=[Note(beat:0,length:1,pitch:60)];pattern.pitchBend=MIDIPitchBendSequence()
        p.schemaVersion=5;p.patterns=[pattern]
        var plan=try ArrangementCompiler.compile(p);plan.occurrences[0].signalPlan=nil
        XCTAssertNoThrow(try ArrangementRenderer.validatePitchBendSupport(project:p,plan:plan))
        plan.occurrences[0].context.rhythm.patternID=pattern.id
        XCTAssertThrowsError(try ArrangementRenderer.validatePitchBendSupport(project:p,plan:plan))
        plan.occurrences[0].context.rhythm.patternID=nil
        var transition=Transition();transition.patternID=pattern.id
        plan.transitions=[ScheduledTransition(edgeID:"test",transition:transition,start:0,duration:1,
            sourceOccurrenceID:plan.occurrences[0].id,targetOccurrenceID:plan.occurrences[0].id,context:plan.occurrences[0].context)]
        XCTAssertThrowsError(try ArrangementRenderer.validatePitchBendSupport(project:p,plan:plan))
    }
    func testNilExpressionPreservesPCMAndMutedGraphDoesNotFail()async throws {
        let p=try fixture(expression:false),plan=try ArrangementCompiler.compile(p)
        let first=try await ArrangementRenderer.render(project:p,root:nil,plan:plan,tailSeconds:0,includeStems:false)
        let second=try await ArrangementRenderer.render(project:p,root:nil,plan:plan,tailSeconds:0,includeStems:false)
        XCTAssertEqual(first.mix.left,second.mix.left);XCTAssertEqual(first.mix.right,second.mix.right)
        var stored=try fixture();stored.arrangements[stored.activeIndex].uses[0].gain=0
        let muted=try await ArrangementRenderer.render(project:stored,root:nil,plan:ArrangementCompiler.compile(stored),tailSeconds:0,includeStems:false)
        XCTAssertEqual(muted.mix.peak,0)
    }
    func testSynthCenterPacketMatchesLegacyGraphWithoutDuplicateNotes()async throws {
        var p=try fixture();let (expressive,clock)=try signal(p)
        XCTAssertNoThrow(try SectionGraphRenderer.validatePitchBendSupport(expressive,project:p))
        let rendered=try await SectionGraphRenderer.render(expressive,project:p,root:nil,clock:clock,tail:0.1)
        p.sections[0].lanes[0].pitchBend=nil
        let (ordinary,_)=try signal(p)
        let expected=try await SectionGraphRenderer.render(ordinary,project:p,root:nil,clock:clock,tail:0.1)
        let actual=try XCTUnwrap(rendered[p.tracks[0].id]),reference=try XCTUnwrap(expected[p.tracks[0].id])
        XCTAssertGreaterThan(actual.peak,0);XCTAssertEqual(actual.left,reference.left);XCTAssertEqual(actual.right,reference.right)
    }
    func testOnlySynthBackendAcceptsAudiblePerformancePackets()throws {
        var p=try fixture();let (plan,_)=try signal(p)
        XCTAssertNoThrow(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p))
        for kind:Instrument.Kind in [.soundBank,.audioUnit,.sampler] {
            p.tracks[0].instrument.kind=kind
            XCTAssertThrowsError(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p))
        }
    }
}
