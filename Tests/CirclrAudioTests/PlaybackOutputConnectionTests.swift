import XCTest
@testable import CirclrAudio

private actor ControlledOutput {
    var runs=0
    private var released=false
    private var continuation:CheckedContinuation<Void,Never>?
    func connect(report:PlaybackOutputConnection.Report) async {
        runs+=1;await report(.device)
        await withCheckedContinuation {reply in
            if released {reply.resume()}else{continuation=reply}
        }
        await report(.routing)
    }
    func finish(){released=true;continuation?.resume();continuation=nil}
}

@MainActor final class PlaybackOutputConnectionTests:XCTestCase {
    private func eventually(_ condition:()->Bool) async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime<deadline else {XCTFail("Expected state was not reached");throw PlaybackOutputWaitError.timedOut}
            try await Task.sleep(for:.milliseconds(5))
        }
    }
    private func cancelled(_ task:Task<Void,Error>) async {
        do {try await task.value;XCTFail("Cancelled playback request must not succeed")}
        catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
    }
    func testStopPreservesOneWorkerAndLateReadyDoesNotReviveRequest() async throws {
        let controlled=ControlledOutput(),connection=PlaybackOutputConnection{await controlled.connect(report:$0)}
        var steps:[PlaybackOutputStatus.Step?]=[]
        var firstRequest:PlaybackOutputStatus.Request?
        connection.onChange={steps.append(connection.status.step);if firstRequest==nil {firstRequest=connection.status.request}}
        defer {connection.onChange=nil;Task{await controlled.finish()}}
        XCTAssertEqual(connection.status.phase,.idle);XCTAssertEqual(connection.status.attempts,0)
        let play=Task{try await connection.waitUntilReady()}
        try await eventually{connection.status.step == .device}
        XCTAssertEqual(firstRequest,.waiting,"The first published device state must not claim playback was cancelled")
        let id=connection.status.attemptID;connection.cancelWait();await cancelled(play)
        XCTAssertEqual(connection.status.phase,.connecting);XCTAssertEqual(connection.status.request,.cancelled)
        await controlled.finish();try await eventually{connection.status.phase == .ready}
        XCTAssertEqual(connection.status.request,.cancelled);XCTAssertEqual(connection.status.attemptID,id)
        try await connection.waitUntilReady()
        XCTAssertEqual(connection.status.request,.none);XCTAssertEqual(connection.status.attempts,1)
        let runs=await controlled.runs;XCTAssertEqual(runs,1)
        XCTAssertTrue(steps.contains(.player));XCTAssertTrue(steps.contains(.device));XCTAssertTrue(steps.contains(.routing));XCTAssertTrue(steps.contains(.ready))
    }
    func testRepeatedTimeoutWaitsOnTheSamePhysicalConnection() async throws {
        let controlled=ControlledOutput(),connection=PlaybackOutputConnection{await controlled.connect(report:$0)}
        defer {Task{await controlled.finish()}}
        for _ in 0..<2 {
            do {try await connection.waitUntilReady(timeout:0.05);XCTFail("Expected timeout")}
            catch PlaybackOutputWaitError.timedOut {} catch {throw error}
            XCTAssertEqual(connection.status.phase,.connecting);XCTAssertEqual(connection.status.request,.timedOut)
            XCTAssertEqual(connection.status.attempts,1)
        }
        let id=connection.status.attemptID
        await controlled.finish();try await eventually{connection.status.phase == .ready}
        XCTAssertEqual(connection.status.request,.timedOut);XCTAssertEqual(connection.status.attemptID,id)
        try await connection.waitUntilReady();XCTAssertEqual(connection.status.request,.none)
    }
    func testCancelledTaskCannotOverwriteTheNextRequest() async throws {
        let controlled=ControlledOutput(),connection=PlaybackOutputConnection{await controlled.connect(report:$0)}
        defer {Task{await controlled.finish()}}
        let first=Task{try await connection.waitUntilReady()}
        try await eventually{connection.status.step == .device}
        first.cancel()
        let next=Task{try await connection.waitUntilReady()}
        await cancelled(first)
        try await eventually{connection.status.request == .waiting}
        XCTAssertEqual(connection.status.phase,.connecting)
        await controlled.finish();try await next.value
        XCTAssertEqual(connection.status.request,.none);XCTAssertEqual(connection.status.attempts,1)
    }
    func testNewWaitSupersedesOldWaitWithoutDuplicatingDeviceWork() async throws {
        let controlled=ControlledOutput(),connection=PlaybackOutputConnection{await controlled.connect(report:$0)}
        defer {Task{await controlled.finish()}}
        let first=Task{try await connection.waitUntilReady()}
        try await eventually{connection.status.step == .device}
        let next=Task{try await connection.waitUntilReady()}
        await cancelled(first)
        XCTAssertEqual(connection.status.request,.waiting)
        await controlled.finish();try await next.value
        XCTAssertEqual(connection.status.phase,.ready);XCTAssertEqual(connection.status.attempts,1)
    }
    func testInvalidOrAlreadyCancelledRequestNeverAcquiresADevice() async throws {
        let controlled=ControlledOutput(),connection=PlaybackOutputConnection{await controlled.connect(report:$0)}
        for timeout in [0,Double.infinity,Double.nan] {
            do {try await connection.waitUntilReady(timeout:timeout);XCTFail("Expected validation failure")}
            catch PlaybackOutputWaitError.invalidTimeout {} catch {throw error}
        }
        let cancelledTask=Task {
            withUnsafeCurrentTask{$0?.cancel()}
            try await connection.waitUntilReady()
        }
        await cancelled(cancelledTask)
        XCTAssertEqual(connection.status.phase,.idle);XCTAssertNil(connection.status.attemptID)
        let runs=await controlled.runs;XCTAssertEqual(runs,0)
    }
}
