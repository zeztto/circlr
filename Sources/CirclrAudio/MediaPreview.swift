import Foundation
import AVFAudio
import CirclrCore

public final class MediaPreviewCancellation:@unchecked Sendable {
    private let lock=NSLock()
    private var cancelled=false
    public init(){}
    public func cancel(){lock.lock();cancelled=true;lock.unlock()}
    public var isCancelled:Bool {lock.lock();defer{lock.unlock()};return cancelled}
}
/// All methods belong to one background operation. No player crosses into the UI actor.
public protocol MediaPreviewPlayer:AnyObject,Sendable {
    func prepare()throws
    func startMuted()->Bool
    func makeAudible()
    func stop()
    var isPlaying:Bool{get}
    var seconds:Double{get}
}
public final class LocalMediaPreviewPlayer:MediaPreviewPlayer,@unchecked Sendable {
    private let player:AVAudioPlayer
    public init(url:URL)throws{player=try AVAudioPlayer(contentsOf:url);player.volume=0}
    public func prepare()throws{guard player.prepareToPlay() else{throw CirclrError("미리 듣기 출력을 준비할 수 없습니다")}}
    public func startMuted()->Bool{player.play()}
    public func makeAudible(){player.volume=0.35}
    public func stop(){player.stop()}
    public var isPlaying:Bool{player.isPlaying}
    public var seconds:Double{player.currentTime}
}
public enum MediaPreview {
    public static func run(_ player:any MediaPreviewPlayer,cancellation:MediaPreviewCancellation,update:@Sendable(Double)->Void)async throws {
        defer{player.stop()}
        func checkpoint()throws{try Task.checkCancellation();if cancellation.isCancelled{throw CancellationError()}}
        try checkpoint();try player.prepare();try checkpoint()
        // AudioQueueStart itself can wait on HAL. Start muted so a cancelled late start is inaudible.
        guard player.startMuted() else{throw CirclrError("미리 듣기를 시작할 수 없습니다")}
        try checkpoint();player.makeAudible();try checkpoint()
        while player.isPlaying {try checkpoint();update(player.seconds);try await Task.sleep(for:.milliseconds(100))}
    }
}
