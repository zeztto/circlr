import AVFoundation
import CryptoKit
import Foundation

/// Decode the visible fifteen-bit counter used only by the movie writer soak.
@main struct InspectMovieSoakCounter {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: inspect-movie-soak-counter <soak.mp4>\n",stderr)
            exit(2)
        }
        let url=URL(fileURLWithPath:CommandLine.arguments[1])
        let asset=AVURLAsset(url:url)
        guard let track=try await asset.loadTracks(withMediaType:.video).first else {
            throw NSError(domain:"MovieSoakCounter",code:1)
        }
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[
            kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        guard reader.startReading() else {throw reader.error ?? NSError(domain:"MovieSoakCounter",code:2)}
        var decoded=0,mismatches=0
        var examples=[[String:Int]]()
        while let sample=output.copyNextSampleBuffer() {
            guard let pixel=CMSampleBufferGetImageBuffer(sample),
                  CVPixelBufferGetWidth(pixel)==1920,CVPixelBufferGetHeight(pixel)==1080,
                  CVPixelBufferLockBaseAddress(pixel,.readOnly)==kCVReturnSuccess else {
                throw NSError(domain:"MovieSoakCounter",code:3)
            }
            defer{CVPixelBufferUnlockBaseAddress(pixel,.readOnly)}
            guard let base=CVPixelBufferGetBaseAddress(pixel) else {
                throw NSError(domain:"MovieSoakCounter",code:4)
            }
            let bytes=base.assumingMemoryBound(to:UInt8.self)
            let stride=CVPixelBufferGetBytesPerRow(pixel)
            guard stride>=1920*4 else {throw NSError(domain:"MovieSoakCounter",code:5)}
            var counter=0
            for bit in 0..<15 {
                let offset=540*stride+(70+bit*125)*4
                let intensity=Int(bytes[offset])+Int(bytes[offset+1])+Int(bytes[offset+2])
                if intensity>384 {counter |= 1<<bit}
            }
            let expected=Int((CMSampleBufferGetPresentationTimeStamp(sample).seconds*30).rounded())
            if counter != expected {
                mismatches+=1
                if examples.count<5 {examples.append(["expected":expected,"decoded":counter])}
            }
            decoded+=1
        }
        guard reader.status == .completed else {throw reader.error ?? NSError(domain:"MovieSoakCounter",code:6)}
        let handle=try FileHandle(forReadingFrom:url)
        defer{try? handle.close()}
        var hash=SHA256()
        while let data=try handle.read(upToCount:1_048_576),!data.isEmpty {hash.update(data:data)}
        let result:[String:Any]=[
            "schema":"circlr-movie-soak-counter-v1",
            "movieSHA256":hash.finalize().map{String(format:"%02x",$0)}.joined(),
            "decodedFrames":decoded,"counterMismatches":mismatches,
            "firstCounterMismatches":examples
        ]
        let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
        if mismatches>0 {exit(1)}
    }
}
