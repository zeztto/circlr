import Foundation
import Darwin

public enum CodexProcessHostError: Error, Equatable {
    case invalidExecutable
    case invalidEnvironment
    case invalidCurrentDirectory
    case alreadyRunning
    case launchFailed
    case stopped
    case staleGeneration
    case invalidPacket
    case packetTooLarge
    case writeFailed
    case writeTimedOut
    case stopTimedOut
}

/// Required child-only launch context. This context replaces the
/// inherited environment rather than merging with the app's credentials.
/// CODEX_HOME is a credential-bearing location and must be chosen by the owner;
/// never place credentials or capabilities in process arguments. This boundary
/// does not control what a launched child later passes to models or tools.
public struct CodexProcessChildConfiguration {
    public static let allowedEnvironmentKeys: Set<String> = [
        "HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "CODEX_HOME"
    ]

    public let environment: [String: String]
    public let currentDirectoryURL: URL

    public init(environment: [String: String], currentDirectoryURL: URL) {
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
    }
}

public enum CodexProcessExit: Equatable {
    case stopped
    case exited(status: Int32)
    case readFailed
    case outputBackpressure
}

/// Owns one app-server child and its stdio pipes. The caller supplies an app-owned,
/// fixed executable and arguments; neither a shell nor user text is executed here.
/// Callbacks carry the transport generation and run on a serial background queue.
/// This host does not parse JSON, authorize tools, or retain/log stderr or credentials.
/// The owner must explicitly call stop() during teardown and weak-capture the host
/// or owning coordinator in callbacks; a callback retain cycle defeats deinit cleanup.
public final class CodexProcessHost: @unchecked Sendable {
    public typealias OutputHandler = @Sendable (UInt64, Data) -> Void
    public typealias ExitHandler = @Sendable (UInt64, CodexProcessExit) -> Void

    private final class Session {
        let generation: UInt64
        let process: Process
        let input: Pipe
        let output: Pipe
        let outputHandler: OutputHandler
        let exitHandler: ExitHandler
        let readerDone = DispatchGroup()
        var stopping = false
        var explicitlyStopped = false
        var pendingOutputBytes = 0
        var pendingOutputChunks = 0

        init(generation: UInt64, process: Process, input: Pipe, output: Pipe,
             outputHandler: @escaping OutputHandler, exitHandler: @escaping ExitHandler) {
            self.generation = generation
            self.process = process
            self.input = input
            self.output = output
            self.outputHandler = outputHandler
            self.exitHandler = exitHandler
        }
    }

    private let executableURL: URL
    private let arguments: [String]
    private let childConfiguration: CodexProcessChildConfiguration
    private let maximumPacketBytes: Int
    private let maximumPendingOutputBytes: Int
    private let writeTimeout: TimeInterval
    private let stopGrace: TimeInterval
    private let operations = NSLock()
    private let readerQueue = DispatchQueue(label: "circlr.codex.stdio.reader", qos: .utility)
    private let readerQueueKey = DispatchSpecificKey<Bool>()
    private let callbackQueue = DispatchQueue(label: "circlr.codex.stdio.callbacks", qos: .utility)
    private var current: Session?
    private var lastGeneration: UInt64 = 0
    #if DEBUG
    // Set before start. A test can hold the narrow post-write-failure window
    // without adding a production-visible callback or changing process timing.
    var beforeWriteFailureCleanupForTesting: (@Sendable () -> Void)?
    var ownedProcessForTesting: Process? {
        operations.lock(); defer { operations.unlock() }
        return current?.process
    }
    #endif

    public init(executableURL: URL, arguments: [String],
                childConfiguration: CodexProcessChildConfiguration,
                maximumPacketBytes: Int = 1_048_576,
                maximumPendingOutputBytes: Int = 1_048_576,
                writeTimeout: TimeInterval = 0.5,
                stopGrace: TimeInterval = 0.25) {
        precondition(maximumPacketBytes > 0 && maximumPacketBytes < Int.max)
        precondition(maximumPendingOutputBytes > 0 && maximumPendingOutputBytes < Int.max)
        precondition(writeTimeout.isFinite && writeTimeout > 0)
        precondition(stopGrace.isFinite && stopGrace > 0)
        self.executableURL = executableURL
        self.arguments = arguments
        self.childConfiguration = childConfiguration
        self.maximumPacketBytes = maximumPacketBytes
        self.maximumPendingOutputBytes = maximumPendingOutputBytes
        self.writeTimeout = writeTimeout
        self.stopGrace = stopGrace
        readerQueue.setSpecific(key: readerQueueKey, value: true)
    }

    deinit { try? stop() }

