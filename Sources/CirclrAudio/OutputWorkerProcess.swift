import Foundation
import AVFAudio
import Darwin
import CirclrCore

/// Owns one child until its termination is observed. No device APIs run in the host.
final class OutputWorkerProcess: @unchecked Sendable {
    private enum Stage { case boot, preparing, starting, playing, closing }
    private let queue = DispatchQueue(label: "circlr.output-host")
    private let lock = NSLock()
    private let executable: URL?
    private var value = PlaybackOutputStatus()
    private var token: MediaPreviewCancellation?
    private var startedAt: TimeInterval?
    // Queue-owned process resources.
    private var child: Process?
    private var input: FileHandle?
    private var directory: URL?
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var stage = Stage.boot
    private var frames = 0

    init(executable: URL? = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("circlr-output-worker")) {
        self.executable = executable
    }
    var status: PlaybackOutputStatus {
        lock.lock(); defer { lock.unlock() }
        var result = value
        if let startedAt { result.elapsedSeconds = Int(max(0, ProcessInfo.processInfo.systemUptime - startedAt)) }
        return result
    }
    private func update(_ body: (inout PlaybackOutputStatus) -> Void) {
        lock.lock(); body(&value); lock.unlock()
    }

    func play(_ pcm: PCM, from: Double, timeout: Double) async throws {
        guard from.isFinite, from >= 0, timeout.isFinite, timeout > 0,
              pcm.left.count == pcm.right.count, pcm.count <= OutputWorkerWire.maximumFrames else { throw PlaybackTransportError.invalidPosition }
        let first = Int(min(Double(pcm.count), (from * PCM.rate).rounded()))
        guard first < pcm.count else { return }
        try Task.checkCancellation()
        let id = UUID(), control = MediaPreviewCancellation()
        try begin(id, control: control)
        queue.async { self.launch(id, control: control, pcm: pcm, first: first) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        do {
            while true {
                try Task.checkCancellation()
                let s = status
                guard s.transport.id == id else { throw CancellationError() }
                if s.transport.didStart { return }
                if let message = s.transport.message { throw PlaybackTransportError.workerFailed(message) }
                if control.isCancelled { throw CancellationError() }
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    cancel(expectedID: id, timedOut: true)
                    throw PlaybackTransportError.timedOut
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch {
            cancel(expectedID: id)
            throw error
        }
    }
    private func begin(_ id: UUID, control: MediaPreviewCancellation) throws {
        lock.lock(); defer { lock.unlock() }
        guard token == nil else { throw PlaybackTransportError.busy }
        token = control
        let attempts = value.attempts + 1
        value = PlaybackOutputStatus(); value.attempts = attempts
        value.attemptID = id; value.phase = .connecting; value.step = .player; value.request = .waiting
        value.transport.id = id; value.transport.phase = .starting
        startedAt = ProcessInfo.processInfo.systemUptime
    }
    func cancel(expectedID: UUID? = nil, timedOut: Bool = false) {
        lock.lock()
        // A completed request can resume after cleanup and a new begin. Its cancellation
        // must not revoke the new session; external STOP still targets the current one.
        guard let token, let id = value.transport.id,
              expectedID == nil || expectedID == id else { lock.unlock(); return }
        token.cancel(); value.transport.phase = .stopping; value.transport.seconds = 0
        if timedOut { value.request = .timedOut }
        else if value.request != .timedOut { value.request = .cancelled }
        lock.unlock()
        queue.async { self.close(id, graceful: true) }
    }

    private func launch(_ id: UUID, control: MediaPreviewCancellation, pcm: PCM, first: Int) {
        session = id; sequence = 0; stage = .boot; frames = pcm.count - first
        do {
            guard !control.isCancelled else { throw CancellationError() }
            guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw PlaybackTransportError.workerFailed("출력 helper를 찾을 수 없습니다. 앱 설치를 확인하세요.")
            }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-output-" + id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            directory = root
            try write(pcm, first: first, to: root.appendingPathComponent("audio.caf"), control: control)
            guard !control.isCancelled else { throw CancellationError() }
            let process = Process(), incoming = Pipe(), outgoing = Pipe(), diagnostic = Pipe()
            process.executableURL = executable
            process.arguments = ["--session", id.uuidString, "--directory", root.path]
            process.standardInput = incoming; process.standardOutput = outgoing; process.standardError = diagnostic
            child = process; input = incoming.fileHandleForWriting
            guard fcntl(incoming.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
                throw PlaybackTransportError.workerFailed("출력 파이프를 만들 수 없습니다")
            }
            process.terminationHandler = { [weak self] process in
                self?.queue.async { self?.exited(id, process: process) }
            }
            do { try process.run() }
            catch {
                try? incoming.fileHandleForReading.close(); try? outgoing.fileHandleForWriting.close(); try? diagnostic.fileHandleForWriting.close()
                try? outgoing.fileHandleForReading.close(); try? diagnostic.fileHandleForReading.close()
                throw error
            }
            // Parent must close its copies so child EOF is observable.
            try? incoming.fileHandleForReading.close(); try? outgoing.fileHandleForWriting.close(); try? diagnostic.fileHandleForWriting.close()
            read(outgoing.fileHandleForReading, session: id, decode: true)
            read(diagnostic.fileHandleForReading, session: id, decode: false)
        } catch {
            if !(error is CancellationError) { update { $0.transport.message = error.localizedDescription } }
            finalize(id)
        }
    }

    private func write(_ pcm: PCM, first: Int, to url: URL, control: MediaPreviewCancellation) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let format = AVAudioFormat(standardFormatWithSampleRate: PCM.rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096), let channels = buffer.floatChannelData else {
            throw PlaybackTransportError.workerFailed("출력 임시 파일을 만들 수 없습니다")
        }
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var offset = first
        while offset < pcm.count {
            if control.isCancelled { throw CancellationError() }
            let count = min(4096, pcm.count - offset)
            for i in 0..<count {
                let l = pcm.left[offset+i], r = pcm.right[offset+i]
                guard l.isFinite, r.isFinite else { throw PlaybackTransportError.workerFailed("출력 오디오 값이 올바르지 않습니다") }
                channels[0][i] = l; channels[1][i] = r
            }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer); offset += count
        }
    }

