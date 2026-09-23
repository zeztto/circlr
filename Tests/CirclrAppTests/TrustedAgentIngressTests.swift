import Foundation
import Darwin
import XCTest
@testable import CirclrApp
import CirclrCore

private func trustedSocketRoundTrip(path: String, packet: Data,
                                    didSend: (() -> Void)? = nil) throws -> Data {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { Darwin.close(fd) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let pathBytes = Array(path.utf8) + [0]
    guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw NSError(domain: "TrustedAgentIngressTests", code: 1)
    }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    var noSignal: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    let outbound = packet + Data([10])
    try outbound.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let sent = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
            guard sent > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            offset += sent
        }
    }
    didSend?()
    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while response.count < 1_048_576 {
        let count = Darwin.read(fd, &buffer, buffer.count)
        guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        response.append(contentsOf: buffer.prefix(count))
        if let newline = response.firstIndex(of: 10) { return Data(response[..<newline]) }
    }
    throw NSError(domain: "TrustedAgentIngressTests", code: 2)
}

@MainActor final class TrustedAgentIngressTests: XCTestCase {
    private func makeStore() throws -> (AppStore, URL) {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("circlr-ti-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let store = AppStore(storageRootOverride: root)
        XCTAssertTrue(store.hasRecoveryOwnership)
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady: false))
        var project = Project()
        _ = project.addTrack(name: "IPC MIDI")
        _ = project.addSection(name: "Verse", at: Point(), bars: 1)
        project.enableAlbum()
        store.project = try SectionGraphMigration.migrate(project)
        return (store, root)
    }

    private func request(_ method: String, project: Project, id: String) -> AgentRequest {
        var request = AgentRequest(method: method, id: id)
        request.projectID = project.id
        request.expectedRevision = project.musicRevision
        return request
    }

    private func send(_ request: AgentRequest, to ingress: TrustedAgentIngress,
                      capability: String? = nil) async throws -> ([String: Any], Data) {
        let packet = try envelope(request, capability: capability ?? ingress.clientCapability)
        let path = ingress.path
        let response = try await Task.detached(priority: .utility) {
            try trustedSocketRoundTrip(path: path, packet: packet)
        }.value
        return (try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any]), response)
    }

    private func envelope(_ request: AgentRequest, capability: String) throws -> Data {
        let typed = try JSONEncoder().encode(request)
        let requestObject = try JSONSerialization.jsonObject(with: typed)
        return try JSONSerialization.data(withJSONObject: [
            "capability": capability,
            "request": requestObject
        ])
    }

    private func assertRejected(_ packet: Data, path: String) async throws {
        let reply = try? await Task.detached(priority: .utility) {
            try trustedSocketRoundTrip(path: path, packet: packet)
        }.value
        if let reply {
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
            XCTAssertEqual(result["ok"] as? Bool, false)
        }
    }

    func testTurnScopedUnixSocketCapabilityStopAndFreshIngress() async throws {
        let (store, root) = try makeStore()
        defer {
            store.stopTrustedAgentTurn()
            store.resetSession()
            store.pauseAgentBridgeForTermination()
            try? FileManager.default.removeItem(at: root)
        }
        let use = try XCTUnwrap(store.project.active.uses.first)
        let section = try XCTUnwrap(store.project.sections.first { $0.id == use.sectionID })
        let lane = try XCTUnwrap(section.lanes.first)
        let arrangementID = store.project.activeArrangementID
        let scope: Set<AgentRunTarget> = [
            .section(arrangementID: arrangementID, useID: use.id),
            .lane(arrangementID: arrangementID, useID: use.id, laneID: lane.id)
        ]
        let firstLease = try store.beginTrustedAgentTurn(sessionID: "ipc-session", turnID: "first",
            methods: ["snapshot", "apply"], targets: scope)
        let first = try TrustedAgentIngress(store: store, lease: firstLease, directory: root)
        XCTAssertNotEqual(URL(fileURLWithPath: first.path).lastPathComponent, "agent.sock")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))

        let (snapshot, snapshotBytes) = try await send(
            request("snapshot", project: store.project, id: "snapshot"), to: first)
        XCTAssertEqual(snapshot["ok"] as? Bool, true)
        let result = try XCTUnwrap(snapshot["result"] as? [String: Any])
        XCTAssertEqual(result["projectID"] as? String, store.project.id)
        XCTAssertFalse(String(decoding: snapshotBytes, as: UTF8.self).contains(first.clientCapability))

        var apply = request("apply", project: store.project, id: "apply")
        var operation = AgentOperation("set_notes")
        operation.arrangementID = arrangementID
        operation.useID = use.id
        operation.laneID = lane.id
        operation.notes = [Note(beat: 0, pitch: 64)]
        var arguments = AgentArguments()
        arguments.operations = [operation]
        apply.arguments = arguments
        let before = store.project.musicRevision
        try await assertRejected(envelope(apply, capability: String(repeating: "0", count: 64)),
                                 path: first.path)
        XCTAssertEqual(store.project.musicRevision, before)
        let (applied, appliedBytes) = try await send(apply, to: first)
        XCTAssertEqual(applied["ok"] as? Bool, true)
        XCTAssertEqual((applied["result"] as? [String: Any])?["state"] as? String, "applied")
        XCTAssertFalse(String(decoding: appliedBytes, as: UTF8.self).contains(first.clientCapability))
        XCTAssertEqual(store.project.musicRevision, before + 1)

        // Hold the MainActor while a client writes. AgentSocket dispatches
        // processing to the main queue, so STOP runs before that callback.
        var queuedApply = request("apply", project: store.project, id: "queued-apply")
        queuedApply.arguments = arguments
        let queuedPacket = try envelope(queuedApply, capability: first.clientCapability)
        let queuedPath = first.path
        let sent = DispatchSemaphore(value: 0)
        let queued = Task.detached(priority: .utility) {
            try trustedSocketRoundTrip(path: queuedPath, packet: queuedPacket) {
                sent.signal()
            }
        }
        XCTAssertEqual(sent.wait(timeout: .now() + 3), .success)
        first.stop()
        XCTAssertNil(store.trustedRun.active)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        let queuedData = try? await queued.value
        if let queuedData {
            let queuedReply = try XCTUnwrap(JSONSerialization.jsonObject(with: queuedData) as? [String: Any])
            XCTAssertEqual(queuedReply["ok"] as? Bool, false)
            XCTAssertEqual(queuedReply["error"] as? String, "trusted_run_stale")
        }
        // Socket cancellation may close the accepted client instead.
        do {
            let (late, _) = try await send(request("snapshot", project: store.project, id: "late"), to: first)
            XCTAssertEqual(late["ok"] as? Bool, false)
        } catch {
            // A removed Unix endpoint rejects a new connection.
        }
        XCTAssertEqual(store.project.musicRevision, before + 1)

        let secondLease = try store.beginTrustedAgentTurn(sessionID: "ipc-session", turnID: "second",
            methods: ["snapshot"], targets: [])
        let second = try TrustedAgentIngress(store: store, lease: secondLease, directory: root)
        defer { second.stop() }
        XCTAssertNotEqual(second.path, first.path)
        let freshRequest = request("snapshot", project: store.project, id: "fresh")
        try await assertRejected(envelope(freshRequest, capability: first.clientCapability),
                                 path: second.path)
        let (fresh, _) = try await send(freshRequest, to: second)
        XCTAssertEqual(fresh["ok"] as? Bool, true)
        XCTAssertEqual((fresh["result"] as? [String: Any])?["revision"] as? Int, before + 1)
    }

    func testLargeAuthorizedEditAndBackgroundRejectionRemainResponsive() async throws {
        let (store, root) = try makeStore()
        defer {
            store.stopTrustedAgentTurn()
            store.resetSession()
            store.pauseAgentBridgeForTermination()
            try? FileManager.default.removeItem(at: root)
        }
        let use = try XCTUnwrap(store.project.active.uses.first)
        let section = try XCTUnwrap(store.project.sections.first { $0.id == use.sectionID })
        let lane = try XCTUnwrap(section.lanes.first)
        let arrangementID = store.project.activeArrangementID
        let lease = try store.beginTrustedAgentTurn(sessionID: "ipc-session", turnID: "large-edit",
            methods: ["snapshot", "apply"], targets: [
                .section(arrangementID: arrangementID, useID: use.id),
                .lane(arrangementID: arrangementID, useID: use.id, laneID: lane.id)
            ])
        let ingress = try TrustedAgentIngress(store: store, lease: lease, directory: root)
        defer { ingress.stop() }
        var apply = request("apply", project: store.project, id: "large-apply")
        var operation = AgentOperation("set_notes")
        operation.arrangementID = arrangementID
        operation.useID = use.id
        operation.laneID = lane.id
        operation.notes = (0..<2_000).map { Note(beat: Double($0) * 0.001,
                                                pitch: 60 + $0 % 12) }
        var arguments = AgentArguments()
        arguments.operations = [operation]
        apply.arguments = arguments
        let revision = store.project.musicRevision
        let validPacket = try envelope(apply, capability: ingress.clientCapability)
        XCTAssertGreaterThan(validPacket.count, 128 * 1024)
        XCTAssertLessThan(validPacket.count, 8_388_608)
        let wrongPacket = try envelope(apply, capability: String(repeating: "0", count: 64))
        XCTAssertGreaterThan(wrongPacket.count, 128 * 1024)
        try await assertRejected(wrongPacket, path: ingress.path)
        XCTAssertEqual(store.project.musicRevision, revision)
        let (afterWrong, _) = try await send(request("snapshot", project: store.project,
                                                    id: "after-wrong-large"), to: ingress)
        XCTAssertEqual(afterWrong["ok"] as? Bool, true)

        try await assertRejected(Data(repeating: 120, count: 8_388_609), path: ingress.path)
        XCTAssertEqual(store.project.musicRevision, revision)
        let (afterOversize, _) = try await send(request("snapshot", project: store.project,
                                                       id: "after-over-8mb"), to: ingress)
        XCTAssertEqual(afterOversize["ok"] as? Bool, true)

        let (applied, _) = try await send(apply, to: ingress)
        XCTAssertEqual(applied["ok"] as? Bool, true)
        XCTAssertEqual((applied["result"] as? [String: Any])?["state"] as? String, "applied")
        XCTAssertEqual(store.project.musicRevision, revision + 1)
    }

    func testCompletedTurnLateSocketRequestPreservesOwnedBounceUntilStop() async throws {
        let (store, root) = try makeStore()
        defer {
            store.stopTrustedAgentTurn()
            store.resetSession()
            store.pauseAgentBridgeForTermination()
            try? FileManager.default.removeItem(at: root)
        }
        let use = try XCTUnwrap(store.project.active.uses.first)
        let section = try XCTUnwrap(store.project.sections.first { $0.id == use.sectionID })
        let trackID = try XCTUnwrap(section.lanes.first?.trackID)
        let arrangementID = store.project.activeArrangementID
        let lease = try store.beginTrustedAgentTurn(sessionID: "ipc-session", turnID: "completed-bounce",
            methods: ["snapshot", "bounce"], targets: [
                .section(arrangementID: arrangementID, useID: use.id), .track(trackID)
            ])
        let ingress = try TrustedAgentIngress(store: store, lease: lease, directory: root)
        var bounce = request("bounce", project: store.project, id: "accepted-bounce")
        var arguments = AgentArguments()
        arguments.arrangementID = arrangementID
        arguments.useID = use.id
        arguments.trackID = trackID
        arguments.tailSeconds = 0
        bounce.arguments = arguments
        let (accepted, _) = try await send(bounce, to: ingress)
        XCTAssertEqual(accepted["ok"] as? Bool, true)
        let jobID = try XCTUnwrap((accepted["result"] as? [String: Any])?["jobID"] as? ID)

        try store.completeTrustedAgentTurn(lease)
        let (late, _) = try await send(request("snapshot", project: store.project,
                                               id: "late-after-complete"), to: ingress)
        XCTAssertEqual(late["ok"] as? Bool, false)
        XCTAssertEqual(late["error"] as? String, "trusted_run_stale")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ingress.path))
        XCTAssertEqual(store.trustedRun.active, lease)
        XCTAssertTrue(store.trustedRun.turnCompleted)
        XCTAssertNoThrow(try store.checkTrustedAgentJobCommit(lease, jobID: jobID))

        let wasRunning = store.agentJob?.state == "running"
        ingress.stop()
        XCTAssertNil(store.trustedRun.active)
        if wasRunning { XCTAssertEqual(store.agentJob?.state, "cancelled") }
        XCTAssertThrowsError(try store.checkTrustedAgentJobCommit(lease, jobID: jobID))
    }
}
