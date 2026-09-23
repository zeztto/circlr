import Foundation
import XCTest
@testable import CirclrApp
@testable import CirclrAudio
import CirclrCore

private actor LoopRenderGate {
    private var opened=false
    private var waiters:[CheckedContinuation<Void,Never>]=[]
    func wait() async {
        if opened {return}
        await withCheckedContinuation {waiters.append($0)}
    }
    func open() {
        opened=true
        for waiter in waiters {waiter.resume()}
        waiters=[]
    }
}

@MainActor final class PlaybackLoopDrainTests:XCTestCase {
    private func store() -> (AppStore,URL) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-loop-drain-\(UUID().uuidString)")
        return (AppStore(storageRootOverride:root),root)
    }
    func testCancelledLoopWorkerRemainsTrackedUntilItFinishes() async throws {
        let (store,root)=store()
        defer {try? FileManager.default.removeItem(at:root)}
        var project=Project()
        _=project.addSection(name:"검증",at:Point(),bars:1)
        let audio=PreparedAudio(plan:try ArrangementCompiler.compile(project),mix:PCM(frames:480),stems:[:],tailSeconds:0)
        let gate=LoopRenderGate()
        let worker=Task.detached(priority:.utility) { () throws -> PreparedAudio in
            await gate.wait() // Deliberately ignores cancellation until the old renderer exits.
            return audio
        }
        store.playbackLoopTransition=WorkspaceLoopTransition(projectID:store.project.id,
            revision:store.project.musicRevision,mode:.song,arrangementID:store.project.activeArrangementID,useID:nil)
        store.playbackLoopWorker=worker
        store.playbackLoopTask=Task {_ = try? await worker.value}
        let request=AgentRequest(method:"export",id:newID())
        XCTAssertThrowsError(try store.beginAgentRender(request,source:"test"))
        store.cancelPlaybackLoopTransition()
        XCTAssertNil(store.playbackLoopTask)
        XCTAssertNil(store.playbackLoopWorker)
        XCTAssertTrue(worker.isCancelled)
        let drain=try XCTUnwrap(store.playbackLoopDrainTask)
        XCTAssertThrowsError(try store.beginAgentRender(request,source:"test"))
        var completed=false
        let observer=Task {await drain.value;completed=true}
        try await Task.sleep(for:.milliseconds(20))
        XCTAssertFalse(completed,"A new render must wait for the canceled worker")
        await gate.open()
        await observer.value
        XCTAssertTrue(completed)
        XCTAssertNil(store.playbackLoopDrainTask)
    }
    func testPrepareWaitsForStoppedLoopAndProductionWorkers() async throws {
        let (store,root)=store()
        defer {try? FileManager.default.removeItem(at:root)}
        _=store.project.addSection(name:"검증",at:Point(),bars:1)
        let plan=try ArrangementCompiler.compile(store.project)
        let audio=PreparedAudio(plan:plan,mix:PCM(frames:480),stems:[:],tailSeconds:0)
        let loopGate=LoopRenderGate(),productionGate=LoopRenderGate()
        let loopWorker=Task.detached(priority:.utility) { () throws -> PreparedAudio in
            await loopGate.wait();return audio
        }
        let productionWorker=Task.detached(priority:.utility) { () throws -> PCM in
            await productionGate.wait();return PCM(frames:480)
        }
        store.playbackLoopWorker=loopWorker
        store.playbackLoopTask=Task {_ = try? await loopWorker.value}
        store.productionWorker=productionWorker
        store.productionTask=Task {_ = try? await productionWorker.value}
        var completed=false
        store.prepare(onlySelection:false,autoplay:false) {_ in completed=true}
        XCTAssertTrue(loopWorker.isCancelled)
        XCTAssertTrue(productionWorker.isCancelled)
        try await Task.sleep(for:.milliseconds(20))
        XCTAssertFalse(completed)
        await loopGate.open()
        try await Task.sleep(for:.milliseconds(20))
        XCTAssertFalse(completed,"Production PCM must be released before the new render starts")
        await productionGate.open()
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while !completed && ProcessInfo.processInfo.systemUptime<deadline {
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertTrue(completed)
    }
    func testAgentExportAfterStopWaitsForPreviousRenderAndProduction() async throws {
        let (store,root)=store()
        defer {try? FileManager.default.removeItem(at:root)}
        _=store.project.addSection(name:"검증",at:Point(),bars:1)
        let plan=try ArrangementCompiler.compile(store.project)
        let audio=PreparedAudio(plan:plan,mix:PCM(frames:480),stems:[:],tailSeconds:0)
        let renderGate=LoopRenderGate(),productionGate=LoopRenderGate()
        let oldRender=Task.detached(priority:.utility) { () throws -> PreparedAudio in
            await renderGate.wait();return audio
        }
        let oldProduction=Task.detached(priority:.utility) { () throws -> PCM in
            await productionGate.wait();return PCM(frames:480)
        }
        store.renderWorker=oldRender
        store.renderTask=Task {_ = try? await oldRender.value}
        store.productionWorker=oldProduction
        store.productionTask=Task {_ = try? await oldProduction.value}
        store.stop()
        var request=AgentRequest(method:"export")
        var arguments=AgentArguments()
        arguments.path=root.appendingPathComponent("agent-export.wav").path
        arguments.tailSeconds=0
        request.arguments=arguments
        _=try store.beginAgentRender(request,source:"test")
        XCTAssertTrue(oldRender.isCancelled)
        XCTAssertTrue(oldProduction.isCancelled)
        try await Task.sleep(for:.milliseconds(20))
        XCTAssertNil(store.productionWorker)
        await renderGate.open()
        try await Task.sleep(for:.milliseconds(20))
        XCTAssertNil(store.productionWorker,"Previous production PCM must also drain")
        await productionGate.open()
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while store.productionWorker == nil && ProcessInfo.processInfo.systemUptime<deadline {
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertNotNil(store.productionWorker)
        store.stop()
        if let task=store.productionTask {await task.value}
    }
}
