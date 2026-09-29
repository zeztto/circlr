import Foundation
import XCTest
import CirclrCore
@testable import CirclrApp

@MainActor final class ProjectDiagnosticsFailureTests: XCTestCase {
    private func fixture() throws -> (AppStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-failure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = AppStore(storageRootOverride: root.appendingPathComponent("support"))
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady: false))
        var project = Project(); project.name = "PRIVATE_WORKING_SONG"
        _ = project.addTrack(name: "PRIVATE_TRACK")
        _ = project.addSection(name: "PRIVATE_SECTION", at: Point(), bars: 2)
        project.enableAlbum(); store.project = project; store.dirty = true
        return (store, root)
    }
    private func export(_ store: AppStore, to target: URL) {
        store.projectMedia.exportDiagnostics(to: target, appVersion: "1.3.0", appBuild: "254", runtime: .init())
    }
    private func settle(_ store: AppStore) async {
        for reader in store.projectMedia.readerTasks { await reader.value }
        for reader in store.projectMedia.readerTasks { await reader.value }
        XCTAssertFalse(store.projectMedia.busy)
        XCTAssertFalse(store.projectMedia.draining)
    }
    private func cleanup(_ store: AppStore, _ root: URL) {
        store.resetSession(); store.pauseAgentBridgeForTermination()
        try? FileManager.default.removeItem(at: root)
    }

    func testDestinationFailureKeepsExistingTargetProjectAndDirtyThenRetryWritesJSON() async throws {
        let (store, root) = try fixture(); defer { cleanup(store, root) }
        let existing = root.appendingPathComponent("existing.json", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let sentinel = existing.appendingPathComponent("keep.bin")
        let originalBytes = Data("user-owned-existing-target".utf8)
        try originalBytes.write(to: sentinel)
        let snapshot = store.project, undo = store.undoCount
        export(store, to: existing)
        await settle(store)
        XCTAssertEqual(try Data(contentsOf: sentinel), originalBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: existing.path), ["keep.bin"])
        XCTAssertEqual(store.project, snapshot); XCTAssertTrue(store.dirty)
        XCTAssertEqual(store.undoCount, undo); XCTAssertNil(store.projectURL)
        XCTAssertFalse(store.projectMedia.message.contains("저장 완료"))

        let retry = root.appendingPathComponent("retry.json")
        export(store, to: retry)
        await settle(store)
        let data = try Data(contentsOf: retry)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, "circlr-project-diagnostics-v1")
        XCTAssertLessThan(data.count, 4096)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("PRIVATE_")); XCTAssertFalse(text.contains(root.path))
        XCTAssertEqual(store.project, snapshot); XCTAssertTrue(store.dirty)
        XCTAssertEqual(store.undoCount, undo); XCTAssertEqual(try Data(contentsOf: sentinel), originalBytes)
        XCTAssertTrue(store.projectMedia.message.contains("저장 완료"))
    }

    func testImmediateCancellationNeverPublishesAndAllowsRetryAfterReaderDrain() async throws {
        let (store, root) = try fixture(); defer { cleanup(store, root) }
        let target = root.appendingPathComponent("cancelled.json"), snapshot = store.project
        // No suspension before cancellation: the MainActor publication task
        // cannot commit first, regardless of detached inspection speed.
        export(store, to: target)
        store.projectMedia.cancel()
        await settle(store)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(store.project, snapshot); XCTAssertTrue(store.dirty)
        let retry = root.appendingPathComponent("after-cancel.json")
        export(store, to: retry)
        await settle(store)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(contentsOf: retry)) as? [String: Any])
        XCTAssertEqual(store.project, snapshot); XCTAssertTrue(store.dirty)
    }

    func testSameIDDocumentEditRejectsStalePublicationWithoutChangingCurrentWork() async throws {
        let (store, root) = try fixture(); defer { cleanup(store, root) }
        let target = root.appendingPathComponent("stale.json"), projectID = store.project.id
        export(store, to: target)
        store.mutate("진단 중 사용자 편집") { $0.name = "PRIVATE_NEWER_EDIT" }
        let updated = store.project, undo = store.undoCount
        await settle(store)
        XCTAssertEqual(store.project.id, projectID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(store.project, updated); XCTAssertTrue(store.dirty)
        XCTAssertEqual(store.undoCount, undo)
        XCTAssertTrue(store.projectMedia.message.contains("곡이 바뀌었습니다"))
    }

    func testLargePrivateActivityAndJobMessageNeverAppearInExportedBytes() async throws {
        let (store, root) = try fixture(); defer { cleanup(store, root) }
        let privateText = String(repeating: "PRIVATE_COMMAND_TOKEN_", count: 50_000)
        store.recordActivity(privateText, privateText)
        store.agentJob = AgentJob(id: privateText, kind: "save", state: "failed", message: privateText, path: "/private/credential-location")
        let target = root.appendingPathComponent("redacted.json")
        store.projectMedia.exportDiagnostics(to: target, appVersion: "1.3.0", appBuild: "254",
            runtime: .init(jobKind: .save, jobState: .failed))
        await settle(store)
        let data = try Data(contentsOf: target), text = String(decoding: try Data(contentsOf: target), as: UTF8.self)
        XCTAssertLessThan(data.count, 4096)
        XCTAssertFalse(text.contains("PRIVATE_COMMAND")); XCTAssertFalse(text.contains("credential-location"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let runtime = try XCTUnwrap(json["runtime"] as? [String: Any])
        XCTAssertEqual(runtime["jobKind"] as? String, "save")
        XCTAssertEqual(runtime["jobState"] as? String, "failed")
        XCTAssertTrue(store.dirty)
    }
}
