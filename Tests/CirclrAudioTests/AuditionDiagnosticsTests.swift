import XCTest
import CirclrCore
@testable import CirclrAudio

private final class DiagnosticBackend:AuditionBackend,@unchecked Sendable {
    let noteGate:DispatchSemaphore?
    let stopGate:DispatchSemaphore?
    init(noteGate:DispatchSemaphore?=nil,stopGate:DispatchSemaphore?=nil){self.noteGate=noteGate;self.stopGate=stopGate}
    func note(_ pitch:Int,velocity:Int,on:Bool,isCurrent:@escaping @Sendable()->Bool)throws {
        if on,let noteGate {_=noteGate.wait(timeout:.now()+3)}
    }
    func stop(){if let stopGate {_=stopGate.wait(timeout:.now()+3)}}
}
private final class DiagnosticReportBox:@unchecked Sendable {
    private let lock=NSLock()
    private var reporters:[AuditionDiagnosticReporter]=[]
    func add(_ reporter:@escaping AuditionDiagnosticReporter){lock.lock();reporters.append(reporter);lock.unlock()}
    func get(_ index:Int)->AuditionDiagnosticReporter?{lock.lock();defer{lock.unlock()};return reporters.indices.contains(index) ? reporters[index]:nil}
}
@MainActor final class AuditionDiagnosticsTests:XCTestCase {
    private func target(_ key:String="a")->AuditionTarget {.init(key:key,instrument:Instrument(),project:Project(),root:nil)}
    private func eventually(_ condition:()->Bool)async throws {
        let end=ProcessInfo.processInfo.systemUptime+2
        while !condition(){if ProcessInfo.processInfo.systemUptime>end {XCTFail("진단 상태 대기 초과");throw CancellationError()};try await Task.sleep(for:.milliseconds(5))}
    }
    func testEveryPreparationStageTimeoutKeepsFrozenInterruptionThroughCleanup()async throws {
        let stages:[AuditionTraceEvent.Stage]=[.sourceLoad,.auInstantiation,.engineCreation,.mixerAcquisition,.routing,.engineStart]
        for stage in stages {
            let gate=DispatchSemaphore(value:0)
            let worker=AuditionTransport(timeout:0.03,diagnosticFactory:{_,_,report in
                report(stage,.entered);_=gate.wait(timeout:.now()+3);report(stage,.completed)
                return DiagnosticBackend()
            })
            defer{gate.signal();worker.shutdown()}
            _=worker.note(target:target(),pitch:60,velocity:90,on:true)
            try await eventually{worker.status.trace?.interruption?.reason == .timedOut}
            let interrupted=try XCTUnwrap(worker.status.trace?.interruption)
            XCTAssertEqual(interrupted.inFlight?.stage,stage)
            XCTAssertEqual(worker.status.heldNotes,0)
            gate.signal();try await eventually{worker.status.phase == .idle}
            XCTAssertEqual(worker.status.trace?.interruption,interrupted)
            XCTAssertEqual(worker.status.trace?.events.last?.stage,.cleanup)
            XCTAssertEqual(worker.status.trace?.events.last?.phase,.completed)
        }
    }
    func testCancelBlockedNoteAndCleanupPreservesNoteAtInterruption()async throws {
        let note=DispatchSemaphore(value:0),stop=DispatchSemaphore(value:0)
        let worker=AuditionTransport(timeout:1){_,_ in DiagnosticBackend(noteGate:note,stopGate:stop)}
        defer{note.signal();stop.signal();worker.shutdown()}
        _=worker.note(target:target(),pitch:60,velocity:90,on:true)
        try await eventually{worker.status.trace?.inFlight?.stage == .note}
        worker.cancel()
        let frozen=worker.status.trace?.interruption
        XCTAssertEqual(frozen?.reason,.cancelled);XCTAssertEqual(frozen?.inFlight?.stage,.note)
        note.signal();try await eventually{worker.status.trace?.inFlight?.stage == .cleanup}
        XCTAssertEqual(worker.status.phase,.stopping);XCTAssertEqual(worker.status.trace?.interruption,frozen)
        stop.signal();try await eventually{worker.status.phase == .idle}
        XCTAssertEqual(worker.status.trace?.interruption,frozen)
    }
    func testSupersededFactoryIsSingleAndOldReporterCannotPolluteSuccessor()async throws {
        let gate=DispatchSemaphore(value:0),box=DiagnosticReportBox()
        let worker=AuditionTransport(timeout:1,diagnosticFactory:{target,_,report in
            box.add(report);report(.sourceLoad,.entered)
            if target.key=="a" {_=gate.wait(timeout:.now()+3)}
            report(.sourceLoad,.completed);return DiagnosticBackend()
        })
        defer{gate.signal();worker.shutdown()}
        _=worker.note(target:target(),pitch:60,velocity:90,on:true)
        try await eventually{worker.status.trace?.inFlight?.stage == .sourceLoad}
        let oldID=worker.status.trace?.sessionID
        _=worker.note(target:target("b"),pitch:62,velocity:90,on:true)
        XCTAssertEqual(worker.status.attempts,1);XCTAssertEqual(worker.status.trace?.interruption?.reason,.superseded)
        gate.signal();try await eventually{worker.status.phase == .ready && worker.status.attempts == 2}
        XCTAssertNotEqual(worker.status.trace?.sessionID,oldID)
        let before=worker.status.trace
        box.get(0)?(.engineStart,.entered);box.get(0)?(.engineStart,.completed)
        XCTAssertEqual(worker.status.trace,before)
        worker.cancel();try await eventually{worker.status.phase == .idle}
        let completed=worker.status.trace
        box.get(1)?(.sourceLoad,.entered)
        XCTAssertEqual(worker.status.trace,completed)
    }
    func testRingRetainsMonotonicSequenceAndRejectsMalformedProgress()throws {
        var trace=AuditionTrace(sessionID:UUID())
        for index in 0..<80 {
            trace.record(.note,.entered,elapsed:Double(index*2));trace.record(.note,.completed,elapsed:Double(index*2+1))
        }
        XCTAssertEqual(trace.events.count,64);XCTAssertEqual(trace.events.first?.sequence,97);XCTAssertEqual(trace.events.last?.sequence,160)
        let before=trace
        trace.record(.note,.entered,elapsed:.nan);trace.record(.note,.entered,elapsed:.infinity)
        trace.record(.note,.entered,elapsed:-1);trace.record(.note,.completed,elapsed:200)
        trace.record(.note,.entered,elapsed:0)
        XCTAssertEqual(trace,before)
        XCTAssertEqual(try JSONDecoder().decode(AuditionTrace.self,from:JSONEncoder().encode(trace)),trace)
        let legacy=Data(#"{"phase":"idle","attempts":0,"heldNotes":0,"elapsedSeconds":0}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(AuditionStatus.self,from:legacy).trace)
    }
    func testPreparationFailureRetainsInFlightStage()async throws {
        let worker=AuditionTransport(timeout:1,diagnosticFactory:{_,_,report in report(.auInstantiation,.entered);throw CirclrError("mock")})
        _=worker.note(target:target(),pitch:60,velocity:90,on:true)
        try await eventually{worker.status.phase == .failed}
        XCTAssertEqual(worker.status.trace?.interruption?.reason,.failed)
        XCTAssertEqual(worker.status.trace?.interruption?.inFlight?.stage,.auInstantiation)
        XCTAssertEqual(worker.status.trace?.inFlight?.phase,.entered)
        worker.shutdown()
    }
}
