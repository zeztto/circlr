import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
import CirclrCore

/// A bounded hand-off: at most one captured image is retained by the encoder queue.
/// AppKit capture remains on the caller's main actor; pixel conversion, PCM packing,
/// codec submission and finalization execute on the private serial queue.
@MainActor public final class CanvasMovieWriter {
    public let url:URL
    public let width:Int
    public let height:Int
    private let worker:CanvasMovieEncoder
    private let state=MovieWriterState()
    private let queue=DispatchQueue(label:"com.circlr.movie-encoder",qos:.userInitiated)
    public var frameCount:Int {state.read{$0.frames}}
    public var submittedFrameCount:Int {state.read{$0.submitted}}
    public var skippedCaptureCount:Int {state.read{$0.skipped}}
    public var droppedFrames:Int {state.read{$0.dropped}}
    public var lastSeconds:Double {state.read{$0.lastSeconds}}
    public var pendingFrameCount:Int {state.read{$0.pending ? 1:0}}
    public var maximumPendingFrames:Int {state.read{$0.maximumPending}}
    public var maximumEncodeSeconds:Double {state.read{$0.maximumEncodeSeconds}}
    public func checkForFailure() throws {if let error=state.read({$0.failure}) {throw error}}
    /// Queue capacity, not a promise that the hardware encoder will accept the next frame.
    public var canAcceptFrame:Bool {state.read{!$0.pending && !$0.closed && $0.failure == nil}}
    /// Call only when a scheduled capture is skipped because canAcceptFrame is false.
    public func reportSkippedCapture() {state.change{if !$0.closed {$0.dropped+=1;$0.skipped+=1}}}
    public init(url:URL,size:CGSize,pcm:PCM) throws {
        worker=try CanvasMovieEncoder(url:url,size:size,pcm:pcm)
        self.url=url;self.width=worker.width;self.height=worker.height
    }
    public func append(_ image:CGImage,seconds:Double) throws {
        guard seconds.isFinite,seconds>=0 else{return}
        let accepted=try state.change { value -> Bool in
            if let failure=value.failure {throw failure}
            guard !value.closed else{return false}
            guard seconds>value.lastSubmitted else{return false}
            guard !value.pending else{value.dropped+=1;value.skipped+=1;return false}
            value.pending=true;value.submitted+=1;value.lastSubmitted=seconds
            value.maximumPending=1;return true
        }
        guard accepted else{return}
        let worker=worker,state=state
        queue.async {
            defer{state.change{$0.pending=false}}
            guard !state.read({$0.cancelled}) else{return}
            let start=ProcessInfo.processInfo.systemUptime
            do {
                let before=worker.frameCount
                try worker.append(image,seconds:seconds)
                state.change {
                    $0.frames=worker.frameCount;$0.lastSeconds=worker.lastSeconds
                    if worker.frameCount==before {$0.dropped+=1}
                    $0.maximumEncodeSeconds=max($0.maximumEncodeSeconds,ProcessInfo.processInfo.systemUptime-start)
                }
            }catch{state.change{$0.failure=error};worker.cancel()}
        }
    }
    public func finish(seconds:Double) async throws {
        let shouldFinish=state.change {value -> Bool in
            guard !value.closed else{return false};value.closed=true;return true
        }
        guard shouldFinish else{return}
        let worker=worker,state=state
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                queue.async {
                    do {
                        if let error=state.read({$0.failure}) {throw error}
                        try worker.finish(seconds:seconds,isCancelled:{state.read{$0.cancelled}},publish:{
                            try state.change {value in
                                guard !value.cancelled else{throw CancellationError()}
                                try worker.publish()
                            }
                        })
                        continuation.resume()
                    }catch{worker.cancel();continuation.resume(throwing:error)}
                }
            }
        } onCancel: {state.change{$0.cancelled=true}}
    }
    public func cancel() {
        state.change{$0.cancelled=true;$0.closed=true}
        let worker=worker
        queue.async{worker.cancel()}
    }
    /// A queue barrier for shutdown/tests; no codec work runs on the waiting actor.
    public func waitUntilIdle() async {
        await withCheckedContinuation { continuation in queue.async{continuation.resume()} }
    }
    deinit {
        state.change{$0.cancelled=true;$0.closed=true}
        let worker=worker
        queue.async{worker.cancel()}
    }
}

