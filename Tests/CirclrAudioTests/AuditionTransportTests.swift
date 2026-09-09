import XCTest
@testable import CirclrAudio
import CirclrCore

private final class AuditionFixture:@unchecked Sendable {
    private let lock=NSLock()
    private var history:[String]=[]
    private var blockedOnce=false
    let block:String?
    let gate=DispatchSemaphore(value:0)
    init(block:String?=nil){self.block=block}
    var events:[String]{lock.lock();defer{lock.unlock()};return history}
    func visit(_ event:String) {
        lock.lock();history.append(event+(Thread.isMainThread ? ".MAIN":""))
        let wait=event==block && !blockedOnce;if wait{blockedOnce=true};lock.unlock()
        if wait {_=gate.wait(timeout:.now()+4)}
    }
}
private final class TestAuditionBackend:AuditionBackend,@unchecked Sendable {
    let f:AuditionFixture
    let key:String
    init(_ f:AuditionFixture,_ key:String){self.f=f;self.key=key;f.visit("init:\(key)")}
    deinit{f.visit("deinit:\(key)")}
    func note(_ pitch:Int,velocity:Int,on:Bool,isCurrent:@escaping @Sendable()->Bool)throws {
        if on {
            f.visit("render:\(key):\(pitch)")
            guard isCurrent() else{return}
            if key=="note-error" {throw CirclrError("controlled note failure")}
            f.visit("on:\(key):\(pitch):\(velocity)")
        }else{f.visit("off:\(key):\(pitch)")}
    }
    func stop(){f.visit("stop:\(key)")}
}

