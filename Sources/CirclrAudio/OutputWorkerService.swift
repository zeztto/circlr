import Foundation
import AVFAudio
import CoreAudio
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
    private let traceOrigin = ProcessInfo.processInfo.systemUptime
    private var outputSelection: OutputDeviceSelection = .systemDefault
    private var deviceBinding: OutputDeviceBinding?
    private var observationID: UUID?
    private var configurationObserver: NSObjectProtocol?
    private var deviceListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var didStart = false
    private var looping = false
    private var loopBuffer: AVAudioPCMBuffer?
    private var loopAudio:OutputWorkerLoopScheduler.Audio?
    private var loopScheduler:OutputWorkerLoopScheduler?
    private var loopStartFrame=0
    private var loopCycleFrames:Int?

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
        emit(.helloBoundaryLoopCapabilities(outputDeviceSelection: true))
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
                try prepare(frames: frames, selection: .systemDefault)
            case .prepareOutput(let frames, let selection):
                try prepare(frames: frames, selection: selection)
            case .prepareLoop(let frames, let selection):
                looping = true
                try prepare(frames: frames, selection: selection)
            case .prepareLoopRange(let frames,let cycleFrames,let startFrame,let selection):
                looping=true;loopCycleFrames=cycleFrames;loopStartFrame=startFrame
                try prepare(frames:frames,selection:selection)
            case .queueLoopChange(let change,let frames,let cycleFrames):
                do {
                    guard active != nil,let scheduler=loopScheduler else{throw WorkerError.invalidState}
                    let path=directory.appendingPathComponent("loop-"+change.uuidString+".caf")
                    let audio=try readLoopAudio(path,frames:frames,cycleFrames:cycleFrames)
                    try scheduler.request(id:change,audio:audio)
                    try? FileManager.default.removeItem(at:path)
                } catch {emit(.loopChangeRejected(change:change,message:"루프 변경을 준비할 수 없습니다: "+failureMessage(error)))}
            case .exitLoop(let change):
                do {
                    guard active != nil,let scheduler=loopScheduler else{throw WorkerError.invalidState}
                    try scheduler.request(id:change,audio:nil)
                } catch {emit(.loopChangeRejected(change:change,message:"루프 종료를 예약할 수 없습니다"))}
            case .play(let run):
                guard let file, active == nil, !used else { throw WorkerError.invalidState }
                used = true
                active = run
                try checkCancellation()
                trace(.engineCreation, .entered)
                let engine = AVAudioEngine(), player = AVAudioPlayerNode()
                self.engine = engine; self.player = player
                engine.attach(player)
                trace(.engineCreation, .completed)
                trace(.outputNodeAcquisition, .entered)
                guard let outputUnit = engine.outputNode.audioUnit else { throw WorkerError.missingOutputUnit }
                trace(.outputNodeAcquisition, .completed)
                try checkCancellation()
                trace(.deviceSelection, .entered)
                let binding = try OutputDeviceBinding(selection: outputSelection, audioUnit: outputUnit)
                self.deviceBinding = binding
                _ = try binding.bind()
                try installDeviceObservers(engine: engine, binding: binding, run: run)
                _ = try binding.revalidate()
                trace(.deviceSelection, .completed)
                trace(.mixerAcquisition, .entered)
                let mixer = engine.mainMixerNode
                trace(.mixerAcquisition, .completed)
                try checkCancellation()
                trace(.routing, .entered)
                engine.connect(player, to: mixer, format: file.processingFormat)
                trace(.routing, .completed)
                try checkCancellation()
                trace(.scheduling, .entered)
                player.volume = 0
                if looping {
                    guard let loopAudio else { throw WorkerError.invalidState }
                    let scheduler=try OutputWorkerLoopScheduler(player:player,audio:loopAudio,fromFrame:loopStartFrame,onBoundary:{[weak self] boundary in
                        guard let self else{return}
                        DispatchQueue.main.async {
                            guard self.active==run else{return}
                            self.emit(.loopChangeScheduled(change:boundary.change.id,elapsedFrame:boundary.elapsedFrame,frames:boundary.sourceFrames,exiting:boundary.change.replacement==nil))
                        }
                    },onFinished:{[weak self] endFrame in
                        DispatchQueue.main.async {
                            guard let self,self.active==run else{return}
                            self.clear();self.emit(.loopFinished(run:run,elapsedFrame:endFrame))
                        }
                    },onFailure:{[weak self] message in
                        DispatchQueue.main.async {
                            guard let self,self.active==run else{return}
                            self.emit(.failure(run:run,message:message));self.clear()
                        }
                    })
                    loopScheduler=scheduler;try scheduler.start();self.loopAudio=nil
                } else { player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self, self.active == run else { return }
                        self.clear()
                        self.emit(.finished(run: run))
                    }
                }
                }
                trace(.scheduling, .completed)
                trace(.engineStart, .entered)
                try engine.start()
                trace(.engineStart, .completed)
                try checkCancellation()
                trace(.playerPlay, .entered)
                player.play()
                try checkCancellation()
                let actualDevice = try binding.revalidate()
                player.volume = 1
                try checkCancellation()
                trace(.playerPlay, .completed)
                emit(.outputDevice(descriptor: actualDevice))
                didStart = true
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
            emit(.failure(run: run, message: failureMessage(error)))
            clear()
            exit(70)
        }
    }

    private func prepare(frames: Int, selection: OutputDeviceSelection) throws {
        guard file == nil, !used else { throw WorkerError.invalidState }
        trace(.fileValidation, .entered)
        let url = directory.appendingPathComponent("audio.caf")
        try Self.validateOwned(url, directory: false)
        let input = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard input.length == frames, input.processingFormat.sampleRate == 48_000,
              input.processingFormat.channelCount == 2,
              input.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM,
              let scratch = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 4096) else { throw WorkerError.invalidFile }
        // Validate with bounded memory; playback streams the already-open file.
        while input.framePosition < input.length {
            try checkCancellation()
            try input.read(into: scratch, frameCount: AVAudioFrameCount(min(4096, input.length - input.framePosition)))
            guard scratch.frameLength > 0, let channels = scratch.floatChannelData else { throw WorkerError.invalidFile }
            for channel in 0..<2 {
                for frame in 0..<Int(scratch.frameLength) {
                    guard channels[channel][frame].isFinite else { throw WorkerError.invalidFile }
                }
            }
        }
        input.framePosition = 0
        if looping {loopAudio=try readLoopAudio(url,frames:frames,cycleFrames:loopCycleFrames ?? frames)}
        file = input
        outputSelection = selection
        trace(.fileValidation, .completed)
        emit(.prepared)
    }

    private func readLoopAudio(_ url:URL,frames:Int,cycleFrames:Int)throws->OutputWorkerLoopScheduler.Audio {
        try Self.validateOwned(url,directory:false)
        guard frames>0,cycleFrames>0,cycleFrames<=frames,
              Double(frames)*8<=ArrangementRenderer.preparationByteLimit/2 else{throw WorkerError.invalidFile}
        let input=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        guard input.length==frames,input.processingFormat.sampleRate==PCM.rate,input.processingFormat.channelCount==2,
              input.fileFormat.streamDescription.pointee.mFormatID==kAudioFormatLinearPCM else{throw WorkerError.invalidFile}
        func read(_ count:Int)throws->AVAudioPCMBuffer {
            guard let buffer=AVAudioPCMBuffer(pcmFormat:input.processingFormat,frameCapacity:AVAudioFrameCount(count)) else{throw WorkerError.invalidFile}
            try checkCancellation();try input.read(into:buffer,frameCount:AVAudioFrameCount(count))
            guard Int(buffer.frameLength)==count,let channels=buffer.floatChannelData else{throw WorkerError.invalidFile}
            for i in 0..<count {
                if i%4096==0 {try checkCancellation()}
                guard channels[0][i].isFinite,channels[1][i].isFinite,abs(channels[0][i])<=1,abs(channels[1][i])<=1 else{throw WorkerError.invalidFile}
            }
            return buffer
        }
        let cycle=try read(cycleFrames),tail=try frames>cycleFrames ? read(frames-cycleFrames):nil
        return .init(cycle:cycle,tail:tail)
    }

    // All observation state and device revalidation belong to the worker's main queue.
    // Never query HAL from a CoreAudio notification thread or reuse a previous run's callback.
    private func installDeviceObservers(engine: AVAudioEngine, binding: OutputDeviceBinding, run: UUID) throws {
        guard let deviceID = binding.deviceID else { throw WorkerError.invalidState }
        let token = UUID()
        observationID = token
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.deviceChanged(run: run, observation: token) }
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        let properties: [(AudioObjectID, AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
            (system, kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal),
            (system, kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal),
            (deviceID, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal),
            (deviceID, kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
        ]
        for (object, selector, scope) in properties {
            var property = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.deviceChanged(run: run, observation: token)
            }
            let status = AudioObjectAddPropertyListenerBlock(object, &property, DispatchQueue.main, listener)
            guard status == noErr else { throw WorkerError.monitorFailed(status) }
            deviceListeners.append((object, property, listener))
        }
    }

    private func deviceChanged(run: UUID, observation: UUID) {
        guard active == run, observationID == observation, let binding = deviceBinding else { return }
        do {
            try checkCancellation()
            _ = try binding.revalidate()
            if didStart, engine?.isRunning != true { throw WorkerError.configurationChanged }
        } catch is CancellationError {
            clear()
        } catch {
            // Publish failure before HAL cleanup, which may block; never retry on a default device.
            emit(.failure(run: run, message: failureMessage(error)))
            clear()
            exit(70)
        }
    }

    private func removeDeviceObservers() {
        observationID = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        for (object, address, listener) in deviceListeners {
            var property = address
            _ = AudioObjectRemovePropertyListenerBlock(object, &property, DispatchQueue.main, listener)
        }
        deviceListeners.removeAll()
        deviceBinding = nil
    }

    private func failureMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "출력 준비 또는 재생에 실패했습니다"
    }

    private func checkCancellation() throws {
        if control.isCancelled { throw CancellationError() }
    }
    private func trace(_ stage: PlaybackOutputTraceEvent.Stage, _ phase: PlaybackOutputTraceEvent.Phase) {
        emit(.trace(stage: stage, phase: phase, elapsedSeconds: max(0, ProcessInfo.processInfo.systemUptime - traceOrigin)))
    }

    private func tick(_ run: UUID) {
        guard active == run, let player, let file,
              let time = player.lastRenderTime, let played = player.playerTime(forNodeTime: time),
              played.sampleRate.isFinite, played.sampleRate > 0 else { return }
        let seconds = Double(played.sampleTime) / played.sampleRate
        guard seconds.isFinite, seconds >= 0 else { return }
        lastSeconds = max(lastSeconds, looping ? seconds : min(Double(file.length) / 48_000, seconds))
        if looping { emit(.loopClock(run: run, seconds: lastSeconds)) }
        else { emit(.clock(run: run, seconds: lastSeconds)) }
    }

    private func clear() {
        active = nil
        didStart = false
        loopScheduler?.cancel();loopScheduler=nil;loopAudio=nil;loopBuffer=nil
        timer?.invalidate(); timer = nil
        removeDeviceObservers()
        player?.stop(); engine?.stop()
        player = nil; engine = nil
        file = nil
    }
}

private enum WorkerError: LocalizedError {
    case invalidFile, invalidState, backpressure, missingOutputUnit, configurationChanged, monitorFailed(OSStatus)
    var errorDescription: String? {
        switch self {
        case .missingOutputUnit: return "출력 장치의 오디오 연결을 만들 수 없습니다"
        case .configurationChanged: return "출력 장치 구성이 바뀌어 재생이 중단되었습니다. 다시 재생하세요."
        case .monitorFailed(let status): return "출력 장치 변경 감시를 시작하지 못했습니다 (OSStatus \(status))"
        default: return "출력 준비 또는 재생에 실패했습니다"
        }
    }
}
