import XCTest
@testable import CirclrCore

final class LevelEditingTests:XCTestCase {
    func fixture()throws->(Project,ID,ID,ID) {
        var p=Project();let track=p.addTrack(name:"베이스");_=p.addSection(name:"Verse",at:Point(),bars:1)
        p=try SectionGraphMigration.migrate(p)
        var second=p.active.uses[0];second.id=newID();second.name="Chorus";p.arrangements[0].uses.append(second)
        let node=p.sections[0].graph!.nodes.first{if case .output=$0.content{return true};return false}!.id
        return (p,track,node,second.id)
    }
    func target(_ p:Project,_ use:ID,_ node:ID,original:Bool=false)->LevelTarget {.circle(.music(arrangementID:p.activeArrangementID,useID:use,nodeID:node),original:original)}
    func testLocalAndTrackScopesStaySeparateAcrossReusedSection()throws {
        var (p,track,node,second)=try fixture();let initial=p,first=p.active.uses[0].id
        try LevelEditing.set(target(p,first,node),gain:0.5,in:&p)
        XCTAssertEqual(try LevelEditing.snapshot(target(p,first,node),in:p).gain,0.5)
        XCTAssertEqual(try LevelEditing.snapshot(target(p,second,node),in:p).gain,1)
        XCTAssertEqual(p.sections,initial.sections);XCTAssertEqual(p.tracks,initial.tracks)
        let sections=p.sections,uses=p.active.uses
        try LevelEditing.set(.track(track),gain:0.2,muted:true,in:&p)
        XCTAssertEqual(p.sections,sections);XCTAssertEqual(p.active.uses,uses)
        XCTAssertEqual(try LevelEditing.snapshot(.track(track),in:p),LevelSnapshot(gain:0.2,muted:true))
        let decoded=try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p));XCTAssertEqual(decoded,p)
    }
    func testOriginalPartialEditNeverCopiesOtherUseOverrides()throws {
        var (p,_,node,second)=try fixture();let first=p.active.uses[0].id
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let i=try XCTUnwrap(graph.nodes.firstIndex{$0.id==node});graph.nodes[i].name="이번 사용 이름";graph.nodes[i].settings.tempo = .local(99);graph.nodes[i].gain=0.25
        try SectionGraphEditing.set(graph,useID:first,original:false,in:&p)
        let original=p.sections[0].graph!,useEdits=p.active.uses[0].graphEdits
        try LevelEditing.set(target(p,first,node,original:true),gain:0.75,muted:true,in:&p)
        var expected=original;expected.nodes[i].gain=0.75;expected.nodes[i].muted=true
        XCTAssertEqual(p.sections[0].graph,expected);XCTAssertEqual(p.active.uses[0].graphEdits,useEdits)
        XCTAssertEqual(try LevelEditing.snapshot(target(p,first,node),in:p),LevelSnapshot(gain:0.25,muted:false))
        XCTAssertEqual(try LevelEditing.snapshot(target(p,second,node),in:p),LevelSnapshot(gain:0.75,muted:true))
    }
    func testInvalidMissingAndNoopAreAtomic()throws {
        var (p,track,node,_)=try fixture();let initial=p,t=target(p,p.active.uses[0].id,node)
        for gain in [Double.nan,Double.infinity,-0.1,4.01] {
            XCTAssertThrowsError(try LevelEditing.set(t,gain:gain,muted:true,in:&p));XCTAssertEqual(p,initial)
            XCTAssertThrowsError(try LevelEditing.set(.track(track),gain:gain,in:&p));XCTAssertEqual(p,initial)
        }
        XCTAssertThrowsError(try LevelEditing.set(t,in:&p));XCTAssertEqual(p,initial)
        XCTAssertThrowsError(try LevelEditing.set(.track("missing"),gain:0.2,in:&p));XCTAssertEqual(p,initial)
        let midi=p.sections[0].graph!.nodes.first{if case .midi=$0.content{return true};return false}!.id
        XCTAssertThrowsError(try LevelEditing.set(target(p,p.active.uses[0].id,midi),gain:0.5,in:&p));XCTAssertEqual(p,initial)
        try LevelEditing.set(t,gain:1,muted:false,in:&p);XCTAssertEqual(p,initial)
    }
}