@MainActor final class AuditionTransportTests:XCTestCase {
    private func target(_ key:String)->AuditionTarget {AuditionTarget(key:key,instrument:Instrument(),project:Project(),root:nil)}
    private func worker(_ f:AuditionFixture,timeout:Double=2)->AuditionTransport {
        AuditionTransport(timeout:timeout){target,control in
            f.visit("prepare:\(target.key)")
            if target.key=="prepare-error" {throw CirclrError("controlled prepare failure")}
            // Deliberately return even after cancellation to exercise late native completion.
            return TestAuditionBackend(f,target.key)
        }
    }
    private func eventually(_ check:()->Bool)async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while !check(){guard ProcessInfo.processInfo.systemUptime<deadline else{XCTFail("State not reached");throw PlaybackTransportError.timedOut};try await Task.sleep(for:.milliseconds(5))}
    }
    func testLazyOutputAndReleasedBeforeReadyNeverSendsOn()async throws {
        let f=AuditionFixture(block:"prepare:a"),w=worker(f),t=target("a")
        XCTAssertNil(w.note(target:t,pitch:60,velocity:0,on:false));XCTAssertTrue(f.events.isEmpty)
        let token=try XCTUnwrap(w.note(target:t,pitch:60,velocity:80,on:true))
        try await eventually{f.events.contains("prepare:a")}
        w.release(token);XCTAssertEqual(w.status.heldNotes,0)
        f.gate.signal();try await eventually{w.status.phase == .ready}
        XCTAssertFalse(f.events.contains(where:{$0.hasPrefix("on:")}))
        w.cancel();try await eventually{f.events.contains("deinit:a")}
        XCTAssertFalse(f.events.contains(where:{$0.hasSuffix(".MAIN")}));XCTAssertEqual(w.status.attempts,1)
    }
    func testCancelDuringPreparationCleansUpLateResultWithoutSound()async throws {
        let f=AuditionFixture(block:"prepare:a"),w=worker(f)
        _=w.note(target:target("a"),pitch:60,velocity:90,on:true)
        try await eventually{f.events.contains("prepare:a")}
        w.cancel();XCTAssertEqual(w.status.phase,.stopping);XCTAssertEqual(w.status.heldNotes,0)
        f.gate.signal();try await eventually{w.status.phase == .idle}
        XCTAssertEqual(f.events.filter{$0=="stop:a"}.count,1)
        XCTAssertTrue(f.events.contains("deinit:a"));XCTAssertFalse(f.events.contains(where:{$0.hasPrefix("on:")}))
    }
    func testLatestTargetWaitsForOldPreparationAndCleanup()async throws {
        let f=AuditionFixture(block:"prepare:a"),w=worker(f)
        _=w.note(target:target("a"),pitch:60,velocity:80,on:true)
        try await eventually{f.events.contains("prepare:a")}
        _=w.note(target:target("b"),pitch:67,velocity:99,on:true)
        XCTAssertEqual(w.status.attempts,1);XCTAssertFalse(f.events.contains("prepare:b"))
        f.gate.signal();try await eventually{f.events.contains("on:b:67:99")}
        let events=f.events
        XCTAssertLessThan(try XCTUnwrap(events.firstIndex(of:"deinit:a")),try XCTUnwrap(events.firstIndex(of:"prepare:b")))
        XCTAssertFalse(events.contains(where:{$0.hasPrefix("on:a:")}));XCTAssertEqual(w.status.attempts,2)
        w.cancel();try await eventually{w.status.phase == .idle}
    }
    func testTimeoutDropsHeldNotesAndDoesNotCreateSecondBackend()async throws {
        let f=AuditionFixture(block:"prepare:a"),w=worker(f,timeout:0.05)
        _=w.note(target:target("a"),pitch:60,velocity:80,on:true)
        try await eventually{w.status.phase == .stopping && w.status.message != nil}
        XCTAssertEqual(w.status.heldNotes,0);XCTAssertEqual(w.status.attempts,1)
        f.gate.signal();try await eventually{w.status.phase == .idle}
        XCTAssertFalse(f.events.contains(where:{$0.hasPrefix("on:")}))
        _=w.note(target:target("a"),pitch:62,velocity:90,on:true)
        try await eventually{f.events.contains("on:a:62:90")};XCTAssertEqual(w.status.attempts,2)
        w.cancel();try await eventually{w.status.phase == .idle}
    }
    func testBlockedNoteRenderingDropsOldNoteAndStaleReleaseKeepsRetrigger()async throws {
        let f=AuditionFixture(block:"render:a:60"),w=worker(f),t=target("a")
        let old=try XCTUnwrap(w.note(target:t,pitch:60,velocity:70,on:true))
        try await eventually{f.events.contains("render:a:60")}
        w.release(old)
        let new=try XCTUnwrap(w.note(target:t,pitch:60,velocity:100,on:true))
        w.release(old);XCTAssertEqual(w.status.heldNotes,1)
        f.gate.signal();try await eventually{f.events.contains("on:a:60:100")}
        XCTAssertFalse(f.events.contains("on:a:60:70"));XCTAssertEqual(w.status.attempts,1)
        w.release(new);try await eventually{w.status.heldNotes==0 && f.events.filter{$0=="off:a:60"}.count==2}
        w.cancel();try await eventually{w.status.phase == .idle}
        XCTAssertFalse(f.events.contains(where:{$0.hasSuffix(".MAIN")}))
    }
    func testWarmRetriggerSendsOffBeforeNewOnAndReusesBackend()async throws {
        let f=AuditionFixture(),w=worker(f),t=target("a")
        let old=try XCTUnwrap(w.note(target:t,pitch:60,velocity:70,on:true))
        try await eventually{f.events.contains("on:a:60:70")}
        let new=try XCTUnwrap(w.note(target:t,pitch:60,velocity:100,on:true));w.release(old)
        try await eventually{f.events.contains("on:a:60:100")}
        XCTAssertLessThan(try XCTUnwrap(f.events.firstIndex(of:"off:a:60")),try XCTUnwrap(f.events.firstIndex(of:"on:a:60:100")))
        XCTAssertEqual(w.status.heldNotes,1);XCTAssertEqual(w.status.attempts,1)
        w.release(new);try await eventually{f.events.filter{$0=="off:a:60"}.count==2}
        w.shutdown();try await eventually{w.status.phase == .idle}
        XCTAssertNil(w.note(target:t,pitch:61,velocity:100,on:true))
    }
    func testBlockedCleanupPreventsAnotherPhysicalPreparation()async throws {
        let f=AuditionFixture(block:"stop:a"),w=worker(f)
        _=w.note(target:target("a"),pitch:60,velocity:80,on:true)
        try await eventually{f.events.contains("on:a:60:80")}
        w.cancel();try await eventually{f.events.contains("stop:a")}
        _=w.note(target:target("b"),pitch:67,velocity:99,on:true)
        XCTAssertFalse(f.events.contains("prepare:b"));XCTAssertEqual(w.status.attempts,1)
        f.gate.signal();try await eventually{f.events.contains("on:b:67:99")}
        w.cancel();try await eventually{w.status.phase == .idle}
    }
    func testFailureIsVisibleAndOldReleaseCannotEraseIt()async throws {
        for key in ["prepare-error","note-error"] {
            let f=AuditionFixture(),w=worker(f),t=target(key)
            let token=try XCTUnwrap(w.note(target:t,pitch:60,velocity:90,on:true))
            try await eventually{w.status.phase == .failed}
            w.release(token);_=w.note(target:t,pitch:60,velocity:0,on:false)
            try await Task.sleep(for:.milliseconds(20))
            XCTAssertEqual(w.status.phase,.failed);XCTAssertNotNil(w.status.message)
            w.cancel();try await eventually{w.status.phase == .idle}
        }
    }
    func testBackendReleaseCompletesBeforeSuccessorFactoryStarts()async throws {
        let f=AuditionFixture(block:"deinit:a"),w=worker(f)
        _=w.note(target:target("a"),pitch:60,velocity:80,on:true)
        try await eventually{f.events.contains("on:a:60:80")}
        _=w.note(target:target("b"),pitch:67,velocity:99,on:true)
        try await eventually{f.events.contains("deinit:a")}
        try await Task.sleep(for:.milliseconds(30))
        XCTAssertFalse(f.events.contains("prepare:b"))
        f.gate.signal();try await eventually{f.events.contains("on:b:67:99")}
        w.cancel();try await eventually{w.status.phase == .idle}
    }
    func testInstrumentChangeWithSameTrackKeyPreparesFreshBackend()async throws {
        let f=AuditionFixture(),w=worker(f),t=target("a")
        _=w.note(target:t,pitch:60,velocity:80,on:true)
        try await eventually{f.events.contains("on:a:60:80")}
        let changed=AuditionTarget(key:"a",instrument:Instrument(program:11),project:Project(),root:nil)
        _=w.note(target:changed,pitch:67,velocity:99,on:true)
        try await eventually{f.events.contains("on:a:67:99")}
        XCTAssertEqual(w.status.attempts,2);XCTAssertEqual(f.events.filter{$0=="stop:a"}.count,1)
        w.cancel();try await eventually{w.status.phase == .idle}
    }
    func testNewTargetDoesNotResetElapsedTimeOfBlockedPreparation()async throws {
        let f=AuditionFixture(block:"prepare:a"),w=worker(f,timeout:3)
        _=w.note(target:target("a"),pitch:60,velocity:80,on:true)
        try await eventually{f.events.contains("prepare:a")}
        try await Task.sleep(for:.milliseconds(1050))
        let elapsed=w.status.elapsedSeconds;XCTAssertGreaterThanOrEqual(elapsed,1)
        _=w.note(target:target("b"),pitch:67,velocity:99,on:true)
        XCTAssertGreaterThanOrEqual(w.status.elapsedSeconds,elapsed);XCTAssertEqual(w.status.attempts,1)
        f.gate.signal();try await eventually{f.events.contains("on:b:67:99")}
        w.cancel();try await eventually{w.status.phase == .idle}
    }
    func testInvalidNotesNeverPrepareOutput()async throws {
        let f=AuditionFixture(),w=worker(f),t=target("a")
        for (pitch,velocity) in [(-1,90),(128,90),(60,-1),(60,128)] {XCTAssertNil(w.note(target:t,pitch:pitch,velocity:velocity,on:true))}
        XCTAssertEqual(w.status.phase,.idle);XCTAssertEqual(w.status.attempts,0);XCTAssertTrue(f.events.isEmpty)
    }
}
