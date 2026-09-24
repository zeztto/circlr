import AppKit
import XCTest
@testable import CirclrApp
import CirclrCore

@MainActor final class SectionReorderToolbarTests:XCTestCase {
    private func fixture() throws -> (AppStore,[ID]) {
        _=NSApplication.shared
        var project=Project()
        project.circleLayout = .orbit
        _=project.addTrack(name:"순서 검증")
        let ids=["Intro","Verse","Chorus"].enumerated().map { index,name in
            project.addSection(name:name,at:Point(Double(index)*400,0),bars:4)
        }
        let index=project.activeIndex
        project.arrangements[index].edges=zip(ids,ids.dropFirst()).map{FlowEdge(from:$0.0,to:$0.1)}
        for i in project.arrangements[index].uses.indices {
            project.arrangements[index].uses[i].isEnd=project.arrangements[index].uses[i].id==ids.last
        }
        project.enableAlbum()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-reorder-toolbar-\(UUID().uuidString)")
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        let store=AppStore(storageRootOverride:root)
        store.project=try SectionGraphMigration.migrate(project)
        store.startupOpen=false
        return (store,ids)
    }

    private func address(_ id:ID,in store:AppStore)->CircleAddress {
        .section(arrangementID:store.project.activeArrangementID,useID:id)
    }
    private func order(_ store:AppStore)throws->[ID] {
        try ArrangementCompiler.compile(store.project).occurrences.map(\.use.id)
    }

    func testSelectedSectionToolbarDispatchesOneMusicalMoveAndUndoWithoutChangingCanvas() throws {
        let (store,ids)=try fixture()
        XCTAssertNil(SectionReorderToolbarState(store:store)) // An album is not a movable section.
        store.selectHierarchy(address(ids[1],in:store))
        let state=try XCTUnwrap(SectionReorderToolbarState(store:store))
        XCTAssertTrue(state.canMoveEarlier)
        XCTAssertTrue(state.canMoveLater)
        XCTAssertTrue(state.help(for:.later).contains("⇧⌥→"))
        let positions=store.project.active.layout.positions
        let revision=store.project.musicRevision

        XCTAssertTrue(state.move(.later,on:store))
        XCTAssertEqual(try order(store),[ids[0],ids[2],ids[1]])
        XCTAssertEqual(store.project.musicRevision,revision+1)
        XCTAssertEqual(store.project.active.layout.positions,positions)
        XCTAssertEqual(store.undoCount,1)
        store.undo()
        XCTAssertEqual(try order(store),ids)
        XCTAssertEqual(store.project.active.layout.positions,positions)
    }

    func testToolbarDisablesBoundaryBranchAndCaptureAndRejectsStaleSelection() throws {
        let (store,ids)=try fixture()
        store.selectHierarchy(address(ids[0],in:store))
        let first=try XCTUnwrap(SectionReorderToolbarState(store:store))
        XCTAssertFalse(first.canMoveEarlier)
        XCTAssertTrue(first.canMoveLater)
        XCTAssertTrue(first.help(for:.earlier).contains("첫 섹션"))
        XCTAssertFalse(first.move(.earlier,on:store))

        store.selectHierarchy(address(ids[2],in:store))
        let last=try XCTUnwrap(SectionReorderToolbarState(store:store))
        XCTAssertTrue(last.canMoveEarlier)
        XCTAssertFalse(last.canMoveLater)
        XCTAssertTrue(last.help(for:.later).contains("마지막 섹션"))
        XCTAssertFalse(first.move(.later,on:store)) // A cached control cannot move a new selection.

        store.selectHierarchy(address(ids[1],in:store))
        store.midiRecording=true
        let duringTake=try XCTUnwrap(SectionReorderToolbarState(store:store))
        XCTAssertFalse(duringTake.canMoveEarlier)
        XCTAssertFalse(duringTake.canMoveLater)
        XCTAssertTrue(duringTake.help(for:.later).contains("녹음"))
        XCTAssertFalse(duringTake.move(.later,on:store))
        store.midiRecording=false

        let ready=try XCTUnwrap(SectionReorderToolbarState(store:store))
        store.moviePreparing=true
        let duringVideo=try XCTUnwrap(SectionReorderToolbarState(store:store))
        XCTAssertFalse(duringVideo.canMoveEarlier)
        XCTAssertFalse(duringVideo.canMoveLater)
        XCTAssertTrue(duringVideo.help(for:.later).contains("영상"))
        XCTAssertFalse(ready.move(.later,on:store)) // Lock changes after a button is drawn.
        store.moviePreparing=false

        var branch=store.project
        branch.arrangements[branch.activeIndex].edges.append(FlowEdge(from:ids[0],to:ids[2]))
        store.project=branch
        let branched=try XCTUnwrap(SectionReorderToolbarState(store:store))
        XCTAssertFalse(branched.canMoveEarlier)
        XCTAssertFalse(branched.canMoveLater)
        XCTAssertFalse(branched.move(.later,on:store))
        XCTAssertEqual(store.undoCount,0)
    }

    func testFreeformToolbarMovesMusicButDoesNotClaimSpatialShortcutMovesSongOrder() throws {
        let (store,ids)=try fixture()
        store.project.circleLayout = .freeform
        store.selectHierarchy(address(ids[1],in:store))
        let state=try XCTUnwrap(SectionReorderToolbarState(store:store))
        XCTAssertTrue(state.canMoveLater)
        XCTAssertFalse(state.help(for:.later).contains("⇧⌥→"))
        let positions=store.project.active.layout.positions
        XCTAssertTrue(state.move(.later,on:store))
        XCTAssertEqual(try order(store),[ids[0],ids[2],ids[1]])
        XCTAssertEqual(store.project.active.layout.positions,positions)
    }
}
