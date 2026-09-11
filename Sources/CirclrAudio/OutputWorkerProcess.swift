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
    private var looping = false
    private var boundaryChangesSupported=false
    private var loopCycleFrames=0
    private var loopStartFrame=0
    private var loopExitScheduled=false
    private var pendingChangeID:UUID?
    private var pendingCycleFrames:Int?
    private var loopEpochFrame:Int64=0
    private var changeFailure:(UUID,String)?
    private var helperTraceEvents = 0
    private var outputSelection: OutputDeviceSelection = .systemDefault
    private var deviceSelectionSupported = false
    private var actualDevice: OutputDeviceDescriptor?
    private var terminationObserved = false
    private var eventsDrained = false
    private var readerControl: MediaPreviewCancellation?
    // Internal scheduling hooks allow deterministic pipe/termination race tests.
    private let beforeEventDelivery: (@Sendable ([OutputWorkerPacket]) -> Void)?
    private let onTerminationObserved: (@Sendable () -> Void)?
    private let beforeLoopChangeReturn:(@Sendable () async -> Void)?

    init(executable: URL? = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("circlr-output-worker"),
         beforeEventDelivery: (@Sendable ([OutputWorkerPacket]) -> Void)? = nil,
         onTerminationObserved: (@Sendable () -> Void)? = nil,
         beforeLoopChangeReturn:(@Sendable () async -> Void)? = nil) {
        self.executable = executable
        self.beforeEventDelivery = beforeEventDelivery
        self.onTerminationObserved = onTerminationObserved
        self.beforeLoopChangeReturn=beforeLoopChangeReturn
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
    private func trace(_ id: UUID, _ stage: PlaybackOutputTraceEvent.Stage, _ phase: PlaybackOutputTraceEvent.Phase,
                       workerElapsed: Double? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard value.transport.id == id, value.transport.phase == .starting,
              let startedAt, value.trace?.sessionID == id,
              let count = value.trace?.events.count, count < PlaybackOutputTrace.maximumEvents else { return }
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        value.trace?.events.append(.init(stage: stage, phase: phase, elapsedSeconds: elapsed, workerElapsedSeconds: workerElapsed))
        if workerElapsed != nil { value.trace?.helperReportsStages = true }
    }

    func play(_ pcm: PCM, from: Double, timeout: Double, selection: OutputDeviceSelection = .systemDefault, loop: Bool = false, exitTail:PCM? = nil) async throws {
        guard from.isFinite, from >= 0, timeout.isFinite, timeout > 0,
              pcm.left.count == pcm.right.count, pcm.count <= OutputWorkerWire.maximumFrames else { throw PlaybackTransportError.invalidPosition }
        try OutputWorkerPacket.validateSelection(selection)
        let first = Int(min(Double(pcm.count), (from * PCM.rate).rounded()))
        guard first < pcm.count else { return }
        guard exitTail == nil || (loop && exitTail!.left.count == exitTail!.right.count && pcm.count <= OutputWorkerWire.maximumFrames-exitTail!.count) else {throw PlaybackTransportError.invalidPosition}
        try Task.checkCancellation()
        let id = UUID(), control = MediaPreviewCancellation()
        try begin(id, control: control, selection: selection)
        queue.async { self.launch(id, control: control, pcm: pcm, first: first, selection: selection, loop: loop, exitTail:exitTail) }
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
    /// The source is staged while the existing output continues. ACK identifies the
    /// exact future sample frame chosen by the bounded scheduler, not a UI timer.
    func changeLoop(cycle:PCM?,tail:PCM?=nil)async throws->PlaybackLoopChangeStatus {
        guard let requestSession=status.transport.id else{throw CancellationError()}
        return try await withTaskCancellationHandler {try await performLoopChange(cycle:cycle,tail:tail,requestSession:requestSession)} onCancel:{self.cancel(expectedID:requestSession)}
    }
    private func performLoopChange(cycle:PCM?,tail:PCM?,requestSession:UUID)async throws->PlaybackLoopChangeStatus {
        try Task.checkCancellation()
        let change=UUID()
        try await withCheckedThrowingContinuation { (reply:CheckedContinuation<Void,Error>) in
            queue.async {
                let state=self.status.transport
                guard self.session==requestSession,self.looping,self.boundaryChangesSupported,!self.loopExitScheduled,self.pendingChangeID==nil,state.phase == .playing,
                      state.loopChange.map({$0.elapsedSeconds<=state.seconds}) ?? true,
                      let session=self.session,let directory=self.directory else {reply.resume(throwing:PlaybackTransportError.busy);return}
                self.lock.lock();let control=self.token;self.lock.unlock()
                guard let control,!control.isCancelled else{reply.resume(throwing:CancellationError());return}
                self.pendingChangeID=change;self.pendingCycleFrames=cycle?.count
                if let cycle {
                    guard cycle.count>0,cycle.left.count==cycle.right.count,
                          tail == nil || tail!.left.count==tail!.right.count,
                          cycle.count<=OutputWorkerWire.maximumFrames-(tail?.count ?? 0) else {
                        self.pendingChangeID=nil;reply.resume(throwing:PlaybackTransportError.invalidPosition);return
                    }
                    let path=directory.appendingPathComponent("loop-"+change.uuidString+".caf")
                    DispatchQueue(label:"circlr.loop-staging",qos:.userInitiated).async {
                        do {
                            try self.write(cycle,first:0,to:path,control:control,tail:tail)
                            self.queue.async {
                                guard self.session==session,!control.isCancelled,self.pendingChangeID==change else {reply.resume(throwing:CancellationError());return}
                                do {try self.send(.queueLoopChange(change:change,frames:cycle.count+(tail?.count ?? 0),cycleFrames:cycle.count));reply.resume()}
                                catch {self.pendingChangeID=nil;reply.resume(throwing:error)}
                            }
                        } catch {self.queue.async {if self.pendingChangeID==change {self.pendingChangeID=nil};reply.resume(throwing:error)}}
                    }
                } else {
                    do {try self.send(.exitLoop(change:change));reply.resume()}
                    catch {self.pendingChangeID=nil;reply.resume(throwing:error)}
                }
            }
        }
        let deadline=ProcessInfo.processInfo.systemUptime+10
        while true {
            try Task.checkCancellation()
            let state=status.transport
            guard state.id==requestSession else{throw CancellationError()}
            if let applied=state.loopChange,applied.id==change {
                await beforeLoopChangeReturn?()
                try Task.checkCancellation()
                guard status.transport.id==requestSession else{throw CancellationError()}
                return applied
            }
            let failure=lock.withLock {changeFailure}
            if let failure,failure.0==change {throw PlaybackTransportError.workerFailed(failure.1)}
            guard state.phase == .playing else{throw CancellationError()}
            guard ProcessInfo.processInfo.systemUptime<deadline else{cancel(expectedID:requestSession);throw PlaybackTransportError.timedOut}
            try await Task.sleep(for:.milliseconds(10))
        }
    }
    private func begin(_ id: UUID, control: MediaPreviewCancellation, selection: OutputDeviceSelection) throws {
        lock.lock(); defer { lock.unlock() }
        guard token == nil else { throw PlaybackTransportError.busy }
        token = control
        let attempts = value.attempts + 1
        value = PlaybackOutputStatus(); value.attempts = attempts
        value.attemptID = id; value.phase = .connecting; value.step = .player; value.request = .waiting
        value.transport.id = id; value.transport.phase = .starting
        value.trace = PlaybackOutputTrace(sessionID: id)
        if case .systemDefault = selection { value.outputSelectionKind = "systemDefault" }
        else { value.outputSelectionKind = "deviceUID" }
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

    private func launch(_ id: UUID, control: MediaPreviewCancellation, pcm: PCM, first: Int, selection: OutputDeviceSelection, loop: Bool, exitTail:PCM?) {
        looping = loop;loopCycleFrames=pcm.count;loopStartFrame=first;loopExitScheduled=false;loopEpochFrame=0
        boundaryChangesSupported=false;pendingChangeID=nil
        lock.lock();changeFailure=nil;lock.unlock()
        session = id; sequence = 0; stage = .boot; frames = loop ? pcm.count+(exitTail?.count ?? 0) : pcm.count-first; helperTraceEvents = 0
        terminationObserved = false; eventsDrained = false
        readerControl = MediaPreviewCancellation()
        outputSelection = selection; deviceSelectionSupported = false; actualDevice = nil
        do {
            guard !control.isCancelled else { throw CancellationError() }
            guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw PlaybackTransportError.workerFailed("출력 helper를 찾을 수 없습니다. 앱 설치를 확인하세요.")
            }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-output-" + id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            directory = root
            trace(id, .cafWrite, .entered)
            try write(pcm, first: loop ? 0:first, to: root.appendingPathComponent("audio.caf"), control: control,tail:exitTail)
            trace(id, .cafWrite, .completed)
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
            trace(id, .helperHello, .entered)
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

    private func write(_ pcm: PCM, first: Int, to url: URL, control: MediaPreviewCancellation,tail:PCM?=nil) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let format = AVAudioFormat(standardFormatWithSampleRate: PCM.rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096), let channels = buffer.floatChannelData else {
            throw PlaybackTransportError.workerFailed("출력 임시 파일을 만들 수 없습니다")
        }
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        for (index,part) in [pcm,tail].compactMap({$0}).enumerated() {
        var offset = index == 0 ? first:0
        while offset < part.count {
            if control.isCancelled { throw CancellationError() }
            let count = min(4096, part.count - offset)
            for i in 0..<count {
                let l = part.left[offset+i], r = part.right[offset+i]
                guard l.isFinite, r.isFinite else { throw PlaybackTransportError.workerFailed("출력 오디오 값이 올바르지 않습니다") }
                channels[0][i] = l; channels[1][i] = r
            }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer); offset += count
        }
        }
    }

    private func read(_ handle: FileHandle, session id: UUID, decode: Bool) {
        guard let readerControl else { try? handle.close(); return }
        let slots = DispatchSemaphore(value: 8)
        DispatchQueue(label: decode ? "circlr.output-events" : "circlr.output-stderr").async {
            defer {
                try? handle.close()
                if decode { self.queue.async { self.didDrainEvents(id) } }
            }
            var buffer = [UInt8](repeating: 0, count: 4096), wire = OutputWorkerWire(session: id)
            do {
                let fd = handle.fileDescriptor
                let flags = fcntl(fd, F_GETFL)
                guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw OutputWorkerWireError.closed }
                while true {
                    // Capture this launch's token: a later launch must never revive an old reader.
                    // Only finalize cancels it, leaving the normal EOF/tail-drain window intact.
                    guard !readerControl.isCancelled else { return }
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                    if count < 0 {
                        if errno == EINTR { continue }
                        if errno == EAGAIN || errno == EWOULDBLOCK {
                            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                            let ready = Darwin.poll(&descriptor, 1, 50)
                            if ready < 0 && errno != EINTR { throw OutputWorkerWireError.closed }
                            continue
                        }
                        throw OutputWorkerWireError.closed
                    }
                    if count == 0 { break }
                    // Drain diagnostics without retaining arbitrary child output.
                    guard decode else { continue }
                    let packets = try wire.receive(Data(buffer.prefix(count)))
                    self.beforeEventDelivery?(packets)
                    let deliveryDeadline = ProcessInfo.processInfo.systemUptime + 2
                    while slots.wait(timeout: .now() + .milliseconds(50)) != .success {
                        guard !readerControl.isCancelled else { return }
                        guard ProcessInfo.processInfo.systemUptime < deliveryDeadline else { throw OutputWorkerWireError.oversizedChunk }
                    }
                    guard !readerControl.isCancelled else { slots.signal(); return }
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
                if !readerControl.isCancelled {
                    self.queue.async { self.fail(id, message: "출력 응답이 올바르지 않습니다. 다시 재생하세요.") }
                }
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
                try prepare(id, supportsSelection: false)
            case .helloCapabilities(let supported) where stage == .boot:
                try prepare(id, supportsSelection: supported)
            case .helloBoundaryLoopCapabilities(let supported) where stage == .boot:
                boundaryChangesSupported=true
                try prepare(id,supportsSelection:supported,supportsLoop:true)
            case .helloLoopCapabilities(let supported) where stage == .boot:
                try prepare(id, supportsSelection: supported, supportsLoop: true)
            case .outputDevice(let descriptor) where stage == .starting && deviceSelectionSupported && actualDevice == nil:
                if case .deviceUID(let uid) = outputSelection, descriptor.uid != uid { throw OutputWorkerWireError.invalidPacket }
                actualDevice = descriptor
                update { $0.actualOutputDeviceName = descriptor.name }
            case .prepared where stage == .preparing:
                guard helperTraceEvents == 0 || helperTraceEvents == 2 else { throw OutputWorkerWireError.invalidPacket }
                stage = .starting; update { $0.step = .device }
                try send(.play(run: id))
            case .started(let run) where run == id && stage == .starting:
                guard !deviceSelectionSupported || actualDevice != nil else { throw OutputWorkerWireError.invalidPacket }
                let traceCount = deviceSelectionSupported ? OutputWorkerWire.traceStages.count : OutputWorkerWire.legacyTraceStages.count
                guard helperTraceEvents == 0 || helperTraceEvents == traceCount * 2 else { throw OutputWorkerWireError.invalidPacket }
                stage = .playing
                update {
                    guard $0.transport.phase == .starting else { return }
                    $0.phase = .ready; $0.step = .ready; $0.request = .none; $0.transport.phase = .playing; $0.transport.didStart = true
                }
            case .clock(let run, let seconds) where run == id && stage == .playing && !looping:
                guard seconds <= Double(frames) / PCM.rate else { throw OutputWorkerWireError.invalidPacket }
                update { if $0.transport.phase == .playing { $0.transport.seconds = max($0.transport.seconds, seconds) } }
            case .loopClock(let run, let seconds) where run == id && stage == .playing && looping:
                update { if $0.transport.phase == .playing { $0.transport.seconds = max($0.transport.seconds, seconds) } }
            case .loopChangeScheduled(let change,let elapsed,let count,let exiting) where stage == .playing && boundaryChangesSupported && pendingChangeID==change:
                let current=status.transport
                guard exiting == (pendingCycleFrames==nil),count == (pendingCycleFrames ?? loopCycleFrames),
                      elapsed>=loopEpochFrame,
                      (elapsed-loopEpochFrame+Int64(loopStartFrame)) % Int64(loopCycleFrames)==0,
                      Double(elapsed)/PCM.rate+1/PCM.rate>=current.seconds else{throw OutputWorkerWireError.invalidPacket}
                pendingChangeID=nil;loopExitScheduled=exiting
                loopEpochFrame=elapsed;loopStartFrame=0;loopCycleFrames=count
                update {$0.transport.loopChange = .init(id:change,elapsedFrame:elapsed,frames:count,exiting:exiting)}
            case .loopChangeRejected(let change,let message) where pendingChangeID==change:
                pendingChangeID=nil;lock.lock();changeFailure=(change,message);lock.unlock()
            case .loopFinished(let run,let endFrame) where run==id && stage == .playing && looping && loopExitScheduled:
                guard endFrame>=loopEpochFrame else{throw OutputWorkerWireError.invalidPacket}
                update {$0.transport.completedSeconds=Double(endFrame)/PCM.rate;$0.transport.phase = .stopping;$0.transport.seconds=0}
                close(id,graceful:false)
            case .finished(let run) where run == id && stage == .playing && (!looping || loopExitScheduled):
                update { $0.transport.completedSeconds=$0.transport.seconds;$0.transport.phase = .stopping; $0.transport.seconds = 0 }
                close(id, graceful: false)
            case .failure(let run, let message) where run == nil || run == id: fail(id, message: message)
            case .trace(let step, let phase, let elapsed):
                guard (step == .fileValidation && stage == .preparing) || (step != .fileValidation && stage == .starting) else {
                    throw OutputWorkerWireError.invalidPacket
                }
                helperTraceEvents += 1
                trace(id, step, phase, workerElapsed: elapsed)
            default: throw OutputWorkerWireError.invalidPacket
            }
        } catch { fail(id, message: "출력 응답 처리에 실패했습니다. 다시 재생하세요.") }
    }
    private func prepare(_ id: UUID, supportsSelection: Bool, supportsLoop: Bool = false) throws {
        trace(id, .helperHello, .completed)
        deviceSelectionSupported = supportsSelection
        if !supportsSelection, case .deviceUID = outputSelection {
            fail(id, message: "출력 helper가 장치 선택을 지원하지 않습니다. 앱 설치를 확인하세요.")
            return
        }
        if looping && !supportsLoop {
            fail(id, message: "출력 helper가 연속 루프를 지원하지 않습니다. 앱 설치를 확인하세요.")
            return
        }
        stage = .preparing; update { $0.step = .routing }
        if looping,boundaryChangesSupported {try send(.prepareLoopRange(frames:frames,cycleFrames:loopCycleFrames,startFrame:loopStartFrame,selection:outputSelection))}
        else if looping {
            guard loopStartFrame==0,frames==loopCycleFrames else{throw PlaybackTransportError.workerFailed("출력 helper가 루프 시작점과 종료 잔향을 지원하지 않습니다")}
            try send(.prepareLoop(frames: frames, selection: outputSelection))
        }
        else if supportsSelection { try send(.prepareOutput(frames: frames, selection: outputSelection)) }
        else { try send(.prepare(frames: frames)) }
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
        terminationObserved = true
        onTerminationObserved?()
        if eventsDrained { finalizeAfterDrain(id); return }
        // A descendant could keep stdout open after the helper exits. Do not
        // retain this session indefinitely, but normally consume all queued EOF
        // diagnostics before clearing its identity and status.
        queue.asyncAfter(deadline: .now() + 2) {
            guard self.session == id, self.terminationObserved else { return }
            self.finalizeAfterDrain(id)
        }
    }
    private func didDrainEvents(_ id: UUID) {
        guard session == id else { return }
        eventsDrained = true
        if terminationObserved { finalizeAfterDrain(id) }
    }
    private func finalizeAfterDrain(_ id: UUID) {
        guard session == id else { return }
        if stage != .closing { update { $0.transport.message = "출력 프로세스가 종료됐습니다. 다시 재생하세요." } }
        finalize(id)
    }
    private func finalize(_ id: UUID) {
        guard session == id else { return }
        // Readers own and close their descriptors. Nonblocking polling lets both
        // release even when an unrelated descendant keeps a pipe writer alive.
        readerControl?.cancel(); readerControl = nil
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
