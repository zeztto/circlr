import Foundation
import AVFAudio
import Darwin
import XCTest
import CirclrCore
import CirclrAudio
@testable import CirclrApp

private actor HelperRenderGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}

private func queuedTrustedRequest(path: String, capability: String,
                                  request: AgentRequest) throws -> [String: Any] {
    let encoded = try JSONEncoder().encode(request)
    let raw = try JSONSerialization.jsonObject(with: encoded)
    let data = try JSONSerialization.data(withJSONObject: [
        "capability": capability, "request": raw
    ]) + Data([10])
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { Darwin.close(fd) }
    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    var noSignal: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw NSError(domain: "TrustedMCPHelperProcessTests", code: 2)
    }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    try data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let n = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
            guard n > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            offset += n
        }
    }
    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while response.count <= 1_048_576 {
        let n = Darwin.read(fd, &buffer, buffer.count)
        guard n > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        response.append(contentsOf: buffer.prefix(n))
        if let end = response.firstIndex(of: 10) {
            guard let object = try JSONSerialization.jsonObject(with: response[..<end]) as? [String: Any] else {
                throw NSError(domain: "TrustedMCPHelperProcessTests", code: 3)
            }
            return object
        }
    }
    throw NSError(domain: "TrustedMCPHelperProcessTests", code: 4)
}

@MainActor final class TrustedMCPHelperProcessTests: XCTestCase {
    private func helperBinary() throws -> URL {
        if let specified = ProcessInfo.processInfo.environment["CIRCLR_TRUSTED_MCP_HELPER_BINARY"] {
            let binary = URL(fileURLWithPath: specified)
            guard binary.path == specified,
                  FileManager.default.isExecutableFile(atPath: binary.path) else {
                XCTFail("CIRCLR_TRUSTED_MCP_HELPER_BINARY must be an executable absolute path")
                throw NSError(domain: "TrustedMCPHelperProcessTests", code: 1)
            }
            return binary
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let candidate = root.appendingPathComponent(".build/debug/circlr-trusted-mcp-helper")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw XCTSkip("Build circlr-trusted-mcp-helper before process integration QA")
        }
        return candidate
    }

