import Foundation
import AVFAudio
import CoreAudio
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
    /// A new full render must not overlap the stopped transport's cached PCM.
    public func stopAndReleasePrepared() {
        stop()
        preparedValue=nil;loopValue=nil
    }
    /// Waits for a stopped output host's queued CAF launch to release its PCM.
    public func waitForStoppedOutputPCMRelease() async {
        await outputWorker?.waitForQueuedPCMRelease()
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

/// CoreMIDI packet timestamps are mach host ticks. Resolve them at receipt,
/// before either parser or UI queue latency can change the musical position.
enum MIDIHostClock {
    static func occurrenceUptime(timeStamp: MIDITimeStamp, receivedHostTime: UInt64,
                                 receivedUptime: Double) -> Double? {
        guard receivedUptime.isFinite, receivedUptime >= 0 else { return nil }
        // A zero timestamp means "now" at the receiving callback, including
        // virtual sources that do not replace zero with a current host tick.
        guard timeStamp != 0 else { return receivedUptime }
        if timeStamp > receivedHostTime {
            let futureTicks = timeStamp - receivedHostTime
            // Absorb only sub-5ms clock skew; a scheduled future event has not
            // happened yet and must not be placed into an earlier recording.
            return futureTicks <= AudioConvertNanosToHostTime(5_000_000) ? receivedUptime : nil
        }
        let ageTicks = receivedHostTime - timeStamp
        guard ageTicks <= AudioConvertNanosToHostTime(30_000_000_000) else { return nil }
        return max(0, receivedUptime - Double(AudioConvertHostTimeToNanos(ageTicks)) / 1_000_000_000)
    }
}

/// MIDI 1.0 running status belongs to one source's byte stream. A message may
/// cross packet boundaries; its musical time is that of its first byte.
struct MIDIMessageParser {
    private struct SourceState {
        var runningStatus:UInt8 = 0
        var pending:[UInt8] = []
        var firstByteTime:Double?
    }
    private var states:[UInt:SourceState] = [:]

    mutating func reset(sourceKey:UInt) {states.removeValue(forKey:sourceKey)}

    mutating func parse(_ bytes:[UInt8],time:Double,sourceKey:UInt,
                        emit:(UInt8,UInt8,UInt8,Double)->Void) {
        var state=states[sourceKey] ?? SourceState()
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte >= 0x80 {
                state.runningStatus = byte < 0xF0 ? byte : 0
                state.pending.removeAll(keepingCapacity:true)
                state.firstByteTime = byte < 0xF0 ? time : nil
                continue
            }
            guard state.runningStatus != 0 else { continue }
            if state.firstByteTime == nil {state.firstByteTime=time}
            state.pending.append(byte)
            let needed = [0xC0,0xD0].contains(state.runningStatus & 0xF0) ? 1 : 2
            if state.pending.count == needed {
                emit(state.runningStatus,state.pending[0],needed == 2 ? state.pending[1] : 0,
                     state.firstByteTime ?? time)
                state.pending.removeAll(keepingCapacity:true)
                state.firstByteTime=nil
            }
        }
        states[sourceKey]=state
    }
}

