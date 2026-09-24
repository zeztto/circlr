import Foundation
import Darwin
import AVFAudio
import XCTest
@testable import CirclrApp
import CirclrCore
import CirclrAudio

/// Holds an earlier production worker until AI STOP has revoked the new
/// bounce. The worker deliberately ignores cancellation, as real renderers
/// may need time to drain already allocated PCM.
private actor AppTurnRenderGate {
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

private func appTurnRoundTrip(path: String, packet: Data) throws -> [String: Any] {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { Darwin.close(fd) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw NSError(domain: "AppOwnedAgentTurnTests", code: 1)
    }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
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
            let written = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
            guard written > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            offset += written
        }
    }
    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while response.count < 1_048_576 {
        let count = Darwin.read(fd, &buffer, buffer.count)
        guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        response.append(contentsOf: buffer.prefix(count))
        if let end = response.firstIndex(of: 10) {
            return try XCTUnwrap(JSONSerialization.jsonObject(with: response[..<end]) as? [String: Any])
        }
    }
    throw NSError(domain: "AppOwnedAgentTurnTests", code: 2)
}

@MainActor final class AppOwnedAgentTurnIntegrationTests: XCTestCase {
    private func makeStore() throws -> (AppStore, URL, ID, ID, ID, ID) {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("circlr-at-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let store = AppStore(storageRootOverride: root)
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady: false))
        var project = Project()
        let trackID = project.addTrack(name: "Selected Keys")
        _ = project.addTrack(name: "Unselected Keys")
        _ = project.addSection(name: "Verse", at: Point(), bars: 1)
        project.enableAlbum()
        store.project = try SectionGraphMigration.migrate(project)
        let use = try XCTUnwrap(store.project.active.uses.first)
        let section = try XCTUnwrap(store.project.sections.first { $0.id == use.sectionID })
        let lane = try XCTUnwrap(section.lanes.first { $0.trackID == trackID })
        store.selectHierarchy(.section(arrangementID: store.project.activeArrangementID, useID: use.id))
        store.selectedTrackID = trackID
        XCTAssertTrue(store.agentStartupReady)
        return (store, root, store.project.activeArrangementID, use.id, lane.id, trackID)
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

