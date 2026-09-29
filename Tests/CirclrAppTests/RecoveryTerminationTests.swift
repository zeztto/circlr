import XCTest
import AppKit
import CirclrCore
@testable import CirclrApp

@MainActor final class RecoveryTerminationTests:XCTestCase {
    func testQuitWithDeferredRecoveryPreservesBytesAndDoesNotAdoptSession() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-deferred-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let recoveryURL=root.appendingPathComponent("recovery-v2.json")
        var prior=Project();prior.name="이전 작업";prior.enableAlbum()
        let bytes=try JSONEncoder().encode(AppStore.Recovery(project:prior,root:nil,date:Date()))
        try bytes.write(to:recoveryURL)
        let store=AppStore(storageRootOverride:root)
        defer{store.stopAgentBridgeForTermination();try? FileManager.default.removeItem(at:root)}
        XCTAssertTrue(store.hasRecoveryOwnership)
        XCTAssertFalse(store.agentStartupReady)
        XCTAssertTrue(store.canDeferStartupRecoveryAtTermination)
        let current=store.project
        let delegate=AppDelegate();delegate.store=store
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared),.terminateNow)
        XCTAssertEqual(try Data(contentsOf:recoveryURL),bytes)
        XCTAssertEqual(store.project,current,"Deferred recovery must not be adopted on quit")
        XCTAssertFalse(store.agentStartupReady)
        XCTAssertTrue(store.canDeferStartupRecoveryAtTermination)
        XCTAssertTrue(store.agentBridgeShuttingDown)
    }

    func testDirtyOrHandledDocumentDoesNotUseDeferredRecoveryQuitBypass() throws {
        _=NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-recovery-quit-routing-\(UUID().uuidString)")
        let store=AppStore(storageRootOverride:root)
        defer{store.stopAgentBridgeForTermination();try? FileManager.default.removeItem(at:root)}
        store.dirty=true
        XCTAssertFalse(store.canDeferStartupRecoveryAtTermination,"Dirty edits must still enter normal save/discard confirmation")
        store.dirty=false
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady:false))
        XCTAssertFalse(store.canDeferStartupRecoveryAtTermination,"A handled startup must use normal document termination")
        XCTAssertTrue(store.confirmTerminationDiscard())
    }
}
