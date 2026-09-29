import AppKit
import XCTest
@testable import CirclrApp

@MainActor private final class HistoryTextView:NSTextView {
    let history=UndoManager()
    override var undoManager:UndoManager? {history}
    func edit(_ text:String) {
        let previous=string
        history.registerUndo(withTarget:self){$0.edit(previous)}
        string=text
    }
}

@MainActor final class NativeTextCommandBoundaryTests:XCTestCase {
    func testFocusedTextUndoAndRedoLeaveSongHistoryUntouched() throws {
        _=NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        store.mutate("곡 이름"){$0.name="유지할 곡"}
        let project=store.project,count=store.undoCount
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:100),styleMask:[.titled],backing:.buffered,defer:false)
        let text=HistoryTextView();window.contentView=text;window.makeFirstResponder(text)
        text.string="초안"
        text.history.beginUndoGrouping();text.edit("편집한 초안");text.history.endUndoGrouping()
        store.undoFocusedContent(in:window)
        XCTAssertEqual(text.string,"초안");XCTAssertEqual(store.project,project);XCTAssertEqual(store.undoCount,count)
        store.undoFocusedContent(redo:true,in:window)
        XCTAssertEqual(text.string,"편집한 초안");XCTAssertEqual(store.project,project)
        window.makeFirstResponder(nil)
        store.undoFocusedContent(in:window)
        XCTAssertNotEqual(store.project.name,project.name)
    }
    func testMarkedTextBlocksSongUndoAndPreservesConsoleDraftUntilCommitted() throws {
        _=NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        store.mutate("곡 이름"){$0.name="유지"}
        let project=store.project
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:100),styleMask:[.titled],backing:.buffered,defer:false)
        let text=HistoryTextView();window.contentView=text;window.makeFirstResponder(text)
        text.setMarkedText("ㅎ",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        XCTAssertTrue(text.hasMarkedText())
        var command="조합 중 초안"
        XCTAssertNil(NativeTextCommandBoundary.takeConsoleCommand(&command,in:window))
        XCTAssertEqual(command,"조합 중 초안")
        store.undoFocusedContent(in:window);store.undoFocusedContent(redo:true,in:window)
        XCTAssertEqual(store.project,project);XCTAssertTrue(text.hasMarkedText())
        text.unmarkText()
        XCTAssertEqual(NativeTextCommandBoundary.takeConsoleCommand(&command,in:window),"조합 중 초안")
        XCTAssertTrue(command.isEmpty)
    }
    func testWindowFieldEditorMarkedTextDoesNotRunProjectUndoOrConsoleCommand() throws {
        _=NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        store.mutate("곡 이름"){$0.name="본문 유지"}
        let original=store.project
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:320,height:100),styleMask:[.titled],backing:.buffered,defer:false)
        let field=NSTextField(frame:NSRect(x:10,y:20,width:280,height:24))
        window.contentView?.addSubview(field)
        field.stringValue="콘솔 초안";field.selectText(nil)
        let editor=try XCTUnwrap(window.fieldEditor(true,for:field) as? NSTextView)
        XCTAssertTrue(editor.isFieldEditor)
        window.makeFirstResponder(editor)
        editor.setMarkedText("한",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        var draft="실행하지 않을 명령"
        XCTAssertNil(NativeTextCommandBoundary.takeConsoleCommand(&draft,in:window))
        store.undoFocusedContent(in:window)
        XCTAssertTrue(editor.hasMarkedText());XCTAssertEqual(store.project,original)
        XCTAssertEqual(draft,"실행하지 않을 명령")
    }

}
