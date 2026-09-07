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
    @MainActor func testCancellationLeavesNoFinalMovie() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let target=folder.appendingPathComponent("cancel.mp4")
        let recorder=try CanvasMovieWriter(url:target,size:CGSize(width:320,height:240),pcm:PCM(frames:4800))
        recorder.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:folder.path).isEmpty)
    }
}
