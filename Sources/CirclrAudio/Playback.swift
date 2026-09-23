import Foundation
import AVFAudio
import CoreMIDI
import CirclrRealtime
import CirclrCore

@MainActor public final class Playback {
    public private(set) var offset:Double=0
    private var preparedValue:PreparedAudio?
    private var loopValue:PlaybackLoopPCM?
    public var prepared:PreparedAudio? {synchronizeLoopBoundary();return preparedValue}
    public var loopPCM:PlaybackLoopPCM? {synchronizeLoopBoundary();return loopValue}
    private var loopEpochSeconds:Double=0
    private var loopDraining=false
    private var loopChangePreparing=false
    private var loopChangeWorker:Task<PlaybackLoopPCM,Error>?
    private var pendingLoop:(PlaybackLoopChangeStatus,PreparedAudio?,PlaybackLoopPCM?)?
    public var pendingLoopChange:PlaybackLoopChangeStatus? {synchronizeLoopBoundary();return pendingLoop?.0}
    private let transport:PlaybackTransport
    private let outputWorker:OutputWorkerProcess?
    private var activeID:UUID?
    private var generation=0
    private var loopPreparation:Task<(PlaybackLoopPCM,PCM),Error>?
    public var onOutputChange:(()->Void)?
    public var outputStatus:PlaybackOutputStatus {
        if let outputWorker {return outputWorker.status}
        var value=outputConnection.status;value.transport=transport.status;return value
    }
    private lazy var outputConnection:PlaybackOutputConnection = {
        let transport=transport
        let connection=PlaybackOutputConnection{report in await transport.connect(report:report)}
        connection.onChange = {[weak self] in self?.onOutputChange?()}
        return connection
    }()
    public init(){transport=PlaybackTransport();outputWorker=OutputWorkerProcess()}
    init(factory:@escaping @Sendable()->any PlaybackBackend){transport=PlaybackTransport(factory:factory);outputWorker=nil}
    init(outputWorker:OutputWorkerProcess){transport=PlaybackTransport();self.outputWorker=outputWorker}
    deinit{loopChangeWorker?.cancel();loopPreparation?.cancel();outputWorker?.cancel();transport.shutdown()}
    public var playing:Bool {if let outputWorker {return outputWorker.status.transport.phase == .playing};let state=transport.status;return state.id==activeID && state.phase == .playing}
    /// Hardware elapsed time remains monotonic while musical position wraps.
    public var elapsedSeconds:Double {
        let state=outputWorker?.status.transport ?? transport.status
        guard state.phase == .playing, outputWorker != nil || state.id == activeID else{return 0}
        return state.seconds
    }
    public var completedElapsedSeconds:Double? {outputStatus.transport.completedSeconds}
    public var loopIteration:Int {synchronizeLoopBoundary();return loopValue?.iteration(elapsed:max(0,elapsedSeconds-loopEpochSeconds),offset:offset) ?? 0}
    private func synchronizeLoopBoundary() {
        guard let pending=pendingLoop,max(elapsedSeconds,completedElapsedSeconds ?? 0)>=pending.0.elapsedSeconds else{return}
        loopEpochSeconds=pending.0.elapsedSeconds;offset=0;loopDraining=pending.0.exiting
        if let audio=pending.1,let loop=pending.2 {preparedValue=audio;loopValue=loop}
        pendingLoop=nil
    }
    public var seconds:Double {musicalSeconds(atElapsed:elapsedSeconds)}
    /// Read a visual position for a nearby future hardware sample without
    /// advancing the transport or committing a scheduled loop transition.
    /// Movie capture uses this with a bounded interpolation of the output clock.
    public func musicalSeconds(atElapsed elapsed:Double) -> Double {visualState(atElapsed:elapsed).seconds}
    /// A pending boundary changes the source as well as the wrapped position.
    /// Return both from one read so a captured frame never uses the new clock
    /// against envelopes from the previous song or section loop.
    public func visualState(atElapsed elapsed:Double) -> (seconds:Double,prepared:PreparedAudio?) {
        guard playing,elapsed.isFinite,elapsed>=0 else{return (0,nil)}
        synchronizeLoopBoundary()
        var audio=preparedValue
        var loop=loopValue,epoch=loopEpochSeconds,draining=loopDraining,positionOffset=offset
        // The requested capture instant can cross an already scheduled output
        // boundary before the next 20 ms worker clock report arrives.
        if let pending=pendingLoop,elapsed>=pending.0.elapsedSeconds {
            epoch=pending.0.elapsedSeconds;draining=pending.0.exiting;positionOffset=0
            if let replacement=pending.2 {loop=replacement}
            if let replacement=pending.1 {audio=replacement}
        }
        if let loop {
            let local=max(0,elapsed-epoch)
            if draining {return (min(loop.duration+loop.exitTail.duration,loop.duration+local),audio)}
            return (loop.position(elapsed:local,offset:positionOffset),audio)
        }
        return (min(audio?.mix.duration ?? .greatestFiniteMagnitude,positionOffset+elapsed),audio)
    }
    public func play(_ audio:PreparedAudio,from:Double=0,selection:OutputDeviceSelection = .systemDefault,loop:Bool=false,onPrepared:(@MainActor (PlaybackLoopPCM?) throws -> Void)?=nil)async throws {
        try await start(audio,from:from,timeout:10,selection:selection,loop:loop,onPrepared:onPrepared)
    }
    func start(_ audio:PreparedAudio,from:Double=0,timeout:Double,selection:OutputDeviceSelection = .systemDefault,loop:Bool=false,onPrepared:(@MainActor (PlaybackLoopPCM?) throws -> Void)?=nil)async throws {
        guard from.isFinite,from>=0,timeout.isFinite,timeout>0 else{throw PlaybackTransportError.invalidPosition}
        try Task.checkCancellation()
        stop();generation+=1;let ticket=generation
        let circular:PlaybackLoopPCM?,pcm:PCM
        if loop {
            let worker=Task.detached(priority:.userInitiated) {
                let cycle=try PlaybackLoopPCM(audio:audio)
                return (cycle,cycle.cycle)
            }
            loopPreparation=worker
            defer {if generation==ticket {loopPreparation=nil}}
            (circular,pcm)=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        } else {circular=nil;pcm=audio.mix}
        try Task.checkCancellation()
        guard generation==ticket else{throw CancellationError()}
        preparedValue=audio;loopValue=circular;loopEpochSeconds=0;loopDraining=false
        offset=try circular.map {Double(try $0.frameOffset(from:from))/PCM.rate} ?? min(audio.mix.duration,from)
        let outputOffset = offset
        guard Int((outputOffset*PCM.rate).rounded())<pcm.count else{return}
        // Prepare a recorder from the exact cycle before any audible output starts.
        // A throwing callback or a callback that stops this run cannot launch it later.
        do {
            try onPrepared?(circular)
            try Task.checkCancellation()
            guard generation==ticket else{throw CancellationError()}
        } catch {
            if generation==ticket {stop()}
            throw error
        }
        if let outputWorker {try await outputWorker.play(pcm,from:outputOffset,timeout:timeout,selection:selection,loop:loop,exitTail:circular?.exitTail);return}
        guard selection == .systemDefault else{throw CirclrError("이 출력 경로는 장치 지정을 지원하지 않습니다") }
        try await outputConnection.waitUntilReady(timeout:timeout)
        try Task.checkCancellation()
        guard generation==ticket else{throw CancellationError()}
        let id=try transport.begin(pcm,from:outputOffset,loop:loop,exitTail:circular?.exitTail);activeID=id
        let deadline=ProcessInfo.processInfo.systemUptime+timeout
        do {
            while true {
                try Task.checkCancellation()
                guard generation==ticket else{throw CancellationError()}
                let state=transport.status
                if state.id==id,state.didStart{return}
                if state.id==id,state.phase == .failed{throw CirclrError(state.message ?? "출력을 시작할 수 없습니다")}
                if state.id==id,state.phase == .idle{throw CancellationError()}
                guard ProcessInfo.processInfo.systemUptime<deadline else{throw PlaybackTransportError.timedOut}
                try await Task.sleep(for:.milliseconds(16))
            }
        }catch{
            transport.cancel(id)
            if activeID==id{activeID=nil;offset=0}
            throw error
        }
    }
    /// Replacement starts at the next boundary not already submitted to hardware.
    /// onScheduled lets movie recording install the same future PCM timeline.
    public func requestLoopChange(to audio:PreparedAudio,onScheduled:(@MainActor (PlaybackLoopChangeStatus,PlaybackLoopPCM?)throws->Void)?=nil)async throws->PlaybackLoopChangeStatus {
        try await changeLoop(to:audio,onScheduled:onScheduled)
    }
    public func finishLoopAtBoundary(onScheduled:(@MainActor (PlaybackLoopChangeStatus,PlaybackLoopPCM?)throws->Void)?=nil)async throws->PlaybackLoopChangeStatus {
        try await changeLoop(to:nil,onScheduled:onScheduled)
    }
    private func changeLoop(to audio:PreparedAudio?,onScheduled:(@MainActor (PlaybackLoopChangeStatus,PlaybackLoopPCM?)throws->Void)?)async throws->PlaybackLoopChangeStatus {
        synchronizeLoopBoundary()
        guard playing,let current=loopValue,!loopDraining,pendingLoop==nil,!loopChangePreparing,let outputWorker else{throw PlaybackTransportError.busy}
        let ticket=generation;loopChangePreparing=true
        defer {if generation==ticket {loopChangePreparing=false;loopChangeWorker=nil}}
        do {
            let replacement:PlaybackLoopPCM?
            if let audio {
                let retained=Double(current.cycle.count+current.exitTail.count)*16+Double(preparedValue?.mix.count ?? 0)*8+(preparedValue?.stems.values.reduce(0.0){$0+Double($1.count)*8} ?? 0)
                let worker=Task.detached(priority:.userInitiated){try PlaybackLoopPCM(audio:audio,additionalRetainedBytes:retained)}
                loopChangeWorker=worker
                replacement=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
            } else {replacement=nil}
            try Task.checkCancellation();guard generation==ticket else{throw CancellationError()}
            let change=try await outputWorker.changeLoop(cycle:replacement?.cycle,tail:replacement?.exitTail)
            try Task.checkCancellation();guard generation==ticket else{throw CancellationError()}
            pendingLoop=(change,audio,replacement)
            do {try onScheduled?(change,replacement)} catch {stop();throw error}
            return change
        } catch {
            if error is CancellationError,generation==ticket {stop()}
            throw error
        }
    }
    public func stop() {
        generation+=1;loopPreparation?.cancel();loopPreparation=nil;pendingLoop=nil;loopChangePreparing=false;loopChangeWorker?.cancel();loopChangeWorker=nil
        if let outputWorker {outputWorker.cancel();activeID=nil;offset=0;return}
        outputConnection.cancelWait()
        if let activeID{transport.cancel(activeID)}
        activeID=nil;offset=0
    }
}

