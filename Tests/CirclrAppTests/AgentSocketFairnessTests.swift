import Foundation
import Darwin
import XCTest
@testable import CirclrApp

private func fairnessConnect(path: String) throws -> Int32 {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        Darwin.close(fd)
        throw NSError(domain: "AgentSocketFairnessTests", code: 1)
    }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        let failure = errno
        Darwin.close(fd)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
    }
    var timeout = timeval(tv_sec: 4, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var noSignal: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    return fd
}

private func fairnessRoundTrip(path: String, packet: Data) throws -> Data {
    let fd = try fairnessConnect(path: path)
    defer { Darwin.close(fd) }
    let outbound = packet + Data([10])
    let sent = outbound.withUnsafeBytes {
        Darwin.write(fd, $0.baseAddress!, $0.count)
    }
    guard sent == outbound.count else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 128)
    while response.count < 1024 {
        let count = Darwin.read(fd, &buffer, buffer.count)
        guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        response.append(contentsOf: buffer.prefix(count))
        if let newline = response.firstIndex(of: 10) { return Data(response[..<newline]) }
    }
    throw NSError(domain: "AgentSocketFairnessTests", code: 2)
}

@MainActor final class AgentSocketFairnessTests: XCTestCase {
    func testIdleSameUIDClientCannotDelayFollowingValidRequest() async throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("circlr-fair-\(UUID().uuidString.prefix(8))", isDirectory: true)
        var socket: AgentSocket? = try AgentSocket(directory: directory,
            maximumRequestBytes: 256,
            preflight: { $0 == Data("valid".utf8) },
            onRequest: { _, reply in reply(Data("accepted".utf8)) })
        defer {
            socket = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let path = try XCTUnwrap(socket?.path)
        let idle = try fairnessConnect(path: path)
        defer { Darwin.close(idle) }
        // Give the listening source time to accept the idle same-UID peer.
        try await Task.sleep(for: .milliseconds(100))
        let start = ContinuousClock.now
        let reply = try await Task.detached(priority: .utility) {
            try fairnessRoundTrip(path: path, packet: Data("valid".utf8))
        }.value
        let elapsed = start.duration(to: .now)
        XCTAssertEqual(reply, Data("accepted".utf8))
        XCTAssertLessThan(elapsed, .seconds(1), "한 개의 무응답 연결이 정상 요청을 대기시켰습니다")
    }

    func testIdleDeadlineClosesClientAndDoesNotBlockNextRequest() async throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("circlr-fair-\(UUID().uuidString.prefix(8))", isDirectory: true)
        var socket: AgentSocket? = try AgentSocket(directory: directory,
            maximumRequestBytes: 8,
            preflight: { $0 == Data("valid".utf8) },
            onRequest: { _, reply in reply(Data("ok".utf8)) })
        defer {
            socket = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let path = try XCTUnwrap(socket?.path)
        let idle = try fairnessConnect(path: path)
        defer { Darwin.close(idle) }
        let idleResult = await Task.detached(priority: .utility) { () -> Int in
            var byte: UInt8 = 0
            return Darwin.read(idle, &byte, 1)
        }.value
        XCTAssertEqual(idleResult, 0, "3초 수신 기한 후 idle peer의 EOF가 필요합니다")
        let reply = try await Task.detached(priority: .utility) {
            try fairnessRoundTrip(path: path, packet: Data("valid".utf8))
        }.value
        XCTAssertEqual(reply, Data("ok".utf8))
        let oversized = try await Task.detached(priority: .utility) { () throws -> Int in
            let fd = try fairnessConnect(path: path)
            defer { Darwin.close(fd) }
            let packet = Data("12345678\n".utf8)
            _ = packet.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
            var byte: UInt8 = 0
            return Darwin.read(fd, &byte, 1)
        }.value
        XCTAssertEqual(oversized, 0, "수신 크기 제한을 넘긴 peer는 닫아야 합니다")
    }

    func testServerTeardownClosesPendingClientWithoutLateCallback() async throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("circlr-fair-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let unexpected = expectation(description: "테어다운 후 callback 금지")
        unexpected.isInverted = true
        var socket: AgentSocket? = try AgentSocket(directory: directory,
            onRequest: { _, reply in unexpected.fulfill(); reply(Data("unexpected".utf8)) })
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try XCTUnwrap(socket?.path)
        let idle = try fairnessConnect(path: path)
        defer { Darwin.close(idle) }
        try await Task.sleep(for: .milliseconds(100))
        socket = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        let pendingResult = await Task.detached(priority: .utility) { () -> Int in
            var byte: UInt8 = 0
            return Darwin.read(idle, &byte, 1)
        }.value
        XCTAssertEqual(pendingResult, 0)
        await fulfillment(of: [unexpected], timeout: 0.05)
    }

