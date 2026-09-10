import Foundation
import AVFAudio
import CirclrCore

// Instantiated only by the audition worker service.
final class NativeAuditionBackend:AuditionBackend,@unchecked Sendable {
    private var synth:LiveSynth?
    private var sampler:LiveSampler?
    private var engine:AVAudioEngine?
    private var unit:AVAudioUnit?
    private let drums:Bool
    init(target:AuditionTarget,control:MediaPreviewCancellation,report:@escaping AuditionDiagnosticReporter)async throws {
        drums=target.instrument.drums
        let current:@Sendable()->Bool = {!control.isCancelled}
        switch target.instrument.kind {
        case .synthesizer:synth=try LiveSynth(patch:target.instrument.synth ?? SynthPatch(),isCurrent:current,report:report)
        case .sampler:
            guard let settings=target.instrument.sample else{throw CirclrError("샘플을 선택하세요")}
            sampler=try LiveSampler(settings:settings,project:target.project,root:target.root,isCurrent:current,report:report)
        case .soundBank,.audioUnit:
            report(.auInstantiation,.entered)
            let unit=try await AudioUnitHost.instrument(target.instrument)
            report(.auInstantiation,.completed)
            guard current() else{throw CancellationError()}
            report(.engineCreation,.entered)
            let engine=AVAudioEngine();self.engine=engine;self.unit=unit
            report(.engineCreation,.completed)
            report(.mixerAcquisition,.entered)
            let mixer=engine.mainMixerNode
            report(.mixerAcquisition,.completed)
            report(.routing,.entered)
            engine.attach(unit);engine.connect(unit,to:mixer,format:AVAudioFormat(standardFormatWithSampleRate:PCM.rate,channels:2))
            report(.routing,.completed)
            guard current() else{throw CancellationError()}
            report(.engineStart,.entered)
            try engine.start()
            report(.engineStart,.completed)
        }
        guard current() else{stop();throw CancellationError()}
    }
    func note(_ pitch:Int,velocity:Int,on:Bool,isCurrent:@escaping @Sendable()->Bool)throws {
        guard !on || isCurrent() else{return}
        if let synth {synth.note(pitch,velocity:velocity,on:on)}
        else if let sampler {try sampler.note(pitch,velocity:velocity,on:on,isCurrent:isCurrent)}
        else {
            guard let midi=unit?.auAudioUnit.scheduleMIDIEventBlock else{throw CirclrError("선택한 Audio Unit은 MIDI 입력을 지원하지 않습니다")}
            let bytes:[UInt8]=[(on ? 0x90:0x80)|(drums ? 9:0),UInt8(clamping:pitch),UInt8(clamping:velocity)]
            bytes.withUnsafeBufferPointer{midi(AUEventSampleTimeImmediate,0,3,$0.baseAddress!)}
        }
    }
    func stop(){synth?.stop();sampler?.stop();engine?.stop()}
}
