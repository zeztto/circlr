import XCTest
@testable import CirclrCore

final class AudioImportPlacementTests:XCTestCase {
    func fixture()throws->Project {
        var p=Project();_=p.addTrack(name:"키보드");_=p.addSection(name:"구간",at:Point(),bars:2)
        p.sections[0].meterChanges=[MeterChange(bar:1,meter:Meter(3,8))]
        p.sections[0].tempoChanges=[TempoChange(beat:4,bpm:60)]
        return try SectionGraphMigration.migrate(p)
    }
    func target(_ p:Project)->AudioImportDestination {.section(arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:p.tracks[0].id,beat:0,position:Point(30,90),original:true)}
    func testStartUsesTargetMeterTempoAndPreservesDestination()throws {
        let p=try fixture(),before=p,t=target(p),clock=try AudioImportPlacement.clock(t,in:p)
        XCTAssertEqual(clock.beats,5.5);XCTAssertEqual(clock.seconds(at:4.5),2.5)
        let moved=try AudioImportPlacement.start(4.5,of:t,in:p)
        XCTAssertEqual(moved,.section(arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:p.tracks[0].id,beat:4.5,position:Point(30,90),original:true))
        XCTAssertEqual(AudioImportPlacement.beat(moved),4.5);XCTAssertEqual(p,before)
    }
    func testInvalidAndExclusiveEndCannotBecomeImportStart()throws {
        let p=try fixture(),t=target(p)
        for value in [-1,5.5,Double.nan,Double.infinity] {XCTAssertThrowsError(try AudioImportPlacement.start(value,of:t,in:p))}
        XCTAssertNoThrow(try AudioImportPlacement.start(5.5.nextDown,of:t,in:p))
        XCTAssertThrowsError(try AudioImportPlacement.clock(.section(arrangementID:p.active.id,useID:"missing",trackID:nil,beat:0,position:nil,original:false),in:p))
    }
    func testTrackChangePreservesScopeAndRejectsMissingTrack()throws {
        let p=try fixture(),t=try AudioImportPlacement.start(2.25,of:target(p),in:p)
        XCTAssertEqual(try AudioImportPlacement.track(nil,of:t,in:p),.section(arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:nil,beat:2.25,position:Point(30,90),original:true))
        XCTAssertThrowsError(try AudioImportPlacement.track("missing",of:t,in:p))
    }
    func testPatternUsesFractionalLoopAndCannotChangeTrack()throws {
        var p=try fixture();var pattern=RhythmPattern(name:"루프",trackID:p.tracks[0].id);pattern.length=3.25;p.patterns.append(pattern)
        let t=AudioImportDestination.pattern(id:pattern.id,beat:0)
        XCTAssertEqual(try AudioImportPlacement.clock(t,in:p).beats,3.25)
        XCTAssertEqual(try AudioImportPlacement.start(2.5,of:t,in:p),.pattern(id:pattern.id,beat:2.5))
        XCTAssertThrowsError(try AudioImportPlacement.start(3.25,of:t,in:p))
        XCTAssertThrowsError(try AudioImportPlacement.track(nil,of:t,in:p))
        XCTAssertThrowsError(try AudioImportPlacement.clock(.pattern(id:"missing",beat:0),in:p))
    }
    func testSectionSearchPreservesOrderAndIncludesPathsAndEmptyTracks() {
        let a=StudioSectionRoute(id:.section(arrangementID:"song",useID:"a"),name:"후렴",path:"앨범 › Citypop",tracks:[])
        let b=StudioSectionRoute(id:.section(arrangementID:"song",useID:"b"),name:"후렴",path:"앨범 › Nordic",tracks:[])
        XCTAssertEqual(AudioImportPlacement.sections([b,a],query:"").map(\.id),[b.id,a.id])
        XCTAssertEqual(AudioImportPlacement.sections([b,a],query:"ＣＩＴＹＰＯＰ 후렴").map(\.id),[a.id])
        XCTAssertTrue(AudioImportPlacement.sections([b,a],query:"verse").isEmpty)
    }
}
