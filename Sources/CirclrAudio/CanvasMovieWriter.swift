import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
import CirclrCore

/// Records caller-supplied canvas frames alongside the same prepared PCM used for playback.
/// All calls belong to one actor; file/codec work never enters the audio render callback.
@MainActor public final class CanvasMovieWriter {
    public let url:URL
    public let width:Int
    public let height:Int
    public private(set) var frameCount=0
    public private(set) var droppedFrames=0
    public private(set) var lastSeconds=0.0
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
    public func finish(seconds:Double) async throws {
        guard !ended else{return};ended=true
        guard frameCount>0 else{cancel();throw CirclrError("녹화된 화면이 없습니다")}
        let duration=min(pcm.duration,max(lastSeconds+1/30,seconds))
        let end=CMTime(seconds:duration,preferredTimescale:48_000)
        let limit=min(pcm.count,Int((duration*PCM.rate).rounded()))
        video.markAsFinished()
        let deadline=Date().addingTimeInterval(20)
        do {
            while audioCursor<limit {
                try Task.checkCancellation()
                if writer.status == .failed {throw writer.error ?? CirclrError("영상 인코딩 실패")}
                if Date()>deadline {throw CirclrError("영상 오디오 저장 대기 시간이 지났습니다")}
                try appendAudio(until:limit)
                if audioCursor<limit {try await Task.sleep(for:.milliseconds(5))}
            }
            audio.markAsFinished();writer.endSession(atSourceTime:end)
            await writer.finishWriting()
            guard writer.status == .completed else{throw writer.error ?? CirclrError("영상을 완성하지 못했습니다")}
            try FileManager.default.moveItem(at:staging,to:url)
        }catch{cancel();throw error}
    }
    public func cancel() {
        ended=true
        if writer.status == .writing {writer.cancelWriting()}
        try? FileManager.default.removeItem(at:staging)
    }
}
