import AppKit
import XCTest
import CirclrCore
@testable import CirclrApp

@MainActor final class MIDIClipboardWorkspaceTests: XCTestCase {
    func fixture() throws -> (AppStore, URL, NSPasteboard) {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-\(UUID().uuidString)")
        let store = AppStore(storageRootOverride: root)
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady: false))
        var p = Project(); let track = p.addTrack(name: "드럼", drums: true)
        _ = p.addTrack(name: "신스")
        _ = p.addSection(name: "A", at: Point(), bars: 2)
        _ = p.addSection(name: "B", at: Point(1000, 0), bars: 2)
        p.enableAlbum(); store.project = try SectionGraphMigration.migrate(p)
        store.selectedTrackID = track
        select(store, index: 0)
        var lane = try XCTUnwrap(store.currentLane)
        lane.notes = [Note(beat: 1, length: 0.25, pitch: 36, velocity: 111), Note(beat: 1.75, length: 0.5, pitch: 42, velocity: 73)]
        var project = store.project
        try ProjectEditing.setLane(lane, for: store.selectedUse!.id, original: false, in: &project)
        store.project = project; store.selectMIDINotes(Set(lane.notes.map(\.id)))
        return (store, root, NSPasteboard(name: .init("circlr-test-\(UUID().uuidString)")))
    }
    func select(_ store: AppStore, index: Int) {
        let use = store.project.active.uses[index]
        store.editPatternID = nil; store.selection = [use.id]
        store.hierarchySelection = .section(arrangementID: store.project.activeArrangementID, useID: use.id)
        store.selectMIDINotes([])
    }
    func clean(_ store: AppStore, _ root: URL, _ board: NSPasteboard) {
        board.releaseGlobally(); store.resetSession(); store.pauseAgentBridgeForTermination()
        try? FileManager.default.removeItem(at: root)
    }
    func testCopyAcrossSectionsAtCursorThenUndoRedoAndSaveReopen() throws {
        let (store, root, board) = try fixture(); defer { clean(store, root, board) }
        let original = try XCTUnwrap(store.currentLane).notes
        let sourceTrack = store.selectedTrackID
        XCTAssertTrue(store.copyMIDIPhrase(pasteboard: board)); XCTAssertEqual(store.undoCount, 0)
        select(store, index: 1); store.selectedTrackID = store.project.tracks[1].id; store.selectedBeat = 3
        XCTAssertTrue(store.pasteMIDIPhrase(pasteboard: board)); XCTAssertEqual(store.undoCount, 1)
        let pasted = try XCTUnwrap(store.currentLane).notes
        XCTAssertEqual(pasted.map(\.beat), [3, 3.75]); XCTAssertEqual(pasted.map(\.pitch), [36, 42])
        XCTAssertEqual(pasted.map(\.velocity), [111, 73]); XCTAssertTrue(Set(pasted.map(\.id)).isDisjoint(with: original.map(\.id)))
        store.undo(); XCTAssertTrue(store.currentLane?.notes.isEmpty == true)
        store.redo(); XCTAssertEqual(store.currentLane?.notes, pasted)
        let url = root.appendingPathComponent("Phrase.circlr")
        _ = try ProjectStore.saveSession(store.project, to: url, mediaRoot: nil)
        let reopened = try ProjectStore.load(url)
        XCTAssertEqual(reopened.project.active.uses, store.project.active.uses)
        select(store, index: 0); store.selectedTrackID = sourceTrack; XCTAssertEqual(store.currentLane?.notes, original)
    }
    func testCutOneUndoAndFailedPastePreservesTargetAndClipboard() throws {
        let (store, root, board) = try fixture(); defer { clean(store, root, board) }
        let original = try XCTUnwrap(store.currentLane).notes
        XCTAssertTrue(store.copyMIDIPhrase(cut: true, pasteboard: board))
        XCTAssertTrue(store.currentLane?.notes.isEmpty == true); XCTAssertEqual(store.undoCount, 1)
        store.undo(); XCTAssertEqual(store.currentLane?.notes, original)
        let bytes = board.data(forType: AppStore.midiClipboardType)
        select(store, index: 1); store.selectedBeat = store.editorBeats - 0.1
        let project = store.project, undo = store.undoCount
        XCTAssertFalse(store.pasteMIDIPhrase(pasteboard: board))
        XCTAssertEqual(store.project, project); XCTAssertEqual(store.undoCount, undo)
        XCTAssertEqual(board.data(forType: AppStore.midiClipboardType), bytes)
        board.clearContents(); board.setString("일반 텍스트", forType: .string)
        XCTAssertFalse(store.pasteMIDIPhrase(pasteboard: board)); XCTAssertEqual(store.project, project)
        XCTAssertEqual(board.string(forType: .string), "일반 텍스트")
    }
    func testPatternPasteAndOriginalBeatRemainCanonicalQuarterNotes() throws {
        let (store, root, board) = try fixture(); defer { clean(store, root, board) }
        XCTAssertTrue(store.copyMIDIPhrase(pasteboard: board))
        var pattern = RhythmPattern(name: "공유 드럼", trackID: store.selectedTrackID!)
        pattern.length = 4
        store.project.patterns.append(pattern); store.editPatternID = pattern.id; store.selectedBeat = 0
        XCTAssertTrue(store.pasteMIDIPhrase(atOriginalBeat: true, pasteboard: board))
        XCTAssertEqual(store.project.patterns.last?.notes.map(\.beat), [1, 1.75])
        XCTAssertEqual(store.project.patterns.last?.notes.map(\.pitch), [36, 42])
        XCTAssertEqual(store.undoCount, 1)
        store.undo(); XCTAssertTrue(store.project.patterns.last?.notes.isEmpty == true)
    }
    func testRecordingLockRejectsCutWithoutChangingEitherClipboardOrNotes() throws {
        let (store, root, board) = try fixture(); defer { store.midiRecording = false; clean(store, root, board) }
        board.setString("기존 텍스트", forType: .string)
        let original = store.project
        store.midiRecording = true
        XCTAssertFalse(store.copyMIDIPhrase(cut: true, pasteboard: board))
        XCTAssertEqual(store.project, original); XCTAssertEqual(board.string(forType: .string), "기존 텍스트")
    }
    func testOversizedSelectionCutKeepsSourceAndExistingClipboard() throws {
        let (store, root, board) = try fixture(); defer { clean(store, root, board) }
        var lane = try XCTUnwrap(store.currentLane)
        lane.notes = (0...MIDIClipboard.maximumNotes).map { Note(beat: Double($0 % 16) / 4, length: 0.125, pitch: 36) }
        var project = store.project
        try ProjectEditing.setLane(lane, for: store.selectedUse!.id, original: false, in: &project)
        store.project = project; store.selectMIDINotes(Set(lane.notes.map(\.id)))
        board.setString("기존 텍스트", forType: .string)
        XCTAssertFalse(store.copyMIDIPhrase(cut: true, pasteboard: board))
        XCTAssertEqual(store.project, project); XCTAssertEqual(store.undoCount, 0)
        XCTAssertEqual(board.string(forType: .string), "기존 텍스트")
    }
    func testEditorResponderActionsAndNativeKeyboardPreserveTextFocus() throws {
        let (store, root, board) = try fixture(); defer { clean(store, root, board) }
        let views: [NSView] = [OrbitMIDIView(store: store), PianoRollView(store: store),
            StepGridView(store: store, grid: try StepGrid(subdivisions: 4, beats: 8), page: 0, pitches: [36, 42])]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.close() }
        let original = try XCTUnwrap(store.currentLane).notes
        for view in views {
            store.selectMIDINotes(Set(original.map(\.id)))
            window.contentView = view; window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
            XCTAssertTrue(view.responds(to: #selector(NSText.copy(_:))))
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
            XCTAssertTrue(view.performKeyEquivalent(with: event))
            XCTAssertNotNil(NSPasteboard.general.data(forType: AppStore.midiClipboardType))
            store.selectedBeat = 4
            let paste = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9))
            XCTAssertTrue(view.performKeyEquivalent(with: paste)); XCTAssertEqual(store.currentLane?.notes.count, 4)
            let cut = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7))
            XCTAssertTrue(view.performKeyEquivalent(with: cut)); XCTAssertEqual(store.currentLane?.notes, original)
        }
        let text = NSTextView(); text.string = "텍스트 선택"; window.contentView = text
        window.makeFirstResponder(text); text.setSelectedRange(NSRange(location: 0, length: 3))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        XCTAssertFalse(store.handleMIDIBatchKey(event))
        text.copy(nil); XCTAssertEqual(NSPasteboard.general.string(forType: .string), "텍스트")
    }
}
