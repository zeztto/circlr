import AVFAudio
import Foundation
import CirclrCore

public struct CaptureFormat:Equatable,Codable,Sendable {
    public let sampleRate:Double
    public let channels:UInt32
    public init(sampleRate:Double,channels:UInt32){self.sampleRate=sampleRate;self.channels=channels}
}
public struct CapturedAudio:Sendable {
    public let url:URL
    public let format:CaptureFormat
    public let frames:Int64
    public var duration:Double {Double(frames)/format.sampleRate}
    public init(url:URL,format:CaptureFormat,frames:Int64){self.url=url;self.format=format;self.frames=frames}
}
protocol AudioCaptureBackend:AnyObject {
    func start(to:URL,maximumSeconds:Double,control:CaptureControl)throws->CaptureFormat
    func stop()throws->CapturedAudio?
}

/// The backend and every AVAudioEngine operation belong to one serial queue.
private final class CaptureAttempt:@unchecked Sendable {
    let id=UUID(),control:CaptureControl
    private let queue=DispatchQueue(label:"circlr.audio-capture",qos:.userInitiated)
    private let factory:@Sendable ()->AudioCaptureBackend
    private var backend:AudioCaptureBackend?
    init(control:CaptureControl,factory:@escaping @Sendable ()->AudioCaptureBackend){self.control=control;self.factory=factory}
    func start(to url:URL,maximumSeconds:Double,reply:@escaping @Sendable (Result<CaptureFormat,Error>)->Void) {
        queue.async {
            let backend=self.factory();self.backend=backend
            do {reply(.success(try backend.start(to:url,maximumSeconds:maximumSeconds,control:self.control)))}
            catch {self.control.disable();_ = try? backend.stop();self.backend=nil;reply(.failure(error))}
        }
    }
    func finish(reply:@escaping @Sendable (Result<CapturedAudio?,Error>)->Void) {
        control.disable()
        queue.async {defer{self.backend=nil};reply(Result{try self.backend?.stop()})}
    }
}

/// UI cancellation never waits for a blocked driver. Its worker must still clean up before retry.
@MainActor public final class AudioRecorder {
    public enum Phase:String,Sendable {case idle,starting,recording,cancelling,finishing,failed}
    public private(set) var phase:Phase = .idle
    public private(set) var format:CaptureFormat?
    public private(set) var message=""
    public var onChange:(()->Void)?
    public var busy:Bool {attempt != nil}
    public var recording:Bool {phase == .recording}
    public var frames:UInt64 {attempt?.control.frames ?? completedFrames}
    public var seconds:Double {format.map{Double(frames)/$0.sampleRate} ?? 0}
    public var reachedLimit:Bool {attempt?.control.reachedLimit ?? false}
    public var interrupted:Bool {attempt?.control.interrupted ?? false}
    public func takePeak()->Float {attempt?.control.takePeak() ?? 0}
    private var attempt:CaptureAttempt?
    private var completedFrames:UInt64=0
    private var startReply:((Result<CaptureFormat,Error>)->Void)?
    private var timeoutTask:Task<Void,Never>?
    private let factory:@Sendable ()->AudioCaptureBackend
    public init(){factory={EngineCaptureBackend()}}
    init(factory:@escaping @Sendable ()->AudioCaptureBackend){self.factory=factory}
    deinit {timeoutTask?.cancel();attempt?.finish{_ in}}
    public func start(to url:URL,maximumSeconds:Double,timeout:Double=10,completion:@escaping (Result<CaptureFormat,Error>)->Void)throws {
        guard attempt==nil else{throw CirclrError("이전 입력 장치를 정리하고 있습니다")}
        guard maximumSeconds.isFinite,maximumSeconds>0,maximumSeconds<=86400,timeout.isFinite,timeout>0,timeout<=60 else{throw CirclrError("녹음 시간 범위를 확인하세요")}
        let next=CaptureAttempt(control:try CaptureControl(),factory:factory)
        attempt=next;format=nil;completedFrames=0;startReply=completion;phase = .starting;message="입력 장치 연결 중";onChange?()
        next.start(to:url,maximumSeconds:maximumSeconds){[weak self] result in Task{@MainActor in self?.started(next.id,result:result)}}
        timeoutTask=Task{[weak self] in
            do {try await Task.sleep(for:.seconds(timeout))}catch{return}
            guard let self,self.attempt?.id==next.id,self.phase == .starting else{return}
            self.cancelStart(reason:CirclrError("입력 장치 연결이 \(Int(timeout))초를 넘었습니다. 장치 응답을 기다리며 정리합니다"))
        }
    }
    private func started(_ id:UUID,result:Result<CaptureFormat,Error>) {
        guard attempt?.id==id,phase == .starting else{return}
        timeoutTask?.cancel();timeoutTask=nil;let reply=startReply;startReply=nil
        switch result {
        case .success(let value):format=value;phase = .recording;message="오디오 녹음 중"
        case .failure(let error):attempt=nil;phase = .failed;message=error.localizedDescription
        }
        onChange?();reply?(result)
    }
    public func cancelStart(reason:Error?=nil) {
        guard let current=attempt,phase == .starting else{return}
        current.control.disable();timeoutTask?.cancel();timeoutTask=nil
        phase = .cancelling;message=reason?.localizedDescription ?? "녹음 시작 취소 · 장치 정리 중";onChange?()
        let reply=startReply;startReply=nil;reply?(.failure(reason ?? CancellationError()))
        current.finish{[weak self] result in Task{@MainActor in
            guard let self,self.attempt?.id==current.id else{return}
            self.completedFrames=current.control.frames;self.attempt=nil
            if case .failure(let error)=result {self.phase = .failed;self.message=error.localizedDescription}
            else {self.phase=reason == nil ? .idle:.failed;self.message=reason?.localizedDescription ?? "녹음 시작 취소"}
            self.onChange?()
        }}
    }
    public func stop(completion:@escaping (Result<CapturedAudio?,Error>)->Void) {
        guard let current=attempt,phase == .recording else{completion(.failure(CirclrError("진행 중인 오디오 녹음이 없습니다")));return}
        current.control.disable();phase = .finishing;message="녹음 파일 마무리 중";onChange?()
        current.finish{[weak self] result in Task{@MainActor in
            guard let self,self.attempt?.id==current.id else{return}
            self.completedFrames=current.control.frames;self.attempt=nil
            switch result {
            case .success(let audio):self.phase=audio == nil ? .failed:.idle;self.message=audio == nil ? "입력 오디오가 없어 take를 만들지 않았습니다":"녹음 파일 저장 완료"
            case .failure(let error):self.phase = .failed;self.message=error.localizedDescription
            }
            self.onChange?();completion(result)
        }}
    }
}