public final class MIDIInput {
    // CoreMIDI can shut down MIDIServer after the last client is disposed. On
    // this macOS, recreating a client later in the same process returns -2.
    // Keep one client for the process and dispose each input's own endpoints.
    private static let clientLock = NSLock()
    private static var processClient = MIDIClientRef()
    private static func acquireClient() throws -> MIDIClientRef {
        clientLock.lock()
        defer { clientLock.unlock() }
        if processClient != 0 { return processClient }
        var client = MIDIClientRef()
        let status = MIDIClientCreateWithBlock("circlr" as CFString, &client, nil)
        guard status == noErr else { throw CirclrError("MIDI client 생성 실패: \(status)") }
        processClient = client
        return client
    }
    private var port = MIDIPortRef(), destination = MIDIEndpointRef()
    // CoreMIDI echoes each connection's opaque context to the read block.
    // Distinct stable addresses keep running status local to one input source.
    private var sourceContexts: [UnsafeMutableRawPointer] = []
    public var onMessage: ((UInt8, UInt8, UInt8, Double) -> Void)?
    public private(set) var endpointName = "써클러 MIDI 입력"
    public init(endpointName:String = "써클러 MIDI 입력") throws {
        self.endpointName = endpointName
        let client = try Self.acquireClient()
        var status: OSStatus
        status = MIDIInputPortCreateWithBlock(client,"입력" as CFString,&port) { [weak self] list,sourceContext in
            self?.receive(list,sourceKey:sourceContext.map { UInt(bitPattern:$0) } ?? 0)
        }
        guard status == noErr else { throw CirclrError("MIDI 입력 생성 실패: \(status)") }
        for i in 0..<MIDIGetNumberOfSources() {
            let context=UnsafeMutableRawPointer.allocate(byteCount:1,alignment:1)
            if MIDIPortConnectSource(port,MIDIGetSource(i),context) == noErr {sourceContexts.append(context)}
            else {context.deallocate()}
        }
        status = MIDIDestinationCreateWithBlock(client,endpointName as CFString,&destination) { [weak self] list,_ in
            self?.receive(list,sourceKey:0)
        }
        guard status == noErr else {
            MIDIPortDispose(port);port=0
            for context in sourceContexts {context.deallocate()}
            sourceContexts=[]
            throw CirclrError("가상 MIDI 입력 생성 실패: \(status)")
        }
    }
    deinit {
        if destination != 0 { MIDIEndpointDispose(destination) }
        if port != 0 { MIDIPortDispose(port) }
        for context in sourceContexts {context.deallocate()}
    }
    private var parser=MIDIMessageParser()
    private let parserQueue = DispatchQueue(label:"circlr.midi-parser")
    /// Enqueue a MainActor barrier after every packet already accepted by the
    /// parser. The short grace captures callbacks arriving at a stop boundary.
    /// AppStore also has a finite fallback if a hostile parser never drains.
    public func drain(after grace: DispatchTimeInterval = .milliseconds(30), completion: @escaping () -> Void) {
        parserQueue.asyncAfter(deadline: .now() + grace) {
            DispatchQueue.main.async(execute: completion)
        }
    }
    private func receive(_ list:UnsafePointer<MIDIPacketList>,sourceKey:UInt) {
        let receivedHostTime = AudioGetCurrentHostTime()
        let receivedUptime = ProcessInfo.processInfo.systemUptime
        let raw = UnsafeRawPointer(list).advanced(by:MemoryLayout<MIDIPacketList>.offset(of:\.packet)!)
        var packet = raw.assumingMemoryBound(to:MIDIPacket.self)
        for _ in 0..<list.pointee.numPackets {
            let time = MIDIHostClock.occurrenceUptime(timeStamp: packet.pointee.timeStamp,
                                                       receivedHostTime: receivedHostTime,
                                                       receivedUptime: receivedUptime)
            let data = UnsafeRawPointer(packet).advanced(by:MemoryLayout<MIDIPacket>.offset(of:\.data)!).assumingMemoryBound(to:UInt8.self)
            let bytes = Array(UnsafeBufferPointer(start:data,count:Int(packet.pointee.length)))
            if let time { parserQueue.async { [weak self] in self?.parse(bytes,time:time,sourceKey:sourceKey) } }
            else {parserQueue.async { [weak self] in self?.parser.reset(sourceKey:sourceKey) }}
            packet = UnsafePointer(MIDIPacketNext(packet))
        }
    }

    private func parse(_ bytes:[UInt8],time:Double,sourceKey:UInt) {
        parser.parse(bytes,time:time,sourceKey:sourceKey) { [weak self] status,pitch,velocity,occurrence in
            self?.onMessage?(status,pitch,velocity,occurrence)
        }
    }
}
