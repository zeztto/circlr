import Foundation
import AVFAudio
import AudioToolbox
import CirclrCore

public enum AudioUnitHost {
    public static let bankURL = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
    public static func installed(type: OSType) -> [PluginDescriptor] {
        let description = AudioComponentDescription(componentType: type, componentSubType: 0, componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
        return AVAudioUnitComponentManager.shared().components(matching: description).map { c in let d = c.audioComponentDescription; return PluginDescriptor(name: c.name, type: d.componentType, subtype: d.componentSubType, manufacturer: d.componentManufacturer) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public static func instantiate(_ descriptor: PluginDescriptor) async throws -> AVAudioUnit {
        let d = AudioComponentDescription(componentType: descriptor.type, componentSubType: descriptor.subtype, componentManufacturer: descriptor.manufacturer, componentFlags: 0, componentFlagsMask: 0)
        return try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: d, options: []) { unit, error in
                if let error { continuation.resume(throwing: error) }
                else if let unit {
                    if let state = descriptor.state {
                        do { guard let value = try PropertyListSerialization.propertyList(from: state, format: nil) as? [String: Any] else { throw CirclrError("Audio Unit state 형식 오류") }; unit.auAudioUnit.fullState = value }
                        catch { continuation.resume(throwing: error); return }
                    }
                    continuation.resume(returning: unit)
                } else { continuation.resume(throwing: CirclrError("\(descriptor.name)을 열 수 없습니다")) }
            }
        }
    }
    public static func instrument(_ config: Instrument) async throws -> AVAudioUnit {
        guard config.kind == .soundBank || config.kind == .audioUnit else {throw CirclrError("이 악기는 내장 신스·샘플 엔진에서 재생하세요")}
        if config.kind == .audioUnit {
            guard let plugin = config.plugin else { throw CirclrError("가상악기를 선택하세요") }
            return try await instantiate(plugin)
        }
        let sampler = AVAudioUnitSampler()
        try sampler.loadSoundBankInstrument(at: bankURL, program: UInt8(clamping: config.program), bankMSB: UInt8(config.drums ? kAUSampler_DefaultPercussionBankMSB : kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        return sampler
    }
    public static func capture(_ unit: AVAudioUnit) throws -> Data? {
        guard let state = unit.auAudioUnit.fullState else { return nil }
        return try PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
    }
    public static func renderNotes(_ notes: [Note], instrument config: Instrument, clock: MusicClock, tail: Double = 2, hostContext: MusicContext? = nil) async throws -> PCM {
        let frames = Int(ceil((clock.seconds + tail) * PCM.rate))
        if notes.isEmpty { return PCM(frames: frames) }
        let unit = try await instrument(config), engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: PCM.rate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        engine.attach(unit); engine.connect(unit, to: engine.mainMixerNode, format: format)
        final class Position { var frame = 0 }
        let position = Position()
        unit.auAudioUnit.musicalContextBlock = { tempo, numerator, denominator, beat, offset, downbeat in
            if let hostContext {
                let q = Double(position.frame) / PCM.rate * hostContext.tempo / 60
                tempo?.pointee = hostContext.tempo; numerator?.pointee = Double(hostContext.meter.numerator); denominator?.pointee = hostContext.meter.denominator
                beat?.pointee = q; offset?.pointee = Int((ceil(q)-q)*60/hostContext.tempo*PCM.rate)
                downbeat?.pointee = floor(q/hostContext.meter.quarters)*hostContext.meter.quarters
                return true
            }
            let q = clock.beat(atSeconds: Double(position.frame)/PCM.rate), bar = clock.bar(at: q)
            tempo?.pointee = clock.bpm(at: q); numerator?.pointee = Double(clock.meters[bar].numerator); denominator?.pointee = clock.meters[bar].denominator
            beat?.pointee = q; offset?.pointee = Int((ceil(q)-q)*60/clock.bpm(at: q)*PCM.rate); downbeat?.pointee = clock.barStarts[bar]; return true
        }
        try engine.start(); defer { engine.stop(); unit.auAudioUnit.musicalContextBlock = nil }
        guard let midi = unit.auAudioUnit.scheduleMIDIEventBlock else { throw CirclrError("선택한 Audio Unit은 MIDI 입력을 지원하지 않습니다") }
        struct Event { var frame: Int; var pitch: UInt8; var velocity: UInt8; var on: Bool }
        var events: [Event] = []
        for note in notes where note.beat < clock.beats {
            events.append(Event(frame: max(0, Int((clock.seconds(at: note.beat)*PCM.rate).rounded())), pitch: UInt8(clamping: note.pitch), velocity: UInt8(clamping: note.velocity), on: true))
            events.append(Event(frame: max(0, Int((clock.seconds(at: min(clock.beats,note.beat+note.length))*PCM.rate).rounded())), pitch: UInt8(clamping: note.pitch), velocity: 0, on: false))
        }
        events.sort { $0.frame == $1.frame ? (!$0.on && $1.on) : $0.frame < $1.frame }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        var output = PCM(frames: frames), eventIndex = 0, active = [Int](repeating: 0, count: 128), retries = 0
        while position.frame < frames {
            try Task.checkCancellation()
            while eventIndex < events.count && events[eventIndex].frame <= position.frame {
                let e = events[eventIndex]; eventIndex += 1
                active[Int(e.pitch)] += e.on ? 1 : -1
                if e.on || active[Int(e.pitch)] <= 0 {
                    let bytes: [UInt8] = [(e.on ? 0x90 : 0x80) | (config.drums ? 9 : 0),e.pitch,e.velocity]
                    bytes.withUnsafeBufferPointer { midi(AUEventSampleTimeImmediate, 0, 3, $0.baseAddress!) }
                }
            }
            let next = eventIndex < events.count ? events[eventIndex].frame : frames
            let count = min(1024, frames-position.frame, max(1,next-position.frame))
            let status = try engine.renderOffline(AVAudioFrameCount(count), to: buffer)
            if status == .success {
                guard Int(buffer.frameLength) > 0, let channels = buffer.floatChannelData else { throw CirclrError("Audio Unit render가 빈 buffer를 반환했습니다") }
                let n = min(Int(buffer.frameLength),frames-position.frame)
                for j in 0..<n { output.left[position.frame+j] = channels[0][j]; output.right[position.frame+j] = channels[1][j] }
                position.frame += n; retries = 0
            } else { retries += 1; if retries > 32 { throw CirclrError("Audio Unit offline render를 진행할 수 없습니다: \(status.rawValue)") } }
        }
        return output
    }
    public static func process(_ input: PCM, unit: AVAudioUnit, duration: Double? = nil) throws -> PCM {
        let engine = AVAudioEngine(), player = AVAudioPlayerNode(), format = AVAudioFormat(standardFormatWithSampleRate: PCM.rate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        engine.attach(player); engine.attach(unit); engine.connect(player,to:unit,format:format); engine.connect(unit,to:engine.mainMixerNode,format:format)
        player.scheduleBuffer(try input.buffer()); try engine.start(); player.play(); defer { engine.stop() }
        let frames = Int(((duration ?? input.duration)*PCM.rate).rounded())
        var output = PCM(frames: frames), cursor = 0, retries = 0
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        while cursor < frames {
            try Task.checkCancellation()
            let status = try engine.renderOffline(AVAudioFrameCount(min(1024,frames-cursor)),to:buffer)
            if status == .success, let channels = buffer.floatChannelData, buffer.frameLength > 0 {
                let count = min(Int(buffer.frameLength), frames-cursor)
                for i in 0..<count { output.left[cursor+i] = channels[0][i]; output.right[cursor+i] = channels[1][i] }
                cursor += count; retries = 0
            } else { retries += 1; if retries > 32 { throw CirclrError("Effect의 offline render를 진행할 수 없습니다") } }
        }
        return output
    }
    public static func stretch(_ input: PCM, rate: Double) throws -> PCM {
        guard rate >= 0.25 && rate <= 4 else { throw CirclrError("오디오 tempo 추종은 원속도의 0.25–4배 범위에서 지원합니다") }
        let unit = AVAudioUnitTimePitch(); unit.rate = Float(rate); unit.pitch = 0
        return try process(input, unit: unit, duration: input.duration/rate)
    }
}