    private func send(_ request: AgentRequest, via ingress: TrustedAgentIngress,
                      capability: String? = nil) async throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let packet = try JSONSerialization.data(withJSONObject: [
            "capability": capability ?? ingress.clientCapability, "request": object
        ])
        let path = ingress.path
        return try await Task.detached(priority: .utility) {
            try appTurnRoundTrip(path: path, packet: packet)
        }.value
    }

    private func assertSocketClosed(_ ingress: TrustedAgentIngress, store: AppStore) async throws {
        let path = ingress.path
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        do {
            let late = try await send(request("snapshot", store: store, id: UUID().uuidString), via: ingress)
            XCTAssertEqual(late["ok"] as? Bool, false)
        } catch {
            // Unlinked Unix sockets reject new connects.
        }
    }

    private func apply(_ store: AppStore, arrangement: ID, use: ID, lane: ID, id: String) -> AgentRequest {
        var request = request("apply", store: store, id: id)
        var operation = AgentOperation("set_notes")
        operation.arrangementID = arrangement
        operation.useID = use
        operation.laneID = lane
        operation.notes = [Note(beat: 0, length: 1, pitch: 64, velocity: 100)]
        var args = AgentArguments()
        args.operations = [operation]
        request.arguments = args
        return request
    }

    private func bounce(_ store: AppStore, arrangement: ID, use: ID, track: ID, id: String) -> AgentRequest {
        var request = request("bounce", store: store, id: id)
        var args = AgentArguments()
        args.arrangementID = arrangement
        args.useID = use
        args.trackID = track
        args.tailSeconds = 0
        request.arguments = args
        return request
    }

    private func inspect(_ store: AppStore, arrangement: ID, use: ID, lane: ID, id: String) -> AgentRequest {
        var request = request("inspect", store: store, id: id)
        var args = AgentArguments()
        args.arrangementID = arrangement
        args.useID = use
        args.laneID = lane
        request.arguments = args
        return request
    }

    private func job(_ store: AppStore, jobID: ID, id: String) -> AgentRequest {
        var request = request("job", store: store, id: id)
        request.expectedRevision = nil
        var args = AgentArguments()
        args.jobID = jobID
        request.arguments = args
        return request
    }

    private func notes(_ store: AppStore, useID: ID, laneID: ID) throws -> [Note] {
        let use = try XCTUnwrap(store.project.active.uses.first { $0.id == useID })
        let section = try XCTUnwrap(store.project.sections.first { $0.id == use.sectionID })
        return try XCTUnwrap(ArrangementCompiler.effectiveLanes(section: section, use: use)
            .first { $0.id == laneID }).notes
    }

    private func selectSavedDocument(_ store:AppStore,root:URL) throws -> URL {
        let target=root.appendingPathComponent("Agent Song.circlr",isDirectory:true)
        store.project=try ProjectStore.saveSession(store.project,to:target,mediaRoot:nil)
        store.projectURL=target
        store.mediaRoot=target
        store.dirty=false
        return target
    }

    private func waitForOwnedJob(_ store:AppStore,id:ID) async throws {
        for _ in 0..<400 where store.agentJob?.id==id && store.agentJob?.state=="running" {
            try await Task.sleep(for:.milliseconds(50))
        }
        XCTAssertEqual(store.agentJob?.id,id)
        XCTAssertEqual(store.agentJob?.state,"completed",store.agentJob?.message ?? "")
    }

    func testTrustedEditSaveReopenAndExportUseAppSelectedDestinations() async throws {
        let (store,root,arrangement,use,lane,_)=try makeStore()
        defer {cleanUp(store,root:root)}
        let document=try selectSavedDocument(store,root:root)
        let output=root.appendingPathComponent("approved-render.wav")
        let ingress=try store.startAppOwnedTrustedAgentTurn(exportDestination:output)
        XCTAssertTrue(store.trustedRun.active?.methods.contains("save") == true)
        XCTAssertTrue(store.trustedRun.active?.methods.contains("export") == true)
        var forged=request("save",store:store,id:"forged-save-path")
        var forgedArgs=AgentArguments();forgedArgs.path=root.appendingPathComponent("other.circlr").path
        forged.arguments=forgedArgs
        let denied=try await send(forged,via:ingress)
        XCTAssertEqual(denied["ok"] as? Bool,false)
        XCTAssertFalse(FileManager.default.fileExists(atPath:forgedArgs.path!))
        let edit=try await send(apply(store,arrangement:arrangement,use:use,lane:lane,
                                      id:"notes-before-save"),via:ingress)
        XCTAssertEqual(edit["ok"] as? Bool,true)

        let saveReply=try await send(request("save",store:store,id:"save-selected-document"),via:ingress)
        XCTAssertEqual(saveReply["ok"] as? Bool,true)
        let savedReceipt=try XCTUnwrap(saveReply["result"] as? [String:Any])
        XCTAssertNil(savedReceipt["path"])
        let saveJob=try XCTUnwrap(savedReceipt["jobID"] as? ID)
        try await waitForOwnedJob(store,id:saveJob)
        let reopened=try ProjectStore.load(document)
        let savedUse=try XCTUnwrap(reopened.project.active.uses.first{$0.id==use})
        let savedSection=try XCTUnwrap(reopened.project.sections.first{$0.id==savedUse.sectionID})
        let savedLane=try XCTUnwrap(ArrangementCompiler.effectiveLanes(
            section:savedSection,use:savedUse).first{$0.id==lane})
        XCTAssertEqual(savedLane.notes.count,1)
        XCTAssertEqual(savedLane.notes.first?.pitch,64)
        XCTAssertFalse(store.dirty)

        let exportReply=try await send(request("export",store:store,id:"export-selected-wav"),via:ingress)
        XCTAssertEqual(exportReply["ok"] as? Bool,true)
        let exportedReceipt=try XCTUnwrap(exportReply["result"] as? [String:Any])
        XCTAssertNil(exportedReceipt["path"])
        let exportJob=try XCTUnwrap(exportedReceipt["jobID"] as? ID)
        try store.completeTrustedAgentTurn(try XCTUnwrap(store.trustedRun.active))
        try await waitForOwnedJob(store,id:exportJob)
        let audio=try AVAudioFile(forReading:output)
        XCTAssertGreaterThan(audio.length,0)
        let count=AVAudioFrameCount(min(audio.length,48_000))
        let buffer=try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:audio.processingFormat,
                                                 frameCapacity:count))
        try audio.read(into:buffer)
        let samples=try XCTUnwrap(buffer.floatChannelData)
        XCTAssertTrue((0..<Int(buffer.frameLength)).contains{abs(samples[0][$0])>0.0001})
        XCTAssertFalse(FileManager.default.fileExists(atPath:ingress.path))
    }

    func testTrustedSaveStopBeforeStagingPreservesSelectedDocument() async throws {
        let (store,root,arrangement,use,lane,_)=try makeStore()
        defer {cleanUp(store,root:root)}
        let document=try selectSavedDocument(store,root:root)
        let manifest=document.appendingPathComponent("manifest.json")
        let original=try Data(contentsOf:manifest)
        let ingress=try store.startAppOwnedTrustedAgentTurn()
        _=try await send(apply(store,arrangement:arrangement,use:use,lane:lane,
                               id:"edit-before-stop"),via:ingress)
        let gate=AppTurnRenderGate()
        let priorWorker=Task.detached(priority:.utility) { () throws -> PCM in
            await gate.wait()
            return PCM(frames:48)
        }
        store.productionWorker=priorWorker
        store.productionTask=Task {_ = try? await priorWorker.value}
        let accepted=try await send(request("save",store:store,id:"save-then-stop"),via:ingress)
        XCTAssertEqual(accepted["ok"] as? Bool,true)
        XCTAssertEqual(store.agentJob?.state,"running")
        let acceptedTask=store.productionTask
        store.stopTrustedAgentTurn()
        await gate.release()
        if let acceptedTask {await acceptedTask.value}
        XCTAssertEqual(try Data(contentsOf:manifest),original)
        XCTAssertEqual(try notes(store,useID:use,laneID:lane).count,1)
        XCTAssertEqual(store.agentJob?.state,"cancelled")
        let entries=try FileManager.default.contentsOfDirectory(atPath:root.path)
        XCTAssertFalse(entries.contains{$0.hasPrefix(".circlr-save-")})
        try await assertSocketClosed(ingress,store:store)
    }

    func testTrustedExportRejectsReplacementOfSelectedFolder() async throws {
        let (store,root,_,_,_,_)=try makeStore()
        defer {cleanUp(store,root:root)}
        _=try selectSavedDocument(store,root:root)
        let selected=root.appendingPathComponent("selected-exports",isDirectory:true)
        let moved=root.appendingPathComponent("moved-exports",isDirectory:true)
        try FileManager.default.createDirectory(at:selected,withIntermediateDirectories:true)
        let output=selected.appendingPathComponent("approved.wav")
        let ingress=try store.startAppOwnedTrustedAgentTurn(exportDestination:output)
        try FileManager.default.moveItem(at:selected,to:moved)
        try FileManager.default.createDirectory(at:selected,withIntermediateDirectories:true)
        let accepted=try await send(request("export",store:store,id:"replaced-folder"),via:ingress)
        XCTAssertEqual(accepted["ok"] as? Bool,true)
        let jobID=try XCTUnwrap((accepted["result"] as? [String:Any])?["jobID"] as? ID)
        for _ in 0..<400 where store.agentJob?.id==jobID && store.agentJob?.state=="running" {
            try await Task.sleep(for:.milliseconds(50))
        }
        XCTAssertEqual(store.agentJob?.id,jobID)
        XCTAssertEqual(store.agentJob?.state,"failed")
        XCTAssertFalse(FileManager.default.fileExists(atPath:output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:moved.appendingPathComponent("approved.wav").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:selected.path),[])
    }

    func testOwnedSocketEditsUndoAndCompletedBounceProducesSignal() async throws {
        let (store, root, arrangement, use, lane, track) = try makeStore()
        defer { cleanUp(store, root: root) }
        let otherLane = try XCTUnwrap(store.project.sections.first?.lanes.first { $0.trackID != track }?.id)
        let originalSelection = store.hierarchySelection
        let ingress = try store.startAppOwnedTrustedAgentTurn()
        XCTAssertTrue(store.trustedAgentIngress === ingress)
        XCTAssertEqual(store.trustedRun.active?.targets, [
            .section(arrangementID: arrangement, useID: use),
            .lane(arrangementID: arrangement, useID: use, laneID: lane),
            .track(track)
        ])
        XCTAssertNotEqual(URL(fileURLWithPath: ingress.path).lastPathComponent, "agent.sock")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ingress.path))
        let snapshot = try await send(request("snapshot", store: store, id: "snapshot"), via: ingress)
        XCTAssertEqual(snapshot["ok"] as? Bool, true)
        XCTAssertEqual((snapshot["result"] as? [String: Any])?["projectID"] as? ID, store.project.id)
        let before = store.project.musicRevision
        let denied = try await send(apply(store, arrangement: arrangement, use: use,
                                          lane: otherLane, id: "other-lane"), via: ingress)
        XCTAssertEqual(denied["ok"] as? Bool, false)
        XCTAssertEqual(store.project.musicRevision, before)
        let applied = try await send(apply(store, arrangement: arrangement, use: use,
                                           lane: lane, id: "first-apply"), via: ingress)
        XCTAssertEqual(applied["ok"] as? Bool, true)
        XCTAssertEqual(try notes(store, useID: use, laneID: lane).count, 1)
        XCTAssertEqual(try notes(store, useID: use, laneID: otherLane).count, 0)
        let inspected = try await send(inspect(store, arrangement: arrangement, use: use,
                                                lane: lane, id: "inspect-after-apply"), via: ingress)
        XCTAssertEqual(inspected["ok"] as? Bool, true)
        XCTAssertEqual((inspected["result"] as? [String: Any])?["total"] as? Int, 1)
        XCTAssertEqual(store.undoCount, 1)
        store.undo() // This is the user's ordinary AppStore Undo, not an AI command.
        XCTAssertEqual(try notes(store, useID: use, laneID: lane).count, 0)
        XCTAssertEqual(try notes(store, useID: use, laneID: otherLane).count, 0)
        XCTAssertEqual(store.hierarchySelection, originalSelection)
        XCTAssertEqual(store.project.musicRevision, before + 2)
        let inspectedUndo = try await send(inspect(store, arrangement: arrangement, use: use,
                                                    lane: lane, id: "inspect-after-undo"), via: ingress)
        XCTAssertEqual((inspectedUndo["result"] as? [String: Any])?["total"] as? Int, 0)
        let reapplied = try await send(apply(store, arrangement: arrangement, use: use,
                                             lane: lane, id: "second-apply"), via: ingress)
        XCTAssertEqual(reapplied["ok"] as? Bool, true)
        let accepted = try await send(bounce(store, arrangement: arrangement, use: use,
                                              track: track, id: "bounce"), via: ingress)
        XCTAssertEqual(accepted["ok"] as? Bool, true)
        let jobID = try XCTUnwrap((accepted["result"] as? [String: Any])?["jobID"] as? ID)
        let receipt = try await send(job(store, jobID: jobID, id: "job-before-complete"), via: ingress)
        XCTAssertEqual(receipt["ok"] as? Bool, true)
        XCTAssertEqual((receipt["result"] as? [String: Any])?["jobID"] as? ID, jobID)
        let lease = try XCTUnwrap(store.trustedRun.active)
        try store.completeTrustedAgentTurn(lease)
        XCTAssertNil(store.trustedAgentIngress)
        try await assertSocketClosed(ingress, store: store)
        XCTAssertEqual(store.trustedRun.active, lease)
        for _ in 0..<400 where store.agentJob?.state == "running" {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(store.agentJob?.id, jobID)
        XCTAssertEqual(store.agentJob?.state, "completed")
        let asset = try XCTUnwrap(store.project.assets.last)
        XCTAssertGreaterThan(asset.duration, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        let audio = try AVAudioFile(forReading: URL(fileURLWithPath: asset.path))
        let count = AVAudioFrameCount(min(audio.length, 48_000))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: count))
        try audio.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertTrue((0..<Int(buffer.frameLength)).contains { abs(samples[0][$0]) > 0.0001 },
                      "A completed bounce must contain actual nonzero audio")
    }

    func testConsoleAIStopClosesOwnedSocketAndBlocksLateBounce() async throws {
        let (store, root, arrangement, use, lane, track) = try makeStore()
        defer { cleanUp(store, root: root) }
        let first = try store.startAppOwnedTrustedAgentTurn()
        _ = try await send(apply(store, arrangement: arrangement, use: use,
                                 lane: lane, id: "seed-note"), via: first)
        let before = store.project
        let drainGate = AppTurnRenderGate()
        let priorWorker = Task.detached(priority: .utility) { () throws -> PCM in
            await drainGate.wait()
            return PCM(frames: 48)
        }
        store.productionWorker = priorWorker
        store.productionTask = Task { _ = try? await priorWorker.value }
        let accepted: [String: Any]
        do {
            accepted = try await send(bounce(store, arrangement: arrangement, use: use,
                                              track: track, id: "cancelled-bounce"), via: first)
        } catch {
            await drainGate.release()
            throw error
        }
        XCTAssertEqual(accepted["ok"] as? Bool, true)
        XCTAssertEqual(store.agentJob?.state, "running",
                       "The accepted bounce must still be waiting at the deterministic drain checkpoint")
        let acceptedTask = store.productionTask
        try store.cancelConsoleAgentJob(try XCTUnwrap(store.agentJob?.id))
        await drainGate.release()
        if let acceptedTask { await acceptedTask.value }
        XCTAssertNil(store.trustedRun.active)
        XCTAssertNil(store.trustedAgentIngress)
        try await assertSocketClosed(first, store: store)
        do {
            let late = try await send(apply(store, arrangement: arrangement, use: use,
                                             lane: lane, id: "late-apply"), via: first)
            XCTAssertEqual(late["ok"] as? Bool, false)
        } catch {
            // The removed endpoint rejects a new connection.
        }
        XCTAssertEqual(store.agentJob?.state, "cancelled")
        XCTAssertEqual(store.project, before)
        XCTAssertTrue(store.project.assets.isEmpty)
        let bounceFiles = (try? FileManager.default.contentsOfDirectory(atPath:
            root.appendingPathComponent("Bounces").path)) ?? []
        XCTAssertFalse(bounceFiles.contains { $0.hasPrefix(".circlr-agent-") || $0.hasSuffix(".wav") })
        let second = try store.startAppOwnedTrustedAgentTurn()
        XCTAssertNotEqual(second.path, first.path)
        do {
            let oldCapability = try await send(request("snapshot", store: store, id: "old-capability"),
                                               via: second, capability: first.clientCapability)
            XCTAssertEqual(oldCapability["ok"] as? Bool, false)
        } catch {
            // AgentSocket preflight can reject authentication without a reply.
        }
        store.resetSession()
        try await assertSocketClosed(second, store: store)
    }

    func testConsolePublicJobCancelLeavesTrustedTurnAndTransportUntouched() async throws {
        let (store, root, arrangement, use, lane, track) = try makeStore()
        defer { cleanUp(store, root: root) }
        let trusted = try store.startAppOwnedTrustedAgentTurn()
        _ = try await send(apply(store, arrangement: arrangement, use: use,
                                 lane: lane, id: "public-seed-note"), via: trusted)
        let drainGate = AppTurnRenderGate()
        let priorWorker = Task.detached(priority: .utility) { () throws -> PCM in
            await drainGate.wait()
            return PCM(frames: 48)
        }
        store.productionWorker = priorWorker
        store.productionTask = Task { _ = try? await priorWorker.value }
        let priorPlaying = store.playback.playing
        let accepted: [String: Any]
        do {
            accepted = try store.executeAgent(bounce(store, arrangement: arrangement,
                use: use, track: track, id: "public-bounce"), source: "외부 MCP")
        } catch {
            await drainGate.release()
            throw error
        }
        let jobID = try XCTUnwrap(accepted["jobID"] as? ID)
        XCTAssertEqual(store.agentJob?.state, "running")
        let acceptedTask = store.productionTask

        try store.cancelConsoleAgentJob(jobID)
        await drainGate.release()
        if let acceptedTask { await acceptedTask.value }

        XCTAssertEqual(store.agentJob?.state, "cancelled")
        XCTAssertNotNil(store.trustedRun.active)
        XCTAssertNotNil(store.trustedAgentIngress)
        XCTAssertEqual(store.playback.playing, priorPlaying)
        let snapshot = try await send(request("snapshot", store: store, id: "trusted-still-active"),
                                      via: trusted)
        XCTAssertEqual(snapshot["ok"] as? Bool, true)
    }

    func testDocumentAndTerminationCloseOwnedIngress() async throws {
        let (store, root, _, _, _, _) = try makeStore()
        defer { cleanUp(store, root: root) }
        let first = try store.startAppOwnedTrustedAgentTurn()
        store.projectURL = root.appendingPathComponent("different.circlr")
        XCTAssertNil(store.trustedRun.active)
        try await assertSocketClosed(first, store: store)
        let second = try store.startAppOwnedTrustedAgentTurn()
        store.pauseAgentBridgeForTermination()
        XCTAssertNil(store.trustedRun.active)
        try await assertSocketClosed(second, store: store)
        store.resumeAgentBridgeAfterCancelledTermination()
        let third = try store.startAppOwnedTrustedAgentTurn()
        store.mediaRoot = root.appendingPathComponent("moved-media")
        XCTAssertNil(store.trustedRun.active)
        try await assertSocketClosed(third, store: store)
        let fourth = try store.startAppOwnedTrustedAgentTurn()
        store.stop()
        XCTAssertNil(store.trustedRun.active)
        try await assertSocketClosed(fourth, store: store)
    }

    func testReplacementClosesOldTurnAndSocketCreationFailureRevokesLease() async throws {
        let (store, root, _, _, _, _) = try makeStore()
        defer { cleanUp(store, root: root) }
        let first = try store.startAppOwnedTrustedAgentTurn()
        let firstLease = try XCTUnwrap(store.trustedRun.active)
        let second = try store.startAppOwnedTrustedAgentTurn()
        XCTAssertFalse(firstLease == store.trustedRun.active)
        XCTAssertTrue(store.trustedAgentIngress === second)
        try await assertSocketClosed(first, store: store)
        store.stopTrustedAgentTurn()

        let agentDirectory = root.appendingPathComponent("Agent")
        try FileManager.default.removeItem(at: agentDirectory)
        try Data("occupied".utf8).write(to: agentDirectory)
        XCTAssertThrowsError(try store.startAppOwnedTrustedAgentTurn())
        XCTAssertNil(store.trustedRun.active)
        XCTAssertNil(store.trustedAgentIngress)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    func testExpiryRevokesAppOwnedLeaseAndUnlinksSocket() async throws {
        let (store, root, _, _, _, _) = try makeStore()
        defer { cleanUp(store, root: root) }
        let lease = try store.beginTrustedAgentTurn(sessionID: UUID().uuidString,
            turnID: UUID().uuidString, methods: ["snapshot"], targets: [], ttl: 0.05)
        let ingress = try TrustedAgentIngress(store: store, lease: lease,
            directory: root.appendingPathComponent("Agent"))
        store.trustedAgentIngress = ingress
        XCTAssertTrue(FileManager.default.fileExists(atPath: ingress.path))
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while store.trustedRun.active != nil && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(store.trustedRun.active)
        XCTAssertNil(store.trustedAgentIngress)
        try await assertSocketClosed(ingress, store: store)
    }
}
