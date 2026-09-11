import XCTest
@testable import CirclrCore

final class AudioImportPlacementTests:XCTestCase {
    func testContainerImportDoesNotReusePreviousTrack() {
        let music=CircleAddress.music(arrangementID:"a",useID:"u",nodeID:"n")
        XCTAssertEqual(AudioImportPlacement.suggestedTrack(for:music,selectedTrack:"drums"),"drums")
        for selection:CircleAddress? in [nil,.album,.sound,.composition("c"),.section(arrangementID:"a",useID:"u"),.group(parent:music,id:"g")] {
            XCTAssertNil(AudioImportPlacement.suggestedTrack(for:selection,selectedTrack:"drums"))
        }
        XCTAssertNil(AudioImportPlacement.suggestedTrack(for:music,selectedTrack:nil))
    }
    func testDestinationLabelNamesScopeTrackAndOneBasedBeat()throws {
        let p=try fixture()
        let d=AudioImportDestination.section(arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:nil,beat:4,position:nil,original:false)
        let label=AudioImportPlacement.destinationLabel(d,in:p)
        XCTAssertTrue(label.contains("새 트랙"));XCTAssertTrue(label.contains("5박"));XCTAssertTrue(label.contains("이번 사용"))
        XCTAssertTrue(label.contains(p.active.uses[0].name))
    }
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
    func testTrackSearchNormalizesNamesAndKeepsDuplicateIdentityAndProjectOrder()throws {
        var p=try fixture();p.tracks[0].name="Nordic 패드"
        let second=p.addTrack(name:"Nordic 패드"),third=p.addTrack(name:"Citypop 키보드")
        let before=p
        let all=try AudioImportPlacement.tracks(for:target(p),in:p,query:"")
        XCTAssertEqual(all.map(\.trackID),[nil,p.tracks[0].id,second,third])
        let results=try AudioImportPlacement.tracks(for:target(p),in:p,query:"ＮＯＲＤＩＣ 패드")
        XCTAssertEqual(results.map(\.trackID),[p.tracks[0].id,second])
        XCTAssertTrue(results[0].detail.hasPrefix("1번 트랙"));XCTAssertTrue(results[1].detail.hasPrefix("2번 트랙"))
        XCTAssertEqual(AudioImportPlacement.trackLabel(p.tracks[0].id,in:p),"1 · Nordic 패드")
        XCTAssertEqual(AudioImportPlacement.trackLabel(second,in:p),"2 · Nordic 패드")
        XCTAssertEqual(AudioImportPlacement.trackLabel(nil,in:p),"새 트랙")
        XCTAssertEqual(AudioImportPlacement.trackLabel("missing",in:p),"삭제된 트랙")
        XCTAssertEqual(try AudioImportPlacement.tracks(for:target(p),in:p,query:"2번 트랙").map(\.trackID),[second])
        XCTAssertEqual(try AudioImportPlacement.tracks(for:target(p),in:p,query:"새 트랙").map(\.trackID),[nil])
        XCTAssertTrue(try AudioImportPlacement.tracks(for:target(p),in:p,query:"없는 트랙").isEmpty)
        XCTAssertEqual(p,before)
    }
    func testTrackUsageReadsRequestedUseAndOriginalScope()throws {
        var p=try fixture();var lane=p.sections[0].lanes[0]
        lane.notes=[Note(beat:0,pitch:60)];p.sections[0].lanes[0]=lane
        lane.notes.append(Note(beat:1,pitch:64))
        lane.audio=[AudioClip(assetID:"usage-only",duration:1,beat:0)]
        p.arrangements[0].uses[0].laneOverrides[lane.id]=lane
        let original=target(p),use=AudioImportDestination.section(arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:nil,beat:0,position:nil,original:false)
        let source=try AudioImportPlacement.tracks(for:original,in:p,query:"키보드")
        let local=try AudioImportPlacement.tracks(for:use,in:p,query:"키보드")
        XCTAssertTrue(source[0].detail.contains("오디오 0개 · MIDI 노트 1개"))
        XCTAssertTrue(local[0].detail.contains("오디오 1개 · MIDI 노트 2개"))
        _=p.addTrack(name:"비어 있음")
        XCTAssertTrue(try AudioImportPlacement.tracks(for:use,in:p,query:"비어 있음")[0].detail.contains("아직 사용하지 않음"))
    }
    func testTrackSearchRejectsMissingSectionAndPatternDestination()throws {
        var p=try fixture();let pattern=RhythmPattern(name:"리듬",trackID:p.tracks[0].id);p.patterns.append(pattern)
        XCTAssertThrowsError(try AudioImportPlacement.tracks(for:.section(arrangementID:p.active.id,useID:"missing",trackID:nil,beat:0,position:nil,original:false),in:p,query:""))
        XCTAssertThrowsError(try AudioImportPlacement.tracks(for:.pattern(id:pattern.id,beat:0),in:p,query:""))
    }
    func testLargeTrackCatalogSearchKeepsOriginalOrdinalAndLongName()throws {
        var p=try fixture()
        for index in 2...160 {_=p.addTrack(name:"편곡 레이어 \(index)")}
        p.tracks[149].name=String(repeating:"겨울밤의 긴 패드 이름 ",count:12)
        let choices=try AudioImportPlacement.tracks(for:target(p),in:p,query:"150번")
        XCTAssertEqual(choices.count,1);XCTAssertEqual(choices[0].trackID,p.tracks[149].id)
        XCTAssertEqual(choices[0].name,p.tracks[149].name)
        XCTAssertTrue(choices[0].detail.hasPrefix("150번 트랙"))
    }
}
