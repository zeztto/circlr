import AVFoundation
import CryptoKit
import Foundation

@main struct InspectMovieTiming {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: inspect-movie-timing <file.mp4>\n", stderr)
            exit(2)
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard let videoTrack = video.first else { throw NSError(domain: "MovieTiming", code: 1) }
        var videoHashes: [(pts: Double, index: Int, hash: SHA256.Digest)] = []
        var identicalVideoFrames = 0
        var identicalVideoRun = 0
        var longestIdenticalVideoRun = 0
        var firstIdenticalVideoPTS: [Double] = []
        var checkedVideoFrames = 0
        var videoWidth = 0
        var videoHeight = 0

        func timestamps(_ track: AVAssetTrack) throws -> [Double] {
            let reader = try AVAssetReader(asset: asset)
            // Decode video: compressed H.264 packet count is not display-frame count.
            let settings: [String: Any]? = track.mediaType == .video
                ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA] : nil
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? NSError(domain: "MovieTiming", code: 2) }
            var result: [Double] = []
            while let sample = output.copyNextSampleBuffer() {
                let presentationSeconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                result.append(presentationSeconds)
                if track.mediaType == .video {
                    guard let pixel = CMSampleBufferGetImageBuffer(sample),
                          CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_32BGRA else {
                        throw NSError(domain: "MovieTiming", code: 5)
                    }
                    checkedVideoFrames += 1
                    videoWidth = CVPixelBufferGetWidth(pixel)
                    videoHeight = CVPixelBufferGetHeight(pixel)
                    guard CVPixelBufferLockBaseAddress(pixel, .readOnly) == kCVReturnSuccess else {
                        throw NSError(domain: "MovieTiming", code: 4)
                    }
                    defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
                    guard let base = CVPixelBufferGetBaseAddress(pixel) else {
                        throw NSError(domain: "MovieTiming", code: 4)
                    }
                    let rowBytes = videoWidth * 4
                    let stride = CVPixelBufferGetBytesPerRow(pixel)
                    guard stride >= rowBytes else { throw NSError(domain: "MovieTiming", code: 6) }
                    var visiblePixels = Data(count: rowBytes * videoHeight)
                    visiblePixels.withUnsafeMutableBytes { destination in
                        guard let target = destination.baseAddress else { return }
                        for row in 0..<videoHeight {
                            memcpy(target.advanced(by: row * rowBytes),
                                   base.advanced(by: row * stride), rowBytes)
                        }
                    }
                    videoHashes.append((presentationSeconds, checkedVideoFrames, SHA256.hash(data: visiblePixels)))
                }
            }
            guard reader.status == .completed else { throw reader.error ?? NSError(domain: "MovieTiming", code: 3) }
            return result
        }

        // H.264 B-frames are read in decode order; sort PTS for display cadence.
        let videoPTS = try timestamps(videoTrack).sorted()
        var previousVideoHash: SHA256.Digest?
        for frame in videoHashes.sorted(by: { $0.pts == $1.pts ? $0.index < $1.index : $0.pts < $1.pts }) {
            if frame.hash == previousVideoHash {
                identicalVideoFrames += 1
                identicalVideoRun += 1
                longestIdenticalVideoRun = max(longestIdenticalVideoRun, identicalVideoRun)
                if firstIdenticalVideoPTS.count < 10 { firstIdenticalVideoPTS.append(frame.pts) }
            } else {
                identicalVideoRun = 0
            }
            previousVideoHash = frame.hash
        }
        let audioPTS = try (audio.first.map(timestamps) ?? []).sorted()
        let deltas = zip(videoPTS.dropFirst(), videoPTS).map(-)
        let positiveDeltas = deltas.filter { $0 > 0 && $0.isFinite }.sorted()
        let longestGaps = deltas.enumerated().sorted { $0.element > $1.element }.prefix(5).map { index, gap in
            ["atSeconds": videoPTS[index], "gapMilliseconds": gap * 1000]
        }
        func percentile(_ fraction: Double) -> Double {
            guard !positiveDeltas.isEmpty else { return 0 }
            return positiveDeltas[Int(Double(positiveDeltas.count - 1) * fraction)]
        }
        let report: [String: Any] = [
            "file": url.path,
            "durationSeconds": CMTimeGetSeconds(duration),
            "videoFrames": videoPTS.count,
            "videoContentFramesChecked": checkedVideoFrames,
            "videoWidth": videoWidth,
            "videoHeight": videoHeight,
            "videoFirstPTS": videoPTS.first ?? 0,
            "videoLastPTS": videoPTS.last ?? 0,
            "videoAverageFPS": videoPTS.count > 1 ? Double(videoPTS.count - 1) / max(0.001, (videoPTS.last ?? 0) - (videoPTS.first ?? 0)) : 0,
            "videoDuplicatePTS": deltas.filter { $0 == 0 }.count,
            "videoContentIdenticalAdjacentFrames": identicalVideoFrames,
            "videoContentIdenticalLongestRun": longestIdenticalVideoRun,
            "videoContentIdenticalFirstPTS": firstIdenticalVideoPTS,
            "videoGapsOverTwoFrames": deltas.filter { $0 > 2.0 / 30.0 }.count,
            "videoDeltaP50Milliseconds": percentile(0.50) * 1000,
            "videoDeltaP95Milliseconds": percentile(0.95) * 1000,
            "videoDeltaP99Milliseconds": percentile(0.99) * 1000,
            "videoMaximumGapMilliseconds": (positiveDeltas.last ?? 0) * 1000,
            "videoLongestGaps": longestGaps,
            "audioPackets": audioPTS.count,
            "audioFirstPTS": audioPTS.first ?? 0,
            "audioLastPTS": audioPTS.last ?? 0,
            "startAVOffsetMilliseconds": ((audioPTS.first ?? 0) - (videoPTS.first ?? 0)) * 1000,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
