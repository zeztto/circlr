import XCTest
import AppKit
@testable import CirclrApp

@MainActor final class ProjectMediaCommandTests:XCTestCase {
    func testPaletteIncludesSearchableMediaRecoveryCommandAndUsesGuardedAction() async throws {
        _=NSApplication.shared
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-media-command-\(UUID().uuidString)")
        let store=AppStore(storageRootOverride:root)
        defer{store.projectMedia.cancel();store.pauseAgentBridgeForTermination();try? FileManager.default.removeItem(at:root)}
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady:false));store.startupOpen=false
        store.showCommands()
        let command=try XCTUnwrap(store.commandPalette?.commands.first{$0.id=="project-media"})
        for word in ["미디어","복구","누락","재연결","사본","진단"] {
            XCTAssertTrue((command.title+" "+command.detail).contains(word))
        }
        store.midiRecording=true
        command.run()
        XCTAssertFalse(store.projectMediaOpen,"Recording guard must remain active even after opening the palette")
        store.midiRecording=false
        store.startupOpen=true
        command.run();XCTAssertFalse(store.projectMediaOpen)
        store.startupOpen=false
        command.run()
        XCTAssertTrue(store.projectMediaOpen);XCTAssertNil(store.commandPalette)
        store.projectMedia.cancel()
        for reader in store.projectMedia.readerTasks {await reader.value}
    }
}
