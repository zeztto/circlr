import Foundation
import Darwin
import XCTest
@testable import CirclrCodex

final class CodexOfflineSessionCoordinatorTests: XCTestCase {
    private final class Observer: @unchecked Sendable {
        private let lock = NSLock()
        private var received: [CodexEvent] = []
        private var receivedSnapshots: [CodexOfflineSessionSnapshot] = []

        func append(_ snapshot: CodexOfflineSessionSnapshot, _ events: [CodexEvent]) {
            lock.lock()
            received += events
            receivedSnapshots.append(snapshot)
            lock.unlock()
        }

        var events: [CodexEvent] {
            lock.lock(); defer { lock.unlock() }
            return received
        }

        var snapshots: [CodexOfflineSessionSnapshot] {
            lock.lock(); defer { lock.unlock() }
            return receivedSnapshots
        }
    }

    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath,
                           line: UInt = #line) {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !predicate() && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(predicate(), file: file, line: line)
    }

    private func fixture(mode: String = "normal", blockDelivery: DispatchSemaphore? = nil,
                         deliveryEntered: DispatchSemaphore? = nil) throws -> (directory: URL, marker: URL, coordinator: CodexOfflineSessionCoordinator, observer: Observer) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("circlr-offline-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let resolved = directory.path.withCString({ realpath($0, nil) }) else {
            throw CodexProcessHostError.invalidCurrentDirectory
        }
        defer { free(resolved) }
        let canonicalDirectory = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        let script = canonicalDirectory.appendingPathComponent("fake-app-server.py")
        let marker = canonicalDirectory.appendingPathComponent("approval-reply.json")
        let source = #"""
        #!/usr/bin/python3
        import json
        import sys
        import time

        marker = sys.argv[1]
        mode = sys.argv[2]
        catalog_count = 0

        def send(value):
            sys.stdout.write(json.dumps(value, separators=(',', ':')) + '\n')
            sys.stdout.flush()

        for line in sys.stdin:
            value = json.loads(line)
            method = value.get('method')
            if method == 'initialize':
                send({'id': value['id'], 'result': {'userAgent': 'offline-fixture'}})
            elif method == 'initialized':
                if mode == 'flood-output':
                    time.sleep(0.15)
                    burst = json.dumps({'method': 'fixture/noise', 'params': {'text': 'x' * 4000}},
                                       separators=(',', ':')) + '\n'
                    for _ in range(1500):
                        sys.stdout.write(burst)
                        sys.stdout.flush()
            elif method == 'account/read':
                send({'id': value['id'], 'result': {'account': None, 'requiresOpenaiAuth': True}})
            elif method == 'model/list':
                catalog_count += 1
                if catalog_count == 1:
                    result = {'data': [{'id': 'model-old', 'isDefault': True}], 'nextCursor': 'page-2'}
                elif catalog_count == 2:
                    result = {'data': [{'id': 'model-keep', 'isDefault': False}], 'nextCursor': None}
                else:
                    result = {'data': [{'id': 'model-keep', 'isDefault': True}], 'nextCursor': None}
                send({'id': value['id'], 'result': result})
            elif method == 'thread/start':
                send({'id': value['id'], 'result': {'thread': {'id': 'thread-fixture'}}})
            elif method == 'turn/start':
                send({'id': value['id'], 'result': {'turn': {'id': 'turn-fixture'}}})
                approval = {'id': 900, 'method': 'item/fileChange/requestApproval',
                            'params': {'threadId': 'thread-fixture', 'turnId': 'turn-fixture', 'itemId': 'file-1'}}
                if mode == 'completion-with-approval':
                    completed = {'method': 'turn/completed',
                                 'params': {'threadId': 'thread-fixture',
                                            'turn': {'id': 'turn-fixture', 'status': 'completed'}}}
                    sys.stdout.write(json.dumps(approval, separators=(',', ':')) + '\n' +
                                     json.dumps(completed, separators=(',', ':')) + '\n')
                    sys.stdout.flush()
                else:
                    send(approval)
            elif method == 'turn/interrupt':
                send({'id': value['id'], 'result': {}})
                late = {'method': 'item/agentMessage/delta',
                        'params': {'threadId': 'thread-fixture', 'turnId': 'turn-fixture',
                                   'itemId': 'answer', 'delta': 'late secret'}}
                done = {'method': 'turn/completed',
                        'params': {'threadId': 'thread-fixture',
                                   'turn': {'id': 'turn-fixture', 'status': 'interrupted'}}}
                sys.stdout.write(json.dumps(late, separators=(',', ':')) + '\n' +
                                 json.dumps(done, separators=(',', ':')) + '\n')
                sys.stdout.flush()
            elif value.get('id') == 900:
                with open(marker, 'w') as output:
                    json.dump(value, output)
        """#
        try source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let host = CodexProcessHost(
            executableURL: script, arguments: [marker.path, mode],
            childConfiguration: CodexProcessChildConfiguration(
                environment: ["LANG": "C", "PATH": "/usr/bin:/bin"],
                currentDirectoryURL: canonicalDirectory))
        let observer = Observer()
        let coordinator = CodexOfflineSessionCoordinator(
            host: host, authorizedThreadCWD: canonicalDirectory.path, version: "0.80.0",
            onUpdate: { snapshot, events in
                if snapshot.connection == .initializing && events.isEmpty {
                    deliveryEntered?.signal()
                    blockDelivery?.wait()
                }
                observer.append(snapshot, events)
            })
        return (canonicalDirectory, marker, coordinator, observer)
    }

    func testFakeChildConnectsCatalogAndDeclinesApprovalThenSuppressesCancelledText() throws {
        let f = try fixture()
        defer { try? f.coordinator.stop(); try? FileManager.default.removeItem(at: f.directory) }
        let generation = try f.coordinator.start()
        waitUntil { f.coordinator.snapshot.connection == .protocolReady }
        _ = try f.coordinator.readAccount()
        waitUntil { f.observer.events.contains(.accountRead(CodexAccountSummary(authMode: .signedOut, plan: nil))) }
        _ = try f.coordinator.refreshModelCatalog()
        waitUntil { f.coordinator.snapshot.modelCatalogComplete }
        XCTAssertEqual(f.coordinator.snapshot.modelIDs, ["model-keep", "model-old"])
        XCTAssertThrowsError(try f.coordinator.startThread(model: "unlisted")) {
            XCTAssertEqual($0 as? CodexOfflineSessionError, .modelNotListed)
        }
        _ = try f.coordinator.startThread(model: "model-old")
        waitUntil { f.coordinator.snapshot.threadID == "thread-fixture" }
        _ = try f.coordinator.startTurn(threadID: "thread-fixture", text: "offline fixture")
        waitUntil { FileManager.default.fileExists(atPath: f.marker.path) }
        let reply = try JSONDecoder().decode(CodexJSONValue.self, from: Data(contentsOf: f.marker))
        XCTAssertEqual(reply["id"], .integer(900))
        XCTAssertEqual(reply["error"]?["code"], .integer(-32602))
        XCTAssertNil(reply["result"])
        XCTAssertEqual(f.coordinator.snapshot.generation, generation)
        try f.coordinator.cancelTurn()
        waitUntil { f.coordinator.snapshot.turn == .interrupted }
        XCTAssertFalse(f.observer.events.contains {
            if case .assistantDelta(_, let text) = $0 { return text.contains("late secret") }
            return false
        })
        XCTAssertTrue(f.observer.events.contains(.serverRequestRejected(
            id: CodexServerRequestID(.integer(900)), method: "item/fileChange/requestApproval")))
    }

    func testCatalogDriftBlocksPreviouslySelectedModelAndRestartChangesGeneration() throws {
        let f = try fixture()
        defer { try? f.coordinator.stop(); try? FileManager.default.removeItem(at: f.directory) }
        let first = try f.coordinator.start()
        waitUntil { f.coordinator.snapshot.connection == .protocolReady }
        _ = try f.coordinator.refreshModelCatalog()
        waitUntil { f.coordinator.snapshot.modelCatalogComplete }
        _ = try f.coordinator.startThread(model: "model-old")
        waitUntil { f.coordinator.snapshot.threadID == "thread-fixture" }
        _ = try f.coordinator.refreshModelCatalog()
        waitUntil { f.coordinator.snapshot.modelCatalogComplete }
        XCTAssertEqual(f.coordinator.snapshot.modelIDs, ["model-keep"])
        XCTAssertThrowsError(try f.coordinator.startTurn(threadID: "thread-fixture", text: "stale model")) {
            XCTAssertEqual($0 as? CodexOfflineSessionError, .modelNotListed)
        }
        try f.coordinator.stop()
        let second = try f.coordinator.start()
        XCTAssertEqual(second, first + 1)
        waitUntil { f.coordinator.snapshot.connection == .protocolReady }
        #if DEBUG
        f.coordinator.receiveForTesting(Data("{\"id\":1,\"result\":{\"thread\":{\"id\":\"stale\"}}}\n".utf8),
                                        generation: first)
        XCTAssertEqual(f.coordinator.snapshot.connection, .protocolReady)
        XCTAssertNil(f.coordinator.snapshot.threadID)
        #endif
        XCTAssertFalse(f.coordinator.snapshot.modelCatalogComplete)
        XCTAssertNil(f.coordinator.snapshot.selectedModel)
        XCTAssertThrowsError(try f.coordinator.startThread(model: "model-old")) {
            XCTAssertEqual($0 as? CodexOfflineSessionError, .modelCatalogUnavailable)
        }
    }

    func testCompletionAndApprovalInOneReadDoNotReviveFinishedRequest() throws {
        let f = try fixture(mode: "completion-with-approval")
        defer { try? f.coordinator.stop(); try? FileManager.default.removeItem(at: f.directory) }
        _ = try f.coordinator.start()
        waitUntil { f.coordinator.snapshot.connection == .protocolReady }
        _ = try f.coordinator.refreshModelCatalog()
        waitUntil { f.coordinator.snapshot.modelCatalogComplete }
        _ = try f.coordinator.startThread(model: "model-old")
        waitUntil { f.coordinator.snapshot.threadID == "thread-fixture" }
        _ = try f.coordinator.startTurn(threadID: "thread-fixture", text: "finish")
        waitUntil { f.coordinator.snapshot.turn == .completed }
        XCTAssertEqual(f.coordinator.snapshot.connection, .protocolReady)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.marker.path))
    }

    func testCancelFencesTextAlreadyQueuedBehindSlowObserver() throws {
        let gate = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        let f = try fixture(blockDelivery: gate, deliveryEntered: entered)
        defer {
            gate.signal()
            try? f.coordinator.stop()
            try? FileManager.default.removeItem(at: f.directory)
        }
        let generation = try f.coordinator.start()
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        waitUntil { f.coordinator.snapshot.connection == .protocolReady }
        _ = try f.coordinator.refreshModelCatalog()
        waitUntil { f.coordinator.snapshot.modelCatalogComplete }
        _ = try f.coordinator.startThread(model: "model-old")
        waitUntil { f.coordinator.snapshot.threadID == "thread-fixture" }
        _ = try f.coordinator.startTurn(threadID: "thread-fixture", text: "cancel")
        waitUntil { f.coordinator.snapshot.turn == .running }
        #if DEBUG
        f.coordinator.receiveForTesting(Data("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-fixture\",\"turnId\":\"turn-fixture\",\"itemId\":\"queued\",\"delta\":\"queued before cancel\"}}\n".utf8), generation: generation)
        #endif
        try f.coordinator.cancelTurn()
        gate.signal()
        waitUntil { f.coordinator.snapshot.turn == .interrupted }
        waitUntil { f.coordinator.pendingDeliveriesForTesting == 0 }
        XCTAssertFalse(f.observer.events.contains {
            if case .assistantDelta(_, let text) = $0 { return text == "queued before cancel" }
            return false
        })
    }

    func testSlowObserverTriggersBoundedDeliveryFailure() throws {
        let gate = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        let f = try fixture(blockDelivery: gate, deliveryEntered: entered)
        defer {
            gate.signal()
            try? f.coordinator.stop()
            try? FileManager.default.removeItem(at: f.directory)
        }
        let generation = try f.coordinator.start()
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        waitUntil { f.coordinator.snapshot.connection == .protocolReady }
        #if DEBUG
        for index in 0..<64 {
            f.coordinator.receiveForTesting(Data("{\"method\":\"fixture/\(index)\",\"params\":{}}\n".utf8),
                                            generation: generation)
        }
        #endif
        XCTAssertEqual(f.coordinator.snapshot.failure, .deliveryBackpressure)
        XCTAssertNil(f.coordinator.snapshot.generation)
        let pending = f.coordinator.pendingDeliveriesForTesting
        XCTAssertLessThanOrEqual(pending, 33)
        for _ in 0..<12 {
            XCTAssertThrowsError(try f.coordinator.start()) {
                XCTAssertEqual($0 as? CodexOfflineSessionError, .deliveryBackpressure)
            }
            XCTAssertEqual(f.coordinator.pendingDeliveriesForTesting, pending)
        }
        gate.signal()
        waitUntil { f.coordinator.pendingDeliveriesForTesting == 0 }
        XCTAssertEqual(f.observer.snapshots.last?.failure, .deliveryBackpressure)
    }

    func testBlockedReducerAppliesHostIngressBackpressure() throws {
        let f = try fixture(mode: "flood-output")
        defer { try? f.coordinator.stop(); try? FileManager.default.removeItem(at: f.directory) }
        _ = try f.coordinator.start()
        waitUntil { f.coordinator.snapshot.connection == .protocolReady }
        #if DEBUG
        let entered = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        f.coordinator.blockStateQueueForTesting(entered: entered, gate: gate)
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        waitUntil { !f.coordinator.hostRunningForTesting }
        gate.signal()
        waitUntil { f.coordinator.snapshot.failure == .childExited(.outputBackpressure) }
        #endif
    }
}