private final class MovieWriterState:@unchecked Sendable {
    struct Value {
        var frames=0,submitted=0,dropped=0,skipped=0,maximumPending=0
        var pending=false,closed=false,cancelled=false
        var lastSubmitted = -Double.infinity,lastSeconds=0.0,maximumEncodeSeconds=0.0
        var failure:Error?
    }
    private var value=Value()
    private let lock=NSLock()
    func read<T>(_ body:(Value)->T)->T {lock.lock();defer{lock.unlock()};return body(value)}
    @discardableResult func change<T>(_ body:(inout Value)throws->T) rethrows -> T {lock.lock();defer{lock.unlock()};return try body(&value)}
}

/// Accessed exclusively by CanvasMovieWriter's encoder queue after initialization.
private final class CanvasMovieEncoder:@unchecked Sendable {
    let url:URL
    let width:Int
    let height:Int
    private(set) var frameCount=0
    private(set) var droppedFrames=0
    private(set) var lastSeconds=0.0
    private let staging:URL
    private let writer:AVAssetWriter
    private let video:AVAssetWriterInput
    private let audio:AVAssetWriterInput
    private let adaptor:AVAssetWriterInputPixelBufferAdaptor
    private let pcm:PCM
    private let audioFormat:CMAudioFormatDescription
    private var audioCursor=0
    private var lastTime=CMTime.invalid
    private var ended=false

