import XCTest
@testable import CirclrCore

/// View persistence only; MIDI editing transactions are covered by the sustain editing suite.
final class SustainSavedWorkspaceTests: XCTestCase {
    func testLegacyAndMalformedSavedViewsDoNotCreatePedalState() throws {
        for json in [#"{}"#,#"{"page":"content","original":true}"#,#"{"page":"pitchBend","pitchBend":{"selectedIndex":1,"displayedBeats":16}}"#] {
            let state = try JSONDecoder().decode(StudioWorkspace.self,from:Data(json.utf8))
            XCTAssertNil(state.sustain)
        }
        let malformed = try JSONDecoder().decode(StudioWorkspace.self,from:Data(#"{"page":"sustain","original":true,"sustain":{"selectedIndex":"bad","displayedBeats":8}}"#.utf8))
        XCTAssertEqual(malformed.page,.sustain); XCTAssertTrue(malformed.original)
        XCTAssertNil(malformed.sustain)
        let invalid = try JSONDecoder().decode(StudioWorkspace.self,from:Data(#"{"page":"sustain","sustain":{"selectedIndex":100000,"displayedBeats":0}}"#.utf8))
        XCTAssertEqual(invalid.sustain,.init())
    }
    func testRestorationKeepsMIDIHostsAndRejectsAudioSectionAndMissingAddress() throws {
        let project = try StudioNavigationRhythmTests().fixture(), before = project
        let use = project.active.uses[0]
        let graph = try XCTUnwrap(SectionGraphEditing.effective(section:project.sections[0],use:use))
        let midi = try XCTUnwrap(graph.nodes.first{if case .midi = $0.content{return true};return false})
        func address(_ id:ID) -> CircleAddress {.music(arrangementID:project.active.id,useID:use.id,nodeID:id)}
        var workspace = StudioWorkspace(page:.sustain)
        workspace.original = true; workspace.sustain = .init(selectedIndex:0,displayedBeats:32)
        for target in [address(midi.id),address("rhythm-midi:\(project.tracks[0].id)")] {
            let restored = workspace.restored(at:target,in:project)
            XCTAssertEqual(restored.page,.sustain); XCTAssertEqual(restored.sustain,workspace.sustain)
            XCTAssertTrue(restored.original)
        }
        for target in [CircleAddress.section(arrangementID:project.active.id,useID:use.id),address("rhythm-audio:\(project.tracks[0].id)")] {
            let restored = workspace.restored(at:target,in:project)
            XCTAssertEqual(restored.page,.content); XCTAssertNil(restored.sustain)
        }
        XCTAssertEqual(workspace.restored(at:address("deleted"),in:project),.init())
        XCTAssertEqual(project,before,"Restoring a view must not materialize or modify MIDI expression")
    }
    func testPackageSaveReopenKeepsPedalViewCameraAndOriginalMusic() throws {
        var project = Project()
        _ = project.addTrack(name:"페달 연주")
        _ = project.addSection(name:"A",at:Point(),bars:2)
        project.tracks[0].instrument = .synthesizer(.keys)
        project.sections[0].lanes[0].notes = [.init(beat:0,length:0.5,pitch:60)]
        project.enableAlbum()
        project = try SectionGraphMigration.migrate(project)
        var lane = project.sections[0].lanes[0]
        lane.sustain = .init(channel:2,initialValue:63,events:[.init(beat:1,rawValue:127),.init(beat:2,rawValue:0)])
        try ProjectEditing.setLane(lane,for:project.active.uses[0].id,original:true,in:&project)
        let graph = try XCTUnwrap(project.sections[0].graph)
        let midi = try XCTUnwrap(graph.nodes.first{if case .midi = $0.content{return true};return false})
        let address = CircleAddress.music(arrangementID:project.active.id,useID:project.active.uses[0].id,nodeID:midi.id)
        XCTAssertNotNil(try StudioNavigation.scene(revealing:address,in:project).node(address),
            "Saved editor fixture must have an addressable album music circle before writing")
        let music = project
        var workspace = StudioWorkspace(page:.sustain)
        workspace.original = true; workspace.sustain = .init(selectedIndex:1,displayedBeats:64)
        project.hierarchyView = .init(camera:.init(pan:.init(-37,24),zoom:1.5),width:1019,height:768,
            selection:address,settingsOpen:false,midiStepMode:false,workspace:workspace)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let saved = try ProjectStore.save(project,to:directory.appendingPathComponent("pedal.circlr"),mediaRoot:nil)
        let reopened = try ProjectStore.load(directory.appendingPathComponent("pedal.circlr")).project
        XCTAssertEqual(reopened,saved)
        XCTAssertEqual(reopened.hierarchyView,project.hierarchyView)
        XCTAssertEqual(reopened.hierarchyView?.workspace?.restored(at:address,in:reopened),workspace)
        XCTAssertEqual(reopened.sections,music.sections); XCTAssertEqual(reopened.patterns,music.patterns)
        XCTAssertEqual(reopened.arrangements,music.arrangements); XCTAssertEqual(reopened.tracks,music.tracks)
        XCTAssertEqual(reopened.schemaVersion,music.schemaVersion); XCTAssertEqual(reopened.musicRevision,music.musicRevision)
        XCTAssertEqual(reopened.sections[0].lanes[0].sustain,lane.sustain)
    }
}
