import Foundation
import AVFAudio
import CirclrCore

public struct PlaybackLoopChangeStatus:Equatable,Codable,Sendable {
    public let id:UUID
    public let elapsedFrame:Int64
    public let frames:Int
    public let exiting:Bool
    public var elapsedSeconds:Double {Double(elapsedFrame)/PCM.rate}
}

public struct PlaybackTransportStatus:Equatable,Codable,Sendable {
    public enum Phase:String,Codable,Sendable {case idle,starting,playing,stopping,failed}
    public var phase:Phase = .idle
    public var id:UUID?
    public var seconds:Double=0
    public var didStart=false
    public var message:String?
    public var loopChange:PlaybackLoopChangeStatus?
    /// Exact final clock for natural completion; nil for STOP/cancellation.
    public var completedSeconds:Double?
    public var pending:Bool {phase == .starting || phase == .stopping}
    public init(){}
}

public enum PlaybackTransportError:LocalizedError {
    case busy,timedOut,invalidPosition
    case workerFailed(String)
    public var errorDescription:String? {
        switch self {
        case .workerFailed(let message):return message
        case .busy:return "이전 출력 작업을 정리하고 있습니다. 정리가 끝나면 다시 재생하세요."
        case .timedOut:return "출력 시작이 지연되어 재생 요청을 취소했습니다. 장치 정리가 끝나면 다시 재생하세요."
        case .invalidPosition:return "재생 시작 위치가 올바르지 않습니다"
        }
    }
}

/// The queue alone owns the backend, including its initialization and final release.
protocol PlaybackBackend:AnyObject {
    func attach()
    func acquireOutput()
    func route()
    func start(_ pcm:PCM,from:Double,control:MediaPreviewCancellation,finished:@escaping @Sendable()->Void)throws
    func startLoop(_ pcm:PCM,from:Double,tail:PCM?,control:MediaPreviewCancellation)throws
    func stop()
    var seconds:Double{get}
    var running:Bool{get}
}

extension PlaybackBackend {
    func startLoop(_ pcm:PCM,from:Double,tail:PCM?,control:MediaPreviewCancellation)throws {
        throw CirclrError("이 출력 backend는 루프를 지원하지 않습니다")
    }
}

final class PlaybackTransport:@unchecked Sendable {
    private let queue=DispatchQueue(label:"circlr.playback-output",qos:.userInitiated)
    private let lock=NSLock()
    private var value=PlaybackTransportStatus()
    private var control:MediaPreviewCancellation?
    private let factory:@Sendable()->any PlaybackBackend
    // Access only on queue.
    private var backend:(any PlaybackBackend)?
    private var timer:DispatchSourceTimer?
    private var closed=false
    init(factory:@escaping @Sendable()->any PlaybackBackend={EnginePlaybackBackend()}){self.factory=factory}
    var status:PlaybackTransportStatus {lock.lock();defer{lock.unlock()};return value}
    private func perform(_ operation:@escaping @Sendable(PlaybackTransport)->Void)async {
        await withCheckedContinuation {reply in queue.async{operation(self);reply.resume()}}
    }
    func connect(report:PlaybackOutputConnection.Report)async {
        await perform {s in guard !s.closed else{return};s.backend=s.factory();s.backend?.attach()}
        await report(.device)
        await perform {s in guard !s.closed else{return};s.backend?.acquireOutput()}
        await report(.routing)
        await perform {s in guard !s.closed else{return};s.backend?.route()}
    }
    func begin(_ pcm:PCM,from:Double,loop:Bool=false,exitTail:PCM?=nil)throws->UUID {
        lock.lock()
        guard control==nil else{lock.unlock();throw PlaybackTransportError.busy}
        let id=UUID(),token=MediaPreviewCancellation()
        control=token;value=PlaybackTransportStatus();value.id=id;value.phase = .starting
        lock.unlock()
        queue.async {
            do {
                guard !self.closed,let backend=self.backend else{throw CancellationError()}
                if loop {try backend.startLoop(pcm,from:from,tail:exitTail,control:token)}
                else {try backend.start(pcm,from:from,control:token){[weak self] in
                    guard let self else{return};self.queue.async{self.finish(id)}
                }}
                guard !token.isCancelled else{throw CancellationError()}
                self.lock.lock()
                if self.value.id==id,self.value.phase == .starting {self.value.phase = .playing;self.value.didStart=true}
                self.lock.unlock()
                let timer=DispatchSource.makeTimerSource(queue:self.queue);self.timer=timer
                timer.schedule(deadline:.now(),repeating:.milliseconds(16))
                timer.setEventHandler{[weak self] in self?.tick(id)};timer.resume()
            }catch {self.finish(id,error:error is CancellationError ? nil:error.localizedDescription)}
        }
        return id
    }
    func cancel(_ id:UUID) {
        lock.lock()
        guard value.id==id,let token=control else{lock.unlock();return}
        token.cancel();value.phase = .stopping;value.seconds=0
        lock.unlock()
        queue.async{self.finish(id)}
    }
    private func tick(_ id:UUID) {
        let state=status
        guard state.id==id,state.phase == .playing,let backend else{return}
        let running=backend.running
        let seconds=running ? backend.seconds:0
        guard running else{finish(id);return}
        lock.lock();defer{lock.unlock()}
        // A blocked clock query must not restore a cancelled run's time or state.
        if value.id==id,value.phase == .playing,seconds.isFinite {value.seconds=max(value.seconds,seconds)}
    }
    private func finish(_ id:UUID,error:String?=nil) {
        lock.lock()
        guard value.id==id,control != nil else{lock.unlock();return}
        control?.cancel();value.phase = .stopping;value.seconds=0
        lock.unlock()
        timer?.cancel();timer=nil
        backend?.stop()
        lock.lock();defer{lock.unlock()}
        guard value.id==id else{return}
        control=nil;value.phase=error == nil ? .idle:.failed;value.message=error
    }
    func shutdown() {
        let state=status;if let id=state.id{cancel(id)}
        queue.async{self.closed=true;self.timer?.cancel();self.timer=nil;self.backend=nil}
    }
}

