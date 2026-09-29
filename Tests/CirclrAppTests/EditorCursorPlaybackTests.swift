import XCTest
import CirclrCore
@testable import CirclrApp

@MainActor final class EditorCursorPlaybackTests:XCTestCase {
    func testCursorUsesSourceClockAndStartOffsetAndRejectsSharedPattern() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        var p=Project();_=p.addTrack(name:"신스")
        let useID=p.addSection(name:"구간",at:Point(),bars:2)
        p.global.tempo=120;p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        var graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let index=try XCTUnwrap(graph.nodes.firstIndex{$0.content.output == .midi})
        graph.nodes[index].settings.tempo = .local(60)
        graph.nodes[index].startBeat=2;graph.nodes[index].lengthBeats=2;graph.nodes[index].repeatCount=2
        try SectionGraphEditing.set(graph,useID:useID,original:false,in:&p)
        store.project=p;store.selection=[useID]
        store.hierarchySelection = .music(arrangementID:p.activeArrangementID,useID:useID,nodeID:graph.nodes[index].id)
        store.selectedBeat=0.75
        XCTAssertEqual(try XCTUnwrap(store.editorCursorPlaybackSeconds),1.75,accuracy:0.000001)
        XCTAssertTrue(store.canPlayFromEditorCursor)
        store.selectedBeat=2;XCTAssertNil(store.editorCursorPlaybackSeconds)
        store.selectedBeat = .nan;XCTAssertNil(store.editorCursorPlaybackSeconds)
        store.selectedBeat=0.5;store.editPatternID="shared";XCTAssertNil(store.editorCursorPlaybackSeconds)
    }
    func testCursorConvertsInheritedTempoChangesRatherThanUsingGlobalBPM() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        let id=store.project.addSection(name:"후반",at:Point(),bars:2)
        store.project.global.tempo=120;store.selection=[id];store.selectedBeat=6
        XCTAssertEqual(try XCTUnwrap(store.editorCursorPlaybackSeconds),3,accuracy:0.000001)
        store.mutate("tempo"){$0.global.tempo=60}
        XCTAssertEqual(try XCTUnwrap(store.editorCursorPlaybackSeconds),6,accuracy:0.000001)
        store.midiRecording=true;XCTAssertFalse(store.canPlayFromEditorCursor);store.midiRecording=false
    }
}