public final class TakeWriter {
    private let queue = DispatchQueue(label:"circlr.take-writer")
    private var file: AVAudioFile?
    private var failure: Error?
    private let ring: OpaquePointer
    private let scratch: AVAudioPCMBuffer
    private var timer: DispatchSourceTimer?
    public let url: URL
    public private(set) var frames: AVAudioFramePosition = 0
    public init(url:URL,format:AVAudioFormat) throws {
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              let scratch = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4096),
              let ring = circlr_ring_create(format.channelCount,4096,64) else { throw CirclrError("녹음 입력은 Float32 non-interleaved 형식이어야 합니다") }
        self.ring = ring; self.scratch = scratch; self.url = url
        do { try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true); file = try AVAudioFile(forWriting:url,settings:format.settings) }
        catch { throw error }
        let timer = DispatchSource.makeTimerSource(queue:queue); self.timer = timer
        timer.schedule(deadline:.now(),repeating:.milliseconds(5)); timer.setEventHandler { [weak self] in self?.drain() }; timer.resume()
    }
    deinit { timer?.cancel(); circlr_ring_destroy(ring) }
    public func append(_ buffer:AVAudioPCMBuffer,frames:AVAudioFrameCount?=nil) {
        guard let channels = buffer.floatChannelData,buffer.format.channelCount>=scratch.format.channelCount else { return }
        let pointers = UnsafeRawPointer(channels).assumingMemoryBound(to:Optional<UnsafePointer<Float>>.self)
        let count=min(frames ?? buffer.frameLength,buffer.frameLength);var offset:UInt32=0
        while offset<count {let n=min(4096,count-offset);_=circlr_ring_push_offset(ring,pointers,offset,n);offset+=n}
    }
    private func drain() {
        guard let channels = scratch.floatChannelData else { return }
        let pointers = UnsafeRawPointer(channels).assumingMemoryBound(to:Optional<UnsafeMutablePointer<Float>>.self)
        while true {
            let n = circlr_ring_pop(ring,pointers); if n == 0 { break }; scratch.frameLength = n
            do { if let file { try file.write(from:scratch); frames += AVAudioFramePosition(n) } } catch { failure = error }
        }
    }
    public func finish() throws {
        timer?.cancel(); timer = nil
        try queue.sync { drain(); file = nil; if let failure { throw failure }; if circlr_ring_overruns(ring)>0 { throw CirclrError("녹음 쓰기가 입력을 따라가지 못했습니다. 보존된 원본: \(url.path)") } }
    }
}

