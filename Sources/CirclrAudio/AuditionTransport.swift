import Foundation
import AVFAudio
import CirclrCore

public struct AuditionStatus:Equatable,Codable,Sendable {
    public enum Phase:String,Codable,Sendable {case idle,preparing,ready,stopping,failed}
    public var phase:Phase = .idle
    public var attempts=0
    public var heldNotes=0
    public var elapsedSeconds=0
    public var message:String?
    public var pending:Bool {phase == .preparing || phase == .stopping}
    public init(){}
}

public struct AuditionTarget:@unchecked Sendable {
    public let key:String
    let instrument:Instrument
    let project:Project
    let root:URL?
    public init(key:String,instrument:Instrument,project:Project,root:URL?){self.key=key;self.instrument=instrument;self.project=project;self.root=root}
    fileprivate func matches(_ other:Self)->Bool {key==other.key && instrument==other.instrument && root==other.root}
}
public struct AuditionNoteToken:Equatable,Sendable {
    fileprivate let session:UUID
    fileprivate let id:UUID
    fileprivate let pitch:Int
}
protocol AuditionBackend:AnyObject,Sendable {
    func note(_ pitch:Int,velocity:Int,on:Bool,isCurrent:@escaping @Sendable()->Bool)throws
    func stop()
}

/// UI writes only desired notes. Backend preparation, note work and cleanup never run on MainActor.
public final class AuditionTransport:@unchecked Sendable {
    private struct Held {let token:AuditionNoteToken;let velocity:Int}
    private struct Request {let id:UUID;let target:AuditionTarget;let control:MediaPreviewCancellation;var notes:[Int:Held]=[:]}
    private let lock=NSLock()
    private var desired:Request?
    private var value=AuditionStatus()
    private var startedAt:TimeInterval?
    private var drainQueued=false
    private var closed=false
    private let queue=DispatchQueue(label:"circlr.audition",qos:.userInitiated)
    private let factory:@Sendable(AuditionTarget,MediaPreviewCancellation)async throws->any AuditionBackend
    private let timeout:TimeInterval
    // Worker queue owns these; a backend in the factory is private until the factory completes.
    private var backend:(any AuditionBackend)?
    private var backendID:UUID?
    private var preparingID:UUID?
    private var sounding:[Int:AuditionNoteToken]=[:]

