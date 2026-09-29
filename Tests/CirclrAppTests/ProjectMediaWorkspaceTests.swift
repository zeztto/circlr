import XCTest
import AppKit
import CirclrCore
@testable import CirclrApp

@MainActor final class ProjectMediaWorkspaceTests:XCTestCase {
    func wait(_ predicate:@escaping ()->Bool) async {
        for _ in 0..<2000 {if predicate(){return};try? await Task.sleep(for:.milliseconds(2))}
        XCTFail("작업 완료 시간 초과")
    }
    func fixture() throws -> (AppStore,URL) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-media-\(UUID().uuidString)")
        let store=AppStore(storageRootOverride:root.appendingPathComponent("support"))
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady:false))
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var project=Project();project.name="미디어 복구 검사";project.enableAlbum();store.project=project;store.dirty=true
        return(store,root)
    }
    func cleanup(_ store:AppStore,_ root:URL){store.projectMedia.cancel();store.resetSession();store.pauseAgentBridgeForTermination();try? FileManager.default.removeItem(at:root)}
    func testPortableCopyColdReopensWithoutChangingOpenDocumentOrDirty() async throws {
        let(store,root)=try fixture();defer{cleanup(store,root)}
        let snapshot=store.project,target=root.appendingPathComponent("copy.circlr")
        store.projectMedia.portableCopy(to:target)
        await wait{!store.projectMedia.busy}
        XCTAssertEqual(store.projectMedia.exportedURL,target,store.projectMedia.message)
        let loaded=try ProjectStore.load(target)
        XCTAssertEqual(loaded.project.id,snapshot.id);XCTAssertEqual(loaded.project.name,snapshot.name)
        XCTAssertEqual(store.project,snapshot);XCTAssertTrue(store.dirty);XCTAssertNil(store.projectURL)
    }
    func testCancelledCopyDoesNotPublishOrClearDirty() async throws {
        let(store,root)=try fixture();defer{cleanup(store,root)}
        let snapshot=store.project,target=root.appendingPathComponent("cancel.circlr")
        store.projectMedia.portableCopy(to:target);store.projectMedia.cancel()
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.path));XCTAssertEqual(store.project,snapshot);XCTAssertTrue(store.dirty)
    }
    func testDestinationCollisionIsPreserved() async throws {
        let(store,root)=try fixture();defer{cleanup(store,root)}
        let target=root.appendingPathComponent("existing.circlr")
        try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)
        let sentinel=target.appendingPathComponent("keep");try Data("original".utf8).write(to:sentinel)
        store.projectMedia.portableCopy(to:target)
        XCTAssertFalse(store.projectMedia.busy);XCTAssertNil(store.projectMedia.exportedURL)
        XCTAssertEqual(try Data(contentsOf:sentinel),Data("original".utf8));XCTAssertTrue(store.dirty)
    }
    func testRelinkSameNameWrongContentFailsAndMatchingContentSupportsUndo() async throws {
        let(store,root)=try fixture();defer{cleanup(store,root)}
        let good=root.appendingPathComponent("good.wav"),bad=root.appendingPathComponent("elsewhere/good.wav")
        try FileManager.default.createDirectory(at:bad.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("original-content".utf8).write(to:good);try Data("different-content".utf8).write(to:bad)
        var asset=Asset(name:"good.wav",path:root.appendingPathComponent("missing.wav").path,duration:1,sampleRate:48000)
        asset.checksum=try ProjectStore.checksum(good);store.project.assets=[asset]
        let snapshot=store.project
        store.projectMedia.relink(assetID:asset.id,candidate:bad)
        await wait{!store.projectMedia.busy};XCTAssertEqual(store.project,snapshot)
        store.projectMedia.relink(assetID:asset.id,candidate:good)
        await wait{!store.projectMedia.busy}
        XCTAssertEqual(store.project.assets.first?.path,good.path)
        store.undo();XCTAssertEqual(store.project.assets.first?.path,asset.path)
    }
    func testDocumentChangedDuringCopyRejectsPublication() async throws {
        let(store,root)=try fixture();defer{cleanup(store,root)}
        let target=root.appendingPathComponent("stale.circlr")
        store.projectMedia.portableCopy(to:target)
        store.project.name="다른 곡"
        await wait{!store.projectMedia.busy}
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.path));XCTAssertEqual(store.project.name,"다른 곡")
    }
    func testMediaOverlayDoesNotDispatchMIDIEnterOrDelete() throws {
        let(store,root)=try fixture();defer{cleanup(store,root)}
        store.projectMediaOpen=true
        let snapshot=store.project
        for key in [UInt16(36),51,49,123] {
            let event=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:key))
            XCTAssertFalse(store.handleMIDIKey(event,topPitch:72))
        }
        XCTAssertEqual(store.project,snapshot)
    }

    func testCancelledPortableReaderKeepsDemoUntilDocumentRetirementDrains() async throws {
        let(store,root)=try fixture();defer{cleanup(store,root)}
        let demo=root.appendingPathComponent("owned-demo.circlr")
        _=try ProjectStore.saveSession(store.project,to:demo,mediaRoot:nil)
        let loaded=try ProjectStore.load(demo)
        store.project=loaded.project;store.mediaRoot=demo;store.projectURL=demo
        store.demoCopyLease=try DemoCopyLease(root:demo,project:store.project)
        let started=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        defer{release.signal()}
        let workspace=ProjectMediaWorkspace(store:store,preparePortable:{project,target,mediaRoot in
            started.signal()
            _=release.wait(timeout:.now()+10)
            // Deliberately ignore cancellation, like an in-progress filesystem read.
            return try ProjectStore.prepareSessionSave(project,to:target,mediaRoot:mediaRoot)
        })
        store.projectMedia=workspace
        let target=root.appendingPathComponent("copy.circlr")
        workspace.portableCopy(to:target)
        await wait{started.wait(timeout:.now()) == .success}
        workspace.cancel()
        XCTAssertTrue(workspace.draining)
        XCTAssertEqual(workspace.readerTasks.count,1)
        workspace.portableCopy(to:root.appendingPathComponent("second.circlr"))
        XCTAssertFalse(workspace.busy,"A draining reader must prevent unbounded new work")
        store.retireDemoCopy();store.project=Project();store.mediaRoot=nil;store.projectURL=nil;store.resetSession()
        for _ in 0..<20{await Task.yield()}
        XCTAssertTrue(FileManager.default.fileExists(atPath:demo.path),"The cancelled reader still owns demo IO")
        release.signal()
        await wait{!workspace.draining && !FileManager.default.fileExists(atPath:demo.path)}
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        XCTAssertTrue(workspace.readerTasks.isEmpty)
    }

}
