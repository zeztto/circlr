import AppKit
import XCTest
@testable import CirclrApp
import CirclrCore

@MainActor final class CanvasSectionReorderTests: XCTestCase {
    private func fixture() throws -> (Project,[ID]) {
        var project=Project()
        project.circleLayout = .orbit
        _=project.addTrack(name:"검증 악기")
        let ids=["A","B","C"].enumerated().map { index,name in
            project.addSection(name:name,at:Point(Double(index)*300,0),bars:index+1)
        }
        let index=project.activeIndex
        project.arrangements[index].edges=zip(ids,ids.dropFirst()).map{FlowEdge(from:$0.0,to:$0.1)}
        for i in project.arrangements[index].uses.indices {
            project.arrangements[index].uses[i].isEnd=project.arrangements[index].uses[i].id==ids.last
        }
        project.enableAlbum()
        return (try SectionGraphMigration.migrate(project),ids)
    }

    private func order(_ project:Project)throws->[ID] {
        try ArrangementCompiler.compile(project).occurrences.map(\.use.id)
    }

    func testSelectedMiddleSectionMovesByOneAndUndoRestoresSongTimeWithoutMovingCanvas() throws {
        _=NSApplication.shared
        let (project,ids)=try fixture()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-section-order-\(UUID().uuidString)")
        defer {try? FileManager.default.removeItem(at:root)}
        let store=AppStore(storageRootOverride:root)
        store.project=project
        store.startupOpen=false
        let address=CircleAddress.section(arrangementID:project.activeArrangementID,useID:ids[1])
        store.selectHierarchy(address)
        let originalPositions=store.project.active.layout.positions

        XCTAssertNotNil(CanvasSectionReorder.placement(for:address,direction:.earlier,in:store.project))
        XCTAssertNotNil(CanvasSectionReorder.placement(for:address,direction:.later,in:store.project))
        XCTAssertTrue(store.moveSectionOccurrence(address,direction:.earlier))
        XCTAssertEqual(try order(store.project),[ids[1],ids[0],ids[2]])
        XCTAssertEqual(store.hierarchySelection,address)
        XCTAssertEqual(store.project.active.layout.positions,originalPositions)
        var timeline=CanvasSongTimeline(scene:try HierarchySceneBuilder.build(store.project))
        XCTAssertEqual(timeline.orderLabel(for:address),"01")
        XCTAssertEqual(store.undoCount,1)

        store.undo()
        XCTAssertEqual(try order(store.project),ids)
        XCTAssertEqual(store.hierarchySelection,address)
        XCTAssertEqual(store.project.active.layout.positions,originalPositions)
        timeline=CanvasSongTimeline(scene:try HierarchySceneBuilder.build(store.project))
        XCTAssertEqual(timeline.orderLabel(for:address),"02")

        XCTAssertTrue(store.moveSectionOccurrence(address,direction:.later))
        XCTAssertEqual(try order(store.project),[ids[0],ids[2],ids[1]])
        timeline=CanvasSongTimeline(scene:try HierarchySceneBuilder.build(store.project))
        XCTAssertEqual(timeline.orderLabel(for:address),"03")
        store.undo()
        XCTAssertEqual(try order(store.project),ids)
    }

    func testOutOfRangeAndStaleCommandsCannotCreateHistoryOrChangeSelection() throws {
        _=NSApplication.shared
        let (project,ids)=try fixture()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-section-order-bound-\(UUID().uuidString)")
        defer {try? FileManager.default.removeItem(at:root)}
        let store=AppStore(storageRootOverride:root)
        store.project=project
        store.startupOpen=false
        let first=CircleAddress.section(arrangementID:project.activeArrangementID,useID:ids[0])
        let last=CircleAddress.section(arrangementID:project.activeArrangementID,useID:ids[2])
        let canvas=AlbumCanvasView(store:store)
        canvas.frame=NSRect(x:0,y:0,width:720,height:900)
        canvas.scene=try HierarchySceneBuilder.build(project)
        func actions(for address:CircleAddress)throws->[NSMenuItem] {
            let node=try XCTUnwrap(canvas.scene?.node(address))
            let menu=canvas.circleMenu(at:NSPoint(x:360,y:450),selected:node)
            menu.update() // AppKit validates items before a popup is displayed.
            return menu.items
                .filter{$0.title.hasPrefix("순서 앞으로") || $0.title.hasPrefix("순서 뒤로")}
        }
        let firstActions=try actions(for:first),lastActions=try actions(for:last)
        XCTAssertEqual(firstActions.map(\.isEnabled),[false,true])
        XCTAssertEqual(lastActions.map(\.isEnabled),[true,false])
        store.selectHierarchy(first)
        XCTAssertNil(CanvasSectionReorder.placement(for:first,direction:.earlier,in:project))
        XCTAssertNil(CanvasSectionReorder.placement(for:last,direction:.later,in:project))
        store.showCommands()
        XCTAssertFalse(store.commandPalette?.commands.contains(where:{$0.id=="section-earlier"}) ?? true)
        XCTAssertTrue(store.commandPalette?.commands.contains(where:{$0.id=="section-later"}) ?? false)
        store.commandPalette=nil
        store.selectHierarchy(last)
        store.showCommands()
        XCTAssertTrue(store.commandPalette?.commands.contains(where:{$0.id=="section-earlier"}) ?? false)
        XCTAssertFalse(store.commandPalette?.commands.contains(where:{$0.id=="section-later"}) ?? true)
        store.commandPalette=nil
        store.selectHierarchy(first)
        XCTAssertFalse(store.moveSectionOccurrence(first,direction:.earlier))
        XCTAssertFalse(store.moveSectionOccurrence(last,direction:.later))
        XCTAssertFalse(store.moveSectionOccurrence(first,direction:.later,expectedProjectID:"different-project"))
        XCTAssertFalse(store.moveSectionOccurrence(first,direction:.later,expectedRevision:project.musicRevision+1))
        XCTAssertEqual(store.undoCount,0)
        XCTAssertEqual(store.hierarchySelection,first)
        XCTAssertEqual(try order(store.project),ids)

        var branch=project
        branch.arrangements[branch.activeIndex].edges.append(FlowEdge(from:ids[0],to:ids[2]))
        XCTAssertNil(CanvasSectionReorder.placement(for:first,direction:.later,in:branch))
    }
}
