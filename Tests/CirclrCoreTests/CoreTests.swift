import XCTest
@testable import CirclrCore

final class CoreTests: XCTestCase {
    func song() -> Project {
        var p = Project(); _ = p.addTrack(name:"악기")
        let a = p.addSection(name:"벌스",at:Point(),bars:8), b = p.addSection(name:"브리지",at:Point(240,0),bars:4)
        try! ProjectEditing.connect(from:a,to:b,in:&p)
        p.arrangements[0].uses[1].settings.tempo = .local(96)
        p.arrangements[0].uses[1].settings.meter = .local(Meter(7,8))
        return p
    }
    func testIndependentTempoAndMeterAndOverlap() throws {
        var p = song(); var plan = try ArrangementCompiler.compile(p)
        XCTAssertEqual(plan.duration,24.75,accuracy:0.0000001)
        XCTAssertEqual(plan.occurrences[0].clock.beats,32); XCTAssertEqual(plan.occurrences[1].clock.beats,14)
        p.arrangements[0].edges[0].transition.mode = .overlap
        p.arrangements[0].edges[0].transition.length = 1
        plan = try ArrangementCompiler.compile(p)
        XCTAssertEqual(plan.duration,22.75,accuracy:0.0000001)
        XCTAssertEqual(plan.occurrences[1].start,14,accuracy:0.0000001)
        p.arrangements[0].edges[0].transition.mode = .insert
        XCTAssertEqual(try ArrangementCompiler.compile(p).duration,26.75,accuracy:0.0000001)
    }
    func testFieldInheritanceAndGlobalReset() throws {
        var p = song(); p.global.tempo = 132; p.global.scale = Scale(root:5)
        var result = try ArrangementCompiler.compile(p)
        XCTAssertEqual(result.occurrences[0].context.tempo,132)
        XCTAssertEqual(result.occurrences[1].context.tempo,96)
        XCTAssertEqual(result.occurrences[1].context.scale.root,5)
        p.sections[1].settings.tempo = .local(80)
        p.arrangements[0].uses[1].settings.tempo = Setting(source:.global)
        result = try ArrangementCompiler.compile(p)
        XCTAssertEqual(result.occurrences[1].context.tempo,132)
        p.arrangements[0].uses[1].settings.rhythm = .local(RhythmAssignment())
        XCTAssertNil(try ArrangementCompiler.compile(p).occurrences[1].context.rhythm.patternID)
    }
    func testRepeatIsTotalAndUnfoldPreservesPlan() throws {
        var p = song(); let id = p.active.uses[0].id
        p.arrangements[0].uses[0].repeatCount = 2
        let before = try ArrangementCompiler.compile(p)
        XCTAssertEqual(before.duration,40.75,accuracy:0.0000001)
        XCTAssertEqual(before.occurrences.map(\.iteration),[0,1,0])
        try ProjectEditing.unfoldRepeats(id,in:&p)
        let after = try ArrangementCompiler.compile(p)
        XCTAssertEqual(after.duration,before.duration,accuracy:0.0000001)
        XCTAssertEqual(after.occurrences.count,3)
        XCTAssertEqual(after.occurrences.map(\.section.id),before.occurrences.map(\.section.id))
    }
    func testVariantKeepsOriginalAndNewArrangementIndependent() throws {
        var p = song(); let use = p.active.uses[0]; var lane = p.sections[0].lanes[0]
        lane.notes = [Note(beat:0,pitch:60)]
        try ProjectEditing.setLane(lane,for:use.id,original:false,in:&p)
        XCTAssertTrue(p.sections[0].lanes[0].notes.isEmpty)
        XCTAssertEqual(try ArrangementCompiler.compile(p).occurrences[0].lanes[0].notes[0].pitch,60)
        let firstID = p.active.id
        ProjectEditing.duplicateArrangement(in:&p,name:"B")
        XCTAssertNotEqual(firstID,p.active.id); XCTAssertNotEqual(use.id,p.active.uses[0].id)
        p.arrangements[p.activeIndex].uses[0].laneOverrides[lane.id]?.notes[0].pitch = 72
        XCTAssertEqual(p.arrangements[0].uses[0].laneOverrides[lane.id]?.notes[0].pitch,60)
    }
    func testOrphanOverrideFailsInsteadOfDiscarding() throws {
        var p = song(); let lane = p.sections[0].lanes[0]
        try ProjectEditing.setLane(lane,for:p.active.uses[0].id,original:false,in:&p)
        p.sections[0].lanes = []
        XCTAssertThrowsError(try ArrangementCompiler.compile(p))
    }
    func testClockRingVariableMeterAndTempoInverse() throws {
        let clock = try MusicClock(bars:2,context:MusicContext(),meterChanges:[MeterChange(bar:1,meter:Meter(7,8))],tempoChanges:[TempoChange(beat:4,bpm:96)])
        XCTAssertEqual(clock.angle(at:4),192,accuracy:0.0000001)
        XCTAssertEqual(clock.seconds,4.1875,accuracy:0.0000001)
        for q in stride(from:0.0,through:7.5,by:0.03125) { XCTAssertEqual(clock.beat(atSeconds:clock.seconds(at:q)),q,accuracy:0.00000001) }
    }
    func testLayoutNeverChangesExecution() throws {
        var p = song(); let before = try ArrangementCompiler.compile(p)
        p.arrangements[0].layout.pan = Point(999,-420); p.arrangements[0].layout.zoom = 0.5
        p.arrangements[0].layout.groups = [CanvasGroup(name:"그룹",members:p.active.uses.map(\.id))]
        p.arrangements[0].layout.groups[0].collapsed = true
        let after = try ArrangementCompiler.compile(p)
        XCTAssertEqual(after.duration,before.duration)
        XCTAssertEqual(after.occurrences.map(\.start),before.occurrences.map(\.start))
    }
    func testCycleAndUnresolvedBranchesAndInvalidTempoFail() throws {
        var p = song(); let a = p.active.uses[0].id, b = p.active.uses[1].id
        XCTAssertThrowsError(try ProjectEditing.connect(from:b,to:a,in:&p))
        let c = p.addSection(name:"다른 끝",at:Point(500,100))
        try ProjectEditing.connect(from:a,to:c,in:&p)
        XCTAssertThrowsError(try ArrangementCompiler.compile(p))
        p.arrangements[0].chosenEdges[a] = p.active.edges.first(where:{$0.to == b})!.id
        XCTAssertNoThrow(try ArrangementCompiler.compile(p))
        p.global.tempo = .nan
        XCTAssertThrowsError(try ArrangementCompiler.compile(p))
    }
    func testNoThreeWayOverlap() throws {
        var p = song(); let b = p.active.uses[1].id
        let c = p.addSection(name:"후렴",at:Point(500,0),bars:8)
        try ProjectEditing.connect(from:b,to:c,in:&p)
        for i in p.arrangements[0].edges.indices { p.arrangements[0].edges[i].transition.mode = .overlap; p.arrangements[0].edges[i].transition.anchor = .seconds; p.arrangements[0].edges[i].transition.length = 5 }
        XCTAssertThrowsError(try ArrangementCompiler.compile(p))
    }
    func testPackageRoundtripPreservesAssetBytesAndRejectsEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(newID())
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:root) }
        let source = root.appendingPathComponent("recorded.bin"), bytes = Data([0,5,9,255,17])
        try bytes.write(to:source)
        var p = song(); p.assets = [Asset(name:"원본",path:source.path,duration:1,sampleRate:48000)]
        let url = root.appendingPathComponent("song.circlr")
        let saved = try ProjectStore.save(p,to:url,mediaRoot:nil)
        XCTAssertEqual(try Data(contentsOf:source),bytes)
        let loaded = try ProjectStore.load(url)
        XCTAssertEqual(saved,loaded.project)
        XCTAssertEqual(try Data(contentsOf:ProjectStore.assetURL(saved.assets[0],root:url)),bytes)
        _ = try ProjectStore.save(saved,to:url,mediaRoot:url)
        var invalid = saved.assets[0]; invalid.path = "../../escape"
        XCTAssertThrowsError(try ProjectStore.assetURL(invalid,root:url))
    }
}
