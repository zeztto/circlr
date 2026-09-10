import XCTest
@testable import CirclrCore

final class AgentSustainEditingTests:XCTestCase {
    func fixture()throws->Project {try HierarchyEditingTests().fixture()}
    func operation(_ p:Project,kind:String="insert")->AgentOperation {
        var op=AgentOperation("edit_sustain");op.arrangementID=p.activeArrangementID;op.useID=p.active.uses[0].id
        op.laneID=p.sections[0].lanes[0].id;op.original=false
        var change=AgentSustainChange(kind:kind)
        if kind=="insert" {change.beat=1;change.rawValue=127}
        op.sustainChange=change;return op
    }
    func request(_ p:Project,_ ops:[AgentOperation])->AgentRequest {
        var request=AgentRequest(method:"edit");request.projectID=p.id;request.expectedRevision=p.musicRevision
        var args=AgentArguments();args.operations=ops;request.arguments=args;return request
    }
    func testPreviewCandidateScopeSchemaAndUndo()throws {
        var p=try fixture();_=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point())
        let before=p,op=operation(p)
        let result=try AgentProjectEditing.apply(request(p,[op]),to:p)
        XCTAssertEqual(p,before);XCTAssertEqual(result.schemaVersion,7)
        XCTAssertEqual(result.sections,p.sections);XCTAssertEqual(result.active.uses[1],p.active.uses[1])
        XCTAssertEqual(result.active.uses[0].laneOverrides[op.laneID!]?.sustain?.events,[.init(beat:1,rawValue:127)])
        let restored=try CircleHistory.restore(p,layoutOnly:false,current:result)
        XCTAssertNil(restored.active.uses[0].laneOverrides[op.laneID!]);XCTAssertEqual(restored.schemaVersion,p.schemaVersion)
    }
    func testAllChangesAndInactiveAddressPreserveActiveSelection()throws {
        var p=try fixture();let active=p.activeArrangementID
        ProjectEditing.duplicateArrangement(in:&p,name:"대안");var op=operation(p);p.activeArrangementID=active
        p=try AgentProjectEditing.apply(request(p,[op]),to:p)
        XCTAssertEqual(p.activeArrangementID,active)
        var change=AgentSustainChange(kind:"update");change.index=0;change.beat=2;change.rawValue=63;op.sustainChange=change
        p=try AgentProjectEditing.apply(request(p,[op]),to:p)
        change=AgentSustainChange(kind:"setInitial");change.channel=4;change.rawValue=64;op.sustainChange=change
        p=try AgentProjectEditing.apply(request(p,[op]),to:p)
        change=AgentSustainChange(kind:"remove");change.index=0;op.sustainChange=change
        p=try AgentProjectEditing.apply(request(p,[op]),to:p)
        let use=try XCTUnwrap(p.arrangements.first{$0.id==op.arrangementID}?.uses.first{$0.id==op.useID})
        XCTAssertEqual(use.laneOverrides[op.laneID!]?.sustain?.initialValue,64)
        XCTAssertEqual(use.laneOverrides[op.laneID!]?.sustain?.events,[])
        op.sustainChange=AgentSustainChange(kind:"clear");p=try AgentProjectEditing.apply(request(p,[op]),to:p)
        XCTAssertNil(p.arrangements.first{$0.id==op.arrangementID}?.uses.first?.laneOverrides[op.laneID!]?.sustain)
    }
    func testPairedChannelInsertSeedAndMismatchedInitialAtomic()throws {
        var p=try fixture();p.schemaVersion=5;p.sections[0].lanes[0].pitchBend = .init(channel:7)
        var op=operation(p);op.original=true
        p=try AgentProjectEditing.apply(request(p,[op]),to:p)
        XCTAssertEqual(p.sections[0].lanes[0].sustain?.channel,7)
        let before=p
        var change=AgentSustainChange(kind:"setInitial");change.channel=0;change.rawValue=127;op.sustainChange=change
        XCTAssertThrowsError(try AgentSustainEditing.apply(op,in:&p));XCTAssertEqual(p,before)
    }
    func testSharedPatternAddressAndChannelFailureAreAtomic()throws {
        var p=try fixture();var pattern=RhythmPattern(name:"공유",trackID:p.tracks[0].id)
        pattern.pitchBend = .init(channel:3);p.patterns=[pattern];p.schemaVersion=5
        var op=operation(p);op.arrangementID=nil;op.useID=nil;op.laneID=nil;op.original=nil
        op.patternID=pattern.id;op.trackID=pattern.trackID
        p=try AgentProjectEditing.apply(request(p,[op]),to:p)
        XCTAssertEqual(p.patterns[0].sustain?.channel,3);let before=p
        var change=AgentSustainChange(kind:"setInitial");change.channel=2;change.rawValue=0;op.sustainChange=change
        XCTAssertThrowsError(try AgentSustainEditing.apply(op,in:&p));XCTAssertEqual(p,before)
        op.sustainChange=AgentSustainChange(kind:"clear");op.useID=p.active.uses[0].id
        XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[op]),to:p))
    }
    func testUnknownNullMissingMixedAndUnrelatedFieldsReject()throws {
        let p=try fixture(),base=operation(p)
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(base)) as? [String:Any])
        for key in ["unknown","nodeID","name"] {
            var changed=object;changed[key]="unexpected"
            XCTAssertThrowsError(try JSONDecoder().decode(AgentOperation.self,from:JSONSerialization.data(withJSONObject:changed)))
        }
        for key in ["original","sustainChange","trackID"] {
            var changed=object;changed[key]=NSNull()
            XCTAssertThrowsError(try JSONDecoder().decode(AgentOperation.self,from:JSONSerialization.data(withJSONObject:changed)))
        }
        for text in [#"{"kind":"clear","index":null}"#,#"{"kind":"clear","unknown":1}"#,#"{"kind":"remove"}"#,#"{"kind":"insert","beat":1,"rawValue":127,"channel":0}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(AgentSustainChange.self,from:Data(text.utf8)).resolved())
        }
        var op=base;op.name="bad";XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[op]),to:p))
        op=base;op.original=nil;XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[op]),to:p))
        op=base;op.laneID="missing";XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[op]),to:p))
        op=base;op.kind="set_track";XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[op]),to:p))
        let roundTrip=try JSONDecoder().decode(AgentOperation.self,from:JSONEncoder().encode(base))
        XCTAssertEqual(roundTrip.sustainChange?.rawValue,127)
    }
    func testClearAbsentExpressionDoesNotCreateUseOverrideOrPromoteSchema()throws {
        var p=try fixture();let before=p,op=operation(p,kind:"clear")
        try AgentSustainEditing.apply(op,in:&p)
        XCTAssertEqual(p,before)
        XCTAssertEqual(try AgentProjectEditing.apply(request(p,[op]),to:p),before)
        var missing=op;missing.laneID="missing"
        XCTAssertThrowsError(try AgentSustainEditing.apply(missing,in:&p))
        XCTAssertEqual(p,before)
    }

    func testMixedBatchFailureAndStaleRevisionDoNotMutateInput()throws {
        let p=try fixture(),before=p,first=operation(p)
        var second=first;second.sustainChange?.rawValue=128
        XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[first,second]),to:p));XCTAssertEqual(p,before)
        var stale=request(p,[first]);stale.expectedRevision = p.musicRevision+1
        XCTAssertThrowsError(try AgentProjectEditing.apply(stale,to:p));XCTAssertEqual(p,before)
    }
}