    public var isRunning: Bool {
        operations.lock(); defer { operations.unlock() }
        return current.map { !$0.stopping && $0.process.isRunning } ?? false
    }

    /// A successful launch creates a new generation. Launch failure leaves the host
    /// stopped and reports only a fixed error, never Foundation's path/stderr text.
    @discardableResult
    public func start(onOutput: @escaping OutputHandler,
                      onExit: @escaping ExitHandler) throws -> UInt64 {
        operations.lock(); defer { operations.unlock() }
        guard current == nil else { throw CodexProcessHostError.alreadyRunning }
        guard lastGeneration < UInt64.max else { throw CodexProcessHostError.stopped }
        guard executableURL.isFileURL, executableURL.path.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CodexProcessHostError.invalidExecutable
        }

        guard childConfiguration.environment.allSatisfy({ key, value in
            CodexProcessChildConfiguration.allowedEnvironmentKeys.contains(key) &&
                !value.contains("\0")
        }) else { throw CodexProcessHostError.invalidEnvironment }

        let directory = childConfiguration.currentDirectoryURL
        var isDirectory: ObjCBool = false
        guard directory.isFileURL, directory.path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let resolved = directory.path.withCString({ realpath($0, nil) }) else {
            throw CodexProcessHostError.invalidCurrentDirectory
        }
        defer { free(resolved) }
        guard directory.path == String(cString: resolved) else {
            throw CodexProcessHostError.invalidCurrentDirectory
        }

        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = childConfiguration.environment
        process.currentDirectoryURL = childConfiguration.currentDirectoryURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let inputFD = input.fileHandleForWriting.fileDescriptor
        let outputFD = output.fileHandleForReading.fileDescriptor
        guard fcntl(inputFD, F_SETNOSIGPIPE, 1) == 0,
              Self.makeNonblocking(inputFD), Self.makeNonblocking(outputFD) else {
            Self.close(input: input, output: output)
            throw CodexProcessHostError.launchFailed
        }
        do { try process.run() }
        catch {
            Self.close(input: input, output: output)
            throw CodexProcessHostError.launchFailed
        }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        let generation = lastGeneration + 1
        lastGeneration = generation
        let session = Session(generation: generation, process: process, input: input, output: output,
                              outputHandler: onOutput, exitHandler: onExit)
        current = session
        session.readerDone.enter()
        readerQueue.async { [weak self] in
            defer { session.readerDone.leave() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                // Release the owner after each bounded poll/read. Otherwise an
                // idle child keeps the host alive forever and deinit cannot stop it.
                let keepReading: Bool
                if let owner = self { keepReading = owner.readOne(session, buffer: &buffer) }
                else { return }
                if !keepReading { return }
            }
        }
        return generation
    }

    /// Write one complete JSONL packet. A partial or timed-out write stops the
    /// child because the reducer cannot safely replay a half-written RPC packet.
    public func write(_ packet: Data, generation: UInt64) throws {
        guard !packet.isEmpty, packet.last == 0x0A,
              !packet.dropLast().contains(0x0A) else { throw CodexProcessHostError.invalidPacket }
        guard packet.count <= maximumPacketBytes else { throw CodexProcessHostError.packetTooLarge }
        operations.lock()
        guard let session = current else {
            operations.unlock(); throw CodexProcessHostError.stopped
        }
        guard session.generation == generation else {
            operations.unlock(); throw CodexProcessHostError.staleGeneration
        }
        guard !session.stopping, session.process.isRunning else {
            operations.unlock(); throw CodexProcessHostError.stopped
        }
        let deadline = ProcessInfo.processInfo.systemUptime + writeTimeout
        let fd = session.input.fileHandleForWriting.fileDescriptor
        var offset = 0
        var failure: CodexProcessHostError?
        while offset < packet.count {
            // EINTR and repeated short writes must obey the same deadline as
            // EAGAIN; this lock also gates stop and replacement.
            if ProcessInfo.processInfo.systemUptime >= deadline {
                failure = .writeTimedOut
                break
            }
            let written = packet.withUnsafeBytes { bytes in
                Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), packet.count - offset)
            }
            if written > 0 { offset += written; continue }
            if written < 0 && errno == EINTR { continue }
            if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                if ProcessInfo.processInfo.systemUptime < deadline {
                    Thread.sleep(forTimeInterval: 0.005)
                    continue
                }
                failure = .writeTimedOut
            } else { failure = .writeFailed }
            break
        }
        if let failure {
            // Fence this exact child while the write lock is still held. A
            // concurrent stop/restart may replace it before cleanup resumes.
            session.stopping = true
            session.explicitlyStopped = true
            operations.unlock()
            #if DEBUG
            beforeWriteFailureCleanupForTesting?()
            #endif
            try? stop(only: session)
            throw failure
        }
        operations.unlock()
    }

    /// Close stdin, then terminate and reap this child with a finite grace period.
    /// A rare unkillable child remains owned so a later stop can retry; a new child
    /// cannot start while that session is present.
    public func stop() throws { try stop(only: nil) }

    private func stop(only expected: Session?) throws {
        operations.lock()
        guard let session = current else { operations.unlock(); return }
        if let expected, session !== expected { operations.unlock(); return }
        session.stopping = true
        session.explicitlyStopped = true
        try? session.input.fileHandleForWriting.close()
        operations.unlock()

        guard Self.terminate(session.process, grace: stopGrace) else {
            throw CodexProcessHostError.stopTimedOut
        }
        // When deinit runs after the reader's final strong owner reference is
        // released, this call is itself on readerQueue. The current readOne has
        // returned, so waiting for its own group would deadlock.
        if DispatchQueue.getSpecific(key: readerQueueKey) != true {
            guard session.readerDone.wait(timeout: .now() + stopGrace + 0.1) == .success else {
                throw CodexProcessHostError.stopTimedOut
            }
        }
        operations.lock()
        let owns = current === session
        if owns { current = nil }
        operations.unlock()
        if owns {
            try? session.output.fileHandleForReading.close()
            callbackQueue.async { session.exitHandler(session.generation, .stopped) }
        }
    }

    private func readOne(_ session: Session, buffer: inout [UInt8]) -> Bool {
        let fd = session.output.fileHandleForReading.fileDescriptor
        operations.lock()
        let active = current === session && !session.stopping
        operations.unlock()
        if !active { return false }
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
        let ready = Darwin.poll(&descriptor, 1, 50)
        if ready == 0 {
            // A descendant may have inherited stdout and kept the pipe open
            // after the owned app-server child exited. Do not wait forever.
            if !session.process.isRunning { finishAfterEOF(session, reason: nil); return false }
            return true
        }
        if ready < 0 && errno == EINTR { return true }
        guard ready > 0 else { finishAfterEOF(session, reason: .readFailed); return false }
        let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if count < 0 && (errno == EINTR || errno == EAGAIN) { return true }
        if count > 0 {
            let chunk = Data(buffer.prefix(count))
            operations.lock()
            let hasCapacity = session.pendingOutputChunks < 256 &&
                chunk.count <= maximumPendingOutputBytes - session.pendingOutputBytes
            if hasCapacity {
                session.pendingOutputBytes += chunk.count
                session.pendingOutputChunks += 1
            }
            operations.unlock()
            guard hasCapacity else { finishAfterEOF(session, reason: .outputBackpressure); return false }
            callbackQueue.async { [weak self] in
                guard let self else { return }
                self.operations.lock()
                let active = self.lastGeneration == session.generation && !session.explicitlyStopped
                session.pendingOutputBytes -= chunk.count
                session.pendingOutputChunks -= 1
                self.operations.unlock()
                if active { session.outputHandler(session.generation, chunk) }
            }
            return true
        }
        finishAfterEOF(session, reason: count == 0 ? nil : .readFailed)
        return false
    }

    private func finishAfterEOF(_ session: Session, reason: CodexProcessExit?) {
        operations.lock()
        guard current === session, !session.stopping else { operations.unlock(); return }
        session.stopping = true
        try? session.input.fileHandleForWriting.close()
        operations.unlock()
        let reaped = Self.terminate(session.process, grace: stopGrace)
        operations.lock()
        let owns = reaped && current === session
        if owns { current = nil }
        operations.unlock()
        if owns {
            try? session.output.fileHandleForReading.close()
            let outcome = reason ?? .exited(status: session.process.terminationStatus)
            callbackQueue.async { session.exitHandler(session.generation, outcome) }
        }
    }

    private static func makeNonblocking(_ fd: Int32) -> Bool {
        let flags = fcntl(fd, F_GETFL)
        return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0
    }

    private static func terminate(_ process: Process, grace: TimeInterval) -> Bool {
        let now = { ProcessInfo.processInfo.systemUptime }
        let eofDeadline = now() + grace
        while process.isRunning && now() < eofDeadline { Thread.sleep(forTimeInterval: 0.005) }
        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGTERM)
            let termDeadline = now() + grace
            while process.isRunning && now() < termDeadline { Thread.sleep(forTimeInterval: 0.005) }
        }
        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            let killDeadline = now() + grace
            while process.isRunning && now() < killDeadline { Thread.sleep(forTimeInterval: 0.005) }
        }
        guard !process.isRunning else { return false }
        process.waitUntilExit()
        return true
    }

    private static func close(input: Pipe, output: Pipe) {
        try? input.fileHandleForReading.close()
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
    }
}
