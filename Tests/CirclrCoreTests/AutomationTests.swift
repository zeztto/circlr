import XCTest
@testable import CirclrCore

final class AutomationTests:XCTestCase {
    func node()->MusicCircle {MusicCircle(name:"자동화",content:.mix)}
    func value(_ plans:[AutomationPlan],_ t:Double)->Double {
        let spans=plans[0].spans
        return (spans.first{t<$0.end} ?? spans.last!).value(at:t)
    }
    func testBeatLinearTempoBoundariesAndTailHold()throws {
        var n=node();n.automation=[AutomationLane(parameter:.gain,points:[.init(beat:0,value:0),.init(beat:4,value:1)])]
        let c=MusicContext(),clock=try MusicClock(bars:2,context:c,tempoChanges:[.init(beat:2,bpm:60)])
        let p=try AutomationCompiler.compile(n,context:c,clock:clock)
        XCTAssertEqual(value(p,0.5),0.25,accuracy:1e-12);XCTAssertEqual(value(p,1),0.5,accuracy:1e-12)
        XCTAssertEqual(value(p,2),0.75,accuracy:1e-12);XCTAssertEqual(value(p,3),1);XCTAssertEqual(value(p,clock.seconds+2),1)
    }
    func testProcessingEditorClockMatchesRenderedLocalAndInheritedBeats()throws {
        var n=node(),c=MusicContext();c.tempo=240;n.settings.tempo = .local(240)
        n.automation=[AutomationLane(parameter:.gain,points:[.init(beat:0,value:0),.init(beat:4,value:1)])]
        let parent=try MusicClock(bars:2,context:MusicContext(),tempoChanges:[.init(beat:2,bpm:60)])
        for local in [true,false] {
            n.settings.tempo=local ? .local(240):Setting()
            let clock=try AutomationCompiler.editingClock(n,context:c,parent:parent)
            let plans=try AutomationCompiler.compile(n,context:c,clock:parent)
            let t=clock.seconds(at:3)
            XCTAssertEqual(t,local ? 0.75:2,accuracy:1e-12)
            XCTAssertEqual(clock.beat(atSeconds:t),3,accuracy:1e-12)
            XCTAssertEqual(value(plans,t),0.75,accuracy:1e-12)
        }
    }
    func testLocalTempoExplicitRepeatAndEndValue()throws {
        var n=node();n.content = .audio(laneID:"l",clipID:"c");n.startBeat=1;n.lengthBeats=2;n.repeatCount=2;n.settings.tempo = .local(240)
        n.automation=[AutomationLane(parameter:.gain,points:[.init(beat:0,value:0),.init(beat:2,value:1)])]
        let clock=try MusicClock(bars:2,context:MusicContext());var c=MusicContext();c.tempo=240
        let p=try AutomationCompiler.compile(n,context:c,clock:clock)
        XCTAssertEqual(value(p,0.25),0);XCTAssertEqual(value(p,0.75),0.5,accuracy:1e-12);XCTAssertEqual(value(p,1),0)
        XCTAssertEqual(value(p,1.25),0.5,accuracy:1e-12);XCTAssertEqual(value(p,1.5),1);XCTAssertEqual(value(p,5),1)
        n.lengthBeats=nil
        let continuous=try AutomationCompiler.compile(n,context:c,clock:clock);XCTAssertEqual(value(continuous,1.25),1)
    }
    func testInheritedRepeatedCurveAcrossTempoChange()throws {
        var n=MusicCircle(name:"반복",content:.audio(laneID:"l",clipID:"c"));n.lengthBeats=4;n.repeatCount=2
        n.automation=[AutomationLane(parameter:.gain,points:[.init(beat:0,value:0),.init(beat:4,value:1)])]
        let c=MusicContext(),clock=try MusicClock(bars:2,context:c,tempoChanges:[.init(beat:2,bpm:60)])
        let p=try AutomationCompiler.compile(n,context:c,clock:clock)
        XCTAssertEqual(value(p,1),0.5);XCTAssertEqual(value(p,3),0);XCTAssertEqual(value(p,5),0.5);XCTAssertEqual(value(p,7),1)
    }
    func testHoldAndInvalidPointOrNodeContracts()throws {
        var n=node();let lane=AutomationLane(parameter:.pan,points:[.init(beat:0,value:-1,shape:.hold),.init(beat:1,value:1)])
        n.automation=[lane];let p=try AutomationCompiler.compile(n,context:MusicContext(),clock:MusicClock(bars:1,context:MusicContext()))
        XCTAssertEqual(value(p,0.49),-1);XCTAssertEqual(value(p,0.5),1)
        for invalid in [Double.nan,Double.infinity,1.01] {n.automation![0].points[0].value=invalid;XCTAssertThrowsError(try AutomationCompiler.validate(n))}
        n.automation=[lane];n.automation![0].points[1].beat=0;XCTAssertThrowsError(try AutomationCompiler.validate(n))
        n.automation=[lane];n.content = .midi(laneID:"m");XCTAssertThrowsError(try AutomationCompiler.validate(n))
        n.content = .audio(laneID:"a",clipID:"b");n.lengthBeats=0;XCTAssertThrowsError(try AutomationCompiler.compile(n,context:MusicContext(),clock:MusicClock(bars:1,context:MusicContext())))
    }
    func fixture()throws->Project {var p=Project();_=p.addTrack(name:"트랙");_=p.addSection(name:"구간",at:Point(),bars:4);return try SectionGraphMigration.migrate(p)}
    func testVariantNoOpToggleClearAndPersistence()throws {
        var p=try fixture();let u=p.active.uses[0].id,n=p.sections[0].graph!.nodes.first{$0.supportsAutomation}!.id
        _=try ProjectEditing.reuse(u,in:&p,at:Point());let base=p.sections[0]
        let points:[AutomationPoint]=[.init(beat:4,value:0.4),.init(beat:0,value:1)]
        try AutomationEditing.set(parameter:.gain,points:points,nodeID:n,useID:u,in:&p)
        let edited=p;try AutomationEditing.set(parameter:.gain,points:points,nodeID:n,useID:u,in:&p);XCTAssertEqual(p,edited)
        XCTAssertEqual(p.sections[0],base);XCTAssertNil(p.active.uses[1].graphEdits)
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
        try AutomationEditing.set(parameter:.gain,enabled:false,nodeID:n,useID:u,in:&p)
        let graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]));XCTAssertEqual(graph.nodes.first{$0.id==n}?.automation?.first?.enabled,false)
        try AutomationEditing.set(parameter:.gain,points:[],nodeID:n,useID:u,in:&p);XCTAssertNil(p.active.uses[0].graphEdits)
    }
    func testMCPDefaultsInvalidBatchAndStaleRevision()throws {
        let p=try fixture(),n=p.sections[0].graph!.nodes.first{$0.supportsAutomation}!.id
        let point=try JSONDecoder().decode(AutomationPoint.self,from:Data(#"{"beat":0,"value":0.5}"#.utf8));XCTAssertFalse(point.id.isEmpty);XCTAssertEqual(point.shape,.linear)
        var op=AgentOperation("set_automation");op.useID=p.active.uses[0].id;op.nodeID=n;op.parameter = .gain;op.automationPoints=[point]
        var r=AgentRequest(method:"apply");r.projectID=p.id;r.expectedRevision=p.musicRevision;r.arguments=AgentArguments();r.arguments?.operations=[op]
        let result=try AgentProjectEditing.apply(r,to:p);XCTAssertNotEqual(result,p)
        var bad=op;bad.automationPoints=[AutomationPoint(beat:0,value:5)];r.arguments?.operations=[op,bad];XCTAssertThrowsError(try AgentProjectEditing.apply(r,to:p))
        r.expectedRevision = -1;r.arguments?.operations=[op];XCTAssertThrowsError(try AgentProjectEditing.apply(r,to:p))
    }
    func testAudioDuplicateShiftsCurveAndRejectsNegativePointTimeAtomically()throws {
        var p=try fixture();let asset=Asset(name:"원본",path:"source.wav",duration:1,sampleRate:48000);p.assets=[asset]
        let clip=AudioClip(assetID:asset.id,duration:1,beat:2);var lane=p.sections[0].lanes[0];lane.audio=[clip]
        try ProjectEditing.setLane(lane,for:p.active.uses[0].id,original:true,in:&p)
        let u=p.active.uses[0].id,n=p.sections[0].graph!.nodes.first{if case .audio=$0.content{return true};return false}!.id
        try AutomationEditing.set(parameter:.gain,points:[.init(beat:0,value:0),.init(beat:2,value:1)],nodeID:n,useID:u,in:&p)
        let copy=try XCTUnwrap(AudioEditing.apply(.duplicate(beatOffset:2),nodeID:n,useID:u,in:&p))
        let graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]));XCTAssertEqual(graph.nodes.first{$0.id==copy}?.automation?.first?.points.map(\.beat),[2,4])
        let before=p;XCTAssertThrowsError(try AudioEditing.apply(.duplicate(beatOffset:-1),nodeID:n,useID:u,in:&p));XCTAssertEqual(p,before)
    }
}
