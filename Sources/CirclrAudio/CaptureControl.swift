import AVFAudio
import CirclrRealtime
import CirclrCore
import Foundation

/// Shared with the input callback. All mutable state is in C atomics.
public final class CaptureControl:@unchecked Sendable {
    private let pointer:OpaquePointer
    public init()throws {guard let p=circlr_capture_create() else{throw CirclrError("녹음 입력 상태를 준비할 수 없습니다")};pointer=p}
    deinit{circlr_capture_destroy(pointer)}
    public var enabled:Bool {circlr_capture_enabled(pointer)}
    public var frames:UInt64 {circlr_capture_frames(pointer)}
    public var reachedLimit:Bool {circlr_capture_at_limit(pointer)}
    public func takePeak()->Float {circlr_capture_peak(pointer)}
    public func disable(){circlr_capture_disable(pointer)}
    public func interrupt(){circlr_capture_interrupt(pointer)}
    public var interrupted:Bool {circlr_capture_interrupted(pointer)}
    public func limit(frames:UInt64){circlr_capture_limit(pointer,frames)}
    func waitForCallbacks(){while circlr_capture_inflight(pointer)>0 {Thread.sleep(forTimeInterval:0.001)}}
    public func append(_ buffer:AVAudioPCMBuffer,to writer:TakeWriter,channels:UInt32) {
        guard let data=buffer.floatChannelData,channels>0,channels<=buffer.format.channelCount else{return}
        let n=circlr_capture_enter(pointer,buffer.frameLength);guard n>0 else{return}
        writer.append(buffer,frames:n)
        let pointers=UnsafeRawPointer(data).assumingMemoryBound(to:Optional<UnsafePointer<Float>>.self)
        circlr_capture_leave(pointer,pointers,channels,n)
    }
}
