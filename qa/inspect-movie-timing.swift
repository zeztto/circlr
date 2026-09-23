import AVFoundation
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

        func timestamps(_ track: AVAssetTrack) throws -> [Double] {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? NSError(domain: "MovieTiming", code: 2) }
            var result: [Double] = []
            while let sample = output.copyNextSampleBuffer() {
                result.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)))
            }
            guard reader.status == .completed else { throw reader.error ?? NSError(domain: "MovieTiming", code: 3) }
            return result
        }

        // H.264 B-frames are read in decode order; sort PTS for display cadence.
        let videoPTS = try timestamps(videoTrack).sorted()
        let audioPTS = try (audio.first.map(timestamps) ?? []).sorted()
        let deltas = zip(videoPTS.dropFirst(), videoPTS).map(-)
        let positiveDeltas = deltas.filter { $0 > 0 && $0.isFinite }.sorted()
        func percentile(_ fraction: Double) -> Double {
            guard !positiveDeltas.isEmpty else { return 0 }
            return positiveDeltas[Int(Double(positiveDeltas.count - 1) * fraction)]
        }
        let report: [String: Any] = [
            "file": url.path,
            "durationSeconds": CMTimeGetSeconds(duration),
            "videoFrames": videoPTS.count,
            "videoFirstPTS": videoPTS.first ?? 0,
            "videoLastPTS": videoPTS.last ?? 0,
            "videoNominalFPS": videoPTS.count > 1 ? Double(videoPTS.count - 1) / max(0.001, (videoPTS.last ?? 0) - (videoPTS.first ?? 0)) : 0,
            "videoDuplicatePTS": deltas.filter { $0 == 0 }.count,
            "videoGapsOverTwoFrames": deltas.filter { $0 > 2.0 / 30.0 }.count,
            "videoDeltaP50Milliseconds": percentile(0.50) * 1000,
            "videoDeltaP95Milliseconds": percentile(0.95) * 1000,
            "videoDeltaP99Milliseconds": percentile(0.99) * 1000,
            "videoMaximumGapMilliseconds": (positiveDeltas.last ?? 0) * 1000,
            "audioPackets": audioPTS.count,
            "audioFirstPTS": audioPTS.first ?? 0,
            "audioLastPTS": audioPTS.last ?? 0,
            "startAVOffsetMilliseconds": ((audioPTS.first ?? 0) - (videoPTS.first ?? 0)) * 1000,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