private final class EngineCaptureBackend:AudioCaptureBackend {
    private var engine:AVAudioEngine?,input:AVAudioInputNode?,writer:TakeWriter?,control:CaptureControl?
    private var tapInstalled=false
    private var configurationObserver:NSObjectProtocol?
    func start(to url:URL,maximumSeconds:Double,control:CaptureControl)throws->CaptureFormat {
        self.control=control
        func check()throws {if !control.enabled{throw CancellationError()}}
        try check();let engine=AVAudioEngine();self.engine=engine
        let input=engine.inputNode;self.input=input;try check()
        let inputFormat=input.outputFormat(forBus:0)
        guard inputFormat.sampleRate.isFinite,(8000...384000).contains(inputFormat.sampleRate),(1...32).contains(inputFormat.channelCount),inputFormat.commonFormat == .pcmFormatFloat32,!inputFormat.isInterleaved else {throw CirclrError("사용 가능한 Float32 오디오 입력 장치가 없습니다")}
        let channels=min(2,inputFormat.channelCount)
        guard let format=AVAudioFormat(standardFormatWithSampleRate:inputFormat.sampleRate,channels:channels) else{throw CirclrError("녹음 형식을 만들 수 없습니다")}
        control.limit(frames:UInt64((maximumSeconds*format.sampleRate).rounded(.down)))
        let writer=try TakeWriter(url:url,format:format);self.writer=writer;try check()
        input.installTap(onBus:0,bufferSize:1024,format:inputFormat){buffer,_ in control.append(buffer,to:writer,channels:channels)};tapInstalled=true
        try check();try engine.start();try check()
        configurationObserver=NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:engine,queue:nil){[weak control] _ in control?.interrupt()}
        return CaptureFormat(sampleRate:format.sampleRate,channels:channels)
    }
    func stop()throws->CapturedAudio? {
        control?.disable()
        if let configurationObserver {NotificationCenter.default.removeObserver(configurationObserver);self.configurationObserver=nil}
        if tapInstalled {input?.removeTap(onBus:0);tapInstalled=false}
        engine?.stop();control?.waitForCallbacks()
        let current=writer;writer=nil;input=nil;engine=nil;control=nil
        guard let current else{return nil}
        try current.finish();let file=try AVAudioFile(forReading:current.url)
        guard file.length>0 else{return nil}
        return CapturedAudio(url:current.url,format:CaptureFormat(sampleRate:file.processingFormat.sampleRate,channels:file.processingFormat.channelCount),frames:file.length)
    }
}
