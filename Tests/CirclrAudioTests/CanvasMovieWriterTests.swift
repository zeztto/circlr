import XCTest
import AVFoundation
import CoreGraphics
import CryptoKit
import Darwin
@testable import CirclrAudio

final class CanvasMovieWriterTests:XCTestCase {
    @MainActor func testAudioEndpointFrameCountMatchesDecodedMovie() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let target=folder.appendingPathComponent("endpoint.mp4")
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:160,height:120),pcm:PCM(frames:48_000))
        let context=CGContext(data:nil,width:160,height:120,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image=context.makeImage()!
        for index in 0...30 {
            try recorder.append(image,seconds:Double(index)/30)
            await recorder.waitUntilIdle()
            try await Task.sleep(for:.milliseconds(20))
        }
        try await recorder.finish(seconds:1)
        let presentation=try await decodedVideoPresentation(at:target)
        XCTAssertEqual(recorder.submittedFrameCount,31)
        XCTAssertEqual(recorder.frameCount,31)
        XCTAssertEqual(recorder.droppedFrames,0)
        XCTAssertEqual(recorder.frameCount,presentation.count)
        XCTAssertEqual(presentation.max() ?? -1,1,accuracy:0.001)
        let duration=try await AVURLAsset(url:target).load(.duration)
        XCTAssertEqual(duration.seconds,1+1/30,accuracy:0.001)
        XCTAssertEqual(try PCM.read(target).duration,1,accuracy:0.001)
    }
    @MainActor func testNearAudioEndpointFrameCountMatchesDecodedMovie() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let target=folder.appendingPathComponent("near-endpoint.mp4")
        // The final 30 fps PTS precedes the PCM end by only 20 audio frames.
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:160,height:120),pcm:PCM(frames:48_020))
        let context=CGContext(data:nil,width:160,height:120,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image=context.makeImage()!
        for index in 0...30 {
            try recorder.append(image,seconds:Double(index)/30)
            await recorder.waitUntilIdle()
            try await Task.sleep(for:.milliseconds(20))
        }
        try await recorder.finish(seconds:48_020.0/PCM.rate)
        let presentation=try await decodedVideoPresentation(at:target)
        XCTAssertEqual(recorder.submittedFrameCount,31)
        XCTAssertEqual(recorder.frameCount,31)
        XCTAssertEqual(recorder.droppedFrames,0)
        XCTAssertEqual(recorder.frameCount,presentation.count)
        XCTAssertEqual(presentation.max() ?? -1,1,accuracy:0.001)
        let duration=try await AVURLAsset(url:target).load(.duration)
        XCTAssertEqual(duration.seconds,1+1/30,accuracy:0.001)
        XCTAssertEqual(try PCM.read(target).duration,48_020.0/PCM.rate,accuracy:0.001)
    }
    @MainActor func testValidFrameTwentyMillisecondsBeforeAudioEndIsPreserved() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let target=folder.appendingPathComponent("valid-tail-frame.mp4")
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:160,height:120),pcm:PCM(frames:48_000))
        let context=CGContext(data:nil,width:160,height:120,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image=context.makeImage()!
        for index in 0..<30 {
            try recorder.append(image,seconds:Double(index)/30)
            await recorder.waitUntilIdle()
            try await Task.sleep(for:.milliseconds(20))
        }
        try recorder.append(image,seconds:0.98)
        await recorder.waitUntilIdle()
        try await recorder.finish(seconds:1)
        let presentation=try await decodedVideoPresentation(at:target)
        XCTAssertEqual(recorder.submittedFrameCount,31)
        XCTAssertEqual(recorder.frameCount,31)
        XCTAssertEqual(presentation.count,31)
        XCTAssertEqual(presentation.max() ?? -1,0.98,accuracy:0.001)
        let duration=try await AVURLAsset(url:target).load(.duration)
        XCTAssertEqual(duration.seconds,1,accuracy:0.001)
        XCTAssertEqual(try PCM.read(target).duration,1,accuracy:0.001)
    }
    @MainActor func testScheduledLoopExitEndpointFrameCountMatchesDecodedMovie() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let target=folder.appendingPathComponent("loop-exit-endpoint.mp4")
        let mix=PCM(frames:18_000)
        let loop=try PlaybackLoopPCM(mix:mix,bodySeconds:0.25)
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:160,height:120),pcm:mix,loop:loop)
        try recorder.scheduleAudio(loop:nil,exitTail:PCM(frames:24_000),atFrame:24_000)
        let context=CGContext(data:nil,width:160,height:120,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image=context.makeImage()!
        for index in 0...30 {
            try recorder.append(image,seconds:Double(index)/30)
            await recorder.waitUntilIdle()
            try await Task.sleep(for:.milliseconds(20))
        }
        try await recorder.finish(seconds:1)
        let presentation=try await decodedVideoPresentation(at:target)
        XCTAssertEqual(recorder.submittedFrameCount,31)
        XCTAssertEqual(recorder.frameCount,31)
        XCTAssertEqual(recorder.droppedFrames,0)
        XCTAssertEqual(presentation.count,recorder.frameCount)
        XCTAssertEqual(presentation.max() ?? -1,1,accuracy:0.001)
        let asset=AVURLAsset(url:target)
        let duration=try await asset.load(.duration)
        XCTAssertEqual(duration.seconds,1+1/30,accuracy:0.001)
        XCTAssertEqual(try PCM.read(target).duration,1,accuracy:0.001)
    }
    @MainActor private func decodedVideoPresentation(at target:URL) async throws -> [Double] {
        let asset=AVURLAsset(url:target)
        let tracks=try await asset.loadTracks(withMediaType:.video)
        let video=try XCTUnwrap(tracks.first)
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:video,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        reader.add(output);XCTAssertTrue(reader.startReading())
        var presentation=[Double]()
        while let sample=output.copyNextSampleBuffer() {
            presentation.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        XCTAssertEqual(reader.status,.completed)
        return presentation
    }
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

    /// Opt-in encoder soak with a separate real-time scheduler diagnostic. It
    /// bypasses AppKit/audio devices and never discards a frame after host delay.
    @MainActor func testTenMinuteFullHDLoopSoak() async throws {
        guard ProcessInfo.processInfo.environment["CIRCLR_MOVIE_SOAK"] == "1" else {
            throw XCTSkip("Set CIRCLR_MOVIE_SOAK=1 for the real-time movie soak")
        }
        let requested=ProcessInfo.processInfo.environment["CIRCLR_MOVIE_SOAK_SECONDS"].flatMap(Double.init) ?? 600
        guard requested.isFinite,requested>=1,requested<=600,
              abs(requested*30-(requested*30).rounded())<0.000_001 else {
            XCTFail("CIRCLR_MOVIE_SOAK_SECONDS must be 1...600 on a 30 fps frame boundary")
            return
        }
        let seconds=Int((requested*30).rounded())
        let duration=Double(seconds)/30
        let fullRun=seconds == 18_000
        let stallSetting=ProcessInfo.processInfo.environment["CIRCLR_MOVIE_SOAK_INJECT_STALL_MS"]
        let injectedStallMilliseconds=stallSetting.flatMap(Int.init) ?? 0
        guard stallSetting == nil || (duration>=2 && duration<=5 && injectedStallMilliseconds>=50 && injectedStallMilliseconds<=500) else {
            XCTFail("Injected stall is only valid for a 2...5 second QA run (50...500 ms)")
            return
        }
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
            .appendingPathComponent("qa/generated/r80-build231-movie-soak",isDirectory:true)
        let folder=root.appendingPathComponent("run-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let free=(try FileManager.default.attributesOfFileSystem(forPath:folder.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free >= (fullRun ? 4_294_967_296:134_217_728) else {
            throw XCTSkip("Insufficient QA disk space for the requested movie soak")
        }
        let target=folder.appendingPathComponent("soak.mp4")
        let logURL=folder.appendingPathComponent("diagnostics.jsonl")
        FileManager.default.createFile(atPath:logURL.path,contents:nil)
        let log=try FileHandle(forWritingTo:logURL)
        defer{try? log.close()}
        var pcm=PCM(frames:48_000)
        for index in 0..<pcm.count {
            let value=Float(sin(Double(index)*2 * .pi*440/PCM.rate))*0.08
            pcm.left[index]=value;pcm.right[index]=value
        }
        let loop=try PlaybackLoopPCM(mix:pcm,bodySeconds:1)
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:1920,height:1080),pcm:pcm,loop:loop)
        defer{recorder.cancel()}
        XCTAssertEqual(recorder.width,1920)
        XCTAssertEqual(recorder.height,1080)
        func image(_ index:Int)->CGImage {
            let context=CGContext(data:nil,width:1920,height:1080,bitsPerComponent:8,bytesPerRow:0,
                                  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray:0.03,alpha:1))
            context.fill(CGRect(x:0,y:0,width:1920,height:1080))
            context.setFillColor(CGColor(gray:1,alpha:1))
            // Fifteen high-contrast bits give each of 18,000 frames a distinct
            // visible marker even after lossy H.264 color quantization.
            for bit in 0..<15 where index & (1<<bit) != 0 {
                context.fill(CGRect(x:30+bit*125,y:360,width:80,height:300))
            }
            return context.makeImage()!
        }
        func residentBytes()->UInt64? {
            var info=mach_task_basic_info_data_t()
            var count=mach_msg_type_number_t(MemoryLayout.size(ofValue:info)/MemoryLayout<natural_t>.size)
            let result:kern_return_t=withUnsafeMutablePointer(to:&info) {
                $0.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {
                    task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count)
                }
            }
            return result == KERN_SUCCESS ? UInt64(info.resident_size):nil
        }
        var stableRSS:UInt64?
        var maximumStableRSS:UInt64=0
        var generatorMilliseconds=[Double]()
        var maximumScheduleLatenessMilliseconds=0.0
        var lateScheduleCount=0
        var encoderWaitCount=0
        var maximumEncoderWaitMilliseconds=0.0
        var injectedStallObserved=false
        func record(_ frame:Int) throws {
            let rss=residentBytes()
            if frame >= 1_800,stableRSS == nil {stableRSS=rss}
            if let rss,stableRSS != nil {maximumStableRSS=max(maximumStableRSS,rss)}
            let data:[String:Any]=[
                "elapsedSeconds":Double(frame)/30,"submitted":recorder.submittedFrameCount,
                "encoded":recorder.frameCount,"skipped":recorder.skippedCaptureCount,
                "dropped":recorder.droppedFrames,"pending":recorder.pendingFrameCount,
                "maximumPending":recorder.maximumPendingFrames,
                "maximumEncodeSeconds":recorder.maximumEncodeSeconds,
                "lastGeneratorMilliseconds":generatorMilliseconds.last ?? 0,
                "maximumGeneratorMilliseconds":generatorMilliseconds.max() ?? 0,
                "maximumScheduleLatenessMilliseconds":maximumScheduleLatenessMilliseconds,
                "lateScheduleCountOverOneFrame":lateScheduleCount,
                "encoderWaitCount":encoderWaitCount,
                "maximumEncoderWaitMilliseconds":maximumEncoderWaitMilliseconds,
                "residentBytes":rss as Any? ?? NSNull()
            ]
            let line=try JSONSerialization.data(withJSONObject:data,options:[.sortedKeys])
            try log.write(contentsOf:line+Data([0x0a]))
        }
        print("Movie soak artifacts: \(folder.path)")
        let openingStarted=ProcessInfo.processInfo.systemUptime
        let opening=image(0)
        generatorMilliseconds.append((ProcessInfo.processInfo.systemUptime-openingStarted)*1000)
        try recorder.append(opening,seconds:0)
        await recorder.waitUntilIdle() // Match the app's prepared opening frame.
        try record(0)
        let started=ProcessInfo.processInfo.systemUptime
        for frame in 1..<seconds {
            try Task.checkCancellation()
            let deadline=started+Double(frame)/30
            let delay=deadline-ProcessInfo.processInfo.systemUptime
            if delay>0 {try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000))}
            if frame == 30 && injectedStallMilliseconds>0 {
                try await Task.sleep(nanoseconds:UInt64(injectedStallMilliseconds)*1_000_000)
                injectedStallObserved=true
            }
            let lateness=max(0,(ProcessInfo.processInfo.systemUptime-deadline)*1000)
            maximumScheduleLatenessMilliseconds=max(maximumScheduleLatenessMilliseconds,lateness)
            if lateness>1000/30 {lateScheduleCount+=1}
            let generationStarted=ProcessInfo.processInfo.systemUptime
            let frameImage=image(frame)
            generatorMilliseconds.append((ProcessInfo.processInfo.systemUptime-generationStarted)*1000)
            if !recorder.canAcceptFrame {
                let waitStarted=ProcessInfo.processInfo.systemUptime
                await recorder.waitUntilIdle()
                maximumEncoderWaitMilliseconds=max(maximumEncoderWaitMilliseconds,
                    (ProcessInfo.processInfo.systemUptime-waitStarted)*1000)
                encoderWaitCount+=1
            }
            // Use the original 30 Hz PTS after a late host wake-up. Catch-up
            // frames exercise encoder continuity, not real-time GUI capture.
            try recorder.append(frameImage,seconds:Double(frame)/30)
            if frame%900 == 0 {try record(frame)}
        }
        await recorder.waitUntilIdle()
        try record(seconds)
        try await recorder.finish(seconds:duration)
        XCTAssertEqual(recorder.submittedFrameCount,seconds)
        XCTAssertEqual(recorder.frameCount,seconds)
        XCTAssertEqual(recorder.skippedCaptureCount,0)
        XCTAssertEqual(recorder.droppedFrames,0)
        XCTAssertEqual(recorder.maximumPendingFrames,1)
        XCTAssertEqual(recorder.pendingFrameCount,0)
        XCTAssertTrue(FileManager.default.fileExists(atPath:target.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:folder.path).contains{$0.hasPrefix(".circlr-movie-")})
        if fullRun {
            XCTAssertNotNil(stableRSS)
            if let stableRSS {
                let growth=maximumStableRSS>stableRSS ? maximumStableRSS-stableRSS:0
                XCTAssertLessThanOrEqual(growth,512*1024*1024,"RSS grew more than 512 MiB after the 60-second warm-up")
            }
        }
        let asset=AVURLAsset(url:target)
        let movieDuration=try await asset.load(.duration).seconds
        XCTAssertEqual(movieDuration,duration,accuracy:0.03)
        let tracks=try await asset.loadTracks(withMediaType:.video)
        let track=try XCTUnwrap(tracks.first)
        let size=try await track.load(.naturalSize)
        XCTAssertEqual(size.width,1920)
        XCTAssertEqual(size.height,1080)
        let audioTracks=try await asset.loadTracks(withMediaType:.audio)
        XCTAssertEqual(audioTracks.count,1)
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let decodeStarted=ProcessInfo.processInfo.systemUptime
        var frames=[(time:Double,hash:SHA256.Digest)]()
        var counterMismatches=0
        var firstCounterMismatches=[[String:Int]]()
        var visible=Data(count:1920*1080*4)
        while let sample=output.copyNextSampleBuffer() {
            let time=CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let pixel=try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            XCTAssertEqual(CVPixelBufferGetWidth(pixel),1920)
            XCTAssertEqual(CVPixelBufferGetHeight(pixel),1080)
            XCTAssertEqual(CVPixelBufferLockBaseAddress(pixel,.readOnly),kCVReturnSuccess)
            defer{CVPixelBufferUnlockBaseAddress(pixel,.readOnly)}
            let bytesPerRow=CVPixelBufferGetBytesPerRow(pixel)
            XCTAssertGreaterThanOrEqual(bytesPerRow,1920*4)
            let base=try XCTUnwrap(CVPixelBufferGetBaseAddress(pixel))
            let bytes=base.assumingMemoryBound(to:UInt8.self)
            var counter=0
            for bit in 0..<15 {
                let offset=540*bytesPerRow+(70+bit*125)*4
                let intensity=Int(bytes[offset])+Int(bytes[offset+1])+Int(bytes[offset+2])
                if intensity>384 {counter |= 1<<bit}
            }
            let expected=Int((time*30).rounded())
            if counter != expected {
                counterMismatches+=1
                if firstCounterMismatches.count<5 {
                    firstCounterMismatches.append(["expected":expected,"decoded":counter])
                }
            }
            visible.withUnsafeMutableBytes { destination in
                for row in 0..<1080 {
                    memcpy(destination.baseAddress!.advanced(by:row*1920*4),
                           base.advanced(by:row*bytesPerRow),1920*4)
                }
            }
            frames.append((time,SHA256.hash(data:visible)))
        }
        let videoDecodeSeconds=ProcessInfo.processInfo.systemUptime-decodeStarted
        XCTAssertEqual(reader.status,.completed)
        let orderedFrames=frames.sorted{$0.time<$1.time}
        let ordered=orderedFrames.map(\.time)
        let identical=zip(orderedFrames.dropFirst(),orderedFrames).filter{$0.hash==$1.hash}.count
        let gaps=zip(ordered.dropFirst(),ordered).map(-)
        let audioTrack=try XCTUnwrap(audioTracks.first)
        let audioReader=try AVAssetReader(asset:asset)
        let audioOutput=AVAssetReaderTrackOutput(track:audioTrack,outputSettings:nil)
        audioReader.add(audioOutput)
        XCTAssertTrue(audioReader.startReading())
        var audioPackets=0,firstAudioPTS:Double?,lastAudioPTS:Double?
        while let sample=audioOutput.copyNextSampleBuffer() {
            let pts=CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if firstAudioPTS == nil {firstAudioPTS=pts}
            lastAudioPTS=pts;audioPackets+=1
        }
        XCTAssertEqual(audioReader.status,.completed)
        let audioDecodeStarted=ProcessInfo.processInfo.systemUptime
        var audioWindows=[[String:Double]]()
        for start in [0.0,duration/2,max(0,duration-1)] {
            let segment=try PCM.read(target,start:start,duration:min(1,duration-start))
            audioWindows.append(["atSeconds":start,"rms":segment.rms,"durationSeconds":segment.duration])
        }
        let audioWindowDecodeSeconds=ProcessInfo.processInfo.systemUptime-audioDecodeStarted
        let movieFile=try FileHandle(forReadingFrom:target)
        defer{try? movieFile.close()}
        var movieHasher=SHA256()
        while let chunk=try movieFile.read(upToCount:1_048_576),!chunk.isEmpty {movieHasher.update(data:chunk)}
        let movieHash=movieHasher.finalize()
        let sortedGeneration=generatorMilliseconds.sorted()
        let generatorP95=sortedGeneration[Int(Double(sortedGeneration.count-1)*0.95)]
        let memoryStable = !fullRun || (stableRSS.map {maximumStableRSS <= $0+512*1024*1024} ?? false)
        let writerIntegrityPass = recorder.submittedFrameCount == seconds && recorder.frameCount == seconds &&
            recorder.skippedCaptureCount == 0 && recorder.droppedFrames == 0 && recorder.maximumPendingFrames == 1 &&
            recorder.pendingFrameCount == 0 && ordered.count == seconds &&
            gaps.allSatisfy{$0>0 && $0<=2.0/30.0+0.000_001} && identical == 0 && counterMismatches == 0 &&
            abs(movieDuration-duration)<=0.03 && size.width == 1920 && size.height == 1080 &&
            audioPackets>0 && abs((firstAudioPTS ?? -1))<=0.025 &&
            (lastAudioPTS ?? -1)>=duration-0.1 &&
            audioWindows.allSatisfy{($0["rms"] ?? 0)>0.001} && memoryStable
        let schedulerStatus = lateScheduleCount == 0 ? "pass":"fail"
        let inspection:[String:Any]=[
            "schema":"circlr-movie-soak-v1","requestedSeconds":duration,
            "writerIntegrityStatus":writerIntegrityPass ? "pass":"fail",
            "realtimeSchedulerStatus":schedulerStatus,
            "injectedStallAtFrame":injectedStallMilliseconds>0 ? 30:0,
            "injectedStallMilliseconds":injectedStallMilliseconds,
            "injectedStallObserved":injectedStallObserved,
            "movieSHA256":movieHash.map{String(format:"%02x",$0)}.joined(),
            "movieBytes":(try FileManager.default.attributesOfItem(atPath:target.path)[.size] as? NSNumber)?.int64Value ?? 0,
            "movieDurationSeconds":movieDuration,"width":size.width,"height":size.height,
            "submittedFrames":recorder.submittedFrameCount,"encodedFrames":recorder.frameCount,
            "decodedVideoFrames":ordered.count,"skippedCaptures":recorder.skippedCaptureCount,
            "droppedFrames":recorder.droppedFrames,"maximumPendingFrames":recorder.maximumPendingFrames,
            "maximumEncodeSeconds":recorder.maximumEncodeSeconds,
            "generatorP95Milliseconds":generatorP95,
            "generatorMaximumMilliseconds":sortedGeneration.last ?? 0,
            "maximumScheduleLatenessMilliseconds":maximumScheduleLatenessMilliseconds,
            "lateScheduleCountOverOneFrame":lateScheduleCount,
            "encoderWaitCount":encoderWaitCount,
            "maximumEncoderWaitMilliseconds":maximumEncoderWaitMilliseconds,
            "fullPixelVideoDecodeSeconds":videoDecodeSeconds,
            "threeAudioWindowDecodeSeconds":audioWindowDecodeSeconds,
            "duplicateOrBackwardsPTS":gaps.filter{$0<=0}.count,
            "gapsOverTwoFrames":gaps.filter{$0>2.0/30.0+0.000_001}.count,
            "maximumVideoGapMilliseconds":(gaps.max() ?? 0)*1000,
            "identicalAdjacentPresentationFrames":identical,
            "counterMismatches":counterMismatches,
            "firstCounterMismatches":firstCounterMismatches,
            "firstVideoPTS":ordered.first ?? -1,"lastVideoPTS":ordered.last ?? -1,
            "audioPackets":audioPackets,"firstAudioPTS":firstAudioPTS ?? -1,
            "lastAudioPTS":lastAudioPTS ?? -1,
            "startAVOffsetMilliseconds":((firstAudioPTS ?? -1)-(ordered.first ?? -1))*1000,
            "audioWindows":audioWindows,"stableResidentBytes":stableRSS as Any? ?? NSNull(),
            "maximumStableResidentBytes":maximumStableRSS
        ]
        let inspectionData=try JSONSerialization.data(withJSONObject:inspection,options:[.prettyPrinted,.sortedKeys])
        try inspectionData.write(to:folder.appendingPathComponent("inspection.json"),options:.atomic)
        XCTAssertTrue(writerIntegrityPass,"Device-free writer integrity failed; inspect inspection.json")
        if injectedStallMilliseconds>0 {
            XCTAssertTrue(injectedStallObserved)
            XCTAssertEqual(schedulerStatus,"fail","The injected host stall must remain visible as a scheduler failure")
        }
        XCTAssertEqual(ordered.count,recorder.frameCount)
        XCTAssertEqual(ordered.count,seconds)
        XCTAssertEqual(gaps.filter{$0<=0}.count,0)
        XCTAssertEqual(gaps.filter{$0>2.0/30.0+0.000_001}.count,0)
        XCTAssertEqual(identical,0)
        XCTAssertEqual(counterMismatches,0,"Decoded visual counter does not match its presentation frame")
        XCTAssertEqual(ordered.first ?? -1,0,accuracy:0.001)
        XCTAssertGreaterThanOrEqual(ordered.last ?? -1,duration-1.0/30.0-0.002)
        XCTAssertGreaterThan(audioPackets,0)
        XCTAssertEqual(firstAudioPTS ?? -1,0,accuracy:0.025)
        XCTAssertGreaterThanOrEqual(lastAudioPTS ?? -1,duration-0.1)
        for window in audioWindows {
            XCTAssertGreaterThan(window["rms"] ?? 0,0.001,"AAC is silent near \(window["atSeconds"] ?? -1)s")
        }
        print("Movie soak inspection: \(folder.path), \(ordered.count) decoded frames, RSS baseline \(stableRSS.map(String.init) ?? "n/a")")
    }
}