public final class MIDIInput {
    private var client = MIDIClientRef(), port = MIDIPortRef(), destination = MIDIEndpointRef()
    public var onMessage: ((UInt8, UInt8, UInt8, UInt64) -> Void)?
    public private(set) var endpointName = "써클러 MIDI 입력"
    public init(endpointName:String = "써클러 MIDI 입력") throws {
        self.endpointName = endpointName
        var status = MIDIClientCreateWithBlock("circlr" as CFString,&client,nil)
        guard status == noErr else { throw CirclrError("MIDI client 생성 실패: \(status)") }
        status = MIDIInputPortCreateWithBlock(client,"입력" as CFString,&port) { [weak self] list,_ in self?.receive(list) }
        guard status == noErr else { throw CirclrError("MIDI 입력 생성 실패: \(status)") }
        for i in 0..<MIDIGetNumberOfSources() { MIDIPortConnectSource(port,MIDIGetSource(i),nil) }
        status = MIDIDestinationCreateWithBlock(client,endpointName as CFString,&destination) { [weak self] list,_ in self?.receive(list) }
        guard status == noErr else { throw CirclrError("가상 MIDI 입력 생성 실패: \(status)") }
    }
    deinit { if destination != 0 { MIDIEndpointDispose(destination) }; if port != 0 { MIDIPortDispose(port) }; if client != 0 { MIDIClientDispose(client) } }
    private var runningStatus:UInt8 = 0
    private var pending:[UInt8] = []
    private let parserQueue = DispatchQueue(label:"circlr.midi-parser")
    private func receive(_ list:UnsafePointer<MIDIPacketList>) {
        let raw = UnsafeRawPointer(list).advanced(by:MemoryLayout<MIDIPacketList>.offset(of:\.packet)!)
        var packet = raw.assumingMemoryBound(to:MIDIPacket.self)
        for _ in 0..<list.pointee.numPackets {
            let time = packet.pointee.timeStamp
            let data = UnsafeRawPointer(packet).advanced(by:MemoryLayout<MIDIPacket>.offset(of:\.data)!).assumingMemoryBound(to:UInt8.self)
            let bytes = Array(UnsafeBufferPointer(start:data,count:Int(packet.pointee.length)))
            parserQueue.async { [weak self] in self?.parse(bytes,time:time) }
            packet = UnsafePointer(MIDIPacketNext(packet))
        }
    }

    private func parse(_ bytes:[UInt8],time:UInt64) {
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte >= 0x80 { runningStatus = byte < 0xF0 ? byte : 0; pending = []; continue }
            guard runningStatus != 0 else { continue }
            pending.append(byte)
            let needed = [0xC0,0xD0].contains(runningStatus & 0xF0) ? 1 : 2
            if pending.count == needed { onMessage?(runningStatus,pending[0],needed == 2 ? pending[1] : 0,time); pending = [] }
        }
    }
}
