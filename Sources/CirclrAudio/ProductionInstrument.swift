import Foundation
import AVFAudio
import CirclrCore
import CirclrRealtime

public final class SynthEngine {
    private let handle: OpaquePointer
    public init(_ patch: SynthPatch) throws {
        try patch.validate()
        let created:OpaquePointer?
        switch patch.engineVersion {
        case 3: created=circlr_synth_create_v3(Int32(patch.voice.rawValue),patch.cutoff,patch.attack,patch.decay,patch.sustain,patch.release,patch.detune,patch.resonance,patch.stereoWidth,patch.filterEnvelope,patch.character,patch.motion)
        case 2: created=circlr_synth_create_v2(Int32(patch.voice.rawValue),patch.cutoff,patch.attack,patch.decay,patch.sustain,patch.release,patch.detune,patch.resonance,patch.stereoWidth,patch.filterEnvelope)
        default: created=circlr_synth_create(Int32(patch.voice.rawValue),patch.cutoff,patch.attack,patch.decay,patch.sustain,patch.release,patch.detune)
        }
        guard let value=created else {throw CirclrError("신스 메모리를 준비할 수 없습니다")}
        handle=value
    }
    deinit { circlr_synth_destroy(handle) }
    public func note(_ pitch: Int, velocity: Int, on: Bool) { circlr_synth_note(handle,Int32(pitch),Int32(velocity),on ? 1:0) }
    /// Offline render-owner calls; never mix these with queued live notes.
    func ownedNote(stream:UInt64,voice:UInt64,pitch:Int,velocity:Int,on:Bool,bend:Double)throws {
        let accepted = on ? circlr_synth_owned_note_on(handle,stream,voice,Int32(pitch),Int32(velocity),bend) : circlr_synth_owned_note_off(handle,stream,voice)
        guard accepted == 1 else {throw CirclrError("신스 독립 MIDI note를 적용할 수 없습니다")}
    }
    func ownedBend(stream:UInt64,semitones:Double)throws {
        guard circlr_synth_owned_pitch_bend(handle,stream,semitones) == 1 else {throw CirclrError("신스 피치 벤드 상태를 적용할 수 없습니다")}
    }
    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: UInt32) {circlr_synth_render(handle,left,right,frames)}
    public func render(left:UnsafeMutablePointer<Float>,right:UnsafeMutablePointer<Float>,cutoffHz:UnsafePointer<Double>?,resonance:UnsafePointer<Double>?,frames:UInt32) {
        circlr_synth_render_filter(handle,left,right,cutoffHz,resonance,frames)
    }
    /// The render owner supplies one base cutoff per sample without changing the patch or voices.
    public func render(left:UnsafeMutablePointer<Float>,right:UnsafeMutablePointer<Float>,cutoffHz:UnsafePointer<Double>,frames:UInt32) {
        circlr_synth_render_cutoff(handle,left,right,cutoffHz,frames)
    }
}