    private func makeStore() throws -> (AppStore, URL, ID, ID, ID, ID, ID) {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("circlr-mcp-helper-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let store = AppStore(storageRootOverride: root)
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady: false))
        var project = Project()
        let track = project.addTrack(name: "Keys")
        let other = project.addTrack(name: "Other")
        _ = project.addSection(name: "Verse", at: Point(), bars: 1)
        project.enableAlbum()
        store.project = try SectionGraphMigration.migrate(project)
        let use = try XCTUnwrap(store.project.active.uses.first)
        let section = try XCTUnwrap(store.project.sections.first { $0.id == use.sectionID })
        let lane = try XCTUnwrap(section.lanes.first { $0.trackID == track })
        let otherLane = try XCTUnwrap(section.lanes.first { $0.trackID == other })
        store.selectHierarchy(.section(arrangementID: store.project.activeArrangementID, useID: use.id))
        store.selectedTrackID = track
        XCTAssertTrue(store.agentStartupReady)
        return (store, root, store.project.activeArrangementID, use.id, lane.id, otherLane.id, track)
    }

    private func cleanUp(_ store: AppStore, root: URL) {
        store.stopTrustedAgentTurn()
        store.resetSession()
        store.pauseAgentBridgeForTermination()
        try? FileManager.default.removeItem(at: root)
    }

    private func request(_ method: String, store: AppStore, id: String) -> AgentRequest {
        var request = AgentRequest(method: method, id: id)
        request.projectID = store.project.id
        request.expectedRevision = store.project.musicRevision
        return request
    }

    private func tool(_ method: String, request: AgentRequest, rpcID: String) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        return ["jsonrpc": "2.0", "id": rpcID, "method": "tools/call",
                "params": ["name": "circlr_\(method)", "arguments": ["request": object]]]
    }

    private func result(_ reply: [String: Any]) throws -> [String: Any] {
        let payload = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(payload["isError"] as? Bool, false, "\(reply)")
        return try XCTUnwrap(payload["structuredContent"] as? [String: Any])
    }

    private func assertChildExited(_ helper: TrustedMCPHelperSession,
                                   file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<150 where helper.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(helper.isRunning, "App-owned helper must exit after turn closure",
                       file: file, line: line)
    }

    private func apply(_ store: AppStore, arrangement: ID, use: ID, lane: ID,
                       id: String, pitch: Int = 64) -> AgentRequest {
        var request = request("apply", store: store, id: id)
        var operation = AgentOperation("set_notes")
        operation.arrangementID = arrangement
        operation.useID = use
        operation.laneID = lane
        operation.notes = [Note(beat: 0, length: 1, pitch: pitch, velocity: 100)]
        var arguments = AgentArguments()
        arguments.operations = [operation]
        request.arguments = arguments
        return request
    }

    private func inspect(_ store: AppStore, arrangement: ID, use: ID, lane: ID,
                         id: String) -> AgentRequest {
        var request = request("inspect", store: store, id: id)
        var arguments = AgentArguments()
        arguments.arrangementID = arrangement
        arguments.useID = use
        arguments.laneID = lane
        request.arguments = arguments
        return request
    }

    private func bounce(_ store: AppStore, arrangement: ID, use: ID,
                        track: ID, id: String) -> AgentRequest {
        var request = request("bounce", store: store, id: id)
        var arguments = AgentArguments()
        arguments.arrangementID = arrangement
        arguments.useID = use
        arguments.trackID = track
        arguments.tailSeconds = 0
        request.arguments = arguments
        return request
    }

    func testActualChildMCPApplyUndoReapplyBounceAndLifecycle() async throws {
        let binary = try helperBinary()
        let (store, root, arrangement, use, lane, otherLane, track) = try makeStore()
        defer { cleanUp(store, root: root) }
        let helper = try store.startAppOwnedTrustedMCPHelperTurn(executable: binary)
        let ingress = try XCTUnwrap(store.trustedAgentIngress)
        XCTAssertTrue(helper.isRunning)
        XCTAssertEqual(store.trustedAgentIngress?.helperSession === helper, true)
        XCTAssertFalse(helper.processIdentifier == getpid())

        let initialized = try await helper.request(["jsonrpc": "2.0", "id": "init",
            "method": "initialize", "params": ["protocolVersion": "2025-06-18"]])
        XCTAssertEqual((initialized["result"] as? [String: Any])?["protocolVersion"] as? String,
                       "2025-06-18")
        let listed = try await helper.request(["jsonrpc": "2.0", "id": "list", "method": "tools/list"])
        let tools = try XCTUnwrap((listed["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }),
                       ["circlr_snapshot", "circlr_inspect", "circlr_apply", "circlr_bounce", "circlr_job"])
        XCTAssertFalse(String(describing: listed).contains(ingress.clientCapability))
        XCTAssertFalse(String(describing: listed).contains(ingress.path))
        let unknown = try await helper.request(["jsonrpc": "2.0", "id": "unknown",
            "method": "tools/call", "params": ["name": "circlr_save", "arguments": ["request": [:]]]])
        XCTAssertNotNil(unknown["error"])
        let disguised = try await helper.request(["jsonrpc": "2.0", "id": "disguised",
            "method": "tools/call", "params": ["name": "circlr_extra_snapshot",
                "arguments": ["request": [:]]]])
        XCTAssertNotNil(disguised["error"])
        let hugeID = try await helper.request(["jsonrpc": "2.0",
            "id": String(repeating: "x", count: 900_000), "method": "tools/list"])
        XCTAssertNotNil(hugeID["error"])
        let hugeInvalidID = try await helper.request(["jsonrpc": "2.0",
            "id": String(repeating: "x", count: 900_000)])
        XCTAssertNotNil(hugeInvalidID["error"])
        XCTAssertTrue((hugeInvalidID["id"] as? NSNull) != nil)
        XCTAssertTrue(helper.isRunning)
        let secondBootstrap = try await helper.request(["version": 1, "id": "again"])
        XCTAssertNotNil(secondBootstrap["error"])

        let snapshot = try result(await helper.request(tool("snapshot",
            request: request("snapshot", store: store, id: "snapshot"), rpcID: "s")))
        XCTAssertEqual(snapshot["projectID"] as? ID, store.project.id)
        let baseline = store.project.musicRevision
        let denied = try await helper.request(tool("apply", request: apply(store,
            arrangement: arrangement, use: use, lane: otherLane, id: "other-lane"), rpcID: "deny"))
        XCTAssertEqual((denied["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertEqual(store.project.musicRevision, baseline)
        _ = try result(await helper.request(tool("apply", request: apply(store,
            arrangement: arrangement, use: use, lane: lane, id: "first-apply"), rpcID: "a1")))
        XCTAssertEqual(store.undoCount, 1)
        let oldRevision = baseline
        var outdated = apply(store, arrangement: arrangement, use: use, lane: lane, id: "outdated")
        outdated.expectedRevision = oldRevision
        let rejected = try await helper.request(tool("apply", request: outdated, rpcID: "old"))
        XCTAssertEqual((rejected["result"] as? [String: Any])?["isError"] as? Bool, true)
        var reused = apply(store, arrangement: arrangement, use: use, lane: lane,
                           id: "first-apply", pitch: 67)
        reused.expectedRevision = baseline
        let duplicate = try await helper.request(tool("apply", request: reused, rpcID: "duplicate"))
        XCTAssertEqual((duplicate["result"] as? [String: Any])?["isError"] as? Bool, true)
        var forged = request("apply", store: store, id: "forged-path")
        var forgedArgs = AgentArguments()
        forgedArgs.path = root.appendingPathComponent("forged.wav").path
        forged.arguments = forgedArgs
        let forbidden = try await helper.request(tool("apply", request: forged, rpcID: "forbidden"))
        XCTAssertNotNil(forbidden["error"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: forgedArgs.path!))

        let withNotes = try result(await helper.request(tool("inspect", request: inspect(store,
            arrangement: arrangement, use: use, lane: lane, id: "with-notes"), rpcID: "i1")))
        XCTAssertEqual(withNotes["total"] as? Int, 1)
        store.undo()
        let afterUndo = try result(await helper.request(tool("inspect", request: inspect(store,
            arrangement: arrangement, use: use, lane: lane, id: "after-undo"), rpcID: "i2")))
        XCTAssertEqual(afterUndo["total"] as? Int, 0)
        _ = try result(await helper.request(tool("apply", request: apply(store,
            arrangement: arrangement, use: use, lane: lane, id: "reapply"), rpcID: "a2")))

        let accepted = try result(await helper.request(tool("bounce", request: bounce(store,
            arrangement: arrangement, use: use, track: track, id: "bounce"), rpcID: "b")))
        let jobID = try XCTUnwrap(accepted["jobID"] as? ID)
        var jobRequest = request("job", store: store, id: "job-status")
        jobRequest.expectedRevision = nil
        var args = AgentArguments()
        args.jobID = jobID
        jobRequest.arguments = args
        let job = try result(await helper.request(tool("job", request: jobRequest, rpcID: "j")))
        XCTAssertEqual(job["jobID"] as? ID, jobID)
        for _ in 0..<400 where store.agentJob?.state == "running" {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(store.agentJob?.state, "completed")
        let asset = try XCTUnwrap(store.project.assets.last)
        let audio = try AVAudioFile(forReading: URL(fileURLWithPath: asset.path))
        XCTAssertGreaterThan(audio.length, 0)
        let frames = AVAudioFrameCount(min(audio.length, 48_000))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat,
                                                frameCapacity: frames))
        try audio.read(into: pcm)
        let samples = try XCTUnwrap(pcm.floatChannelData)
        XCTAssertTrue((0..<Int(pcm.frameLength)).contains { abs(samples[0][$0]) > 0.0001 })

        let wasPlaying = store.playback.playing
        store.stopTrustedAgentTurn()
        try await assertChildExited(helper)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ingress.path))
        XCTAssertEqual(store.playback.playing, wasPlaying)
        await XCTAssertThrowsErrorAsync(try await helper.request(["jsonrpc": "2.0",
            "id": "late", "method": "tools/list"]))
    }

    func testDocumentSwapAndCompletedTurnCloseChild() async throws {
        let binary = try helperBinary()
        let (store, root, _, _, _, _, _) = try makeStore()
        defer { cleanUp(store, root: root) }
        let first = try store.startAppOwnedTrustedMCPHelperTurn(executable: binary)
        store.projectURL = root.appendingPathComponent("other.circlr")
        try await assertChildExited(first)
        let second = try store.startAppOwnedTrustedMCPHelperTurn(executable: binary)
        try store.completeTrustedAgentTurn(try XCTUnwrap(store.trustedRun.active))
        try await assertChildExited(second)
    }

    func testTTLClosesChildAndRevokesLease() async throws {
        let binary = try helperBinary()
        let (store, root, _, _, _, _, _) = try makeStore()
        defer { cleanUp(store, root: root) }
        let lease = try store.beginTrustedAgentTurn(sessionID: UUID().uuidString,
            turnID: UUID().uuidString, methods: ["snapshot"], targets: [], ttl: 0.05)
        let ingress = try TrustedAgentIngress(store: store, lease: lease,
            directory: root.appendingPathComponent("Agent"))
        store.trustedAgentIngress = ingress
        let helper = try ingress.startHelper(executable: binary)
        XCTAssertTrue(helper.isRunning)
        for _ in 0..<200 where store.trustedRun.active != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(store.trustedRun.active)
        try await assertChildExited(helper)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ingress.path))
    }

    func testUnexpectedChildExitRevokesTrustedTurn() async throws {
        let binary = try helperBinary()
        let (store, root, _, _, _, _, _) = try makeStore()
        defer { cleanUp(store, root: root) }
        let helper = try store.startAppOwnedTrustedMCPHelperTurn(executable: binary)
        let ingress = try XCTUnwrap(store.trustedAgentIngress)
        XCTAssertEqual(Darwin.kill(helper.processIdentifier, SIGKILL), 0)
        for _ in 0..<200 where store.trustedRun.active != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(store.trustedRun.active)
        try await assertChildExited(helper)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ingress.path))
    }

    func testQueuedWriteAfterChildCrashCannotCommitBeforeAsyncRevoke() async throws {
        let binary = try helperBinary()
        let (store, root, arrangement, use, lane, _, _) = try makeStore()
        defer { cleanUp(store, root: root) }
        let helper = try store.startAppOwnedTrustedMCPHelperTurn(executable: binary)
        let ingress = try XCTUnwrap(store.trustedAgentIngress)
        let revision = store.project.musicRevision
        let request = apply(store, arrangement: arrangement, use: use,
                            lane: lane, id: "queued-after-crash")
        let path = ingress.path, capability = ingress.clientCapability
        let pending = Task.detached(priority: .utility) {
            try? queuedTrustedRequest(path: path, capability: capability, request: request)
        }
        XCTAssertEqual(Darwin.kill(helper.processIdentifier, SIGKILL), 0)
        // Keep MainActor occupied until the socket queue has queued its
        // callback. The callback may beat the async termination handler.
        usleep(30_000)
        let reply = await pending.value
        if let reply { XCTAssertEqual(reply["ok"] as? Bool, false) }
        XCTAssertEqual(store.project.musicRevision, revision)
        XCTAssertEqual(store.undoCount, 0)
        for _ in 0..<200 where store.trustedRun.active != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(store.trustedRun.active)
        try await assertChildExited(helper)
    }

    func testSuspendedChildCannotBlockAppOnStdinWrite() async throws {
        let binary = try helperBinary()
        let (store, root, _, _, _, _, _) = try makeStore()
        defer { cleanUp(store, root: root) }
        let helper = try store.startAppOwnedTrustedMCPHelperTurn(executable: binary)
        XCTAssertEqual(Darwin.kill(helper.processIdentifier, SIGSTOP), 0)
        let start = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await helper.request(["jsonrpc": "2.0", "id": "backpressure",
                "method": "tools/list", "padding": String(repeating: "x", count: 900_000)])
            XCTFail("Suspended child must not accept a complete large frame")
        } catch {
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 5)
        }
        for _ in 0..<250 where store.trustedRun.active != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(store.trustedRun.active)
        try await assertChildExited(helper)
    }

    func testInFlightMCPReplyIsDroppedAfterStop() async throws {
        let binary = try helperBinary()
        let (store, root, _, _, _, _, _) = try makeStore()
        defer { cleanUp(store, root: root) }
        let helper = try store.startAppOwnedTrustedMCPHelperTurn(executable: binary)
        XCTAssertEqual(Darwin.kill(helper.processIdentifier, SIGSTOP), 0)
        let pending = Task { try await helper.request(["jsonrpc": "2.0",
            "id": "pending", "method": "tools/list"]) }
        try await Task.sleep(for: .milliseconds(50))
        store.stopTrustedAgentTurn()
        do {
            _ = try await pending.value
            XCTFail("Stopped turn must not deliver an in-flight MCP result")
        } catch { /* expected */ }
        XCTAssertNil(store.trustedRun.active)
        try await assertChildExited(helper)
    }

    func testCompleteRetainsAcceptedBounceWhileStopCancelsIt() async throws {
        let binary = try helperBinary()
        for shouldComplete in [true, false] {
            let (store, root, arrangement, use, lane, _, track) = try makeStore()
            defer { cleanUp(store, root: root) }
            let helper = try store.startAppOwnedTrustedMCPHelperTurn(executable: binary)
            _ = try result(await helper.request(tool("apply", request: apply(store,
                arrangement: arrangement, use: use, lane: lane, id: "seed"), rpcID: "seed")))
            let gate = HelperRenderGate()
            let priorWorker = Task.detached(priority: .utility) { () throws -> PCM in
                await gate.wait()
                return PCM(frames: 48)
            }
            store.productionWorker = priorWorker
            store.productionTask = Task { _ = try? await priorWorker.value }
            let accepted = try result(await helper.request(tool("bounce", request: bounce(store,
                arrangement: arrangement, use: use, track: track, id: "bounce"), rpcID: "bounce")))
            let jobID = try XCTUnwrap(accepted["jobID"] as? ID)
            XCTAssertEqual(store.agentJob?.state, "running")
            let acceptedTask = store.productionTask
            if shouldComplete {
                let lease = try XCTUnwrap(store.trustedRun.active)
                try store.completeTrustedAgentTurn(lease)
                XCTAssertEqual(store.trustedRun.active, lease)
            } else {
                store.stopTrustedAgentTurn()
                XCTAssertNil(store.trustedRun.active)
            }
            try await assertChildExited(helper)
            await gate.release()
            if let acceptedTask { await acceptedTask.value }
            XCTAssertEqual(store.agentJob?.id, jobID)
            XCTAssertEqual(store.agentJob?.state, shouldComplete ? "completed" : "cancelled")
            XCTAssertEqual(store.project.assets.isEmpty, !shouldComplete)
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T,
                                           file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch { /* expected */ }
}
