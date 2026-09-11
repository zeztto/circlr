import XCTest
@testable import CirclrCore

final class SectionLengthEditingTests:XCTestCase {
    private func fixture()throws->Project {
        var p=Project();_=p.addTrack(name:"원본");_=p.addSection(name:"A",at:Point(),bars:2)
        p=try SectionGraphMigration.migrate(p)
        _=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point())
        return p
    }
    func testOverrideThenClearRestoresSharedSourceAndNoOpPreservesProject()throws {
        var p=try fixture();let before=p,ai=p.active.id,ui=p.active.uses[0].id
        let initial=try SectionLengthEditing.snapshot(arrangementID:ai,useID:ui,in:p)
        XCTAssertEqual(initial.sourceBars,2);XCTAssertEqual(initial.effectiveBars,2);XCTAssertNil(initial.barsOverride)
        let changed=try SectionLengthEditing.set(bars:4,arrangementID:ai,useID:ui,in:&p)
        XCTAssertEqual(changed.effectiveBars,4);XCTAssertEqual(changed.barsOverride,4);XCTAssertEqual(changed.sourceBars,2)
        XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.active.uses[1],before.active.uses[1])
        let cleared=try SectionLengthEditing.set(bars:nil,arrangementID:ai,useID:ui,in:&p)
        XCTAssertEqual(cleared,initial);XCTAssertEqual(p,before)
        _=try SectionLengthEditing.set(bars:nil,arrangementID:ai,useID:ui,in:&p);XCTAssertEqual(p,before)
        _=try SectionLengthEditing.set(bars:2,arrangementID:ai,useID:ui,in:&p)
        XCTAssertEqual(p.active.uses[0].barsOverride,2)
    }
    func testExplicitInactiveArrangementOwnsRepeatedUseID()throws {
        var p=try fixture();var other=p.active;other.id=newID();other.name="B";p.arrangements.append(other)
        let before=p
        _=try SectionLengthEditing.set(bars:3,arrangementID:other.id,useID:other.uses[0].id,in:&p)
        XCTAssertEqual(p.activeArrangementID,before.activeArrangementID);XCTAssertEqual(p.active,before.active)
        XCTAssertEqual(p.arrangements[1].uses[0].barsOverride,3);XCTAssertEqual(p.sections,before.sections)
        XCTAssertEqual(p.schemaVersion,before.schemaVersion);XCTAssertEqual(p.musicRevision,before.musicRevision)
    }
    func testInvalidRangesAndAddressesAreAtomic()throws {
        let base=try fixture()
        for bars in [0,-1,4097,Int.max] {
            var p=base;XCTAssertThrowsError(try SectionLengthEditing.set(bars:bars,arrangementID:p.active.id,useID:p.active.uses[0].id,in:&p));XCTAssertEqual(p,base)
        }
        for (ai,ui) in [("missing",base.active.uses[0].id),(base.active.id,"missing")] {
            var p=base;XCTAssertThrowsError(try SectionLengthEditing.snapshot(arrangementID:ai,useID:ui,in:p))
            XCTAssertThrowsError(try SectionLengthEditing.set(bars:nil,arrangementID:ai,useID:ui,in:&p));XCTAssertEqual(p,base)
        }
        var p=base;_=try SectionLengthEditing.set(bars:4096,arrangementID:p.active.id,useID:p.active.uses[0].id,in:&p)
        XCTAssertEqual(p.active.uses[0].barsOverride,4096)
    }
    func testTempoAndMeterMetadataAtNewEndRejectShrinkAndClear()throws {
        var p=try fixture();p.schemaVersion=4;p.arrangements[0].uses[0].barsOverride=4
        p.arrangements[0].uses[0].tempoOverride = .init(initialBPM:120,changes:[.init(beat:8,bpm:90)])
        let before=p,ai=p.active.id,ui=p.active.uses[0].id
        for bars:Int? in [2,nil] {XCTAssertThrowsError(try SectionLengthEditing.set(bars:bars,arrangementID:ai,useID:ui,in:&p));XCTAssertEqual(p,before)}
        _=try SectionLengthEditing.set(bars:3,arrangementID:ai,useID:ui,in:&p)
        XCTAssertEqual(p.active.uses[0].tempoOverride,before.active.uses[0].tempoOverride)
        p=try fixture();p.sections[0].meterChanges=[.init(bar:1,meter:.init(3,4))]
        let meterBefore=p
        XCTAssertThrowsError(try SectionLengthEditing.set(bars:1,arrangementID:p.active.id,useID:p.active.uses[0].id,in:&p));XCTAssertEqual(p,meterBefore)
    }
    private func request(_ ops:[AgentOperation],_ p:Project)->AgentRequest {
        var r=AgentRequest(method:"apply");r.projectID=p.id;r.expectedRevision=p.musicRevision
        r.arguments=AgentArguments();r.arguments?.operations=ops;return r
    }
    private func operation(_ kind:String,_ p:Project,bars:Int?=nil)->AgentOperation {
        var op=AgentOperation(kind);op.arrangementID=p.active.id;op.useID=p.active.uses[0].id;op.bars=bars;return op
    }
    func testAgentExplicitInactiveSetClearAndRoundTripPreserveActiveSelection()throws {
        var p=try fixture();var other=p.active;other.id=newID();other.name="B";p.arrangements.append(other)
        var op=operation("set_use_length_override",p,bars:5);op.arrangementID=other.id
        let decoded=try JSONDecoder().decode(AgentRequest.self,from:JSONEncoder().encode(request([op],p)))
        let changed=try AgentProjectEditing.apply(decoded,to:p)
        XCTAssertEqual(changed.active,p.active);XCTAssertEqual(changed.activeArrangementID,p.activeArrangementID)
        XCTAssertEqual(changed.arrangements[1].uses[0].barsOverride,5)
        var clear=operation("clear_use_length_override",changed);clear.arrangementID=other.id
        XCTAssertEqual(try AgentProjectEditing.apply(request([clear],changed),to:changed),p)
    }
    func testAgentStrictFieldsMissingAddressesAndInvalidBatchAreAtomic()throws {
        let p=try fixture(),good=operation("set_use_length_override",p,bars:4)
        var cases:[AgentOperation]=[]
        var bad=good;bad.name="unrelated";cases.append(bad)
        bad=good;bad.bars=nil;cases.append(bad)
        bad=good;bad.bars=0;cases.append(bad)
        bad=good;bad.bars=4097;cases.append(bad)
        bad=good;bad.arrangementID=nil;cases.append(bad)
        bad=good;bad.arrangementID="missing";cases.append(bad)
        bad=good;bad.useID=nil;cases.append(bad)
        bad=good;bad.useID="missing";cases.append(bad)
        bad=operation("clear_use_length_override",p,bars:2);cases.append(bad)
        bad=operation("clear_use_length_override",p);bad.name="unrelated";cases.append(bad)
        for invalid in cases {
            XCTAssertThrowsError(try AgentProjectEditing.apply(request([invalid],p),to:p))
            XCTAssertThrowsError(try AgentProjectEditing.apply(request([good,invalid],p),to:p))
        }
        XCTAssertNil(p.active.uses[0].barsOverride)
        var stale=request([good],p);stale.expectedRevision=p.musicRevision+1
        XCTAssertThrowsError(try AgentProjectEditing.apply(stale,to:p))
    }
    func testLegacyAgentSectionAppliesFinalSettingsBeforeLengthValidation()throws {
        var p=try fixture();p.sections[0].meterChanges=[.init(bar:1,meter:.init(3,4))]
        var op=operation("set_section",p,bars:1);op.name="편집한 사용";op.repeatCount=2
        var settings=ContextSettings();settings.meter = .local(Meter(4,4));op.settings=settings
        let changed=try AgentProjectEditing.apply(request([op],p),to:p)
        XCTAssertEqual(changed.active.uses[0].barsOverride,1);XCTAssertEqual(changed.active.uses[0].settings,settings)
        XCTAssertEqual(changed.active.uses[0].name,"편집한 사용");XCTAssertEqual(changed.active.uses[0].repeatCount,2)
        XCTAssertEqual(changed.sections,p.sections);XCTAssertEqual(changed.active.uses[1],p.active.uses[1])
        op.settings=nil
        XCTAssertThrowsError(try AgentProjectEditing.apply(request([op],p),to:p))
    }

}