public enum ProductionInstrument {
    public static func render(_ notes:[Note], instrument:Instrument, project:Project, root:URL?, clock:MusicClock, tail:Double, hostContext:MusicContext? = nil,automation:[AutomationPlan] = [],performances:[MIDIPerformanceStream] = []) async throws -> PCM {
        _ = try frameCount(clock:clock,tail:tail)
        guard instrument.kind == .synthesizer || !automation.contains(where:{$0.parameter == .synthCutoff || $0.parameter == .synthResonance}) else {
            throw CirclrError("필터 cutoff·resonance 오토메이션은 내장 신스에만 적용할 수 있습니다")
        }
        guard performances.isEmpty || instrument.kind == .synthesizer else { throw CirclrError("피치 벤드 연주는 내장 신스에서만 렌더할 수 있습니다") }
        if instrument.kind == .synthesizer {
            if !performances.isEmpty { return try synth(notes,patch:instrument.synth ?? SynthPatch(),clock:clock,tail:tail,automation:automation,performances:performances) }
            return try synth(notes,patch:instrument.synth ?? SynthPatch(),clock:clock,tail:tail,automation:automation)
        }
        if instrument.kind == .sampler {
            guard let sample=instrument.sample else {throw CirclrError("샘플 악기의 원본을 선택하세요")}
            if let zones=sample.zones,!zones.isEmpty {
                var result=PCM(frames:try frameCount(clock:clock,tail:tail))
                for zone in zones {
                    let matching=notes.filter{$0.pitch==zone.pitch};if matching.isEmpty{continue}
                    guard let asset=project.assets.first(where:{$0.id==zone.assetID}) else {throw CirclrError("드럼 샘플을 찾을 수 없습니다")}
                    let config=SampleInstrument(assetID:asset.id,rootPitch:zone.pitch,oneShot:sample.oneShot)
                    result.mix(try sampler(matching,source:PCM.read(ProjectStore.assetURL(asset,root:root)),settings:config,clock:clock,tail:tail))
                }
                return result
            }
            guard let asset=project.assets.first(where:{$0.id==sample.assetID}) else {throw CirclrError("샘플 악기의 원본을 선택하세요")}
            return try sampler(notes,source:PCM.read(ProjectStore.assetURL(asset,root:root)),settings:sample,clock:clock,tail:tail)
        }
        return try await AUInstrumentWorkerProcess().render(notes:notes,instrument:instrument,clock:clock,tail:tail,hostContext:hostContext)
    }
    public static func synth(_ notes:[Note],patch:SynthPatch,clock:MusicClock,tail:Double,automation:[AutomationPlan] = [],blockSize:Int = 1024) throws -> PCM {
        guard (1...65536).contains(blockSize) else { throw CirclrError("신스 렌더 block 크기를 확인하세요") }
        guard patch.engineVersion>=2 || !automation.contains(where:{$0.parameter == .synthResonance}) else {throw CirclrError("Resonance 오토메이션은 내장 신스 engine 2·3에서만 지원합니다")}
        let engine=try SynthEngine(patch),frames=try frameCount(clock:clock,tail:tail)
        struct Event {var frame:Int;var note:Note;var on:Bool}
        var events:[Event]=[]
        for note in notes where note.beat<clock.beats {
            try ArrangementCompiler.validateNote(note)
            let first=Int((clock.seconds(at:note.beat)*PCM.rate).rounded()),last=Int((clock.seconds(at:min(clock.beats,note.beat+note.length))*PCM.rate).rounded())
            events.append(Event(frame:first,note:note,on:true));events.append(Event(frame:max(first+1,last),note:note,on:false))
        }
        events.sort{$0.frame == $1.frame ? (!$0.on && $1.on):$0.frame<$1.frame}
        // The legacy C queue has 2048 slots. Reject an overflowing sample
        // before rendering instead of accepting the C overflow all-notes-off.
        var batchFrame = -1, batchCount = 0
        for event in events {
            if event.frame != batchFrame {batchFrame=event.frame;batchCount=0}
            batchCount+=1
            guard batchCount<=2048 else {throw CirclrError("한 sample의 MIDI note 이벤트가 신스 queue 한도 2048개를 넘습니다")}
        }
        var cutoff=try SynthCutoffCursor(automation),resonance=try SynthResonanceCursor(automation)
        var cutoffSamples=[Double](repeating:patch.cutoff,count:blockSize)
        var resonanceSamples=[Double](repeating:patch.resonance,count:blockSize)
        var result=PCM(frames:frames),cursor=0,index=0
        while cursor<frames {
            try Task.checkCancellation()
            while index<events.count && events[index].frame<=cursor {let e=events[index];engine.note(e.note.pitch,velocity:e.note.velocity,on:e.on);index+=1}
            let next=index<events.count ? events[index].frame:frames,count=min(blockSize,frames-cursor,max(1,next-cursor))
            if cutoff.active || resonance.active {
                for i in 0..<count {
                    if cutoff.active {cutoffSamples[i]=cutoff.value(at:Double(cursor+i)/PCM.rate)}
                    if resonance.active {resonanceSamples[i]=resonance.value(at:Double(cursor+i)/PCM.rate)}
                }
                cutoffSamples.withUnsafeBufferPointer { values in resonanceSamples.withUnsafeBufferPointer { resonances in
                    result.left.withUnsafeMutableBufferPointer { l in result.right.withUnsafeMutableBufferPointer { r in
                        engine.render(left:l.baseAddress!+cursor,right:r.baseAddress!+cursor,cutoffHz:cutoff.active ? values.baseAddress:nil,resonance:resonance.active ? resonances.baseAddress:nil,frames:UInt32(count))
                    } }
                } }
            } else {
                result.left.withUnsafeMutableBufferPointer { l in result.right.withUnsafeMutableBufferPointer { r in engine.render(left:l.baseAddress!+cursor,right:r.baseAddress!+cursor,frames:UInt32(count)) } }
            }
            cursor+=count
        }
        return result
    }
    public static func sampler(_ notes:[Note],source:PCM,settings:SampleInstrument,clock:MusicClock,tail:Double) throws -> PCM {
        guard (0...127).contains(settings.rootPitch) else {throw CirclrError("샘플 기준음을 확인하세요")}
        var result=PCM(frames:try frameCount(clock:clock,tail:tail))
        for note in notes where note.beat<clock.beats {
            try Task.checkCancellation();try ArrangementCompiler.validateNote(note)
            let rate=pow(2,Double(note.pitch-settings.rootPitch)/12),first=Int((clock.seconds(at:note.beat)*PCM.rate).rounded())
            let gated=Int(((clock.seconds(at:min(clock.beats,note.beat+note.length))-clock.seconds(at:note.beat))*PCM.rate).rounded())
            let count=min(result.count-first,Int(Double(source.count)/rate),settings.oneShot ? result.count:max(1,gated))
            guard count>0 else {continue}
            for i in 0..<count {let position=Double(i)*rate,j=Int(position),f=Float(position-Double(j)),next=min(source.count-1,j+1)
                let fade=Float(min(1,Double(count-i)/120)),gain=Float(note.velocity)/127*fade
                result.left[first+i]+=(source.left[j]*(1-f)+source.left[next]*f)*gain
                result.right[first+i]+=(source.right[j]*(1-f)+source.right[next]*f)*gain
            }
        }
        return result
    }
    static func frameCount(clock:MusicClock,tail:Double) throws -> Int {
        let frames=try RenderTailPlanner.frameCount(bodySeconds:clock.seconds,tailSeconds:tail)
        guard clock.seconds+tail<1800 else {throw CirclrError("악기의 렌더 길이를 확인하세요")}
        return frames
    }
}

