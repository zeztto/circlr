import XCTest
import AVFoundation
import CoreGraphics
@testable import CirclrAudio

final class CanvasMovieWriterTests:XCTestCase {
    @MainActor func testCanvasMovieContainsVideoAndSynchronizedAudio() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        var pcm=PCM(frames:48_000)
        for i in 0..<pcm.count {pcm.left[i]=Float(sin(Double(i)*2 * .pi*440/48_000))*0.1;pcm.right[i]=pcm.left[i]}
        let target=folder.appendingPathComponent("capture.mp4")
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:320,height:240),pcm:pcm)
        let context=CGContext(data:nil,width:320,height:240,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        for frame in 0..<15 {
            context.setFillColor(CGColor(red:CGFloat(frame)/15,green:0.2,blue:0.4,alpha:1));context.fill(CGRect(x:0,y:0,width:320,height:240))
            try recorder.append(context.makeImage()!,seconds:Double(frame)/30)
            await recorder.waitUntilIdle()
            try await Task.sleep(for:.milliseconds(4))
        }
        try await recorder.finish(seconds:0.5)
        let asset=AVURLAsset(url:target)
        let video=try await asset.loadTracks(withMediaType:.video)
        let audio=try await asset.loadTracks(withMediaType:.audio)
        XCTAssertEqual(video.count,1);XCTAssertEqual(audio.count,1)
        let duration=try await asset.load(.duration)
        XCTAssertEqual(duration.seconds,0.5,accuracy:0.04)
        let size=try await video[0].load(.naturalSize)
        XCTAssertEqual(size.width,320);XCTAssertEqual(size.height,240)
        XCTAssertGreaterThan(recorder.frameCount,1)
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:video[0],outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        reader.add(output);XCTAssertTrue(reader.startReading())
        var times:[Double]=[]
        while let sample=output.copyNextSampleBuffer() {times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)}
        // H.264 samples can be delivered in decode order; presentation order is the visual timeline.
        let presentation=times.sorted()
        XCTAssertEqual(presentation.count,recorder.frameCount)
        XCTAssertEqual(presentation.first ?? -1,0,accuracy:0.001)
        XCTAssertTrue(zip(presentation,presentation.dropFirst()).allSatisfy{$0<$1})
        XCTAssertEqual(recorder.pendingFrameCount,0)
        let generator=AVAssetImageGenerator(asset:asset)
        generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
        func red(at seconds:Double) throws -> UInt8 {
            let image=try generator.copyCGImage(at:CMTime(seconds:seconds,preferredTimescale:30),actualTime:nil)
            let pixel=CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            pixel.draw(image,in:CGRect(x:0,y:0,width:1,height:1));return pixel.data!.load(as:UInt8.self)
        }
        XCTAssertGreaterThan(try Int(red(at:0.3))-Int(red(at:0)),80)
        let decoded=try PCM.read(target)
        XCTAssertGreaterThan(decoded.rms,0.01)
        XCTAssertThrowsError(try CanvasMovieWriter(url:target,size:size,pcm:pcm))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:folder.path).contains(where:{$0.hasPrefix(".circlr-movie")}))
    }
    @MainActor func testLoopMovieRetainsAudioAndMonotonicVideoAcrossThreeCycles() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        var mix=PCM(frames:18_000)
        for i in 0..<mix.count {
            mix.left[i]=Float(sin(Double(i)*2 * .pi*440/PCM.rate))*0.08
            mix.right[i]=mix.left[i]
        }
        let loop=try PlaybackLoopPCM(mix:mix,bodySeconds:0.25)
        let target=folder.appendingPathComponent("three-cycles.mp4")
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:160,height:120),pcm:mix,loop:loop)
        let context=CGContext(data:nil,width:160,height:120,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image=context.makeImage()!
        for frame in 0..<30 {
            try recorder.append(image,seconds:Double(frame)/30)
            await recorder.waitUntilIdle()
            try await Task.sleep(for:.milliseconds(4))
        }
        try await recorder.finish(seconds:1)
        XCTAssertGreaterThan(recorder.lastSeconds,loop.duration*3)
        XCTAssertEqual(recorder.maximumPendingFrames,1)
        let asset=AVURLAsset(url:target)
        let duration=try await asset.load(.duration)
        XCTAssertEqual(duration.seconds,1,accuracy:0.025)
        let video=try await asset.loadTracks(withMediaType:.video)
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:try XCTUnwrap(video.first),outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        reader.add(output);XCTAssertTrue(reader.startReading())
        var times=[Double]()
        while let sample=output.copyNextSampleBuffer() {times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)}
        let ordered=times.sorted()
        // Decode H.264 to presentation frames: compressed reader also returns preroll/
        // dependency packets and no-display markers, which are not displayed frames.
        XCTAssertEqual(reader.status,.completed)
        XCTAssertEqual(times.count,recorder.frameCount)
        XCTAssertTrue(times.allSatisfy(\.isFinite))
        XCTAssertEqual(ordered.first ?? -1,0,accuracy:0.001)
        XCTAssertTrue(zip(ordered,ordered.dropFirst()).allSatisfy{$0<$1})
        XCTAssertGreaterThan(ordered.last ?? 0,0.9)
        let decoded=try PCM.read(target)
        XCTAssertEqual(decoded.duration,1,accuracy:0.025)
        // Lossy AAC is compared to the actual circular steady-state source, not the raw mix.
        for cycle in 0..<4 {
            let start=cycle*loop.bodyFrames+1_000,end=(cycle+1)*loop.bodyFrames-1_000
            var squared=0.0,energy=0.0
            for i in start..<min(end,decoded.count) {
                let actual=Double(decoded.left[i]),expected=Double(loop.cycle.left[i % loop.bodyFrames])
                squared+=(actual-expected)*(actual-expected);energy+=actual*actual
            }
            print("Loop AAC cycle \(cycle): RMSE=\(sqrt(squared/Double(end-start))) RMS=\(sqrt(energy/Double(end-start)))")
            XCTAssertLessThan(sqrt(squared/Double(end-start)),0.025)
            XCTAssertGreaterThan(sqrt(energy/Double(end-start)),0.05)
        }
    }
    @MainActor func testScheduledLoopReplacementAndExitTailMatchDecodedMovie() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        func source(_ frequency:Double) throws->PlaybackLoopPCM {
            var mix=PCM(frames:18_000)
            for i in 0..<mix.count {mix.left[i]=Float(sin(Double(i)*2 * .pi*frequency/PCM.rate))*0.08;mix.right[i]=mix.left[i]}
            return try PlaybackLoopPCM(mix:mix,bodySeconds:0.25)
        }
        let first=try source(440),second=try source(880)
        let target=folder.appendingPathComponent("boundaries.mp4")
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:160,height:120),pcm:first.cycle,loop:first)
        let context=CGContext(data:nil,width:160,height:120,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image=context.makeImage()!
        try recorder.scheduleAudio(loop:second,exitTail:nil,atFrame:24_000)
        for frame in 0..<24 {
            try recorder.append(image,seconds:Double(frame)/30);await recorder.waitUntilIdle()
            try await Task.sleep(for:.milliseconds(4))
        }
        XCTAssertThrowsError(try recorder.scheduleAudio(loop:first,exitTail:nil,atFrame:0))
        try recorder.scheduleAudio(loop:nil,exitTail:second.exitTail,atFrame:60_000)
        for frame in 24..<42 {
            try recorder.append(image,seconds:Double(frame)/30);await recorder.waitUntilIdle()
            try await Task.sleep(for:.milliseconds(4))
        }
        try await recorder.finish(seconds:1.4)
        let decoded=try PCM.read(target)
        let expectedDuration=1.25+second.exitTail.duration
        XCTAssertEqual(decoded.duration,expectedDuration,accuracy:0.025)
        func check(start:Int,end:Int,source:PCM,origin:Int,repeating:Bool) {
            XCTAssertGreaterThanOrEqual(decoded.count,end)
            var error=0.0,energy=0.0
            for i in start..<min(end,decoded.count) {
                let offset=i-origin,index=repeating ? offset % source.count:offset
                let actual=Double(decoded.left[i]),expected=Double(source.left[index])
                error+=(actual-expected)*(actual-expected);energy+=actual*actual
            }
            XCTAssertLessThan(sqrt(error/Double(end-start)),0.025)
            XCTAssertGreaterThan(sqrt(energy/Double(end-start)),0.03)
        }
        check(start:2000,end:22000,source:first.cycle,origin:0,repeating:true)
        check(start:26000,end:58000,source:second.cycle,origin:24000,repeating:true)
        check(start:61000,end:65000,source:second.exitTail,origin:60000,repeating:false)
    }
    @MainActor func testBurstHasBoundedMemoryAndDrainsBeforeFinish() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let target=folder.appendingPathComponent("burst.mp4")
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:320,height:240),pcm:PCM(frames:48000))
        let context=CGContext(data:nil,width:320,height:240,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image=context.makeImage()!
        for frame in 0..<300 {try recorder.append(image,seconds:Double(frame)/300)}
        XCTAssertEqual(recorder.submittedFrameCount+recorder.skippedCaptureCount,300)
        XCTAssertEqual(recorder.maximumPendingFrames,1)
        XCTAssertLessThanOrEqual(recorder.pendingFrameCount,1)
        try await recorder.finish(seconds:1)
        XCTAssertEqual(recorder.pendingFrameCount,0)
        XCTAssertGreaterThan(recorder.frameCount,0)
        XCTAssertLessThanOrEqual(recorder.frameCount,recorder.submittedFrameCount)
        XCTAssertFalse(recorder.canAcceptFrame)
        let asset=AVURLAsset(url:target)
        let duration=try await asset.load(.duration)
        XCTAssertEqual(duration.seconds,1,accuracy:0.04)
        let framesBefore=recorder.frameCount
        try recorder.append(image,seconds:2)
        await recorder.waitUntilIdle()
        XCTAssertEqual(recorder.frameCount,framesBefore)
    }
    @MainActor func testCancelQueuedFrameNeverPublishesLateFile() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let target=folder.appendingPathComponent("cancel-queued.mp4")
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:320,height:240),pcm:PCM(frames:48000))
        let context=CGContext(data:nil,width:320,height:240,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        try recorder.append(context.makeImage()!,seconds:0)
        XCTAssertEqual(recorder.submittedFrameCount,1)
        recorder.cancel()
        try await recorder.finish(seconds:1)
        await recorder.waitUntilIdle()
        XCTAssertFalse(recorder.canAcceptFrame)
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:folder.path).isEmpty)
    }
    @MainActor func testCancelAfterOpeningFrameEncodedNeverPublishesPreparationMovie() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let target=folder.appendingPathComponent("cancel-preparation.mp4")
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:320,height:240),pcm:PCM(frames:48_000))
        let context=CGContext(data:nil,width:320,height:240,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        try recorder.append(context.makeImage()!,seconds:0)
        await recorder.waitUntilIdle()
        XCTAssertEqual(recorder.frameCount,1)
        recorder.cancel()
        await recorder.waitUntilIdle()
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:folder.path).isEmpty)
    }
    @MainActor func testCancellationLeavesNoFinalMovie() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let target=folder.appendingPathComponent("cancel.mp4")
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:320,height:240),pcm:PCM(frames:4800))
        recorder.cancel()
        await recorder.waitUntilIdle()
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:folder.path).isEmpty)
    }
}
