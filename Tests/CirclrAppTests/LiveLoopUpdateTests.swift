import XCTest
import CirclrCore
@testable import CirclrApp
@testable import CirclrAudio

private actor LiveRenderGate {
    var released=false
    var waiters:[CheckedContinuation<Void,Never>]=[]
    func wait() async {if released{return};await withCheckedContinuation{waiters.append($0)}}
    func release(){released=true;for waiter in waiters{waiter.resume()};waiters=[]}
}

private final class LiveStagingGate:@unchecked Sendable {
    let entered:XCTestExpectation
    let release=DispatchSemaphore(value:0)
    private let lock=NSLock()
    private var first=true
    init(_ entered:XCTestExpectation){self.entered=entered}
    func waitOnce(){
        lock.lock();let wait=first;first=false;lock.unlock()
        if wait {entered.fulfill();_ = release.wait(timeout:.now()+5)}
    }
}

@MainActor final class LiveLoopUpdateTests:XCTestCase {
    private func fixture(_ root:URL)throws->URL {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url=root.appendingPathComponent("worker")
        let source = #"""
#!/usr/bin/python3
import sys,json,os
session=sys.argv[2];directory=sys.argv[4];seq=0
countfile=sys.argv[0]+'.changes'
def emit(payload):
 global seq
 seq+=1
 print(json.dumps(dict(version=1,session=session,sequence=seq,payload=payload)),flush=True)
emit({'helloBoundaryLoopCapabilities':{'outputDeviceSelection':False}})
for line in sys.stdin:
 p=json.loads(line)['payload']
 if 'prepareLoopRange' in p: emit({'prepared':{}})
 elif 'play' in p:
  run=p['play']['run'];emit({'started':{'run':run}});emit({'loopClock':{'run':run,'seconds':0.125}})
 elif 'queueLoopChange' in p:
  item=p['queueLoopChange'];change=item['change']
  with open(countfile,'a') as f:f.write(change+'\n')
  emit({'loopChangeScheduled':{'change':change,'elapsedFrame':480000,'frames':item['cycleFrames'],'exiting':False}})
 elif 'stop' in p: break
"""#
        try Data(source.utf8).write(to:url)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:url.path)
        return url
    }
    private func wait(_ condition:()->Bool) async throws {
        let deadline=Date().addingTimeInterval(5)
        while !condition() && Date()<deadline {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertTrue(condition())
    }
    func testRapidEditsCoalesceAndQueuedRevisionRemainsExplicitUntilStop() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let executable=try fixture(root),host=OutputWorkerProcess(executable:executable),playback=Playback(outputWorker:host)
        let store=AppStore(storageRootOverride:root.appendingPathComponent("store"),playbackOverride:playback)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        _=store.project.addSection(name:"Loop",at:Point(),bars:1)
        let plan=try ArrangementCompiler.compile(store.project)
        let audio=PreparedAudio(plan:plan,mix:PCM(frames:Int(plan.duration*PCM.rate)),stems:[:],tailSeconds:0)
        try await playback.play(audio,loop:true)
        store.prepared=audio;store.playbackLoopMode = .song;store.playbackLoopArrangementID=store.project.activeArrangementID
        store.mutate("first"){$0.name="first"};store.refreshLiveLoopUpdate()
        let obsolete=try XCTUnwrap(store.liveLoopUpdate)
        store.mutate("latest"){$0.name="latest"};store.refreshLiveLoopUpdate()
        XCTAssertNotEqual(store.liveLoopUpdate?.id,obsolete.id)
        XCTAssertFalse(store.isLiveLoopRequestCurrent(obsolete,matchingRevision:true))
        store.undo();store.refreshLiveLoopUpdate()
        let latest=store.project.musicRevision
        try await wait{store.liveLoopUpdate?.phase=="queued"}
        XCTAssertEqual(store.liveLoopUpdate?.revision,latest)
        XCTAssertTrue(playback.playing)
        XCTAssertEqual(store.prepared?.plan.revision,plan.revision)
        store.mutate("after queue"){$0.name="after queue"};store.refreshLiveLoopUpdate()
        XCTAssertEqual(store.liveLoopUpdate?.revision,latest,"Already submitted PCM remains identified as an older queued snapshot")
        let commands=try String(contentsOf:executable.appendingPathExtension("changes"),encoding:.utf8)
        XCTAssertEqual(commands.split(separator:"\n").count,1)
        store.stop();XCTAssertNil(store.liveLoopUpdate)
        try await wait{host.status.phase == .idle}
        XCTAssertFalse(playback.playing)
    }
    func testRenderFailureKeepsOriginalLoopAndDocumentReplacementCannotSubmitLatePCM() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let executable=try fixture(root),host=OutputWorkerProcess(executable:executable),playback=Playback(outputWorker:host)
        let store=AppStore(storageRootOverride:root.appendingPathComponent("store"),playbackOverride:playback)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        _=store.project.addSection(name:"Loop",at:Point(),bars:1)
        let original=store.project,plan=try ArrangementCompiler.compile(original)
        let audio=PreparedAudio(plan:plan,mix:PCM(frames:Int(plan.duration*PCM.rate)),stems:[:],tailSeconds:0)
        try await playback.play(audio,loop:true)
        store.prepared=audio;store.playbackLoopMode = .song;store.playbackLoopArrangementID=store.project.activeArrangementID
        store.project.global.tempo=0;store.project.musicRevision+=1
        store.refreshLiveLoopUpdate()
        try await wait{store.liveLoopFailedRevision == store.project.musicRevision}
        XCTAssertTrue(playback.playing);XCTAssertEqual(playback.prepared?.plan.revision,plan.revision)
        XCTAssertFalse(FileManager.default.fileExists(atPath:executable.appendingPathExtension("changes").path))
        store.project=original;store.project.musicRevision+=2
        store.refreshLiveLoopUpdate()
        XCTAssertNotNil(store.liveLoopUpdate)
        store.project.id=newID();store.refreshLiveLoopUpdate()
        XCTAssertNil(store.liveLoopUpdate)
        try await wait{host.status.phase == .idle}
        XCTAssertFalse(FileManager.default.fileExists(atPath:executable.appendingPathExtension("changes").path))
    }
    func testUndoDuringCAFStagingRevokesUnsubmittedPCMWithoutStoppingOutput() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let executable=try fixture(root)
        let gate=LiveStagingGate(expectation(description:"Replacement reached CAF staging"))
        let host=OutputWorkerProcess(executable:executable,beforeLoopCAFWrite:{gate.waitOnce()})
        let playback=Playback(outputWorker:host)
        let store=AppStore(storageRootOverride:root.appendingPathComponent("store"),playbackOverride:playback)
        defer {gate.release.signal();store.stop();try? FileManager.default.removeItem(at:root)}
        _=store.project.addSection(name:"Loop",at:Point(),bars:1)
        let plan=try ArrangementCompiler.compile(store.project)
        let audio=PreparedAudio(plan:plan,mix:PCM(frames:Int(plan.duration*PCM.rate)),stems:[:],tailSeconds:0)
        try await playback.play(audio,loop:true)
        store.prepared=audio;store.playbackLoopMode = .song;store.playbackLoopArrangementID=store.project.activeArrangementID
        store.mutate("edit"){$0.name="edit"};store.refreshLiveLoopUpdate()
        await fulfillment(of:[gate.entered],timeout:3)
        XCTAssertEqual(store.liveLoopUpdate?.phase,"scheduling")
        store.undo() // Revocation is synchronous with revision mutation, before the UI's next tick.
        gate.release.signal()
        try await wait{store.liveLoopUpdate == nil}
        XCTAssertTrue(playback.playing)
        XCTAssertNil(playback.pendingLoopChange)
        XCTAssertEqual(playback.prepared?.plan.revision,plan.revision)
        XCTAssertFalse(FileManager.default.fileExists(atPath:executable.appendingPathExtension("changes").path))
        store.refreshLiveLoopUpdate()
        try await wait{store.liveLoopUpdate?.phase=="queued"}
        XCTAssertEqual(store.liveLoopUpdate?.revision,store.project.musicRevision)
        let commands=try String(contentsOf:executable.appendingPathExtension("changes"),encoding:.utf8)
        XCTAssertEqual(commands.split(separator:"\n").count,1,"Only the current post-Undo revision reaches the worker scheduler")
        store.stop();try await wait{host.status.phase == .idle}
    }
    func testStopInvalidatesRequestAndDrainsDetachedPCMBeforeAnotherRender() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        _=store.project.addSection(name:"Loop",at:Point(),bars:1)
        let audio=PreparedAudio(plan:try ArrangementCompiler.compile(store.project),mix:PCM(frames:480),stems:[:],tailSeconds:0)
        let gate=LiveRenderGate()
        let worker=Task.detached{() throws -> PreparedAudio in await gate.wait();return audio}
        store.liveLoopUpdate=LiveLoopUpdate(projectID:store.project.id,revision:store.project.musicRevision,arrangementID:store.project.activeArrangementID,useID:nil)
        store.liveLoopWorker=worker
        store.liveLoopTask=Task{_ = try? await worker.value}
        store.stop()
        XCTAssertNil(store.liveLoopUpdate)
        XCTAssertTrue(worker.isCancelled)
        XCTAssertNotNil(store.liveLoopDrainTask)
        let request=AgentRequest(method:"export",id:newID())
        XCTAssertThrowsError(try store.beginAgentRender(request,source:"test"))
        var finished=false
        store.prepare(onlySelection:false,autoplay:false){_ in finished=true}
        try await Task.sleep(for:.milliseconds(40))
        XCTAssertFalse(finished)
        await gate.release()
        let deadline=Date().addingTimeInterval(3)
        while !finished && Date()<deadline {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertTrue(finished)
        XCTAssertNil(store.liveLoopDrainTask)
    }
    func testQueuedStateDistinguishesHeardAndPendingRevision() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=AppStore(storageRootOverride:root)
        defer {store.stop();try? FileManager.default.removeItem(at:root)}
        _=store.project.addSection(name:"Loop",at:Point(),bars:1)
        var plan=try ArrangementCompiler.compile(store.project);plan.revision=1
        store.prepared=PreparedAudio(plan:plan,mix:PCM(frames:480),stems:[:],tailSeconds:0)
        var pending=LiveLoopUpdate(projectID:store.project.id,revision:2,arrangementID:store.project.activeArrangementID,useID:nil)
        pending.phase="queued";store.liveLoopUpdate=pending
        XCTAssertEqual(store.liveLoopUpdateState["appliedRevision"] as? Int,1)
        XCTAssertEqual(store.liveLoopUpdateState["pendingRevision"] as? Int,2)
        XCTAssertEqual(store.liveLoopUpdateState["phase"] as? String,"queued")
        store.resetSession();XCTAssertNil(store.liveLoopUpdate)
    }
}