/// A small voice pool keeps rapid one-shots from cutting each other off.
public final class LiveSampler {
    private let audio:AVAudioEngine
    private var players:[AVAudioPlayerNode]=[]
    private var cursor=0
    private let sample:SampleInstrument
    private var sources:[ID:PCM]=[:]
    private var held:[Int:[AVAudioPlayerNode]]=[:]
    public init(settings:SampleInstrument,project:Project,root:URL?,isCurrent:@Sendable()->Bool = {true},report:AuditionDiagnosticReporter?=nil) throws {
        sample=settings
        report?(.engineCreation,.entered);audio=AVAudioEngine();report?(.engineCreation,.completed)
        report?(.sourceLoad,.entered)
        for id in Set((settings.zones ?? []).map(\.assetID)+[settings.assetID]) {
            guard isCurrent() else{throw CancellationError()}
            guard let asset=project.assets.first(where:{$0.id==id}) else {throw CirclrError("샘플 원본을 찾을 수 없습니다")}
            sources[id]=try PCM.read(ProjectStore.assetURL(asset,root:root))
        }
        report?(.sourceLoad,.completed)
        let format=AVAudioFormat(standardFormatWithSampleRate:PCM.rate,channels:2)!
        guard isCurrent() else{throw CancellationError()}
        report?(.mixerAcquisition,.entered);let mixer=audio.mainMixerNode;report?(.mixerAcquisition,.completed)
        report?(.routing,.entered)
        for _ in 0..<32 {guard isCurrent() else{throw CancellationError()};let p=AVAudioPlayerNode();audio.attach(p);audio.connect(p,to:mixer,format:format);players.append(p)}
        report?(.routing,.completed)
        guard isCurrent() else{throw CancellationError()}
        report?(.engineStart,.entered);try audio.start();report?(.engineStart,.completed)
        if !isCurrent(){audio.stop();throw CancellationError()}
    }
    public func note(_ pitch:Int,velocity:Int,on:Bool,isCurrent:@Sendable()->Bool = {true}) throws {
        if !on {if !sample.oneShot {held[pitch]?.forEach{$0.stop()};held[pitch]=nil};return}
        guard isCurrent() else{return}
        let zone=sample.zones?.first{$0.pitch==pitch}
        if sample.zones?.isEmpty == false && zone == nil {return}
        guard let source=sources[zone?.assetID ?? sample.assetID] else {return}
        let root=zone?.pitch ?? sample.rootPitch
        var context=MusicContext();context.tempo=120
        let length=min(60,source.duration/pow(2,Double(pitch-root)/12))
        let clock=try MusicClock(beats:max(0.01,length*2),context:context)
        let pcm=try ProductionInstrument.sampler([Note(beat:0,length:clock.beats,pitch:pitch,velocity:velocity)],source:source,settings:SampleInstrument(assetID:sample.assetID,rootPitch:root),clock:clock,tail:0)
        let buffer=try pcm.buffer();guard isCurrent() else{return}
        let player=players[cursor];cursor=(cursor+1)%players.count;player.stop();player.volume=0;player.scheduleBuffer(buffer)
        guard isCurrent() else{player.stop();return}
        player.play();guard isCurrent() else{player.stop();return};player.volume=1
        guard isCurrent() else{player.stop();return}
        if !sample.oneShot {held[pitch,default:[]].append(player)}
    }
    public func stop(){audio.stop()}
}

