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
    func testVisibleLowerRightCircleDoesNotJumpAboveConsoleOnKeyboardReveal() throws {
        _=NSApplication.shared
        var project=Project();project.circleLayout = .orbit
        _=project.addTrack(name:"검증 악기")
        _=project.addSection(name:"후렴",at:Point(),bars:4)
        project.enableAlbum();project=try SectionGraphMigration.migrate(project)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-l-fit-\(UUID().uuidString)")
        defer{try? FileManager.default.removeItem(at:root)}
        let store=AppStore(storageRootOverride:root);store.project=project;store.startupOpen=false
        store.consoleBounds=CGRect(x:20,y:704,width:820,height:180)
        let canvas=AlbumCanvasView(store:store);canvas.frame=NSRect(x:0,y:0,width:1440,height:900)
        canvas.update();canvas.layout()
        XCTAssertTrue(canvas.cablePointAvailable(Point(1050,740),labels:false))
        XCTAssertFalse(canvas.cablePointAvailable(Point(100,740),labels:false))
        let node=try XCTUnwrap(canvas.scene?.nodes.first{$0.role == .music && $0.childCount == 0})
        let radius=node.outerRadius
        XCTAssertLessThan(radius,200)
        let destination=Point(1100,min(770,820-radius))
        canvas.camera=HierarchyCamera(pan:Point(destination.x-node.center.x,destination.y-node.center.y),zoom:1)
        let original=canvas.camera
        canvas.contextFitAddress = node.id
        XCTAssertTrue(CanvasWorkspaceGeometry.circlesVisible([
            CanvasLabelCircle(id:node.id,center:CGPoint(x:node.center.x,y:node.center.y),radius:radius)
        ],through:original,within:canvas.canvasViewport,avoiding:store.consoleBounds))
        canvas.revealKeyboardSelection(node)
        XCTAssertEqual(canvas.camera,original)
        XCTAssertEqual(canvas.contextFitAddress,node.id)
        let port=try XCTUnwrap(node.ports.first)
        canvas.selectCanvasPort(CirclePortEndpoint(node:node.id,portID:port.id))
        XCTAssertEqual(canvas.camera,original)
    }
    func testManuallyDistantSongSatelliteDoesNotCollapseLocalFit() throws {
        _=NSApplication.shared
        var project=Project();project.circleLayout = .orbit
        _=project.addTrack(name:"검증 악기")
        _=project.addSection(name:"가까운 벌스",at:Point(0,0),bars:4)
        _=project.addSection(name:"가까운 후렴",at:Point(240,0),bars:4)
        let remote=project.addSection(name:"먼 메모",at:Point(30_000,0),bars:4)
        project.arrangements[project.activeIndex].layout.orbitLayoutVersion=1
        project.arrangements[project.activeIndex].layout.orbitPositions=[remote:Point(30_000,0)]
        project.enableAlbum();project=try SectionGraphMigration.migrate(project)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-distant-fit-\(UUID().uuidString)")
        defer{try? FileManager.default.removeItem(at:root)}
        let store=AppStore(storageRootOverride:root);store.project=project;store.startupOpen=false
        store.consoleBounds=CGRect(x:20,y:704,width:820,height:180)
        let canvas=AlbumCanvasView(store:store);canvas.frame=NSRect(x:0,y:0,width:1440,height:900)
        canvas.update();canvas.layout()
        let scene=try XCTUnwrap(canvas.scene)
        let song=try XCTUnwrap(scene.nodes.first{$0.role == .song})
        let distant=scene.immediateSatellites(of:song.id).filter { child in
            hypot(child.center.x-song.center.x,child.center.y-song.center.y)>song.radius*8+child.outerRadius
        }
        XCTAssertFalse(distant.isEmpty)
        let local=try XCTUnwrap(canvas.orbitContextCamera(song.id))
        let all=try XCTUnwrap(CanvasWorkspaceGeometry.fittingCamera(
            circles:CanvasWorkspaceGeometry.contextCircles(song.id,in:scene),within:canvas.canvasViewport,
            avoiding:store.consoleBounds,marginX:50,marginY:50))
        XCTAssertGreaterThan(local.zoom,all.zoom*5)
    }
}
