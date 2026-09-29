import XCTest
import CirclrCore
@testable import CirclrApp

@MainActor final class RecoveryPreservationNoticeTests:XCTestCase {
    func testUnreadableRecoveryIsPreservedBeforeVisibleFailureNotice() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-recovery-notice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let original=root.appendingPathComponent("recovery-v2.json")
        let bytes=Data("{broken-recovery-json".utf8)
        try bytes.write(to:original)
        let store=AppStore(storageRootOverride:root)
        defer{store.stopAgentBridgeForTermination();try? FileManager.default.removeItem(at:root)}
        let snapshot=store.project
        var notices:[URL]=[]
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady:false,onPreservedRecovery:{location in
            notices.append(location)
            XCTAssertEqual(try? Data(contentsOf:location),bytes,"Present only after original bytes are safely preserved")
            XCTAssertFalse(store.agentStartupReady,"The notice precedes continuing to a new session")
        }))
        let preserved=try XCTUnwrap(notices.first)
        XCTAssertEqual(notices.count,1)
        XCTAssertNotEqual(preserved,original)
        XCTAssertEqual(preserved.deletingLastPathComponent().path,root.path)
        XCTAssertEqual(try Data(contentsOf:preserved),bytes)
        XCTAssertEqual(store.project,snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath:original.path))
        store.clearSavedRecovery()
        XCTAssertEqual(try Data(contentsOf:preserved),bytes,"Ordinary recovery cleanup must not erase the preserved source")
    }
}
