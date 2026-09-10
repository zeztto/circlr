import XCTest
@testable import CirclrCore

final class RecordedTakeSummaryTests:XCTestCase {
    func fixture()->Project {
        var p=Project();_=p.addTrack(name:"녹음");_=p.addSection(name:"구간",at:Point(),bars:1)
        p.sections[0].lanes[0].notes=[Note(beat:0,pitch:60)]
        p.sections[0].lanes[0].audio=[AudioClip(assetID:"asset",duration:1)]
        return p
    }
    func take(_ p:Project)->RecordedTake {
        var t=RecordedTake(useID:p.active.uses[0].id,name:"같은 이름",lane:p.sections[0].lanes[0])
        t.targetLaneID=t.lane.id;t.arrangementID=p.active.id;return t
    }
    func summary(_ t:RecordedTake,_ p:Project,laneID:ID?=nil)->RecordedTakeSummary? {
        RecordedTakeSummary.make(t,arrangementID:p.active.id,useID:p.active.uses[0].id,laneID:laneID ?? p.sections[0].lanes[0].id,in:p)
    }
    func testPartialPayloadMatchesActivationAndReadsEffectiveUse()throws {
        var p=fixture(),t=take(p);t.lane.id="recording-container";t.lane.audio=[]
        XCTAssertEqual(summary(t,p)?.matchesCurrentContent,true)
        t.lane.notes[0].pitch=72;XCTAssertEqual(summary(t,p)?.matchesCurrentContent,false)
        let original=p.sections
        try ProjectEditing.activateTake(t,in:&p)
        XCTAssertEqual(summary(t,p)?.matchesCurrentContent,true)
        XCTAssertEqual(summary(t,p)?.noteCount,1);XCTAssertEqual(summary(t,p)?.clipCount,0)
        XCTAssertEqual(p.sections,original)
        var audio=take(p);audio.lane.notes=[]
        XCTAssertEqual(summary(audio,p)?.matchesCurrentContent,true)
        audio.lane.audio[0].duration=0.5
        XCTAssertEqual(summary(audio,p)?.matchesCurrentContent,false)
    }
    func testEmptyAndMixedPayloadAndReadOnly() {
        let p=fixture(),before=p;var t=take(p)
        XCTAssertEqual(summary(t,p)?.matchesCurrentContent,true)
        t.lane.audio[0].gain=0.5;XCTAssertEqual(summary(t,p)?.matchesCurrentContent,false)
        t.lane.notes=[];t.lane.audio=[];XCTAssertEqual(summary(t,p)?.matchesCurrentContent,false)
        XCTAssertEqual(p,before)
    }
    func testExactLaneAndLegacyFirstLaneResolution() {
        var p=fixture();var second=p.sections[0].lanes[0];second.id="second-lane";p.sections[0].lanes.append(second)
        var t=take(p);t.targetLaneID=nil
        XCTAssertNotNil(summary(t,p));XCTAssertNil(summary(t,p,laneID:second.id))
        t.targetLaneID=second.id;XCTAssertNil(summary(t,p));XCTAssertNotNil(summary(t,p,laneID:second.id))
        t.targetLaneID="deleted";XCTAssertNil(summary(t,p))
    }
    func testArrangementOwnerAndLegacyFirstOwner() {
        var p=fixture();var t=take(p);var other=p.active;other.id="other-arrangement";p.arrangements.append(other)
        t.arrangementID=other.id;XCTAssertNil(summary(t,p))
        t.arrangementID=nil;XCTAssertNotNil(summary(t,p))
        p.activeArrangementID=other.id;XCTAssertNil(summary(t,p))
        t.arrangementID=other.id;XCTAssertNotNil(summary(t,p))
    }
}
