import Foundation
import XCTest
@testable import CirclrAudio
import CirclrCore

private actor StopCompletion {
    private var finished=false
    func mark() {finished=true}
    func value() -> Bool {finished}
}

final class WAVExportTransactionTests: XCTestCase {
    private func fixture(frames: Int = 50_000) throws -> PreparedAudio {
        var project=Project()
        _=project.addSection(name:"검증",at:Point(),bars:1)
        var mix=PCM(frames:frames)
        mix.left=[Float](repeating:0.25,count:frames)
        mix.right=[Float](repeating:-0.25,count:frames)
        return PreparedAudio(plan:try ArrangementCompiler.compile(project),mix:mix,stems:[:],tailSeconds:0)
    }
    private func directory() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-wav-transaction-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    func testCancellationDuringChunkedWritePreservesPreviousWAV() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let target=root.appendingPathComponent("mix.wav")
        try PCM(frames:480).writeWAV(target)
        let original=try Data(contentsOf:target)
        let audio=try fixture()
        let worker=Task.detached { () throws -> Void in
            try AudioExport.saveWAV(audio,to:target) { value in
                if value > 0 {withUnsafeCurrentTask{$0?.cancel()}}
            }
        }
        do {try await worker.value;XCTFail("Expected cancellation")}
        catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf:target),original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),["mix.wav"])
    }
    func testPreviousWAVStaysVisibleUntilCompleteReplacement() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let target=root.appendingPathComponent("mix.wav")
        try PCM(frames:480).writeWAV(target)
        let original=try Data(contentsOf:target),audio=try fixture()
        let worker=Task.detached { () throws -> (Bool,Int) in
            var previousVisible=true,chunkCount=0
            try AudioExport.saveWAV(audio,to:target) { _ in
                chunkCount += 1
                previousVisible = previousVisible && ((try? Data(contentsOf:target)) == original)
            }
            return (previousVisible,chunkCount)
        }
        let (previousVisible,chunkCount)=try await worker.value
        XCTAssertTrue(previousVisible)
        XCTAssertGreaterThan(chunkCount,1)
        XCTAssertEqual(try PCM.read(target).count,audio.mix.count)
        XCTAssertNotEqual(try Data(contentsOf:target),original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),["mix.wav"])
    }
    func testStopAtPrePublishBoundaryPreventsWAVReplacement() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let target=root.appendingPathComponent("mix.wav")
        try PCM(frames:480).writeWAV(target)
        let original=try Data(contentsOf:target),audio=try fixture()
        let gate=WAVExportCommitGate(),release=DispatchSemaphore(value:0)
        let staged=expectation(description:"WAV finished staging before publication")
        let worker=Task.detached { () throws -> Void in
            try AudioExport.saveWAV(audio,to:target,progress:nil,commitGate:gate,
                                    beforePublish:{staged.fulfill();release.wait()})
        }
        await fulfillment(of:[staged],timeout:2)
        gate.cancel() // Mirrors AppStore.stop() before it returns.
        release.signal()
        do {try await worker.value;XCTFail("Stopped export published a WAV")}
        catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf:target),original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),["mix.wav"])
    }
    func testStopWaitsForPublicationAlreadyInProgress() async throws {
        let gate=WAVExportCommitGate(),release=DispatchSemaphore(value:0)
        let publishing=expectation(description:"publication entered commit gate")
        let publisher=Task.detached {
            try gate.publish {publishing.fulfill();release.wait()}
        }
        await fulfillment(of:[publishing],timeout:2)
        let completion=StopCompletion()
        let stopping=expectation(description:"stop attempted")
        let stopper=Task.detached {stopping.fulfill();gate.cancel();await completion.mark()}
        await fulfillment(of:[stopping],timeout:2)
        try await Task.sleep(for:.milliseconds(30))
        let returnedBeforePublish=await completion.value()
        XCTAssertFalse(returnedBeforePublish)
        release.signal()
        try await publisher.value
        await stopper.value
        let returnedAfterPublish=await completion.value()
        XCTAssertTrue(returnedAfterPublish)
    }
}
