import XCTest
@testable import CirclrCore

final class SynthCutoffAutomationTests:XCTestCase {
    func fixture()throws->Project {
        var p=try AutomationTests().fixture();p.tracks[0].instrument = .synthesizer(.pad)
        return p
    }
    func instrument(_ p:Project)throws->MusicCircle {
        try XCTUnwrap(p.sections[0].graph?.nodes.first{if case .instrument=$0.content{return true};return false})
    }
    func set(_ p:inout Project,points:[AutomationPoint]?=nil,enabled:Bool?=nil,original:Bool=false)throws {
        let node=try instrument(p)
        try AutomationEditing.set(parameter:.synthCutoff,points:points,enabled:enabled,nodeID:node.id,useID:p.active.uses[0].id,original:original,in:&p)
    }
    func testHzInterpolationLogDisplayAndPatchFallback()throws {
        let p=try fixture(),node=try instrument(p),parameter=AutomationParameter.synthCutoff
        XCTAssertEqual(parameter.rawValue,"synthCutoff");XCTAssertEqual(parameter.range,40...20000)
        XCTAssertEqual(parameter.fallback(node:node,in:p),p.tracks[0].instrument.synth!.cutoff)
        let lane=AutomationLane(parameter:parameter,points:[.init(beat:1,value:400),.init(beat:3,value:6400)])
        XCTAssertEqual(lane.value(at:0),400);XCTAssertEqual(lane.value(at:2),3400);XCTAssertEqual(lane.value(at:8),6400)
        var hold=lane;hold.points[0].shape = .hold
        XCTAssertEqual(hold.value(at:2.999),400);XCTAssertEqual(hold.value(at:3),6400)
        for hz in [40.0,400,3400,6400,20000] {
            XCTAssertEqual(AutomationDisplay.value(atNormalized:AutomationDisplay.normalized(hz,parameter:parameter),parameter:parameter),hz,accuracy:1e-8)
        }
        XCTAssertEqual(AutomationDisplay.normalized(sqrt(40*20000),parameter:parameter),0.5,accuracy:1e-12)
        XCTAssertEqual(AutomationDisplay.nudge(400,parameter:parameter,direction:1),500)
        XCTAssertEqual(AutomationDisplay.nudge(400,parameter:parameter,direction:1,fine:true),401)
        XCTAssertEqual(AutomationDisplay.nudge(400,parameter:parameter,direction:1,coarse:true),1400)
    }
    func testSchemaPromotionRemovalUndoAndMigrationPreserveVersion()throws {
        var p=try fixture();let before=p
        try set(&p,points:[.init(beat:0,value:400)])
        XCTAssertEqual(p.schemaVersion,3);try ProjectStore.validateStructure(p)
        XCTAssertEqual(try SectionGraphMigration.migrate(p).schemaVersion,3)
        let restored=try CircleHistory.restore(before,layoutOnly:false,current:p)
        XCTAssertEqual(restored.schemaVersion,before.schemaVersion)
        var normalized=restored;normalized.musicRevision=before.musicRevision;XCTAssertEqual(normalized,before)
        try set(&p,points:[]);XCTAssertEqual(p.schemaVersion,3)
        p.enableAlbum();XCTAssertEqual(p.schemaVersion,3)
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
    }
    func testUnsupportedTargetsInvalidValuesAndDisabledLanesRejectAtomically()throws {
        let base=try fixture()
        for value in [39.0,20001,.nan,.infinity] {
            var p=base;XCTAssertThrowsError(try set(&p,points:[.init(beat:0,value:value)]));XCTAssertEqual(p,base)
        }
        for kind:Instrument.Kind in [.soundBank,.audioUnit,.sampler] {
            var p=base;p.tracks[0].instrument.kind=kind;let before=p
            XCTAssertThrowsError(try set(&p,points:[.init(beat:0,value:400)],enabled:false));XCTAssertEqual(p,before)
        }
        let target=try XCTUnwrap(base.sections[0].graph?.nodes.first{if case .output=$0.content{return true};return false})
        var p=base
        XCTAssertThrowsError(try AutomationEditing.set(parameter:.synthCutoff,points:[.init(beat:0,value:400)],nodeID:target.id,useID:p.active.uses[0].id,in:&p))
        XCTAssertEqual(p,base)
        try set(&p,points:[.init(beat:0,value:400)],enabled:false)
        p.tracks[0].instrument.kind = .soundBank
        XCTAssertThrowsError(try AutomationCompiler.validateTargets(in:p));XCTAssertThrowsError(try ProjectStore.validateStructure(p))
    }
    func testRawInactiveOverrideAndUnusedOriginalAreValidated()throws {
        var p=try fixture();try set(&p,points:[.init(beat:0,value:400)],enabled:false)
        let version3=p
        p.schemaVersion=2;XCTAssertThrowsError(try ProjectStore.validateStructure(p))
        p=version3
        _=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point())
        p.tracks[0].instrument.kind = .soundBank
        XCTAssertThrowsError(try AutomationCompiler.validateTargets(in:p))
        p=try fixture();try set(&p,points:[.init(beat:0,value:400)],original:true)
        p.arrangements[0].uses=[];p.arrangements[0].startID=nil;p.tracks[0].instrument.kind = .soundBank
        XCTAssertThrowsError(try AutomationCompiler.validateTargets(in:p))
    }
    func testThreeLanesAndOriginalOverrideIndependent()throws {
        var p=try fixture();let node=try instrument(p),use=p.active.uses[0].id
        _=try ProjectEditing.reuse(use,in:&p,at:Point())
        try set(&p,points:[.init(beat:0,value:800)],original:true)
        try set(&p,points:[.init(beat:0,value:400)])
        for parameter:AutomationParameter in [.gain,.pan] {
            try AutomationEditing.set(parameter:parameter,points:[.init(beat:0,value:parameter.neutral)],nodeID:node.id,useID:use,in:&p)
        }
        let graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        XCTAssertEqual(graph.nodes.first{$0.id==node.id}?.automation?.count,3)
        let other=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[1]))
        XCTAssertEqual(other.nodes.first{$0.id==node.id}?.automation?.first{$0.parameter == .synthCutoff}?.points.first?.value,800)
        try ProjectStore.validateStructure(p)
    }
    func testCompiledCurveTempoRepeatDisabledAndTailBoundary()throws {
        var p=try fixture(),node=try instrument(p)
        node.startBeat=1;node.lengthBeats=4;node.repeatCount=2
        node.automation=[.init(parameter:.synthCutoff,points:[.init(beat:0,value:400),.init(beat:4,value:6400)])]
        p.schemaVersion=3
        let clock=try MusicClock(bars:4,context:p.global,tempoChanges:[.init(beat:3,bpm:60)])
        let plans=try AutomationCompiler.compile(node,context:p.global,clock:clock)
        func value(_ beat:Double)->Double {
            let t=clock.seconds(at:beat),spans=plans[0].spans
            return (spans.first{t<$0.end} ?? spans.last!).value(at:t)
        }
        XCTAssertEqual(value(0),400);XCTAssertEqual(value(3),3400,accuracy:1e-8)
        XCTAssertEqual(value(5),400);XCTAssertEqual(value(9),6400)
        XCTAssertEqual(plans[0].spans.last?.to,6400)
        node.automation![0].enabled=false
        XCTAssertTrue(try AutomationCompiler.compile(node,context:p.global,clock:clock).isEmpty)
    }
    func testLoadPreservesLegacyBytesAndRejectsFutureHeaderBeforeUnknownEnum()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".circlr")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let manifest=root.appendingPathComponent("manifest.json")
        for p in [Project(),try fixture()] {
            let bytes=try JSONEncoder().encode(p);try bytes.write(to:manifest)
            XCTAssertEqual(try ProjectStore.load(root).project.schemaVersion,p.schemaVersion)
            XCTAssertEqual(try Data(contentsOf:manifest),bytes)
        }
        let future=Data(#"{"schemaVersion":4,"parameter":"unknownFuture"}"#.utf8);try future.write(to:manifest)
        XCTAssertThrowsError(try ProjectStore.load(root)){error in XCTAssertTrue(error.localizedDescription.contains("더 새로운 프로젝트"))}
        XCTAssertEqual(try Data(contentsOf:manifest),future)
    }
    func testAgentInstrumentChangeRejectsUntilCurveExplicitlyRemoved()throws {
        var p=try fixture();try set(&p,points:[.init(beat:0,value:400)],enabled:false)
        let before=p
        var change=AgentOperation("set_instrument");change.trackID=p.tracks[0].id;change.instrument=Instrument()
        var request=AgentRequest(method:"apply");request.projectID=p.id;request.expectedRevision=p.musicRevision
        request.arguments=AgentArguments();request.arguments?.operations=[change]
        XCTAssertThrowsError(try AgentProjectEditing.apply(request,to:p));XCTAssertEqual(p,before)
        var remove=AgentOperation("set_automation");remove.useID=p.active.uses[0].id;remove.nodeID=try instrument(p).id
        remove.parameter = .synthCutoff;remove.automationPoints=[]
        request.arguments?.operations=[remove,change]
        let result=try AgentProjectEditing.apply(request,to:p)
        XCTAssertEqual(result.tracks[0].instrument.kind,.soundBank);XCTAssertEqual(result.schemaVersion,3)
    }
}