    func testCompletedRequestFloodIsCappedAndStopDrainsAcceptedStaleReplies() async throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("circlr-fair-\(UUID().uuidString.prefix(8))", isDirectory: true)
        var socket: AgentSocket? = try AgentSocket(directory: directory,
            maximumRequestBytes: 64,
            preflight: { $0 == Data("valid".utf8) },
            onRequest: { _, reply in reply(Data("trusted_run_stale".utf8)) })
        defer {
            socket = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let path = try XCTUnwrap(socket?.path)
        // This test intentionally holds the MainActor while 64 complete
        // requests arrive, so none can finish and release its accepted slot.
        var peers = [Int32]()
        for _ in 0..<64 {
            let fd = try fairnessConnect(path: path)
            let packet = Data("valid\n".utf8)
            _ = packet.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
            peers.append(fd)
            usleep(3_000)
        }
        usleep(100_000)
        socket = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        let connectedPeers = peers
        let results = await Task.detached(priority: .utility) { () -> [Data?] in
            connectedPeers.map { fd in
                defer { Darwin.close(fd) }
                var result = Data()
                var bytes = [UInt8](repeating: 0, count: 64)
                while result.count < 128 {
                    let count = Darwin.read(fd, &bytes, bytes.count)
                    guard count > 0 else { return result.isEmpty ? nil : result }
                    result.append(contentsOf: bytes.prefix(count))
                    if result.contains(10) { return result }
                }
                return result
            }
        }.value
        let accepted = results.compactMap { $0 }
        XCTAssertEqual(accepted.count, 32, "완료 요청도 응답까지 32 슬롯 안에 남아야 합니다")
        XCTAssertTrue(accepted.allSatisfy { $0 == Data("trusted_run_stale\n".utf8) })
        XCTAssertEqual(results.count - accepted.count, 32)
    }

    func testAcceptedReplyDeadlineReleasesStalledFDAndFollowingRequestWorks() async throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("circlr-fair-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let entered = expectation(description: "accepted request entered callback")
        var socket: AgentSocket? = try AgentSocket(directory: directory,
            maximumRequestBytes: 32, replyTimeout: 0.3,
            onRequest: { request, reply in
                if request == Data("stall".utf8) { entered.fulfill() }
                else { reply(Data("ok".utf8)) }
            })
        defer {
            socket = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let path = try XCTUnwrap(socket?.path)
        let stalled = try fairnessConnect(path: path)
        defer { Darwin.close(stalled) }
        let packet = Data("stall\n".utf8)
        _ = packet.withUnsafeBytes { Darwin.write(stalled, $0.baseAddress!, $0.count) }
        await fulfillment(of: [entered], timeout: 1)
        let eof = await Task.detached(priority: .utility) { () -> Int in
            var byte: UInt8 = 0
            return Darwin.read(stalled, &byte, 1)
        }.value
        XCTAssertEqual(eof, 0, "응답을 반환하지 않는 callback의 FD는 기한 후 닫혀야 합니다")
        let live = try await Task.detached(priority: .utility) {
            try fairnessRoundTrip(path: path, packet: Data("live".utf8))
        }.value
        XCTAssertEqual(live, Data("ok".utf8))
    }

    func testOversizedReplyIsBoundedAndSocketRemainsResponsive() async throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("circlr-fair-\(UUID().uuidString.prefix(8))", isDirectory: true)
        var socket: AgentSocket? = try AgentSocket(directory: directory,
            onRequest: { request, reply in
                if request == Data("large".utf8) {
                    reply(Data(repeating: 65, count: 8_388_609))
                } else { reply(Data("ok".utf8)) }
            })
        defer {
            socket = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let path = try XCTUnwrap(socket?.path)
        let limited = try await Task.detached(priority: .utility) {
            try fairnessRoundTrip(path: path, packet: Data("large".utf8))
        }.value
        XCTAssertEqual(limited, Data(#"{"ok":false,"error":"response_too_large"}"#.utf8))
        let live = try await Task.detached(priority: .utility) {
            try fairnessRoundTrip(path: path, packet: Data("live".utf8))
        }.value
        XCTAssertEqual(live, Data("ok".utf8))
    }

    func testAggregateRequestByteBudgetRejectsThirdQueuedRequest() async throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("circlr-fair-\(UUID().uuidString.prefix(8))", isDirectory: true)
        var socket: AgentSocket? = try AgentSocket(directory: directory,
            maximumRequestBytes: 512, maximumBufferedBytes: 1024,
            onRequest: { _, reply in reply(Data("ok".utf8)) })
        defer {
            socket = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let path = try XCTUnwrap(socket?.path)
        var peers = [Int32]()
        let packet = Data(repeating: 120, count: 400) + Data([10])
        for _ in 0..<3 {
            let fd = try fairnessConnect(path: path)
            XCTAssertEqual(packet.withUnsafeBytes {
                Darwin.write(fd, $0.baseAddress!, $0.count)
            }, packet.count)
            peers.append(fd)
            usleep(10_000)
        }
        usleep(50_000)
        socket = nil
        let connectedPeers = peers
        let results = await Task.detached(priority: .utility) { () -> [Data?] in
            connectedPeers.map { fd in
                defer { Darwin.close(fd) }
                var result = Data()
                var bytes = [UInt8](repeating: 0, count: 32)
                while result.count < 64 {
                    let count = Darwin.read(fd, &bytes, bytes.count)
                    guard count > 0 else { return result.isEmpty ? nil : result }
                    result.append(contentsOf: bytes.prefix(count))
                    if result.contains(10) { return result }
                }
                return result
            }
        }.value
        XCTAssertEqual(results.compactMap { $0 }.count, 2)
        XCTAssertEqual(results.compactMap { $0 }, [Data("ok\n".utf8), Data("ok\n".utf8)])
    }
}
