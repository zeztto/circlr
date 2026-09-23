import Foundation
import XCTest
@testable import CirclrApp
@testable import CirclrAudio
import CirclrCore

@MainActor final class RenderCacheLifecycleTests: XCTestCase {
    private func storeWithMissingAudio() throws -> (AppStore,URL,PreparedAudio) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-cache-lifecycle-\(UUID().uuidString)")
        let store=AppStore(storageRootOverride:root)
        _=store.project.addTrack(name:"오디오")
        _=store.project.addSection(name:"검증",at:Point(),bars:1)
        let asset=Asset(name:"없는 파일",path:root.appendingPathComponent("missing.wav").path,
                        duration:1,sampleRate:PCM.rate)
        store.project.assets=[asset]
        store.project.sections[0].lanes[0].audio=[AudioClip(assetID:asset.id,duration:1)]
        let cached=PreparedAudio(plan:try AlbumCompiler.executionPlan(store.project),
                                 mix:PCM(frames:480),stems:[:],tailSeconds:0)
        return (store,root,cached)
    }
    func testChangedPlanReleasesCachedPCMWhenNewRenderFails() async throws {
        let (store,root,cached)=try storeWithMissingAudio()
        defer {try? FileManager.default.removeItem(at:root)}
        store.prepared=cached;store.preparedKey="outdated"
        var cacheReused=false
        store.prepare(onlySelection:false,autoplay:false) {_ in cacheReused=true}
        let task=try XCTUnwrap(store.renderTask)
        await task.value
        XCTAssertFalse(cacheReused)
        XCTAssertNil(store.prepared)
        XCTAssertEqual(store.preparedKey,"")
    }
    func testSamePlanReusesCachedPCM() async throws {
        let (store,root,cached)=try storeWithMissingAudio()
        defer {try? FileManager.default.removeItem(at:root)}
        store.prepared=cached
        store.preparedKey="\(store.project.musicRevision):\(store.project.activeArrangementID):all:false:off"
        var reused:PreparedAudio?
        store.prepare(onlySelection:false,autoplay:false) {reused=$0}
        let task=try XCTUnwrap(store.renderTask)
        await task.value
        XCTAssertEqual(reused?.mix.count,480)
        XCTAssertNotNil(store.prepared)
        XCTAssertEqual(store.preparedKey,"\(store.project.musicRevision):\(store.project.activeArrangementID):all:false:off")
    }
    func testWAVExportKeepsMainActorResponsiveAndStopClearsBusyState() async throws {
        let (store,root,cached)=try storeWithMissingAudio()
        defer {try? FileManager.default.removeItem(at:root)}
        let gate=DispatchSemaphore(value:0)
        let entered=expectation(description:"background WAV writer started")
        let safetyRelease=Task.detached {
            try? await Task.sleep(for:.seconds(1))
            gate.signal()
        }
        let start=ProcessInfo.processInfo.systemUptime
        store.exportPreparedWAV(cached,to:root.appendingPathComponent("mix.wav")) { _,_,_,_ in
            entered.fulfill()
            gate.wait()
            try Task.checkCancellation()
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-start,0.8,
                          "The WAV writer must not block the MainActor")
        XCTAssertTrue(store.preparing)
        await fulfillment(of:[entered],timeout:2)
        store.exportPreparedWAV(cached,to:root.appendingPathComponent("second.wav")) { _,_,_,_ in
            XCTFail("A second WAV worker must not start while the first is active")
        }
        XCTAssertEqual(store.status,"WAV 내보내기가 이미 진행 중입니다")
        let heartbeat=Task { @MainActor in true }
        let heartbeatRan=await heartbeat.value
        XCTAssertTrue(heartbeatRan)
        let task=try XCTUnwrap(store.renderTask)
        store.stop()
        XCTAssertFalse(store.preparing)
        gate.signal()
        safetyRelease.cancel()
        await task.value
        await safetyRelease.value
        XCTAssertEqual(store.status,"정지")
    }
}