final class GainEditingTests:XCTestCase {
    func testDecibelInputConvertsToStoredLinearGainAndPreservesUntouchedPrecision()throws {
        for gain in [0.0,1,0.7,0.00000003,4] {
            var edit=NumberEditSession<Int>(presentation:.gainDecibels);edit.begin(value:gain,context:1)
            XCTAssertNil(try edit.resolve(value:gain,context:1,range:0...4))
            if gain>0{XCTAssertEqual(try XCTUnwrap(Double(edit.text)),GainScale.decibels(gain),accuracy:0.0051)}
        }
        var edit=NumberEditSession<Int>(presentation:.gainDecibels);edit.begin(value:1,context:1);edit.text="-6"
        XCTAssertEqual(try XCTUnwrap(edit.resolve(value:1,context:1,range:0...4)),pow(10,-6.0/20),accuracy:1e-12)
        edit.text="0.0";XCTAssertNil(try edit.resolve(value:1,context:1,range:0...4))
    }
    func testSilenceCanBeTypedWithoutAllowingArbitraryInfinityOrUnderflow()throws {
        var edit=NumberEditSession<Int>(presentation:.gainDecibels);edit.begin(value:1,context:1)
        for text in ["−∞","-∞"," -inf ","-infinity"] {edit.text=text;XCTAssertEqual(try edit.resolve(value:1,context:1,range:0...4),0)}
        for text in ["∞","inf","nan","-nan","1e999","-10000","10000","12.1","0 dB",""] {
            edit.text=text;XCTAssertThrowsError(try edit.resolve(value:1,context:1,range:0...4),text)
        }
        edit.begin(value:0,context:1);XCTAssertEqual(edit.text,"−∞");edit.text="0";XCTAssertEqual(try edit.resolve(value:0,context:1,range:0...4),1)
    }
    func testGainDraftRejectsChangedGainAndTargetAndResetKeepsOriginal()throws {
        var edit=NumberEditSession<String>(presentation:.gainDecibels);edit.begin(value:0.7,context:"a:r1");edit.text="-12"
        XCTAssertThrowsError(try edit.resolve(value:0.7,context:"b:r1",range:0...4))
        XCTAssertThrowsError(try edit.resolve(value:0.7,context:"a:r2",range:0...4))
        XCTAssertThrowsError(try edit.resolve(value:0.5,context:"a:r1",range:0...4))
        edit.reset(value:0.7);XCTAssertNil(try edit.resolve(value:0.7,context:"a:r1",range:0...4))
    }
    func testFaderSilenceUnityAndMaximum() {
        XCTAssertEqual(GainScale.gain(atFader:GainScale.minimumFaderDB),0)
        XCTAssertEqual(GainScale.gain(atFader:0),1)
        XCTAssertEqual(GainScale.gain(atFader:GainScale.maximumDB),4,accuracy:1e-12)
        XCTAssertEqual(GainScale.faderValue(0),GainScale.minimumFaderDB)
        XCTAssertEqual(GainScale.faderValue(0.5),20*log10(0.5),accuracy:1e-12)
    }
    func testUnmovedFaderPreservesRawGainIncludingBelowItsVisualFloor() {
        for gain in [0.0,1,0.7,4,1e-12] {
            XCTAssertEqual(GainScale.gain(atFader:GainScale.faderValue(gain)+1e-14,preserving:gain),gain)
        }
        XCTAssertEqual(GainScale.gain(atFader:-6,preserving:1),pow(10,-6.0/20),accuracy:1e-12)
    }
}
