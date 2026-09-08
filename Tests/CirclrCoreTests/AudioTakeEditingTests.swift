import XCTest
@testable import CirclrCore

final class AudioTakeEditingTests:XCTestCase {
    func fixture()throws->Project {var p=Project();_=p.addTrack(name:"녹음");_=p.addSection(name:"구간",at:Point(),bars:1);p.sections[0].lanes[0].notes=[Note(beat:0,pitch:60)];return try SectionGraphMigration.migrate(p)}
    func save(_ asset:Asset,in p:inout Project,projectID:ID?=nil,laneID:ID?=nil)throws {
        try AudioTakeEditing.save(asset:asset,projectID:projectID ?? p.id,arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:p.tracks[0].id,laneID:laneID ?? p.sections[0].lanes[0].id,clock:MusicClock(bars:1,context:p.global),in:&p)
    }
    func testRepeatedFramesBecomeTakesAndPreserveExistingMIDI()throws {
        var p=try fixture();let before=p,asset=Asset(name:"녹음",path:"take.caf",duration:5,sampleRate:44100)
        try save(asset,in:&p);let takes=try XCTUnwrap(p.takes);XCTAssertEqual(takes.count,3);XCTAssertEqual(takes.map{$0.lane.audio[0].duration},[2,2,1]);XCTAssertEqual(takes.map{$0.lane.audio[0].sourceStart},[0,2,4])
        let lane=try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0])[0]
        XCTAssertEqual(lane.notes,before.sections[0].lanes[0].notes);XCTAssertEqual(lane.audio[0].assetID,asset.id);XCTAssertEqual(lane.audio[0].preservesTail,true)
        XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
    }
    func testWrongDocumentDeletedLaneInvalidAssetAreAtomic()throws {
        var p=try fixture();let before=p,asset=Asset(name:"녹음",path:"take.caf",duration:1,sampleRate:48000)
        XCTAssertThrowsError(try save(asset,in:&p,projectID:"other"));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try save(asset,in:&p,laneID:"deleted"));XCTAssertEqual(p,before)
        for duration in [0.0,-1,Double.nan,Double.infinity,513] {var bad=asset;bad.duration=duration;XCTAssertThrowsError(try save(bad,in:&p));XCTAssertEqual(p,before)}
    }
    func testExistingAudioIsKeptAsPriorTakeAndOnlyCurrentUseChanges()throws {
        var p=try fixture();let first=Asset(name:"첫 녹음",path:"first.caf",duration:1,sampleRate:48000),second=Asset(name:"다음 녹음",path:"second.caf",duration:1.5,sampleRate:48000)
        try save(first,in:&p);_=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point());let untouched=p.active.uses[1]
        try save(second,in:&p);XCTAssertEqual(p.active.uses[1],untouched);XCTAssertTrue(p.takes!.contains{$0.lane.audio.first?.assetID==first.id});XCTAssertEqual(p.assets.count,2)
        let firstTake=p.takes!.first{$0.lane.audio.first?.assetID==first.id}!;try ProjectEditing.activateTake(firstTake,in:&p)
        XCTAssertEqual(try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0])[0].audio[0].assetID,first.id)
    }
}
