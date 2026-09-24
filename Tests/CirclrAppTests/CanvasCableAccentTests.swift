import AppKit
import XCTest
@testable import CirclrApp
import CirclrCore

@MainActor final class CanvasCableAccentTests: XCTestCase {
    func testVisibleSelectedCableAccentDoesNotDependOnEditingTools() throws {
        _=NSApplication.shared
        var project=Project()
        project.circleLayout = .orbit
        let first=project.addSection(name:"첫 섹션",at:Point(0,0),bars:4)
        let second=project.addSection(name:"다음 섹션",at:Point(300,0),bars:4)
        project.arrangements[project.activeIndex].edges=[FlowEdge(from:first,to:second)]
        project.enableAlbum()

        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-cable-accent-\(UUID().uuidString)")
        defer {try? FileManager.default.removeItem(at:root)}
        let store=AppStore(storageRootOverride:root)
        store.project=project
        store.startupOpen=false
        let canvas=AlbumCanvasView(store:store)
        canvas.frame=NSRect(x:0,y:0,width:720,height:900)
        canvas.scene=try HierarchySceneBuilder.build(project)
        let edge=try XCTUnwrap(canvas.scene?.edges.first { $0.kind == .flow && $0.connectionID != nil })
        let id=try XCTUnwrap(edge.connectionID)
        canvas.drawingVisibleIDs=[edge.from,edge.to]
        canvas.selectedCable=id
        canvas.selectedCableProjectID=project.id
        store.playbackFollow = .following

        XCTAssertEqual(canvas.selectedCable,id)
        XCTAssertNil(canvas.cableTools)
        XCTAssertNotNil(canvas.selectedCableAccentCurve())
        XCTAssertTrue(canvas.cableEndpointHandles().isEmpty)

        // The opening MP4 frame is captured before movieWriter is assigned.
        canvas.refreshCableTools()
        XCTAssertNotNil(canvas.cableTools)
        canvas.movieCaptureDepth=1
        canvas.refreshCableTools()
        XCTAssertNil(canvas.cableTools)
        XCTAssertNil(canvas.selectedCableAccentCurve())
        XCTAssertTrue(canvas.cableEndpointHandles().isEmpty)
        canvas.movieCaptureDepth=0
        XCTAssertNotNil(canvas.selectedCableAccentCurve())

        canvas.drawingVisibleIDs=[edge.from]
        XCTAssertNil(canvas.selectedCableAccentCurve())
        canvas.drawingVisibleIDs=[edge.from,edge.to]
        canvas.selectedCableProjectID="other-project"
        XCTAssertNil(canvas.selectedCableAccentCurve())
        canvas.selectedCableProjectID=project.id
        canvas.selectedCable = .init(edgeID:"missing",from:edge.from,to:edge.to)
        XCTAssertNil(canvas.selectedCableAccentCurve())
        canvas.selectedCable=id
        store.viewingMode=true
        XCTAssertNil(canvas.selectedCableAccentCurve())
        store.viewingMode=false
        canvas.clearCableSelection()
        XCTAssertNil(canvas.selectedCableAccentCurve())
    }
}