    public init(url:URL,size:CGSize,pcm:PCM) throws {
        guard !FileManager.default.fileExists(atPath:url.path),url.pathExtension.lowercased()=="mp4" else{throw CirclrError("기존 파일을 보존하려면 새 MP4 파일 이름을 지정하세요")}
        guard size.width.isFinite,size.height.isFinite,size.width>=64,size.height>=64,pcm.count>0,pcm.right.count==pcm.count,pcm.left.allSatisfy(\.isFinite),pcm.right.allSatisfy(\.isFinite),pcm.peak<=1 else{throw CirclrError("영상 크기와 오디오 출력을 확인하세요")}
        self.url=url;self.pcm=pcm
        let scale=min(1,1920/size.width,1080/size.height)
        width=max(64,Int(size.width*scale)/2*2);height=max(64,Int(size.height*scale)/2*2)
        staging=url.deletingLastPathComponent().appendingPathComponent(".circlr-movie-\(UUID().uuidString).mp4")
        writer=try AVAssetWriter(outputURL:staging,fileType:.mp4)
        video=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:max(4_000_000,width*height*7),AVVideoExpectedSourceFrameRateKey:30,AVVideoMaxKeyFrameIntervalKey:60,AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel]])
        audio=AVAssetWriterInput(mediaType:.audio,outputSettings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:PCM.rate,AVNumberOfChannelsKey:2,AVEncoderBitRateKey:256_000])
        video.expectsMediaDataInRealTime=true;audio.expectsMediaDataInRealTime=true
        adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:video,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
        var asbd=AudioStreamBasicDescription(mSampleRate:PCM.rate,mFormatID:kAudioFormatLinearPCM,mFormatFlags:kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,mBytesPerPacket:8,mFramesPerPacket:1,mBytesPerFrame:8,mChannelsPerFrame:2,mBitsPerChannel:32,mReserved:0)
        var format:CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator:kCFAllocatorDefault,asbd:&asbd,layoutSize:0,layout:nil,magicCookieSize:0,magicCookie:nil,extensions:nil,formatDescriptionOut:&format)==noErr,let format else{throw CirclrError("영상 오디오 포맷을 준비할 수 없습니다")}
        audioFormat=format
        guard writer.canAdd(video),writer.canAdd(audio) else{throw CirclrError("H.264/AAC 영상 인코더를 사용할 수 없습니다")}
        writer.add(video);writer.add(audio)
        guard writer.startWriting() else{throw writer.error ?? CirclrError("영상 파일을 시작할 수 없습니다")}
        writer.startSession(atSourceTime:.zero)
    }
    public func append(_ image:CGImage,seconds:Double) throws {
        guard !ended,seconds.isFinite,seconds>=0 else{return}
        let time=CMTime(seconds:min(seconds,pcm.duration),preferredTimescale:48_000)
        guard !lastTime.isValid || time>lastTime else{return}
        try appendAudio(until:min(pcm.count,Int((seconds+1/30)*PCM.rate)))
        guard video.isReadyForMoreMediaData else{droppedFrames+=1;return}
        guard let pool=adaptor.pixelBufferPool else{throw CirclrError("영상 프레임 pool을 만들 수 없습니다")}
        var pixel:CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,pool,&pixel)==kCVReturnSuccess,let pixel else{throw CirclrError("영상 프레임 메모리가 부족합니다")}
        CVPixelBufferLockBaseAddress(pixel,[])
        defer{CVPixelBufferUnlockBaseAddress(pixel,[])}
        let info=CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context=CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:info) else{throw CirclrError("영상 프레임을 그릴 수 없습니다")}
        context.setFillColor(CGColor(gray:0,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
        let scale=min(Double(width)/Double(image.width),Double(height)/Double(image.height))
        let w=Double(image.width)*scale,h=Double(image.height)*scale
        context.interpolationQuality = .high
        context.draw(image,in:CGRect(x:(Double(width)-w)/2,y:(Double(height)-h)/2,width:w,height:h))
        guard adaptor.append(pixel,withPresentationTime:time) else{throw writer.error ?? CirclrError("영상 프레임 저장 실패")}
        lastTime=time;lastSeconds=time.seconds;frameCount+=1
    }
    private func appendAudio(until limit:Int) throws {
        while audioCursor<limit,audio.isReadyForMoreMediaData {
            let count=min(2048,limit-audioCursor)
            var samples=[Float](repeating:0,count:count*2)
            for i in 0..<count {samples[i*2]=pcm.left[audioCursor+i];samples[i*2+1]=pcm.right[audioCursor+i]}
            var block:CMBlockBuffer?
            let bytes=count*8
            guard CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:bytes,blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:bytes,flags:0,blockBufferOut:&block)==kCMBlockBufferNoErr,let block else{throw CirclrError("영상 오디오 buffer 준비 실패")}
            let copied=samples.withUnsafeBytes{CMBlockBufferReplaceDataBytes(with:$0.baseAddress!,blockBuffer:block,offsetIntoDestination:0,dataLength:bytes)}
            guard copied==kCMBlockBufferNoErr else{throw CirclrError("영상 오디오 복사 실패")}
            var buffer:CMSampleBuffer?
            guard CMAudioSampleBufferCreateWithPacketDescriptions(allocator:kCFAllocatorDefault,dataBuffer:block,dataReady:true,makeDataReadyCallback:nil,refcon:nil,formatDescription:audioFormat,sampleCount:count,presentationTimeStamp:CMTime(value:CMTimeValue(audioCursor),timescale:48_000),packetDescriptions:nil,sampleBufferOut:&buffer)==noErr,let buffer else{throw CirclrError("영상 오디오 sample 준비 실패")}
            guard audio.append(buffer) else{throw writer.error ?? CirclrError("영상 오디오 저장 실패")}
            audioCursor+=count
        }
    }
    func finish(seconds:Double,isCancelled:()->Bool,publish:()throws->Void) throws {
        guard !ended else{return};ended=true
        guard frameCount>0 else{cancel();throw CirclrError("녹화된 화면이 없습니다")}
        let duration=min(pcm.duration,max(lastSeconds+1/30,seconds))
        let end=CMTime(seconds:duration,preferredTimescale:48_000)
        let limit=min(pcm.count,Int((duration*PCM.rate).rounded()))
        video.markAsFinished()
        let deadline=Date().addingTimeInterval(20)
        do {
            while audioCursor<limit {
                if isCancelled() {throw CancellationError()}
                if writer.status == .failed {throw writer.error ?? CirclrError("영상 인코딩 실패")}
                if Date()>deadline {throw CirclrError("영상 오디오 저장 대기 시간이 지났습니다")}
                try appendAudio(until:limit)
                if audioCursor<limit {Thread.sleep(forTimeInterval:0.005)}
            }
            audio.markAsFinished();writer.endSession(atSourceTime:end)
            let completion=DispatchSemaphore(value:0)
            writer.finishWriting{completion.signal()}
            while completion.wait(timeout:.now()+0.01) == .timedOut {
                if isCancelled() {throw CancellationError()}
                if Date()>deadline {throw CirclrError("영상 인코딩 완료 대기 시간이 지났습니다")}
            }
            if isCancelled() {throw CancellationError()}
            guard writer.status == .completed else{throw writer.error ?? CirclrError("영상을 완성하지 못했습니다")}
            try publish()
        }catch{cancel();throw error}
    }
    func publish() throws {try FileManager.default.moveItem(at:staging,to:url)}
    public func cancel() {
        ended=true
        if writer.status == .writing {writer.cancelWriting()}
        try? FileManager.default.removeItem(at:staging)
    }
}
