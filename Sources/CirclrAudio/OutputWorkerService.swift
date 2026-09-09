import Foundation
import AVFAudio
import Darwin

/// Entrypoint for the bundled, single-session output child. Never call inside the app.
public enum OutputWorkerService {
    public static func run(arguments: [String]) -> Never {
        guard arguments.count == 4, arguments[0] == "--session", let session = UUID(uuidString: arguments[1]),
              arguments[2] == "--directory" else { exit(64) }
        // A disconnected parent must not leave the child alive or trigger SIGPIPE termination mid-write.
        signal(SIGPIPE, SIG_IGN)
        do {
            let service = try Worker(session: session, directory: URL(fileURLWithPath: arguments[3], isDirectory: true))
            service.start()
            RunLoop.main.run()
            exit(0)
        } catch { exit(65) }
    }
}

private final class Worker: @unchecked Sendable {
    private let session: UUID
    private let directory: URL
    private let outputLock = NSLock()
    private let control = MediaPreviewCancellation()
    private var sequence: UInt64 = 0
    private var file: AVAudioFile?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var active: UUID?
    private var used = false
    private var timer: Timer?
    private var lastSeconds = 0.0

    init(session: UUID, directory: URL) throws {
        self.session = session
        self.directory = directory.standardizedFileURL
        try Self.validateOwned(self.directory, directory: true)
    }

    private static func validateOwned(_ url: URL, directory: Bool) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_uid == geteuid(), info.st_mode & 0o077 == 0,
              (info.st_mode & S_IFMT) == (directory ? S_IFDIR : S_IFREG),
              directory || info.st_nlink == 1 else { throw WorkerError.invalidFile }
    }

    func start() {
        emit(.hello)
        let slots = DispatchSemaphore(value: 8)
        DispatchQueue(label: "circlr.output-worker-input").async {
            var wire = OutputWorkerWire(session: self.session, receiving: .commands)
            do {
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count) }
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw WorkerError.invalidState
                    }
                    if count == 0 { break }
                    let packets = try wire.receive(Data(buffer.prefix(count)))
                    if packets.contains(where: { if case .stop = $0.payload { return true }; return false }) { self.control.cancel() }
                    guard slots.wait(timeout: .now() + 2) == .success else { throw WorkerError.backpressure }
                    DispatchQueue.main.async {
                        defer { slots.signal() }
                        for packet in packets { self.handle(packet.payload) }
                    }
                }
                try wire.finish()
                // EOF is also the parent-death cancellation path, even if HAL blocks main.
                exit(0)
            } catch {
                self.emit(.failure(run: nil, message: "출력 연결 데이터가 올바르지 않습니다"))
                exit(66)
            }
        }
    }

    private func emit(_ payload: OutputWorkerPacket.Payload) {
        outputLock.lock()
        defer { outputLock.unlock() }
        guard sequence < UInt64.max else { exit(66) }
        sequence += 1
        do {
            let packet = OutputWorkerPacket(session: session, sequence: sequence, payload: payload)
            try FileHandle.standardOutput.write(contentsOf: OutputWorkerWire.encode(packet))
        } catch { exit(66) }
    }

    private func handle(_ payload: OutputWorkerPacket.Payload) {
        do {
            switch payload {
            case .prepare(let frames):
                guard file == nil, !used else { throw WorkerError.invalidState }
                let url = directory.appendingPathComponent("audio.caf")
                try Self.validateOwned(url, directory: false)
                let input = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
                guard input.length == frames, input.processingFormat.sampleRate == 48_000,
                      input.processingFormat.channelCount == 2,
                      input.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM,
                      let scratch = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 4096) else { throw WorkerError.invalidFile }
                // Validate with bounded memory; playback streams the already-open file.
                while input.framePosition < input.length {
                    try input.read(into: scratch, frameCount: AVAudioFrameCount(min(4096, input.length - input.framePosition)))
                    guard scratch.frameLength > 0, let channels = scratch.floatChannelData else { throw WorkerError.invalidFile }
                    for channel in 0..<2 {
                        for frame in 0..<Int(scratch.frameLength) {
                            guard channels[channel][frame].isFinite else { throw WorkerError.invalidFile }
                        }
                    }
                }
                input.framePosition = 0
                file = input
                emit(.prepared)
            case .play(let run):
                guard let file, active == nil, !used else { throw WorkerError.invalidState }
                used = true
                active = run
                try checkCancellation()
                let engine = AVAudioEngine(), player = AVAudioPlayerNode()
                self.engine = engine; self.player = player
                engine.attach(player)
                let mixer = engine.mainMixerNode
                try checkCancellation()
                engine.connect(player, to: mixer, format: file.processingFormat)
                try checkCancellation()
                player.volume = 0
                player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self, self.active == run else { return }
                        self.clear()
                        self.emit(.finished(run: run))
                    }
                }
                try engine.start()
                try checkCancellation()
                player.play()
                try checkCancellation()
                player.volume = 1
                try checkCancellation()
                emit(.started(run: run))
                timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in self?.tick(run) }
            case .stop(let run):
                guard active == nil || active == run else { throw WorkerError.invalidState }
                clear()
                used = true
                emit(.stopped(run: run))
            default: throw WorkerError.invalidState
            }
        } catch is CancellationError {
            clear()
        } catch {
            let run = active
            // Report before device cleanup, which itself may block.
            emit(.failure(run: run, message: "출력 준비 또는 재생에 실패했습니다"))
            clear()
            exit(70)
        }
    }

    private func checkCancellation() throws {
        if control.isCancelled { throw CancellationError() }
    }

    private func tick(_ run: UUID) {
        guard active == run, let player, let file,
              let time = player.lastRenderTime, let played = player.playerTime(forNodeTime: time),
              played.sampleRate.isFinite, played.sampleRate > 0 else { return }
        let seconds = Double(played.sampleTime) / played.sampleRate
        guard seconds.isFinite, seconds >= 0 else { return }
        lastSeconds = max(lastSeconds, min(Double(file.length) / 48_000, seconds))
        emit(.clock(run: run, seconds: lastSeconds))
    }

    private func clear() {
        active = nil
        timer?.invalidate(); timer = nil
        player?.stop(); engine?.stop()
        player = nil; engine = nil
        file = nil
    }
}

private enum WorkerError: Error { case invalidFile, invalidState, backpressure }