/// Synth note preview and MIDI monitoring use the same oscillator/envelope as offline bounce.
public final class LiveSynth {
    private let synth:SynthEngine
    private let audio:AVAudioEngine
    public init(patch:SynthPatch,isCurrent:@Sendable()->Bool = {true},report:AuditionDiagnosticReporter?=nil) throws {
        report?(.engineCreation,.entered);audio=AVAudioEngine();report?(.engineCreation,.completed)
        report?(.sourceLoad,.entered);synth=try SynthEngine(patch);let engine=synth;report?(.sourceLoad,.completed)
        let format=AVAudioFormat(standardFormatWithSampleRate:PCM.rate,channels:2)!
        let source=AVAudioSourceNode(format:format) { _,_,frames,buffers in
            let list=UnsafeMutableAudioBufferListPointer(buffers)
            guard list.count>=2,let l=list[0].mData?.assumingMemoryBound(to:Float.self),let r=list[1].mData?.assumingMemoryBound(to:Float.self) else {return -1}
            l.initialize(repeating:0,count:Int(frames));r.initialize(repeating:0,count:Int(frames));engine.render(left:l,right:r,frames:frames);return 0
        }
        guard isCurrent() else{throw CancellationError()}
        report?(.mixerAcquisition,.entered);let mixer=audio.mainMixerNode;report?(.mixerAcquisition,.completed)
        report?(.routing,.entered);audio.attach(source);audio.connect(source,to:mixer,format:format);report?(.routing,.completed)
        guard isCurrent() else{throw CancellationError()}
        report?(.engineStart,.entered);try audio.start();report?(.engineStart,.completed)
        if !isCurrent(){audio.stop();throw CancellationError()}
    }
    public func note(_ pitch:Int,velocity:Int,on:Bool){synth.note(pitch,velocity:velocity,on:on)}
    public func stop(){audio.stop()}
}
