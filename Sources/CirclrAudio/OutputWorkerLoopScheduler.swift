import Foundation
import AVFAudio

/// Keeps eight buffers queued, independent of the UI/clock timer. Each buffer can
/// span tiny cycles; changes are assigned exact not-yet-submitted sample frames.
final class OutputWorkerLoopScheduler: @unchecked Sendable {
    struct Audio {
        let cycle:AVAudioPCMBuffer
        let tail:AVAudioPCMBuffer?
        var frames:Int {Int(cycle.frameLength)}
        var tailFrames:Int {Int(tail?.frameLength ?? 0)}
    }
    private let queue=DispatchQueue(label:"circlr.loop-scheduler",qos:.userInitiated)
    private let player:AVAudioPlayerNode
    private var planner:PlaybackLoopSchedule
    private var sources:[UUID:Audio]
    private var inFlight=0
    private var ended=false
    private var cancelled=false
    private let onBoundary:@Sendable (PlaybackLoopSchedule.Boundary)->Void
    private let onFinished:@Sendable (Int64)->Void
    private let onFailure:@Sendable (String)->Void
    init(player:AVAudioPlayerNode,audio:Audio,fromFrame:Int,
         onBoundary:@escaping @Sendable (PlaybackLoopSchedule.Boundary)->Void,
         onFinished:@escaping @Sendable (Int64)->Void,onFailure:@escaping @Sendable (String)->Void)throws {
        let id=UUID()
        self.player=player;self.sources=[id:audio]
        planner=try PlaybackLoopSchedule(source:.init(id:id,frames:audio.frames,tailFrames:audio.tailFrames),fromFrame:fromFrame)
        self.onBoundary=onBoundary;self.onFinished=onFinished;self.onFailure=onFailure
    }
    func start()throws {try queue.sync {try fill()}}
    func request(id:UUID,audio:Audio?)throws {
        try queue.sync {
            guard !cancelled,!ended else{throw PlaybackTransportError.busy}
            let source=audio.map {PlaybackLoopSchedule.Source(id:id,frames:$0.frames,tailFrames:$0.tailFrames)}
            let boundary=try planner.request(.init(id:id,replacement:source))
            if let audio {sources[id]=audio}
            // Reserve and acknowledge now, even when a long cycle ends minutes later.
            onBoundary(boundary)
        }
    }
    func cancel(){queue.sync {cancelled=true;planner.cancel();sources.removeAll()}}
    private func fill()throws {
        while !cancelled,!ended,inFlight<8 {
            guard let first=sources[planner.source.id],
                  let buffer=AVAudioPCMBuffer(pcmFormat:first.cycle.format,frameCapacity:4096),
                  let destination=buffer.floatChannelData else{throw PlaybackTransportError.invalidPosition}
            var count=0
            while count<4096,!ended {
                let step=try planner.next(maxFrames:4096-count)
                if let boundary=step.boundary {
                    if let replacement=boundary.change.replacement {sources=sources.filter{$0.key==replacement.id}}
                }
                if let chunk=step.chunk {
                    guard let audio=sources[chunk.source.id],
                          let source=(chunk.tail ? audio.tail:audio.cycle)?.floatChannelData else{throw PlaybackTransportError.invalidPosition}
                    for channel in 0..<2 {destination[channel].advanced(by:count).update(from:source[channel].advanced(by:chunk.sourceFrame),count:chunk.count)}
                    count+=chunk.count
                }
                ended=step.ended
            }
            guard count>0 else {
                if ended,inFlight==0 {onFinished(planner.elapsedFrame)}
                return
            }
            buffer.frameLength=AVAudioFrameCount(count);inFlight+=1
            player.scheduleBuffer(buffer,completionCallbackType:.dataPlayedBack){[weak self] _ in
                guard let self else{return}
                self.queue.async {
                    guard !self.cancelled else{return}
                    self.inFlight-=1
                    if self.ended,self.inFlight==0 {self.onFinished(self.planner.elapsedFrame);return}
                    do {try self.fill()} catch {self.cancelled=true;self.onFailure(error.localizedDescription)}
                }
            }
        }
    }
}
