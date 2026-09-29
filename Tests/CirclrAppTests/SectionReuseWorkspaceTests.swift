import AppKit
import XCTest
import CirclrCore
@testable import CirclrApp

@MainActor final class SectionReuseWorkspaceTests:XCTestCase {
    func testReuseAfterHasSingleUndoAndStaleContextCannotEdit()throws {
        _=NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-reuse-\(UUID().uuidString)")
        defer{try? FileManager.default.removeItem(at:root)}
        let store=AppStore(storageRootOverride:root)
        var p=Project();_ = p.addTrack(name:"신스")
        let a=p.addSection(name:"A",at:Point(),bars:1),b=p.addSection(name:"B",at:Point(1000,0),bars:1)
        try ProjectEditing.connect(from:a,to:b,in:&p)
        p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        store.project=p;store.startupOpen=false
        store.selectHierarchy(.section(arrangementID:p.activeArrangementID,useID:a))
        let context=try XCTUnwrap(store.sectionInsertionContext())
        store.reuseSection(after:context)
        let after=store.project
        XCTAssertEqual(store.undoCount,1)
        let order=try ArrangementCompiler.compile(after).occurrences.map{$0.use.id}
        XCTAssertEqual(order.count,3);XCTAssertEqual(order.first,a);XCTAssertEqual(order.last,b)
        XCTAssertEqual(after.sections,p.sections)
        store.reuseSection(after:context)
        XCTAssertEqual(store.project,after);XCTAssertEqual(store.undoCount,1)
        store.undo()
        XCTAssertEqual(try ArrangementCompiler.compile(store.project).occurrences.map{$0.use.id},[a,b])
        store.redo()
        XCTAssertEqual(try ArrangementCompiler.compile(store.project).occurrences.map{$0.use.id},order)
    }
}
