import Foundation
import Darwin
import CirclrCore

private func configureTrustedMCPWriter(_ fd: Int32) throws {
    let flags = Darwin.fcntl(fd, F_GETFL)
    guard flags >= 0,
          Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0,
          Darwin.fcntl(fd, F_SETNOSIGPIPE, 1) == 0 else {
        throw CirclrError("trusted_mcp_unavailable: stdin 보호에 실패했습니다")
    }
}

private func writeTrustedMCPFrame(_ packet: Data, to fd: Int32) throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    try packet.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                throw CirclrError("trusted_mcp_unavailable: helper stdin 시간이 초과됐습니다")
            }
            var ready = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let timeout = Int32(min(3000, max(1, Int(remaining * 1000))))
            let polled = Darwin.poll(&ready, 1, timeout)
            if polled < 0 && errno == EINTR { continue }
            guard polled > 0, ready.revents & Int16(POLLOUT) != 0 else {
                throw CirclrError("trusted_mcp_unavailable: helper stdin을 사용할 수 없습니다")
            }
            let written = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
            if written > 0 { offset += written; continue }
            if written < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            throw CirclrError("trusted_mcp_unavailable: helper stdin 쓰기에 실패했습니다")
        }
    }
}

/// Never wait for an uncooperative child on MainActor. Process retains its PID
/// identity while the utility queue observes termination and escalates once.
private func reapTrustedMCPHelper(_ process: Process) {
    let deadline = ProcessInfo.processInfo.systemUptime + 1
    while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
        usleep(20_000)
    }
    if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
}

/// Serializes one app-owned stdio MCP conversation away from MainActor.
private actor TrustedMCPHelperIO {
    private let input: FileHandle
    private let output: FileHandle
    private var pending = Data()

    init(input: FileHandle, output: FileHandle) {
        self.input = input
        self.output = output
    }

    func request(_ object: [String: Any]) throws -> [String: Any] {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CirclrError("trusted_mcp_frame: 요청 형식이 올바르지 않습니다")
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= 1_048_576 else {
            throw CirclrError("trusted_mcp_frame: 요청이 너무 큽니다")
        }
        try writeTrustedMCPFrame(data + Data([10]), to: input.fileDescriptor)
        let fd = output.fileDescriptor
        while true {
            if let end = pending.firstIndex(of: 10) {
                let frame = Data(pending[..<end])
                pending.removeSubrange(...end)
                guard frame.count <= 1_048_576,
                      let result = try JSONSerialization.jsonObject(with: frame) as? [String: Any] else {
                    throw CirclrError("trusted_mcp_frame: 응답 형식이 올바르지 않습니다")
                }
                return result
            }
            guard pending.count <= 1_048_576 else {
                throw CirclrError("trusted_mcp_frame: 응답이 너무 큽니다")
            }
            var ready = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            guard Darwin.poll(&ready, 1, 5000) > 0 else {
                throw CirclrError("trusted_mcp_unavailable: helper 응답 시간이 초과됐습니다")
            }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let n = Darwin.read(fd, &bytes, bytes.count)
            guard n > 0 else { throw CirclrError("trusted_mcp_unavailable: helper가 종료됐습니다") }
            pending.append(contentsOf: bytes.prefix(n))
        }
    }
}

/// Child lifetime is bound to TrustedAgentIngress. This class never exposes
/// its bootstrap capability to MCP parameters, logs, argv, env, or files.
@MainActor final class TrustedMCPHelperSession {
    private let process: Process
    private let stdin: Pipe
    private let stdout: Pipe
    private let io: TrustedMCPHelperIO
    private weak var ingress: TrustedAgentIngress?
    private(set) var stopped = false
    var processIdentifier: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }

    init(ingress: TrustedAgentIngress, executable: URL? = nil) throws {
        let binary = executable ?? Bundle.main.executableURL?
            .deletingLastPathComponent().appendingPathComponent("circlr-trusted-mcp-helper")
        guard let binary, FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw CirclrError("trusted_mcp_unavailable: 내장 helper를 찾을 수 없습니다")
        }
        let child = Process()
        let input = Pipe()
        let output = Pipe()
        child.executableURL = binary
        child.arguments = []
        child.environment = [:]
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak ingress] _ in
            Task { @MainActor in ingress?.helperDidExitUnexpectedly() }
        }
        process = child
        stdin = input
        stdout = output
        self.ingress = ingress
        io = TrustedMCPHelperIO(input: input.fileHandleForWriting,
                                output: output.fileHandleForReading)
        do {
            try child.run()
            try configureTrustedMCPWriter(input.fileHandleForWriting.fileDescriptor)
            let bootstrap: [String: Any] = [
                "version": 1, "socket": ingress.path,
                "capability": ingress.clientCapability,
                "parentPID": Int(getpid()),
                "methods": ingress.helperMethods.sorted()
            ]
            let packet = try JSONSerialization.data(withJSONObject: bootstrap, options: [.sortedKeys])
            guard packet.count <= 4096 else {
                throw CirclrError("trusted_mcp_frame: bootstrap이 너무 큽니다")
            }
            try writeTrustedMCPFrame(packet + Data([10]),
                                     to: input.fileHandleForWriting.fileDescriptor)
        } catch {
            if child.isRunning { child.terminate() }
            input.fileHandleForWriting.closeFile()
            output.fileHandleForReading.closeFile()
            throw error
        }
    }

    func request(_ object: [String: Any]) async throws -> [String: Any] {
        guard !stopped, process.isRunning else {
            throw CirclrError("trusted_mcp_unavailable: helper가 종료됐습니다")
        }
        do {
            let reply = try await io.request(object)
            guard !stopped, ingress?.acceptsHelperResult(self) == true else {
                throw CirclrError("trusted_run_stale: helper 응답이 도착하기 전에 turn이 종료됐습니다")
            }
            return reply
        } catch {
            // Timeout, EOF, or malformed output ends this child turn. The
            // ingress closes both the child and the trusted authority.
            ingress?.helperDidExitUnexpectedly()
            throw error
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        if process.isRunning { process.terminate() }
        stdin.fileHandleForWriting.closeFile()
        stdout.fileHandleForReading.closeFile()
        let child = process
        DispatchQueue.global(qos: .utility).async { reapTrustedMCPHelper(child) }
    }

    deinit {
        // AppStore owns normal STOP. This final safeguard also handles a
        // partially initialized session that never reached the ingress.
        if !stopped && process.isRunning {
            process.terminate()
            let child = process
            DispatchQueue.global(qos: .utility).async { reapTrustedMCPHelper(child) }
        }
    }
}