    private func read(_ handle: FileHandle, session id: UUID, decode: Bool) {
        let slots = DispatchSemaphore(value: 8)
        DispatchQueue(label: decode ? "circlr.output-events" : "circlr.output-stderr").async {
            defer { try? handle.close() }
            var buffer = [UInt8](repeating: 0, count: 4096), wire = OutputWorkerWire(session: id)
            do {
                while true {
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
                    if count < 0 { if errno == EINTR { continue }; throw OutputWorkerWireError.closed }
                    if count == 0 { break }
                    // Drain diagnostics without retaining arbitrary child output.
                    guard decode else { continue }
                    let packets = try wire.receive(Data(buffer.prefix(count)))
                    guard slots.wait(timeout: .now() + 2) == .success else { throw OutputWorkerWireError.oversizedChunk }
                    self.queue.async {
                        defer { slots.signal() }
                        for packet in packets { self.receive(packet.payload, session: id) }
                    }
                }
                if decode {
                    try wire.finish()
                    self.queue.async {
                        guard self.session == id, self.stage != .closing else { return }
                        self.fail(id, message: "출력 연결이 종료됐습니다. 다시 재생하세요.")
                    }
                }
            } catch {
                if decode { self.queue.async { self.fail(id, message: "출력 응답이 올바르지 않습니다. 다시 재생하세요.") } }
            }
        }
    }
    private func send(_ payload: OutputWorkerPacket.Payload) throws {
        guard let id = session, let input, sequence < UInt64.max else { throw OutputWorkerWireError.closed }
        sequence += 1
        try input.write(contentsOf: OutputWorkerWire.encode(.init(session: id, sequence: sequence, payload: payload)))
    }
    private func receive(_ payload: OutputWorkerPacket.Payload, session id: UUID) {
        guard session == id, stage != .closing else { return }
        lock.lock(); let cancelled = token?.isCancelled ?? true; lock.unlock()
        guard !cancelled else { return }
        do {
            switch payload {
            case .hello where stage == .boot:
                stage = .preparing; update { $0.step = .routing }
                try send(.prepare(frames: frames))
            case .prepared where stage == .preparing:
                stage = .starting; update { $0.step = .device }
                try send(.play(run: id))
            case .started(let run) where run == id && stage == .starting:
                stage = .playing
                update {
                    guard $0.transport.phase == .starting else { return }
                    $0.phase = .ready; $0.step = .ready; $0.request = .none; $0.transport.phase = .playing; $0.transport.didStart = true
                }
            case .clock(let run, let seconds) where run == id && stage == .playing:
                guard seconds <= Double(frames) / PCM.rate else { throw OutputWorkerWireError.invalidPacket }
                update { if $0.transport.phase == .playing { $0.transport.seconds = max($0.transport.seconds, seconds) } }
            case .finished(let run) where run == id && stage == .playing:
                update { $0.transport.phase = .stopping; $0.transport.seconds = 0 }
                close(id, graceful: false)
            case .failure(let run, let message) where run == nil || run == id: fail(id, message: message)
            default: throw OutputWorkerWireError.invalidPacket
            }
        } catch { fail(id, message: "출력 응답 처리에 실패했습니다. 다시 재생하세요.") }
    }
    private func fail(_ id: UUID, message: String) {
        guard session == id, stage != .closing else { return }
        update { $0.transport.message = message; $0.transport.phase = .stopping; $0.transport.seconds = 0 }
        close(id, graceful: false)
    }
    private func close(_ id: UUID, graceful: Bool) {
        guard session == id, stage != .closing else { return }
        stage = .closing
        guard let process = child else { finalize(id); return }
        if graceful { try? send(.stop(run: id)) }
        queue.asyncAfter(deadline: .now() + (graceful ? 0.2 : 0)) {
            guard self.session == id, self.child === process else { return }
            try? self.input?.close(); self.input = nil
            self.queue.asyncAfter(deadline: .now() + 0.2) {
                guard self.session == id, self.child === process, process.isRunning else { return }
                process.terminate()
                self.queue.asyncAfter(deadline: .now() + 0.2) {
                    guard self.session == id, self.child === process, process.isRunning else { return }
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }
    private func exited(_ id: UUID, process: Process) {
        guard session == id, child === process else { return }
        if stage != .closing { update { $0.transport.message = "출력 프로세스가 종료됐습니다. 다시 재생하세요." } }
        finalize(id)
    }
    private func finalize(_ id: UUID) {
        guard session == id else { return }
        try? input?.close(); input = nil; child = nil
        if let directory {
            do { try FileManager.default.removeItem(at: directory) }
            catch { update { $0.transport.message = "출력 임시 파일 정리에 실패했습니다: " + directory.path } }
        }
        directory = nil; session = nil
        lock.lock(); defer { lock.unlock() }
        token = nil; startedAt = nil
        value.phase = .idle; value.step = nil
        value.transport.phase = value.transport.message == nil ? .idle : .failed
        value.transport.seconds = 0
    }
}
