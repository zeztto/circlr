import Foundation
import AVFAudio
import CoreMIDI
import CirclrRealtime
import CirclrCore

@MainActor public final class Playback {
    public let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    public private(set) var playing = false
    public private(set) var offset: Double = 0
    public private(set) var prepared: PreparedAudio?
    private var generation = 0
    private var connected = false
    private var connectionTask: Task<Void,Error>?
    // Opening the canvas must not synchronously acquire the system output device.
    public init() {}
    private func connectOutputIfNeeded() async throws {
        guard !connected else { return }
        if connectionTask == nil {
            let engine = engine, player = player
            connectionTask = Task.detached(priority:.userInitiated) {
                engine.attach(player)
                engine.connect(player,to:engine.mainMixerNode,format:AVAudioFormat(standardFormatWithSampleRate:PCM.rate,channels:2))
            }
        }
        try await connectionTask?.value
        connected = true
    }
    public var seconds: Double {
        guard playing, let t = player.lastRenderTime, let p = player.playerTime(forNodeTime:t) else { return offset }
        return offset+Double(p.sampleTime)/p.sampleRate
    }
    public func play(_ audio: PreparedAudio, from: Double = 0) async throws {
        stop(); prepared = audio; offset = max(0,min(audio.mix.duration,from))
        let part = audio.mix.slice(Int((offset*PCM.rate).rounded())..<audio.mix.count)
        guard part.count > 0 else { return }
        generation += 1; let ticket = generation
        try await connectOutputIfNeeded()
        guard generation == ticket, !Task.isCancelled else { return }
        player.scheduleBuffer(try part.buffer(),completionCallbackType:.dataPlayedBack) { [weak self] _ in
            Task { @MainActor in guard let self, self.generation == ticket else { return }; self.playing = false; self.offset = 0 }
        }
        try engine.start(); player.play(); playing = true
    }
    public func stop() { generation += 1; if connected { player.stop(); engine.stop() }; playing = false; offset = 0 }
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
              let ring = circlr_ring_create(format.channelCount,4096,64),
              let scratch = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4096) else { throw CirclrError("녹음 입력은 Float32 non-interleaved 형식이어야 합니다") }
        self.ring = ring; self.scratch = scratch; self.url = url
        do { try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true); file = try AVAudioFile(forWriting:url,settings:format.settings) }
        catch { throw error }
        let timer = DispatchSource.makeTimerSource(queue:queue); self.timer = timer
        timer.schedule(deadline:.now(),repeating:.milliseconds(5)); timer.setEventHandler { [weak self] in self?.drain() }; timer.resume()
    }
    deinit { timer?.cancel(); circlr_ring_destroy(ring) }
    public func append(_ buffer:AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let pointers = UnsafeRawPointer(channels).assumingMemoryBound(to:Optional<UnsafePointer<Float>>.self)
        _ = circlr_ring_push(ring,pointers,buffer.frameLength)
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

@MainActor public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var writer: TakeWriter?
    public private(set) var recording = false
    public init() {}
    public func start(to url:URL) throws {
        guard !recording else { return }
        let input = engine.inputNode, format = input.outputFormat(forBus:0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CirclrError("사용 가능한 오디오 입력 장치가 없습니다") }
        let writer = try TakeWriter(url:url,format:format); self.writer = writer
        input.installTap(onBus:0,bufferSize:1024,format:format) { buffer,_ in writer.append(buffer) }
        do { try engine.start(); recording = true }
        catch { input.removeTap(onBus:0); self.writer = nil; throw error }
    }
    public func stop() throws -> URL? {
        guard recording else { return nil }
        engine.inputNode.removeTap(onBus:0); engine.stop(); recording = false
        let current = writer; writer = nil; try current?.finish(); return current?.url
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
