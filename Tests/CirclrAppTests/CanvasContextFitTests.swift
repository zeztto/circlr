import AppKit
import XCTest
@testable import CirclrApp
import CirclrCore

@MainActor final class CanvasContextFitTests:XCTestCase {
    func testResizeRefitsBrowsingOrbitButPreservesManualZoom() throws {
        _=NSApplication.shared
        var project=Project()
        project.circleLayout = .orbit
        _=project.addTrack(name:"검증 악기")
        for index in 0..<4 {
            _=project.addSection(name:"섹션 \(index+1)",at:Point(Double(index)*240,0),bars:4)
        }
        project.enableAlbum()
        project=try SectionGraphMigration.migrate(project)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-context-fit-\(UUID().uuidString)")
        defer {try? FileManager.default.removeItem(at:root)}
        let store=AppStore(storageRootOverride:root)
        store.project=project
        store.startupOpen=false
        let canvas=AlbumCanvasView(store:store)
        canvas.frame=NSRect(x:0,y:0,width:1440,height:900)
        canvas.update();canvas.layout()
        let song=CircleAddress.composition(try XCTUnwrap(project.album?.children.first))
        canvas.focus(song)
        XCTAssertEqual(canvas.contextFitAddress,song)

        canvas.frame=NSRect(x:0,y:0,width:720,height:900)
        canvas.layout()
        let fitted=try XCTUnwrap(canvas.orbitContextCamera(song))
        XCTAssertEqual(canvas.camera.zoom,fitted.zoom,accuracy:0.000001)
        XCTAssertEqual(canvas.camera.pan.x,fitted.pan.x,accuracy:0.000001)
        XCTAssertEqual(canvas.camera.pan.y,fitted.pan.y,accuracy:0.000001)

        let expandedZoom=canvas.camera.zoom
        store.consoleBounds=CGRect(x:0,y:650,width:720,height:230)
        canvas.update() // Overlay changes the visible viewport without resizing NSView.
        let withConsole=try XCTUnwrap(canvas.orbitContextCamera(song))
        XCTAssertEqual(canvas.camera.zoom,withConsole.zoom,accuracy:0.000001)
        XCTAssertNotEqual(canvas.camera.pan.y,fitted.pan.y)
        store.consoleBounds = .zero
        canvas.update()
        XCTAssertEqual(canvas.camera.zoom,expandedZoom,accuracy:0.000001)

        canvas.setCamera(canvas.camera.zoomed(to:canvas.camera.zoom*1.4,around:Point(360,450)))
        XCTAssertNil(canvas.contextFitAddress)
        let manualZoom=canvas.camera.zoom
        canvas.frame=NSRect(x:0,y:0,width:900,height:900)
        canvas.layout()
        XCTAssertEqual(canvas.camera.zoom,manualZoom,accuracy:0.000001)
        store.consoleBounds=CGRect(x:0,y:650,width:900,height:230)
        canvas.update()
        XCTAssertEqual(canvas.camera.zoom,manualZoom,accuracy:0.000001)
    }
}
