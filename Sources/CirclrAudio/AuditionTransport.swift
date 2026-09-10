import Foundation
import AVFAudio
import CirclrCore

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
    func installFailureHandler(_ handler:@escaping @Sendable(String)->Void)
}
extension AuditionBackend {func installFailureHandler(_ handler:@escaping @Sendable(String)->Void){}}

/// UI writes only desired notes. Backend preparation, note work and cleanup never run on MainActor.
public final class AuditionTransport:@unchecked Sendable {
    private struct Held {let token:AuditionNoteToken;let velocity:Int}
    private struct Request {let id:UUID;let target:AuditionTarget;let control:MediaPreviewCancellation;var notes:[Int:Held]=[:]}
    private let lock=NSLock()
    private var desired:Request?
    private var intentGeneration=UUID()
    private var value=AuditionStatus()
    private var startedAt:TimeInterval?
    private var traceStartedAt:TimeInterval?
    private var traceAccepting=false
    private var drainQueued=false
    private var closed=false
    private let queue=DispatchQueue(label:"circlr.audition",qos:.userInitiated)
    private let factory:@Sendable(AuditionTarget,MediaPreviewCancellation,@escaping AuditionDiagnosticReporter)async throws->any AuditionBackend
    private let timeout:TimeInterval
    // Worker queue owns these; a backend in the factory is private until the factory completes.
    private var backend:(any AuditionBackend)?
    private var backendID:UUID?
    private var preparingID:UUID?
    private var sounding:[Int:AuditionNoteToken]=[:]

