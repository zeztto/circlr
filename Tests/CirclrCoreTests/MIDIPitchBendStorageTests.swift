import XCTest
@testable import CirclrCore

final class MIDIPitchBendStorageTests:XCTestCase {
    func fixture()throws->Project {try HierarchyEditingTests().fixture()}
    var sequence:MIDIPitchBendSequence {.init(channel:3,initialValue:12288,initialRange:.init(semitones:7),events:[.init(beat:1,kind:.value(0)),.init(beat:1,kind:.range(.init(semitones:12,cents:50)))])}
    func testLegacyNilDecodesAndEncodingOmitsNewField()throws {
        let lane=try JSONDecoder().decode(Lane.self,from:Data(#"{"id":"lane","trackID":"track","notes":[],"audio":[]}"#.utf8))
        let pattern=try JSONDecoder().decode(RhythmPattern.self,from:Data(#"{"id":"pattern","name":"old","length":4,"meter":{"numerator":4,"denominator":4},"trackID":"track","notes":[],"audio":[]}"#.utf8))
        XCTAssertNil(lane.pitchBend);XCTAssertNil(pattern.pitchBend)
        let encodedLane=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(lane)) as? [String:Any])
        let encodedPattern=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(pattern)) as? [String:Any])
        XCTAssertNil(encodedLane["pitchBend"]);XCTAssertNil(encodedPattern["pitchBend"])
        var p=try fixture();let schema=p.schemaVersion;try MIDIPitchBendStorage.promote(in:&p);XCTAssertEqual(p.schemaVersion,schema)
    }
    func testUseEditPromotesWithoutChangingOriginalOrOtherUseAndUndoRestoresSchema()throws {
        var p=try fixture();_=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point())
        let before=p,use=p.active.uses[0].id
        var lane=p.sections[0].lanes[0];lane.pitchBend=sequence
        try ProjectEditing.setLane(lane,for:use,original:false,in:&p)
        XCTAssertEqual(p.schemaVersion,5);XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.active.uses[1],before.active.uses[1])
        XCTAssertEqual(try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0]).first{$0.id==lane.id}?.pitchBend,sequence)
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
        let restored=try CircleHistory.restore(before,layoutOnly:false,current:p)
        XCTAssertEqual(restored.schemaVersion,before.schemaVersion);XCTAssertNil(restored.active.uses[0].laneOverrides[lane.id])
        lane.pitchBend=nil;try ProjectEditing.setLane(lane,for:use,original:false,in:&p);XCTAssertEqual(p.schemaVersion,5)
    }
    func testOriginalDuplicateDetachAndNoteEditsPreserveExpression()throws {
        var p=try fixture();var lane=p.sections[0].lanes[0];lane.pitchBend=sequence
        try ProjectEditing.setLane(lane,for:p.active.uses[0].id,original:true,in:&p)
        XCTAssertEqual(p.sections[0].lanes[0].pitchBend,sequence)
        let edited=try MIDIEditing.apply(.transpose(1),to:lane,ids:Set(lane.notes.map(\.id)),beats:8)
        XCTAssertEqual(edited.pitchBend,sequence)
        ProjectEditing.duplicateArrangement(in:&p,name:"대안")
        XCTAssertEqual(try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0]).first{$0.id==lane.id}?.pitchBend,sequence)
        try ProjectEditing.detach(p.active.uses[0].id,in:&p)
        XCTAssertEqual(p.sections.last?.lanes.first{$0.id==lane.id}?.pitchBend,sequence)
        XCTAssertEqual(try SectionGraphMigration.migrate(p).schemaVersion,5)
    }
    func testSharedPatternPromotionAndProjectSaveLoad()throws {
        var p=try fixture();var pattern=RhythmPattern(name:"공유",trackID:p.tracks[0].id);pattern.notes=p.sections[0].lanes[0].notes;pattern.pitchBend=sequence;p.patterns=[pattern]
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
        try MIDIPitchBendStorage.promote(in:&p);XCTAssertEqual(p.schemaVersion,5)
        try ProjectStore.validateStructure(p)
        let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".circlr")
        defer{try? FileManager.default.removeItem(at:path)}
        let saved=try ProjectStore.save(p,to:path,mediaRoot:nil)
        XCTAssertEqual(try ProjectStore.load(path).project,saved)
        XCTAssertEqual(saved.patterns[0].pitchBend,sequence)
        p.patterns[0].pitchBend=nil;try MIDIPitchBendStorage.promote(in:&p);XCTAssertEqual(p.schemaVersion,5)
    }
    func testMalformedHiddenStorageAndSetLaneAreAtomic()throws {
        let base=try fixture();var bad=sequence;bad.events.append(.init(beat:0,kind:.value(8192)))
        for scope in ["original","override","added","pattern","take"] {
            var p=base;var lane=p.sections[0].lanes[0];lane.pitchBend=bad
            switch scope {
            case "original":p.sections[0].lanes[0]=lane
            case "override":p.arrangements[0].uses[0].laneOverrides[lane.id]=lane
            case "added":lane.id=newID();p.arrangements[0].uses[0].addedLanes.append(lane)
            case "pattern":var pattern=RhythmPattern(name:"미사용",trackID:lane.trackID);pattern.pitchBend=bad;p.patterns=[pattern]
            default:p.takes=[RecordedTake(useID:p.active.uses[0].id,name:"녹음",lane:lane)]
            }
            let before=p
            XCTAssertThrowsError(try MIDIPitchBendStorage.promote(in:&p),scope);XCTAssertEqual(p,before)
            p.schemaVersion=5;XCTAssertThrowsError(try ProjectStore.validateStructure(p),scope)
        }
        var p=base,lane=p.sections[0].lanes[0];lane.pitchBend=bad
        XCTAssertThrowsError(try ProjectEditing.setLane(lane,for:p.active.uses[0].id,original:false,in:&p));XCTAssertEqual(p,base)
    }
    func testInactiveArrangementDataRequiresSchemaFive()throws {
        var p=try fixture();var other=p.active;other.id=newID()
        var lane=p.sections[0].lanes[0];lane.pitchBend=sequence;other.uses[0].laneOverrides[lane.id]=lane;p.arrangements.append(other)
        XCTAssertThrowsError(try MIDIPitchBendStorage.validate(in:p))
        try MIDIPitchBendStorage.promote(in:&p);XCTAssertEqual(p.schemaVersion,5)
        XCTAssertNoThrow(try MIDIPitchBendStorage.validate(in:p))
    }
    func testMIDITakeReplacesExpressionIncludingNilAndSummaryMatches()throws {
        var p=try fixture();let source=p.sections[0].lanes[0],use=p.active.uses[0].id
        var take=RecordedTake(useID:use,name:"같은 노트 다른 표현",lane:source)
        take.targetLaneID=source.id;take.arrangementID=p.activeArrangementID;take.lane.pitchBend=sequence
        func matches(_ take:RecordedTake,_ project:Project)->Bool? {
            RecordedTakeSummary.make(take,arrangementID:project.activeArrangementID,useID:use,laneID:source.id,in:project)?.matchesCurrentContent
        }
        XCTAssertEqual(matches(take,p),false)
        try ProjectEditing.activateTake(take,in:&p)
        XCTAssertEqual(p.schemaVersion,5);XCTAssertEqual(matches(take,p),true)
        XCTAssertNil(p.sections[0].lanes[0].pitchBend)
        take.lane.pitchBend=nil
        XCTAssertEqual(matches(take,p),false)
        try ProjectEditing.activateTake(take,in:&p)
        XCTAssertEqual(matches(take,p),true);XCTAssertEqual(p.schemaVersion,5)
        XCTAssertNil(try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0]).first{$0.id==source.id}?.pitchBend)
        var bad=sequence;bad.initialValue=16384;take.lane.pitchBend=bad
        let before=p
        XCTAssertThrowsError(try ProjectEditing.activateTake(take,in:&p));XCTAssertEqual(p,before)
    }
    func testAudioOnlyTakePreservesExistingMIDIExpression()throws {
        var p=try fixture();var source=p.sections[0].lanes[0];source.pitchBend=sequence
        try ProjectEditing.setLane(source,for:p.active.uses[0].id,original:true,in:&p)
        let asset=Asset(name:"새 오디오",path:"take.wav",duration:2,sampleRate:48000);p.assets.append(asset)
        var recorded=Lane(trackID:source.trackID);recorded.audio=[AudioClip(assetID:asset.id,duration:1)]
        var take=RecordedTake(useID:p.active.uses[0].id,name:"오디오",lane:recorded)
        take.targetLaneID=source.id;take.arrangementID=p.activeArrangementID
        try ProjectEditing.activateTake(take,in:&p)
        let result=try XCTUnwrap(try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0]).first{$0.id==source.id})
        XCTAssertEqual(result.pitchBend,sequence);XCTAssertEqual(result.notes,source.notes);XCTAssertEqual(result.audio,recorded.audio)
        XCTAssertEqual(RecordedTakeSummary.make(take,arrangementID:p.activeArrangementID,useID:take.useID,laneID:source.id,in:p)?.matchesCurrentContent,true)
    }
}
