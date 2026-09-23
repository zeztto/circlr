import Foundation
import Darwin
import XCTest
@testable import CirclrCodex

final class CodexProcessHostTests: XCTestCase {
    private final class Observed: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()
        private var didComplete = false
        private var exit: CodexProcessExit?
        private var writeError: CodexProcessHostError?
        private var messages: [String] = []

        func append(_ data: Data, expectedCount: Int) -> Bool {
            lock.lock(); defer { lock.unlock() }
            bytes.append(data)
            if !didComplete && bytes.count >= expectedCount {
                didComplete = true
                return true
            }
            return false
        }
        func output() -> Data { lock.lock(); defer { lock.unlock() }; return bytes }
        func setExit(_ reason: CodexProcessExit) { lock.lock(); exit = reason; lock.unlock() }
        func exitReason() -> CodexProcessExit? { lock.lock(); defer { lock.unlock() }; return exit }
        func setWriteError(_ error: CodexProcessHostError?) { lock.lock(); writeError = error; lock.unlock() }
        func writtenError() -> CodexProcessHostError? { lock.lock(); defer { lock.unlock() }; return writeError }
        func appendMessage(_ text: String) { lock.lock(); messages.append(text); lock.unlock() }
        func orderedMessages() -> [String] { lock.lock(); defer { lock.unlock() }; return messages }
    }

    func testCatExchangesOneJSONLPacketAndStopsCleanly() throws {
        let host = CodexProcessHost(executableURL: URL(fileURLWithPath: "/bin/cat"), arguments: [])
        let received = expectation(description: "cat echoed packet")
        let ended = expectation(description: "child reaped")
        let packet = Data("{\"method\":\"initialized\"}\n".utf8)
        let observedState = Observed()
        let generation = try host.start(onOutput: { observed, bytes in
            XCTAssertEqual(observed, 1)
            if observedState.append(bytes, expectedCount: packet.count) { received.fulfill() }
        }, onExit: { observed, reason in
            XCTAssertEqual(observed, 1)
            observedState.setExit(reason)
            ended.fulfill()
        })
        XCTAssertEqual(generation, 1)
        XCTAssertTrue(host.isRunning)
        try host.write(packet, generation: generation)
        wait(for: [received], timeout: 3)
        XCTAssertEqual(observedState.output(), packet)
        try host.stop()
        wait(for: [ended], timeout: 3)
        XCTAssertEqual(observedState.exitReason(), .stopped)
        XCTAssertFalse(host.isRunning)
        XCTAssertThrowsError(try host.write(packet, generation: generation)) { error in
            XCTAssertEqual(error as? CodexProcessHostError, .stopped)
        }
    }

    func testLaunchFailureStaleGenerationAndPacketBounds() throws {
        let missing = CodexProcessHost(executableURL: URL(fileURLWithPath: "/definitely/not/a/codex-binary"),
                                       arguments: [])
        XCTAssertThrowsError(try missing.start(onOutput: { _, _ in }, onExit: { _, _ in })) { error in
            XCTAssertEqual(error as? CodexProcessHostError, .invalidExecutable)
        }
        XCTAssertFalse(missing.isRunning)

        let host = CodexProcessHost(executableURL: URL(fileURLWithPath: "/bin/cat"),
                                    arguments: [], maximumPacketBytes: 8)
        let first = try host.start(onOutput: { _, _ in }, onExit: { _, _ in })
        XCTAssertThrowsError(try host.start(onOutput: { _, _ in }, onExit: { _, _ in })) { error in
            XCTAssertEqual(error as? CodexProcessHostError, .alreadyRunning)
        }
        try host.stop()
        let second = try host.start(onOutput: { _, _ in }, onExit: { _, _ in })
        XCTAssertEqual(second, first + 1)
        XCTAssertThrowsError(try host.write(Data("{}\n".utf8), generation: first)) { error in
            XCTAssertEqual(error as? CodexProcessHostError, .staleGeneration)
        }
        XCTAssertThrowsError(try host.write(Data("{}".utf8), generation: second)) { error in
            XCTAssertEqual(error as? CodexProcessHostError, .invalidPacket)
        }
        XCTAssertThrowsError(try host.write(Data("{}\n{}\n".utf8), generation: second)) { error in
            XCTAssertEqual(error as? CodexProcessHostError, .invalidPacket)
        }
        XCTAssertThrowsError(try host.write(Data("12345678\n".utf8), generation: second)) { error in
            XCTAssertEqual(error as? CodexProcessHostError, .packetTooLarge)
        }
        try host.write(Data("{}\n".utf8), generation: second)
        try host.stop()
    }

    func testShortLivedChildDeliversOutputBeforeExit() throws {
        let host = CodexProcessHost(executableURL: URL(fileURLWithPath: "/bin/echo"),
                                    arguments: ["{\"id\":1,\"result\":{}}"])
        let ended = expectation(description: "echo exited")
        let observedState = Observed()
        let generation = try host.start(onOutput: { observed, bytes in
            XCTAssertEqual(observed, 1)
            observedState.appendMessage("output:" + String(decoding: bytes, as: UTF8.self))
        }, onExit: { observed, reason in
            XCTAssertEqual(observed, 1)
            observedState.appendMessage("exit:\(reason)")
            ended.fulfill()
        })
        XCTAssertEqual(generation, 1)
        wait(for: [ended], timeout: 3)
        let ordered = observedState.orderedMessages()
        XCTAssertEqual(ordered.count, 2)
        XCTAssertEqual(ordered.first, "output:{\"id\":1,\"result\":{}}\n")
        XCTAssertEqual(ordered.last, "exit:exited(status: 0)")
        XCTAssertFalse(host.isRunning)
    }

    func testStopFromOutputCallbackReapsWithoutDeadlock() throws {
        let host = CodexProcessHost(executableURL: URL(fileURLWithPath: "/bin/cat"), arguments: [])
        let ended = expectation(description: "callback stopped child")
        let observed = Observed()
        let generation = try host.start(onOutput: { [weak host] _, _ in
            try? host?.stop()
        }, onExit: { _, reason in
            observed.setExit(reason)
            ended.fulfill()
        })
        try host.write(Data("{}\n".utf8), generation: generation)
        wait(for: [ended], timeout: 3)
        XCTAssertEqual(observed.exitReason(), .stopped)
        XCTAssertFalse(host.isRunning)
    }

    #if DEBUG
    func testReleasingLastHostReferenceReapsIdleChild() throws {
        var host: CodexProcessHost? = CodexProcessHost(
            executableURL: URL(fileURLWithPath: "/bin/cat"), arguments: [], stopGrace: 0.05)
        weak let weakHost = host
        _ = try host?.start(onOutput: { _, _ in }, onExit: { _, _ in })
        let child = try XCTUnwrap(host?.ownedProcessForTesting)
        XCTAssertTrue(child.isRunning)

        host = nil
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while (weakHost != nil || child.isRunning) && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let deallocatedBeforeCleanup = weakHost == nil
        let childExitedBeforeCleanup = !child.isRunning
        if !deallocatedBeforeCleanup { try? weakHost?.stop() }
        if child.isRunning {
            _ = Darwin.kill(child.processIdentifier, SIGTERM)
            let cleanupDeadline = ProcessInfo.processInfo.systemUptime + 0.2
            while child.isRunning && ProcessInfo.processInfo.systemUptime < cleanupDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if child.isRunning {
                _ = Darwin.kill(child.processIdentifier, SIGKILL)
                let killDeadline = ProcessInfo.processInfo.systemUptime + 0.2
                while child.isRunning && ProcessInfo.processInfo.systemUptime < killDeadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }
        XCTAssertTrue(deallocatedBeforeCleanup, "idle reader retained the host after its last owner released")
        XCTAssertTrue(childExitedBeforeCleanup, "owned child survived host deinitialization")
        XCTAssertFalse(child.isRunning, "test cleanup left an orphan child")
        if !child.isRunning { child.waitUntilExit() }
    }

    func testTimedOutWriteCannotStopAReplacementGeneration() throws {
        // sleep leaves stdin open but unread, so a large nonblocking JSONL
        // packet fills the pipe and reaches the write deadline reliably.
        let host = CodexProcessHost(executableURL: URL(fileURLWithPath: "/bin/sleep"),
                                    arguments: ["5"], maximumPacketBytes: 1_100_000,
                                    writeTimeout: 0.03, stopGrace: 0.05)
        let reachedFailure = DispatchSemaphore(value: 0)
        let releaseCleanup = DispatchSemaphore(value: 0)
        host.beforeWriteFailureCleanupForTesting = {
            reachedFailure.signal()
            _ = releaseCleanup.wait(timeout: .now() + 3)
        }
        let observed = Observed()
        let writeFinished = expectation(description: "failed write returned")
        let first = try host.start(onOutput: { _, _ in }, onExit: { _, _ in })
        let packet = Data(repeating: 0x41, count: 1_000_000) + Data([0x0A])
        DispatchQueue.global(qos: .userInitiated).async {
            do { try host.write(packet, generation: first) }
            catch { observed.setWriteError(error as? CodexProcessHostError) }
            writeFinished.fulfill()
        }
        guard reachedFailure.wait(timeout: .now() + 3) == .success else {
            releaseCleanup.signal()
            try? host.stop()
            return XCTFail("write never entered failure cleanup")
        }
        try host.stop()
        let replacement = try host.start(onOutput: { _, _ in }, onExit: { _, _ in })
        XCTAssertEqual(replacement, first + 1)
        releaseCleanup.signal()
        wait(for: [writeFinished], timeout: 3)
        XCTAssertEqual(observed.writtenError(), .writeTimedOut)
        XCTAssertTrue(host.isRunning, "old write cleanup terminated replacement")
        try host.write(Data("{}\n".utf8), generation: replacement)
        try host.stop()
    }
    #endif
}
