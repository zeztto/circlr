import Foundation
import Darwin
import XCTest
@testable import CirclrCore

/// Starts fresh XCTest processes; never forks an initialized Foundation runtime.
enum StorageProcessFixture {
    static let rootKey = "CIRCLR_STORAGE_QA_CHILD_ROOT"
    static let modeKey = "CIRCLR_STORAGE_QA_CHILD_MODE"

    static func launch(root: URL, mode: String, test: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xctest", "-XCTest", test, Bundle(for: RecoveryProcessTests.self).bundleURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment[rootKey] = root.path
        environment[modeKey] = mode
        process.environment = environment
        let log = root.appendingPathComponent(mode + ".log")
        _ = FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        try handle.close()
        return process
    }

    static func awaitMarker(_ name: String, root: URL, process: Process) throws {
        let marker = root.appendingPathComponent(name)
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: marker.path) {
            guard process.isRunning, Date() < deadline else {
                throw NSError(domain: "StorageProcessFixture", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Child did not reach \(name); inspect \(root.path)"])
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    static func finish(_ process: Process) throws {
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        guard !process.isRunning else {
            killAndWait(process)
            throw NSError(domain: "StorageProcessFixture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Child did not exit"])
        }
        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 0)
    }

    static func killAndWait(_ process: Process) {
        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            XCTAssertFalse(process.isRunning, "SIGKILL child did not exit before cleanup deadline")
            if !process.isRunning { process.waitUntilExit() }
        }
    }

    static func hold(marker: String, root: URL) throws {
        try Data("ready".utf8).write(to: root.appendingPathComponent(marker), options: .atomic)
        // Parent must kill this exact child. A finite timeout prevents orphaned tests.
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        throw NSError(domain: "StorageProcessFixture", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Parent did not kill held child"])
    }
}

final class RecoveryProcessTests: XCTestCase {
    func testSeparateProcessLockSurvivesContentionAndReleasesAfterCrash() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-recovery-process-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let test = "CirclrCoreTests.RecoveryProcessTests/testRecoveryChildHarness"
        let owner = try StorageProcessFixture.launch(root: root, mode: "owner", test: test)
        defer { StorageProcessFixture.killAndWait(owner) }
        try StorageProcessFixture.awaitMarker("owner-ready", root: root, process: owner)
        let original = Data("owned recovery bytes".utf8)
        let recovery = root.appendingPathComponent("recovery-v2.json")
        XCTAssertEqual(try Data(contentsOf: recovery), original)

        let contender = try StorageProcessFixture.launch(root: root, mode: "contender", test: test)
        defer { StorageProcessFixture.killAndWait(contender) }
        try StorageProcessFixture.finish(contender)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("contender-result"), encoding: .utf8), "locked")
        XCTAssertEqual(try Data(contentsOf: recovery), original)

        StorageProcessFixture.killAndWait(owner)
        XCTAssertEqual(owner.terminationReason, .uncaughtSignal)
        XCTAssertEqual(owner.terminationStatus, SIGKILL)
        let next = try RecoveryFileStore(url: recovery)
        XCTAssertEqual(try next.read(), original)
        XCTAssertFalse(try next.write(Data("unadopted".utf8)))
        XCTAssertTrue(try next.adopt(original))
        XCTAssertTrue(try next.write(Data("recovered".utf8)))
        XCTAssertEqual(try next.read(), Data("recovered".utf8))
    }

    func testRecoveryChildHarness() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[StorageProcessFixture.rootKey],
              let mode = environment[StorageProcessFixture.modeKey] else { throw XCTSkip("Child-only storage fixture") }
        let root = URL(fileURLWithPath: path)
        let recovery = root.appendingPathComponent("recovery-v2.json")
        switch mode {
        case "owner":
            let store = try RecoveryFileStore(url: recovery)
            XCTAssertTrue(try store.write(Data("owned recovery bytes".utf8)))
            try withExtendedLifetime(store) { try StorageProcessFixture.hold(marker: "owner-ready", root: root) }
        case "contender":
            do {
                _ = try RecoveryFileStore(url: recovery)
                XCTFail("Another process must not acquire the owner's recovery lock")
            } catch RecoveryFileStore.StoreError.alreadyInUse {
                try Data("locked".utf8).write(to: root.appendingPathComponent("contender-result"), options: .atomic)
            }
        default: XCTFail("Unexpected child mode")
        }
    }
}
