import Foundation
import AppKit
import Darwin
import XCTest
import CirclrCore
import CirclrAudio
@testable import CirclrApp

private actor TerminationFileJobGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    private(set) var drained = false
    private var released = false
    func hold() async {
        entered = true
        if !released { await withCheckedContinuation { continuation = $0 } }
        drained = true
    }
    func release() {
        released = true; continuation?.resume(); continuation = nil
    }
}

@MainActor final class TerminationFileJobTests: XCTestCase {
    /// Calls the real delegate entry in an isolated test process. It deliberately
    /// does NOT call NSApplication.terminate or claim to perform a native quit.
    func testApprovedTerminationCancelsRealHelperFileJobAndRejectsLatePublication() async throws {
        _ = NSApplication.shared
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let binary = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CIRCLR_TRUSTED_MCP_HELPER_BINARY"]
            ?? repo.appendingPathComponent(".build/r130-tests/debug/circlr-trusted-mcp-helper").path)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            XCTFail("Build the real circlr-trusted-mcp-helper for this process test"); return
        }
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("cterm-\(UUID().uuidString.prefix(8))")
        let store = AppStore(storageRootOverride: root)
        let gate = TerminationFileJobGate()
        defer {
            Task { await gate.release() }
            store.stopTrustedAgentTurn(); store.resetSession(); store.stopAgentBridgeForTermination()
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady: false))
        var project = Project()
        let track = project.addTrack(name: "Termination QA")
        _ = project.addSection(name: "Phrase", at: Point(), bars: 1)
        project.enableAlbum(); store.project = try SectionGraphMigration.migrate(project)
        let use = try XCTUnwrap(store.project.active.uses.first)
        store.selectHierarchy(.section(arrangementID: store.project.activeArrangementID, useID: use.id))
        store.selectedTrackID = track
        let document = root.appendingPathComponent("saved.circlr")
        store.project = try ProjectStore.saveSession(store.project, to: document, mediaRoot: nil)
        store.projectURL = document; store.mediaRoot = document; store.dirty = false
        let manifest = document.appendingPathComponent("manifest.json")
        let originalManifest = try Data(contentsOf: manifest), snapshot = store.project
        let target = root.appendingPathComponent("never-published.wav")
        let helper = try store.startAppOwnedTrustedMCPHelperTurn(exportDestination: target, executable: binary)
        let ingress = try XCTUnwrap(store.trustedAgentIngress), pid = helper.processIdentifier
        let socketPath = ingress.path
        XCTAssertTrue(helper.isRunning); XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))

        // Existing productionDrain seam: the accepted real export waits for this
        // deliberately cancellation-insensitive prior reader before it may render.
        let reader = Task.detached(priority: .utility) { () throws -> PCM in
            await gate.hold(); return PCM(frames: 48)
        }
        store.productionWorker = reader
        store.productionTask = Task { _ = try? await reader.value }
        for _ in 0..<100 {
            if await gate.entered { break }
            await Task.yield()
        }
        let entered = await gate.entered; XCTAssertTrue(entered)
        var request = AgentRequest(method: "export", id: "termination-file-export")
        request.projectID = store.project.id; request.expectedRevision = store.project.musicRevision
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
        let reply = try await helper.request(["jsonrpc": "2.0", "id": "export", "method": "tools/call",
            "params": ["name": "circlr_export", "arguments": ["request": raw]]])
        let payload = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(payload["isError"] as? Bool, false)
        let receipt = try XCTUnwrap(payload["structuredContent"] as? [String: Any])
        let jobID = try XCTUnwrap(receipt["jobID"] as? String)
        let pending = try XCTUnwrap(store.productionTask)
        XCTAssertEqual(store.agentJob?.id, jobID); XCTAssertEqual(store.agentJob?.state, "running")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        // Clean saved-document approval path cannot show a modal or call the
        // terminateLater reply API; never terminate any user's application.
        guard !store.dirty, !store.audioRecordingBusy, !store.midiRecording, store.movieFinalizing == nil else {
            XCTFail("Termination harness must remain on clean synchronous approval path"); return
        }
        let delegate = AppDelegate(); delegate.store = store
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
        XCTAssertTrue(store.agentBridgeShuttingDown); XCTAssertNil(store.trustedRun.active)
        XCTAssertNil(store.trustedAgentIngress); XCTAssertNil(store.agentSocket)
        XCTAssertEqual(store.agentJob?.id, jobID); XCTAssertEqual(store.agentJob?.state, "cancelled")
        let drainedAtReturn = await gate.drained
        XCTAssertFalse(drainedAtReturn, "terminateNow revokes publication; it does not await this test-owned reader")
        for _ in 0..<200 {
            if !helper.isRunning && Darwin.kill(pid, 0) == -1 && errno == ESRCH { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(helper.isRunning)
        XCTAssertEqual(Darwin.kill(pid, 0), -1); XCTAssertEqual(errno, ESRCH)
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
        do {
            _ = try await helper.request(["jsonrpc": "2.0", "id": "late", "method": "tools/list"])
            XCTFail("Terminated helper accepted a late request")
        } catch {}

        await gate.release()
        await pending.value
        _ = try await reader.value
        let drained = await gate.drained; XCTAssertTrue(drained)
        XCTAssertEqual(store.agentJob?.state, "cancelled")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try Data(contentsOf: manifest), originalManifest)
        XCTAssertEqual(store.project, snapshot); XCTAssertFalse(store.dirty)
    }
}
