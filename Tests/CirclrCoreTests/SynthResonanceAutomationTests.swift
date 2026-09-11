import XCTest
@testable import CirclrCore

final class SynthResonanceAutomationTests:XCTestCase {
    func fixture()throws->Project {try SynthCutoffAutomationTests().fixture()}
    func node(_ p:Project)throws->MusicCircle {try SynthCutoffAutomationTests().instrument(p)}
    func set(_ p:inout Project,_ points:[AutomationPoint],original:Bool=false,enabled:Bool=true)throws {
        let id=try node(p).id,use=p.active.uses[0].id
        try AutomationEditing.set(parameter:.synthResonance,points:points,enabled:enabled,nodeID:id,useID:use,original:original,in:&p)
    }
    func testDisplayRangePatchFallbackAndEffectiveEngine()throws {
        var p=try fixture();let n=try node(p),parameter=AutomationParameter.synthResonance
        XCTAssertEqual(parameter.range,0...0.9);XCTAssertEqual(parameter.neutral,0.12)
        p.tracks[0].instrument.synth!.resonance=0.37
        XCTAssertEqual(parameter.fallback(node:n,in:p),0.37)
        for engine in 1...3 {p.tracks[0].instrument.synth!.engineVersion=engine;XCTAssertEqual(parameter.supports(node:n,in:p),engine>=2)}
        p.tracks[0].instrument.synth=nil;XCTAssertTrue(parameter.supports(node:n,in:p))
        var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(SynthPatch())) as? [String:Any])
        legacy.removeValue(forKey:"engineVersion")
        p.tracks[0].instrument.synth=try JSONDecoder().decode(SynthPatch.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertFalse(parameter.supports(node:n,in:p))
        XCTAssertEqual(AutomationDisplay.value(0.12,parameter:parameter),"12.00%")
        XCTAssertEqual(AutomationDisplay.normalized(0.45,parameter:parameter),0.5)
        XCTAssertEqual(AutomationDisplay.value(atNormalized:1,parameter:parameter),0.9)
        XCTAssertEqual(NumberEditPresentation.resonancePercent.text(0.12),"12.00")
        XCTAssertEqual(NumberEditPresentation.resonancePercent.parse("90"),0.9)
        XCTAssertEqual(AutomationDisplay.nudge(0.12,parameter:parameter,direction:1),0.13,accuracy:1e-12)
        XCTAssertEqual(AutomationDisplay.nudge(0.12,parameter:parameter,direction:1,fine:true),0.121,accuracy:1e-12)
        XCTAssertEqual(AutomationDisplay.nudge(0.12,parameter:parameter,direction:1,coarse:true),0.22,accuracy:1e-12)
    }
    func testPromotionNoOpRemovalUndoAndRoundTrip()throws {
        var p=try fixture();let before=p
        try set(&p,[]);XCTAssertEqual(p,before)
        try set(&p,[.init(beat:0,value:0),.init(beat:4,value:0.9)])
        XCTAssertEqual(p.schemaVersion,6);try ProjectStore.validateStructure(p)
        let saved=p,id=try node(p).id
        let points=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0])?.nodes.first{$0.id == id}?.automation?.first?.points)
        try set(&p,points)
        XCTAssertEqual(p,saved)
        XCTAssertEqual(try SectionGraphMigration.migrate(p).schemaVersion,6)
        p.enableAlbum();XCTAssertEqual(p.schemaVersion,6)
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
        try set(&p,[]);XCTAssertEqual(p.schemaVersion,6)
        var restored=try CircleHistory.restore(before,layoutOnly:false,current:p);restored.musicRevision=before.musicRevision
        XCTAssertEqual(restored,before)
    }
    func testInvalidAndUnsupportedEditsAreAtomicIncludingDisabled()throws {
        let base=try fixture()
        for value in [-0.001,0.9001,1,.nan,.infinity] {var p=base;XCTAssertThrowsError(try set(&p,[.init(beat:0,value:value)],enabled:false));XCTAssertEqual(p,base)}
        for kind:Instrument.Kind in [.soundBank,.audioUnit,.sampler] {var p=base;p.tracks[0].instrument.kind=kind;let before=p;XCTAssertThrowsError(try set(&p,[.init(beat:0,value:0.12)],enabled:false));XCTAssertEqual(p,before)}
        var p=base;p.tracks[0].instrument.synth!.engineVersion=1;let before=p
        XCTAssertThrowsError(try set(&p,[.init(beat:0,value:0.12)]));XCTAssertEqual(p,before)
        p=base;try set(&p,[.init(beat:0,value:0.12)],enabled:false)
        p.tracks[0].instrument.synth!.engineVersion=1
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
        p=base;try set(&p,[.init(beat:0,value:0.12)]);p.schemaVersion=5
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
    }
    func testOriginalOverrideAndInactiveVariantValidation()throws {
        var p=try fixture();let use=p.active.uses[0].id,id=try node(p).id
        _=try ProjectEditing.reuse(use,in:&p,at:Point())
        try set(&p,[.init(beat:0,value:0.2)],original:true)
        try set(&p,[.init(beat:0,value:0.8)])
        let first=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let other=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[1]))
        XCTAssertEqual(first.nodes.first{$0.id==id}?.automation?.first?.points.first?.value,0.8)
        XCTAssertEqual(other.nodes.first{$0.id==id}?.automation?.first?.points.first?.value,0.2)
        var variant=p.arrangements[0];variant.id=newID();p.arrangements.append(variant)
        try ProjectStore.validateStructure(p)
        p.arrangements[1].uses[0].graphEdits!.nodeOverrides[id]!.automation![0].points[0].value=1
        XCTAssertThrowsError(try AutomationCompiler.validateTargets(in:p))
    }
    func testSchemaSixSectionInsertionAndLoadPreserveLegacy()throws {
        var (p,arr,_,last)=try SectionInsertionTests().fixture();p.schemaVersion=6
        _=try SectionInsertion.insert(arrangementID:arr,afterUseID:last,name:"추가",bars:1,at:Point(),in:&p)
        XCTAssertEqual(p.schemaVersion,6);try ProjectStore.validateStructure(p)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        var resonance=try fixture();try set(&resonance,[.init(beat:0,value:0.12)])
        for value in [try fixture(),resonance] {
            let bytes=try JSONEncoder().encode(value),manifest=root.appendingPathComponent("manifest.json")
            try bytes.write(to:manifest)
            XCTAssertEqual(try ProjectStore.load(root).project,value)
            XCTAssertEqual(try Data(contentsOf:manifest),bytes)
        }
    }
    func testDisconnectedBouncedSourceStillRequiresSupportedEngine()throws {
        var p=try fixture();try set(&p,[.init(beat:0,value:0.12)],enabled:false)
        let asset=Asset(name:"render",path:"media/render.wav",duration:2,sampleRate:48000)
        _=try BounceEditing.apply(asset:asset,trackID:p.tracks[0].id,useID:p.active.uses[0].id,bodySeconds:2,tailSeconds:0,in:&p)
        try ProjectStore.validateStructure(p)
        p.tracks[0].instrument.synth!.engineVersion=1
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
    }
    func testEngineDowngradeAgentBatchRejectsUnlessCurveRemoved()throws {
        var p=try fixture();try set(&p,[.init(beat:0,value:0.4)],enabled:false)
        var change=AgentOperation("set_instrument");change.trackID=p.tracks[0].id;change.instrument=p.tracks[0].instrument;change.instrument!.synth!.engineVersion=1
        var request=AgentRequest(method:"apply");request.projectID=p.id;request.expectedRevision=p.musicRevision;request.arguments=AgentArguments();request.arguments?.operations=[change]
        XCTAssertThrowsError(try AgentProjectEditing.apply(request,to:p))
        var remove=AgentOperation("set_automation");remove.useID=p.active.uses[0].id;remove.nodeID=try node(p).id;remove.parameter = .synthResonance;remove.automationPoints=[]
        request.arguments?.operations=[remove,change]
        let result=try AgentProjectEditing.apply(request,to:p)
        XCTAssertEqual(result.tracks[0].instrument.synth?.engineVersion,1);XCTAssertEqual(result.schemaVersion,6)
    }
}
