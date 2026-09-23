import Foundation
import XCTest
@testable import CirclrApp
import CirclrCore

@MainActor final class TrustedAgentGatewayIntegrationTests: XCTestCase {
    private func makeStore() throws -> (AppStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("circlr-trusted-gateway-\(UUID().uuidString)", isDirectory: true)
        let store = AppStore(storageRootOverride: root)
        XCTAssertTrue(store.hasRecoveryOwnership, "The fixture must own its isolated recovery directory")
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady: false))

        var project = Project()
        _ = project.addTrack(name: "Gateway MIDI")
        _ = project.addSection(name: "Verse", at: Point(), bars: 1)
        project.enableAlbum()
        store.project = try SectionGraphMigration.migrate(project)
        XCTAssertTrue(store.agentStartupReady)
        return (store, root)
    }

    private func cleanUp(_ store: AppStore, root: URL) {
        store.stopTrustedAgentTurn()
        store.resetSession() // Cancels pending recovery writes before removing the test directory.
        store.pauseAgentBridgeForTermination()
        try? FileManager.default.removeItem(at: root)
    }

    private func targets(in project: Project) throws -> (ID, ID, ID, ID, Set<AgentRunTarget>) {
        let arrangementID = project.activeArrangementID
        let use = try XCTUnwrap(project.active.uses.first)
        let section = try XCTUnwrap(project.sections.first { $0.id == use.sectionID })
        let lane = try XCTUnwrap(section.lanes.first)
        let trackID = lane.trackID
        return (arrangementID, use.id, lane.id, trackID, [
            .section(arrangementID: arrangementID, useID: use.id),
            .lane(arrangementID: arrangementID, useID: use.id, laneID: lane.id),
            .track(trackID)
        ])
    }

    private func request(_ method: String, project: Project, id: String) -> AgentRequest {
        var request = AgentRequest(method: method, id: id)
        request.projectID = project.id
        request.expectedRevision = project.musicRevision
        return request
    }

    private func inspect(_ project: Project, arrangementID: ID, useID: ID,
                         laneID: ID, id: String) -> AgentRequest {
        var request = request("inspect", project: project, id: id)
        var arguments = AgentArguments()
        arguments.arrangementID = arrangementID
        arguments.useID = useID
        arguments.laneID = laneID
        request.arguments = arguments
        return request
    }

    private func addNote(_ project: Project, arrangementID: ID, useID: ID,
                         laneID: ID, id: String) -> AgentRequest {
        var request = request("apply", project: project, id: id)
        var operation = AgentOperation("set_notes")
        operation.arrangementID = arrangementID
        operation.useID = useID
        operation.laneID = laneID
        operation.notes = [Note(beat: 0, pitch: 64)]
        var arguments = AgentArguments()
        arguments.operations = [operation]
        request.arguments = arguments
        return request
    }

    private func bounce(_ project: Project, arrangementID: ID, useID: ID,
                        trackID: ID, id: String) -> AgentRequest {
        var request = request("bounce", project: project, id: id)
        var arguments = AgentArguments()
        arguments.arrangementID = arrangementID
        arguments.useID = useID
        arguments.trackID = trackID
        arguments.tailSeconds = 0
        request.arguments = arguments
        return request
    }

    private func noteCount(_ reply: [String: Any]) throws -> Int {
        let notes = try XCTUnwrap(reply["notes"] as? [[String: Any]])
        return notes.count
    }

    func testSnapshotInspectApplyAndUndoUseActualAppStoreHistory() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(store, root: root) }
        let (arrangementID, useID, laneID, _, scope) = try targets(in: store.project)
        let lease = try store.beginTrustedAgentTurn(sessionID: "integration-session",
            turnID: "edit-turn", methods: ["snapshot", "inspect", "apply"], targets: scope)

        let snapshot = try store.executeTrustedAgent(
            request("snapshot", project: store.project, id: "snapshot"), lease: lease)
        let initialRevision = try XCTUnwrap(snapshot["revision"] as? Int)
        XCTAssertEqual(snapshot["projectID"] as? ID, store.project.id)
        XCTAssertEqual(initialRevision, store.project.musicRevision)

        let before = try store.executeTrustedAgent(inspect(store.project,
            arrangementID: arrangementID, useID: useID, laneID: laneID, id: "inspect-before"), lease: lease)
        XCTAssertEqual(try noteCount(before), 0)
        XCTAssertEqual(before["revision"] as? Int, initialRevision)

        let applied = try store.executeTrustedAgent(addNote(store.project,
            arrangementID: arrangementID, useID: useID, laneID: laneID, id: "apply-note"), lease: lease)
        XCTAssertEqual(applied["state"] as? String, "applied")
        XCTAssertEqual(store.undoCount, 1)
        XCTAssertEqual(store.project.musicRevision, initialRevision + 1)
        let after = try store.executeTrustedAgent(inspect(store.project,
            arrangementID: arrangementID, useID: useID, laneID: laneID, id: "inspect-after"), lease: lease)
        XCTAssertEqual(try noteCount(after), 1)
        XCTAssertEqual((after["notes"] as? [[String: Any]])?.first?["pitch"] as? Int, 64)

        store.undo()
        XCTAssertEqual(store.undoCount, 0)
        XCTAssertEqual(store.project.musicRevision, initialRevision + 2)
        let undone = try store.executeTrustedAgent(inspect(store.project,
            arrangementID: arrangementID, useID: useID, laneID: laneID, id: "inspect-undone"), lease: lease)
        XCTAssertEqual(try noteCount(undone), 0)
    }

    func testStopRejectsLateRequestsAndAcceptedBounceCommitThenNewTurnProceeds() throws {
        let (store, root) = try makeStore()
        defer { cleanUp(store, root: root) }
        let (arrangementID, useID, laneID, trackID, scope) = try targets(in: store.project)
        let stopped = try store.beginTrustedAgentTurn(sessionID: "integration-session",
            turnID: "stopped-turn", methods: ["snapshot", "inspect", "apply", "bounce"], targets: scope)
        let before = store.project
        let lateApply = addNote(before, arrangementID: arrangementID, useID: useID,
                                laneID: laneID, id: "late-apply")
        let lateBounce = bounce(before, arrangementID: arrangementID, useID: useID,
                                trackID: trackID, id: "late-bounce")
        var lateSave = request("save", project: before, id: "late-save")
        lateSave.arguments = AgentArguments()
        lateSave.arguments?.path = root.appendingPathComponent("must-not-save.circlr").path
        store.stopTrustedAgentTurn()

        for late in [lateApply, lateSave, lateBounce] {
            XCTAssertThrowsError(try store.executeTrustedAgent(late, lease: stopped)) { error in
                XCTAssertTrue(error.localizedDescription.hasPrefix("trusted_run_stale:"),
                              "Unexpected error for \(late.method): \(error)")
            }
        }
        XCTAssertEqual(store.project, before)
        XCTAssertEqual(store.undoCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lateSave.arguments!.path!))

        let rendering = try store.beginTrustedAgentTurn(sessionID: "integration-session",
            turnID: "render-turn", methods: ["bounce"], targets: scope)
        let receipt = try store.executeTrustedAgent(bounce(store.project,
            arrangementID: arrangementID, useID: useID, trackID: trackID, id: "accepted-bounce"),
            lease: rendering)
        let jobID = try XCTUnwrap(receipt["jobID"] as? ID)
        XCTAssertEqual(receipt["state"] as? String, "running")
        store.stopTrustedAgentTurn()
        XCTAssertEqual(store.agentJob?.state, "cancelled")
        XCTAssertThrowsError(try store.checkTrustedAgentJobCommit(rendering, jobID: jobID))
        XCTAssertEqual(store.project, before)

        let resumed = try store.beginTrustedAgentTurn(sessionID: "integration-session",
            turnID: "next-turn", methods: ["snapshot", "apply"], targets: scope)
        let fresh = try store.executeTrustedAgent(addNote(store.project,
            arrangementID: arrangementID, useID: useID, laneID: laneID, id: "new-turn-apply"),
            lease: resumed)
        XCTAssertEqual(fresh["state"] as? String, "applied")
        XCTAssertEqual(store.project.musicRevision, before.musicRevision + 1)
        XCTAssertEqual(store.undoCount, 1)
    }
}
