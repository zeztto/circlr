import XCTest
@testable import CirclrCore
@testable import CirclrAudio

final class MIDISustainGuardTests:XCTestCase {
    private func packet(raw:Int=0,events:[MIDITimedSustainState]=[],pitch:Bool=true,id:String="pedal")->MIDIPerformanceStream {
        .init(id:id,sourceNodeID:"source",sourceChannel:0,notes:[],startSeconds:0,endSeconds:2,
              initialPitchBend:.init(rawValue:8192,range:.init()),pitchBendStates:[],
              initialSustain:.init(rawValue:raw),sustainStates:events,hasPitchBendExpression:pitch)
    }
    func testAllOffIsEffectFreeButDownAndSameTimeReleaseDownAreRejected()throws {
        XCTAssertNoThrow(try MIDIPitchBendRenderer.validateSustain([packet(raw:63,events:[.init(seconds:1,state:.init(rawValue:0))])]))
        for raw in [64,127] {XCTAssertThrowsError(try MIDIPitchBendRenderer.validateSustain([packet(raw:raw)]))}
        XCTAssertThrowsError(try MIDIPitchBendRenderer.validateSustain([packet(events:[
            .init(seconds:1,state:.init(rawValue:64)),.init(seconds:1,state:.init(rawValue:0))])]))
    }
    func testAllOffPacketKeepsLegacySynthPCM()throws {
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(bars:1,context:context),notes=[Note(beat:0,length:1,pitch:60)]
        let patch=SynthPatch()
        let expected=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0)
        let actual=try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:0,performances:[packet(raw:63)])
        XCTAssertEqual(actual.left,expected.left);XCTAssertEqual(actual.right,expected.right)
    }
    func testMalformedPacketsFailEvenWhenTheyNeverPressPedal()throws {
        for raw in [-1,128] {XCTAssertThrowsError(try MIDIPitchBendRenderer.validateSustain([packet(raw:raw)]))}
        for time in [-1,Double.nan,Double.infinity,2] {
            XCTAssertThrowsError(try MIDIPitchBendRenderer.validateSustain([packet(events:[.init(seconds:time,state:.init(rawValue:0))])]))
        }
        XCTAssertThrowsError(try MIDIPitchBendRenderer.validateSustain([packet(events:[.init(seconds:1,state:.init(rawValue:0)),.init(seconds:0.5,state:.init(rawValue:0))])]))
        XCTAssertThrowsError(try MIDIPitchBendRenderer.validateSustain([packet(events:[.init(seconds:1,state:.init(rawValue:128))])]))
        let large=packet(events:Array(repeating:.init(seconds:1,state:.init(rawValue:0)),count:500000))
        let other=packet(events:large.sustainStates,id:"other")
        XCTAssertThrowsError(try MIDIPitchBendRenderer.validateSustain([large,other]))
    }
    func testCombinedPacketBudgetRetainsOneMillionBoundary()throws {
        let states=Array(repeating:MIDITimedSustainState(seconds:1,state:.init(rawValue:0)),count:999999)
        XCTAssertNoThrow(try MIDIPitchBendRenderer.validateSustain([packet(events:states)]))
        XCTAssertThrowsError(try MIDIPitchBendRenderer.validateSustain([packet(events:states+[.init(seconds:1,state:.init(rawValue:0))])]))
    }
    private func fixture()throws->(Project,SectionSignalPlan,MusicClock) {
        var p=Project();_=p.addTrack(name:"pedal");_=p.addSection(name:"A",at:Point(),bars:1)
        p.tracks[0].instrument = .synthesizer(.keys)
        p.sections[0].lanes[0].notes=[.init(beat:0,length:1,pitch:60)]
        p=try SectionGraphMigration.migrate(p)
        let use=p.active.uses[0],(section,context,clock)=try ArrangementCompiler.context(project:p,use:use)
        var plan=try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:section,use:use,context:context,clock:clock))
        let source=try XCTUnwrap(plan.connections.first{$0.signal == .midi}?.from.nodeID)
        plan.midiPerformances[source]=[packet(raw:127)]
        return (p,plan,clock)
    }
    func testActiveSustainRejectsBeforeAUHelperAndDirectSynth()async throws {
        var (p,plan,clock)=try fixture();p.tracks[0].instrument.kind = .audioUnit;p.tracks[0].instrument.plugin=nil
        do {_=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0);XCTFail("Sustain must reject before AU preparation")}
        catch {XCTAssertTrue(error.localizedDescription.contains("Sustain"),error.localizedDescription)}
        XCTAssertThrowsError(try ProductionInstrument.synth([],patch:SynthPatch(),clock:clock,tail:0,performances:[packet(raw:127)]))
    }
    func testMutedDisconnectedAndZeroGainPathsDoNotBlockStoredSustain()throws {
        let (p,plan,_)=try fixture()
        let source=try XCTUnwrap(plan.midiPerformances.keys.first)
        let instrument=try XCTUnwrap(plan.orderedNodes.firstIndex{if case .instrument=$0.content{return true};return false})
        for variant in 0..<5 {
            var muted=plan
            if variant==0 {muted.orderedNodes[try XCTUnwrap(muted.orderedNodes.firstIndex{$0.id==source})].muted=true}
            if variant==1 {muted.orderedNodes[instrument].muted=true}
            if variant==2 {muted.connections.removeAll{$0.from.nodeID==source}}
            if variant==3 {muted.orderedNodes[instrument].gain=0}
            if variant==4 {muted.connections.removeAll{$0.signal == .audio}}
            XCTAssertNoThrow(try SectionGraphRenderer.validatePitchBendSupport(muted,project:p))
        }
    }
    func testAllOffSustainOnlyPacketDoesNotRequireSynthBackend()throws {
        var (p,plan,_)=try fixture()
        let source=try XCTUnwrap(plan.midiPerformances.keys.first)
        for kind:Instrument.Kind in [.audioUnit,.soundBank,.sampler] {
            p.tracks[0].instrument.kind=kind
            plan.midiPerformances[source]=[packet(raw:63,pitch:false)]
            XCTAssertNoThrow(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p))
            plan.midiPerformances[source]=[packet(raw:-1,pitch:false)]
            XCTAssertThrowsError(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p))
            plan.midiPerformances[source]=[packet(raw:63,pitch:true)]
            XCTAssertThrowsError(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p))
        }
    }
    func testPreOutputBounceMustNotHideSustainBehindDestinationMute()throws {
        let (p,plan,_)=try fixture();var muted=plan
        let output=try XCTUnwrap(muted.orderedNodes.firstIndex{if case .output=$0.content{return true};return false})
        muted.orderedNodes[output].muted=true;muted.orderedNodes[output].gain=0
        XCTAssertNoThrow(try SectionGraphRenderer.validatePitchBendSupport(muted,project:p))
        XCTAssertThrowsError(try SectionGraphRenderer.validatePitchBendSupport(muted,project:p,applyOutputGain:false))
    }
    func testUnusedRouterPortAndZeroRouteRenderSilenceButActiveRouteFails()async throws {
        var (p,_,clock)=try fixture();var graph=try XCTUnwrap(p.sections[0].graph)
        let instrument=try XCTUnwrap(graph.nodes.first{if case .instrument=$0.content{return true};return false})
        let output=try XCTUnwrap(graph.nodes.first{if case .output=$0.content{return true};return false})
        graph.edges.removeAll{$0.signal == .audio}
        let router=MusicCircle(name:"bus",content:.router(AudioRouter()));graph.nodes.append(router)
        try SectionGraphEditing.connect(from:instrument.id,to:router.id,toPortID:AudioRouter.input2,in:&graph)
        try SectionGraphEditing.connect(from:router.id,to:output.id,fromPortID:AudioRouter.output1,in:&graph)
        let index=try XCTUnwrap(graph.nodes.firstIndex{$0.id==router.id})
        for variant in 0..<3 {
            if variant>0 {graph.nodes[index].content = .router(AudioRouter(routes:[.init(input:AudioRouter.input2,output:AudioRouter.output1,gain:variant==1 ? 0:1)]))}
            p.sections[0].graph=graph
            let use=p.active.uses[0],(section,context,_)=try ArrangementCompiler.context(project:p,use:use)
            var plan=try XCTUnwrap(SectionGraphCompiler.compile(project:p,section:section,use:use,context:context,clock:clock))
            let source=try XCTUnwrap(plan.connections.first{$0.signal == .midi}?.from.nodeID)
            plan.midiPerformances[source]=[packet(raw:127)]
            if variant<2 {
                let result=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0)
                XCTAssertEqual(try XCTUnwrap(result[p.tracks[0].id]).peak,0)
            } else {XCTAssertThrowsError(try SectionGraphRenderer.validatePitchBendSupport(plan,project:p))}
        }
    }

}