private final class EnginePlaybackBackend:PlaybackBackend {
    private let engine=AVAudioEngine(),player=AVAudioPlayerNode()
    private var mixer:AVAudioMixerNode?
    private var loopScheduler:OutputWorkerLoopScheduler?
    func attach(){engine.attach(player)}
    func acquireOutput(){mixer=engine.mainMixerNode}
    func route(){if let mixer{engine.connect(player,to:mixer,format:AVAudioFormat(standardFormatWithSampleRate:PCM.rate,channels:2))}}
    func start(_ pcm:PCM,from:Double,control:MediaPreviewCancellation,finished:@escaping @Sendable()->Void)throws {
        func check()throws{if control.isCancelled{throw CancellationError()}}
        try check()
        let part=pcm.slice(Int((from*PCM.rate).rounded())..<pcm.count)
        let buffer=try part.buffer();try check()
        player.volume=0
        player.scheduleBuffer(buffer,completionCallbackType:.dataPlayedBack){_ in finished()}
        try engine.start();try check()
        player.play();try check()
        player.volume=1;try check()
    }
    func startLoop(_ pcm:PCM,from:Double,tail:PCM?,control:MediaPreviewCancellation)throws {
        guard !control.isCancelled else{throw CancellationError()}
        let audio=OutputWorkerLoopScheduler.Audio(cycle:try pcm.buffer(),tail:try tail.flatMap {$0.count>0 ? try $0.buffer():nil})
        let scheduler=try OutputWorkerLoopScheduler(player:player,audio:audio,fromFrame:Int((from*PCM.rate).rounded()),onBoundary:{_ in},onFinished:{_ in},onFailure:{_ in control.cancel()})
        loopScheduler=scheduler;player.volume=0;try scheduler.start()
        try engine.start();guard !control.isCancelled else{throw CancellationError()}
        player.play();player.volume=1
        guard !control.isCancelled else{throw CancellationError()}
    }
    func stop(){loopScheduler?.cancel();loopScheduler=nil;player.stop();engine.stop()}
    var running:Bool{engine.isRunning && player.isPlaying}
    var seconds:Double {
        guard let time=player.lastRenderTime,let played=player.playerTime(forNodeTime:time) else{return 0}
        return max(0,Double(played.sampleTime)/played.sampleRate)
    }
}