    public convenience init(){self.init(timeout:10,diagnosticFactory:{try WorkerAuditionBackend(target:$0,control:$1,report:$2)})}
    convenience init(timeout:TimeInterval,factory:@escaping @Sendable(AuditionTarget,MediaPreviewCancellation)async throws->any AuditionBackend) {
        self.init(timeout:timeout,diagnosticFactory:{target,control,report in
            report(.backendPreparation,.entered)
            let backend=try await factory(target,control)
            report(.backendPreparation,.completed)
            return backend
        })
    }
    init(timeout:TimeInterval,diagnosticFactory:@escaping @Sendable(AuditionTarget,MediaPreviewCancellation,@escaping AuditionDiagnosticReporter)async throws->any AuditionBackend){self.timeout=timeout;self.factory=diagnosticFactory}
    private func report(_ id:UUID,_ stage:AuditionTraceEvent.Stage,_ phase:AuditionTraceEvent.Phase) {
        lock.lock();defer{lock.unlock()}
        guard traceAccepting,value.trace?.sessionID==id,let origin=traceStartedAt else{return}
        value.trace?.record(stage,phase,elapsed:max(0,ProcessInfo.processInfo.systemUptime-origin))
    }
    // Caller holds lock. The diagnostic origin is independent of the existing pending timer.
    private func interruptLocked(_ reason:AuditionTraceInterruption.Reason) {
        guard let origin=traceStartedAt else{return}
        value.trace?.interrupt(reason,elapsed:max(0,ProcessInfo.processInfo.systemUptime-origin))
    }
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
            intentGeneration=UUID()
            if desired != nil {interruptLocked(.superseded)}
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
        lock.lock();intentGeneration=UUID();if desired != nil || value.pending {interruptLocked(.cancelled)}
        desired?.control.cancel();desired=nil;value.heldNotes=0
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
        lock.lock();defer{lock.unlock()};phaseLocked(phase,message:message)
    }
    // Caller holds lock so intent validation and publication are atomic.
    private func phaseLocked(_ phase:AuditionStatus.Phase,message:String?=nil) {
        value.phase=phase;value.message=message
        if value.pending {if startedAt==nil{startedAt=ProcessInfo.processInfo.systemUptime}}
        else {startedAt=nil;value.elapsedSeconds=0}
        if phase == .idle || phase == .failed {traceAccepting=false}
    }
    private func discardBackend() {
        guard backend != nil else{return}
        let id=backendID
        if let id {report(id,.cleanup,.entered)}
        phase(.stopping);backend?.stop();backend=nil;backendID=nil;sounding=[:]
        if let id {report(id,.cleanup,.completed)}
    }
    private func drain() {
        guard preparingID==nil else{return}
        let next=request()
        if backendID != next?.id {discardBackend()}
        guard let next=request() else {
            // A buffered backend failure can precede an already queued drain.
            // Explicit cancel or a new note clears failure; an empty drain must not.
            if status.phase != .failed {phase(.idle)}
            return
        }
        guard backendID==next.id,let backend else{prepare(next);return}
        do {
            for (pitch,token) in sounding where next.notes[pitch]?.token != token {
                try sendNote(backend,id:next.id,pitch:pitch,velocity:0,on:false,isCurrent:{true});sounding[pitch]=nil
            }
            for (pitch,held) in next.notes where sounding[pitch] != held.token {
                let valid:@Sendable()->Bool = {[weak self] in
                    guard let current=self?.request() else{return false}
                    return current.id==held.token.session && current.notes[pitch]?.token==held.token && !current.control.isCancelled
                }
                guard valid() else{continue}
                try sendNote(backend,id:next.id,pitch:pitch,velocity:held.velocity,on:true,isCurrent:valid)
                // Keep the sent token even if it was released while the backend call was blocked.
                sounding[pitch]=held.token
                if !valid() {try sendNote(backend,id:next.id,pitch:pitch,velocity:0,on:false,isCurrent:{true});sounding[pitch]=nil}
            }
            if request()?.id==next.id {phase(.ready)}else{schedule()}
        }catch{
            lock.lock();let same=desired?.id==next.id;let generation=intentGeneration
            if same {interruptLocked(.failed);desired?.control.cancel();desired=nil;value.heldNotes=0}
            lock.unlock();discardBackend()
            if same {publishFailure(error.localizedDescription,generation:generation)}else{schedule()}
        }
    }
    private func backendFailed(_ id:UUID,message:String) {
        guard backendID==id else{return}
        lock.lock();let same=desired?.id==id;let generation=intentGeneration
        if same {interruptLocked(.failed);desired?.control.cancel();desired=nil;value.heldNotes=0}
        lock.unlock()
        discardBackend()
        if same {publishFailure(message,generation:generation)}else{schedule()}
    }
    private func publishFailure(_ message:String,generation:UUID) {
        lock.lock()
        let current=intentGeneration==generation && desired==nil
        if current {phaseLocked(.failed,message:message)}
        lock.unlock()
        if !current {schedule()}
    }
    private func sendNote(_ backend:any AuditionBackend,id:UUID,pitch:Int,velocity:Int,on:Bool,isCurrent:@escaping @Sendable()->Bool)throws {
        report(id,.note,.entered)
        try backend.note(pitch,velocity:velocity,on:on,isCurrent:isCurrent)
        report(id,.note,.completed)
    }
    private func prepare(_ request:Request) {
        preparingID=request.id
        lock.lock();value.phase = .preparing;value.attempts+=1;value.message=nil;startedAt=ProcessInfo.processInfo.systemUptime
        traceStartedAt=ProcessInfo.processInfo.systemUptime;value.trace=AuditionTrace(sessionID:request.id);traceAccepting=true
        if desired?.id != request.id {interruptLocked(desired == nil ? .cancelled:.superseded)}
        lock.unlock()
        let reporter:AuditionDiagnosticReporter = {[weak self] stage,phase in self?.report(request.id,stage,phase)}
        let factory=factory
        Task.detached(priority:.userInitiated){
            let result:Result<any AuditionBackend,Error>
            do {try Task.checkCancellation();if request.control.isCancelled{throw CancellationError()};result = .success(try await factory(request.target,request.control,reporter))}
            catch {result = .failure(error)}
            self.queue.async {
                self.preparingID=nil
                switch result {
                case .success(let ready):
                    self.backend=ready;self.backendID=request.id
                    ready.installFailureHandler{[weak self] message in
                        guard let self else{return}
                        self.queue.async{self.backendFailed(request.id,message:message)}
                    }
                    if self.request()?.id != request.id || request.control.isCancelled {self.discardBackend()}
                    // Release the factory result before preparing a successor on the same queue.
                    self.schedule()
                case .failure(let error):
                    self.lock.lock();let same=self.desired?.id==request.id
                    if same {self.interruptLocked(.failed);self.desired=nil;self.value.heldNotes=0;request.control.cancel()}
                    if same {self.phaseLocked(.failed,message:error.localizedDescription)}
                    self.lock.unlock()
                    if !same {self.schedule()}
                }
            }
        }
        queue.asyncAfter(deadline:.now()+timeout) {
            guard self.preparingID==request.id else{return}
            self.lock.lock()
            if self.desired?.id==request.id {
                self.interruptLocked(.timedOut)
                request.control.cancel();self.desired=nil;self.value.heldNotes=0
                self.value.phase = .stopping;self.value.message="미리 듣기 준비가 지연되어 연주 요청을 취소했습니다. 장치 응답 후 정리합니다."
            }
            self.lock.unlock()
        }
    }
}
