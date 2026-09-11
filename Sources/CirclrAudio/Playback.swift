import Foundation
import AVFAudio
import CoreMIDI
import CirclrRealtime
import CirclrCore

@MainActor public final class Playback {
    public private(set) var offset:Double=0
    public private(set) var prepared:PreparedAudio?
    private let transport:PlaybackTransport
    private let outputWorker:OutputWorkerProcess?
    private var activeID:UUID?
    private var generation=0
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
    deinit{outputWorker?.cancel();transport.shutdown()}
    public var playing:Bool {if let outputWorker {return outputWorker.status.transport.phase == .playing};let state=transport.status;return state.id==activeID && state.phase == .playing}
    public var seconds:Double {
        if let outputWorker {let state=outputWorker.status.transport;return state.phase == .playing ? min(prepared?.mix.duration ?? .greatestFiniteMagnitude,offset+state.seconds):0}
        let state=transport.status
        guard state.id==activeID,state.phase == .playing else{return 0}
        return min(prepared?.mix.duration ?? .greatestFiniteMagnitude,offset+state.seconds)
    }
    public func play(_ audio:PreparedAudio,from:Double=0,selection:OutputDeviceSelection = .systemDefault)async throws {
        try await start(audio,from:from,timeout:10,selection:selection)
    }
    func start(_ audio:PreparedAudio,from:Double=0,timeout:Double,selection:OutputDeviceSelection = .systemDefault)async throws {
        guard from.isFinite,from>=0,timeout.isFinite,timeout>0 else{throw PlaybackTransportError.invalidPosition}
        try Task.checkCancellation()
        stop();prepared=audio;offset=min(audio.mix.duration,from)
        guard Int((offset*PCM.rate).rounded())<audio.mix.count else{return}
        if let outputWorker {try await outputWorker.play(audio.mix,from:offset,timeout:timeout,selection:selection);return}
        guard selection == .systemDefault else{throw CirclrError("이 출력 경로는 장치 지정을 지원하지 않습니다") }
        generation+=1;let ticket=generation
        try await outputConnection.waitUntilReady(timeout:timeout)
        try Task.checkCancellation()
        guard generation==ticket else{throw CancellationError()}
        let id=try transport.begin(audio.mix,from:offset);activeID=id
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
    public func stop() {
        generation+=1
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
