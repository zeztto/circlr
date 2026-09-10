import XCTest
@testable import CirclrCore

final class AgentSharedAudioTests:XCTestCase {
    func fixture()throws->Project {try SharedRhythmAudioEditingTests().fixture()}
    func operation(_ edit:String,_ p:Project)->AgentOperation {
        var op=AgentOperation("edit_shared_audio");op.patternID=p.patterns[0].id;op.trackID=p.patterns[0].trackID;op.clipID=p.patterns[0].audio[0].id;op.edit=edit
        return op
    }
    func request(_ operations:[AgentOperation],_ p:Project)->AgentRequest {
        var r=AgentRequest(method:"apply");r.projectID=p.id;r.expectedRevision=p.musicRevision;r.arguments=AgentArguments();r.arguments?.operations=operations;return r
    }
    func testFourEditsMatchDirectCoreAndPreserveOtherProjectData()throws {
        let p=try fixture()
        for edit in ["split","duplicate","fade","delete"] {
            var op=operation(edit,p);let change:AudioEditing.Change
            switch edit {
            case "split":op.sourceOffset=0.5;change = .split(sourceOffset:0.5)
            case "duplicate":op.beatOffset=2;change = .duplicate(beatOffset:2)
            case "fade":op.fadeIn=0.1;op.fadeOut=0.3;change = .fade(input:0.1,output:0.3)
            default:change = .delete
            }
            let decoded=try JSONDecoder().decode(AgentRequest.self,from:JSONEncoder().encode(request([op],p)))
            var result=try AgentProjectEditing.apply(decoded,to:p),direct=p
            _=try SharedRhythmAudioEditing.apply(change,patternID:p.patterns[0].id,trackID:p.patterns[0].trackID,clipID:p.patterns[0].audio[0].id,in:&direct)
            XCTAssertEqual(result.patterns[0].audio.count,direct.patterns[0].audio.count)
            let originalIDs=Set(p.patterns[0].audio.map(\.id))
            for index in result.patterns[0].audio.indices where !originalIDs.contains(result.patterns[0].audio[index].id) {
                XCTAssertFalse(originalIDs.contains(direct.patterns[0].audio[index].id))
                result.patterns[0].audio[index].id=direct.patterns[0].audio[index].id
            }
            XCTAssertEqual(result,direct,edit)
            var unchanged=result;unchanged.patterns=p.patterns;XCTAssertEqual(unchanged,p,edit)
            XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(result)),result)
        }
    }
    func testMissingAndWrongIdentityCannotEditSharedClip()throws {
        let p=try fixture(),before=p
        for field in ["pattern","track","clip"] {for value:String? in [nil,"missing"] {
            var op=operation("delete",p)
            switch field {case "pattern":op.patternID=value;case "track":op.trackID=value;default:op.clipID=value}
            XCTAssertThrowsError(try AgentProjectEditing.apply(request([op],p),to:p))
            XCTAssertEqual(p,before)
        }}
        var wrongOwner=p;let otherTrack=wrongOwner.addTrack(name:"다른 소유자")
        var op=operation("delete",wrongOwner);op.trackID=otherTrack
        XCTAssertThrowsError(try AgentProjectEditing.apply(request([op],wrongOwner),to:wrongOwner))
    }
    func testInvalidArgumentsAndMixedBatchAreAtomicAndStaleIsRejected()throws {
        let p=try fixture(),before=p
        for edit in ["split","fade","unknown"] {
            XCTAssertThrowsError(try AgentProjectEditing.apply(request([operation(edit,p)],p),to:p))
        }
        var bad=operation("split",p);bad.sourceOffset=0
        var good=operation("fade",p);good.fadeIn=0.1;good.fadeOut=0.1
        var automation=AgentOperation("set_automation");automation.useID=p.active.uses[0].id
        automation.nodeID=p.sections[0].graph?.nodes.first{$0.supportsAutomation}?.id
        automation.parameter = .gain;automation.automationPoints=[AutomationPoint(beat:0,value:0.5)]
        XCTAssertThrowsError(try AgentProjectEditing.apply(request([good,automation,bad],p),to:p));XCTAssertEqual(p,before)
        var stale=request([good],p);stale.expectedRevision=p.musicRevision+1
        XCTAssertThrowsError(try AgentProjectEditing.apply(stale,to:p))
        stale=request([good],p);stale.projectID="other"
        XCTAssertThrowsError(try AgentProjectEditing.apply(stale,to:p));XCTAssertEqual(p,before)
    }
    func testOrdinaryAudioOperationDoesNotImplicitlyEditSharedPatterns()throws {
        let p=try fixture();var op=operation("delete",p);op.kind="edit_audio";op.patternID=nil
        op.useID=p.active.uses[0].id;op.nodeID="rhythm-audio:\(p.tracks[0].id)"
        XCTAssertThrowsError(try AgentProjectEditing.apply(request([op],p),to:p))
    }
    func testConflictingTargetsAndUnsupportedScopeFieldsReject()throws {
        let p=try fixture()
        for field in ["arrangement","use","node","lane","composition","original"] {
            var op=operation("delete",p)
            switch field {
            case "arrangement":op.arrangementID=p.activeArrangementID
            case "use":op.useID=p.active.uses[0].id
            case "node":op.nodeID="rhythm-audio:\(p.tracks[0].id)"
            case "lane":op.laneID=p.sections[0].lanes[0].id
            case "composition":op.compositionID="composition"
            default:op.original=false
            }
            XCTAssertThrowsError(try AgentProjectEditing.apply(request([op],p),to:p),field)
        }
        var ordinary=AgentOperation("edit_audio");ordinary.useID=p.active.uses[0].id;ordinary.nodeID="audio";ordinary.edit="delete";ordinary.original=true
        XCTAssertThrowsError(try AgentProjectEditing.apply(request([ordinary],p),to:p))
        var automation=AgentOperation("set_automation");automation.useID=p.active.uses[0].id
        automation.nodeID=p.sections[0].graph?.nodes.first{$0.supportsAutomation}?.id
        automation.parameter = .gain;automation.automationPoints=[.init(beat:0,value:0.5)];automation.patternID=p.patterns[0].id
        XCTAssertThrowsError(try AgentProjectEditing.apply(request([automation],p),to:p))
    }
}