    public convenience init(){self.init(timeout:10,factory:{try await NativeAuditionBackend(target:$0,control:$1)})}
    init(timeout:TimeInterval,factory:@escaping @Sendable(AuditionTarget,MediaPreviewCancellation)async throws->any AuditionBackend){self.timeout=timeout;self.factory=factory}
    public var status:AuditionStatus {
        lock.lock();defer{lock.unlock()};var result=value
        if result.pending,let startedAt {result.elapsedSeconds=Int(max(0,ProcessInfo.processInfo.systemUptime-startedAt))}
        return result
    }
    @discardableResult public func note(target:AuditionTarget,pitch:Int,velocity:Int,on:Bool)->AuditionNoteToken? {
        guard (0...127).contains(pitch),(0...127).contains(velocity) else{return nil}
        lock.lock()
        guard !closed else{lock.unlock();return nil}
        if !on || velocity==0 {
            guard desired?.target.key==target.key,desired?.notes[pitch] != nil else{lock.unlock();return nil}
            desired?.notes[pitch]=nil;value.heldNotes=desired?.notes.count ?? 0
            lock.unlock();schedule();return nil
        }
        if desired?.target.matches(target) != true {
            desired?.control.cancel();desired=Request(id:UUID(),target:target,control:MediaPreviewCancellation())
            let pending=value.pending
            value.phase=pending ? .stopping:.preparing;value.message=nil
            if !pending {startedAt=ProcessInfo.processInfo.systemUptime}
        }
        let token=AuditionNoteToken(session:desired!.id,id:UUID(),pitch:pitch)
        desired?.notes[pitch]=Held(token:token,velocity:velocity);value.heldNotes=desired?.notes.count ?? 0
        lock.unlock();schedule();return token
    }
    public func release(_ token:AuditionNoteToken) {
        lock.lock()
        guard desired?.id==token.session,desired?.notes[token.pitch]?.token==token else{lock.unlock();return}
        desired?.notes[token.pitch]=nil;value.heldNotes=desired?.notes.count ?? 0
        lock.unlock();schedule()
    }
    public func cancel() {
        lock.lock();desired?.control.cancel();desired=nil;value.heldNotes=0
        if value.phase != .idle {value.phase = .stopping}
        lock.unlock();schedule()
    }
    public func shutdown() {lock.lock();closed=true;lock.unlock();cancel()}
    private func request()->Request? {lock.lock();defer{lock.unlock()};return desired}
    private func schedule() {
        lock.lock();guard !drainQueued else{lock.unlock();return};drainQueued=true;lock.unlock()
        queue.async {self.lock.lock();self.drainQueued=false;self.lock.unlock();self.drain()}
    }
    private func phase(_ phase:AuditionStatus.Phase,message:String?=nil) {
        lock.lock();value.phase=phase;value.message=message
        if value.pending {if startedAt==nil{startedAt=ProcessInfo.processInfo.systemUptime}}
        else {startedAt=nil;value.elapsedSeconds=0}
        lock.unlock()
    }
    private func discardBackend() {
        guard backend != nil else{return}
        phase(.stopping);backend?.stop();backend=nil;backendID=nil;sounding=[:]
    }
    private func drain() {
        guard preparingID==nil else{return}
        let next=request()
        if backendID != next?.id {discardBackend()}
        guard let next=request() else{phase(.idle);return}
        guard backendID==next.id,let backend else{prepare(next);return}
        do {
            for (pitch,token) in sounding where next.notes[pitch]?.token != token {
                try backend.note(pitch,velocity:0,on:false,isCurrent:{true});sounding[pitch]=nil
            }
            for (pitch,held) in next.notes where sounding[pitch] != held.token {
                let valid:@Sendable()->Bool = {[weak self] in
                    guard let current=self?.request() else{return false}
                    return current.id==held.token.session && current.notes[pitch]?.token==held.token && !current.control.isCancelled
                }
                guard valid() else{continue}
                try backend.note(pitch,velocity:held.velocity,on:true,isCurrent:valid)
                // Keep the sent token even if it was released while the backend call was blocked.
                sounding[pitch]=held.token
                if !valid() {try backend.note(pitch,velocity:0,on:false,isCurrent:{true});sounding[pitch]=nil}
            }
            if request()?.id==next.id {phase(.ready)}else{schedule()}
        }catch{
            lock.lock();let same=desired?.id==next.id
            if same {desired?.control.cancel();desired=nil;value.heldNotes=0}
            lock.unlock();discardBackend()
            if same {phase(.failed,message:error.localizedDescription)}else{schedule()}
        }
    }
    private func prepare(_ request:Request) {
        preparingID=request.id
        lock.lock();value.phase = .preparing;value.attempts+=1;value.message=nil;startedAt=ProcessInfo.processInfo.systemUptime;lock.unlock()
        let factory=factory
        Task.detached(priority:.userInitiated){
            let result:Result<any AuditionBackend,Error>
            do {try Task.checkCancellation();if request.control.isCancelled{throw CancellationError()};result = .success(try await factory(request.target,request.control))}
            catch {result = .failure(error)}
            self.queue.async {
                self.preparingID=nil
                switch result {
                case .success(let ready):
                    self.backend=ready;self.backendID=request.id
                    if self.request()?.id != request.id || request.control.isCancelled {self.discardBackend()}
                    // Release the factory result before preparing a successor on the same queue.
                    self.schedule()
                case .failure(let error):
                    self.lock.lock();let same=self.desired?.id==request.id
                    if same {self.desired=nil;self.value.heldNotes=0;request.control.cancel()}
                    self.lock.unlock()
                    if same {self.phase(.failed,message:error.localizedDescription)}else{self.schedule()}
                }
            }
        }
        queue.asyncAfter(deadline:.now()+timeout) {
            guard self.preparingID==request.id else{return}
            self.lock.lock()
            if self.desired?.id==request.id {
                request.control.cancel();self.desired=nil;self.value.heldNotes=0
                self.value.phase = .stopping;self.value.message="미리 듣기 준비가 지연되어 연주 요청을 취소했습니다. 장치 응답 후 정리합니다."
            }
            self.lock.unlock()
        }
    }
}

private final class NativeAuditionBackend:AuditionBackend,@unchecked Sendable {
    private var synth:LiveSynth?
    private var sampler:LiveSampler?
    private var engine:AVAudioEngine?
    private var unit:AVAudioUnit?
    private let drums:Bool
    init(target:AuditionTarget,control:MediaPreviewCancellation)async throws {
        drums=target.instrument.drums
        let current:@Sendable()->Bool = {!control.isCancelled}
        switch target.instrument.kind {
        case .synthesizer:synth=try LiveSynth(patch:target.instrument.synth ?? SynthPatch(),isCurrent:current)
        case .sampler:
            guard let settings=target.instrument.sample else{throw CirclrError("샘플을 선택하세요")}
            sampler=try LiveSampler(settings:settings,project:target.project,root:target.root,isCurrent:current)
        case .soundBank,.audioUnit:
            let unit=try await AudioUnitHost.instrument(target.instrument)
            guard current() else{throw CancellationError()}
            let engine=AVAudioEngine();self.engine=engine;self.unit=unit
            engine.attach(unit);engine.connect(unit,to:engine.mainMixerNode,format:AVAudioFormat(standardFormatWithSampleRate:PCM.rate,channels:2))
            guard current() else{throw CancellationError()}
            try engine.start()
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
