import Foundation
import Accelerate
import CirclrCore

/// Small immutable readouts of the rendered signal; never work on the audio callback.
public struct PlaybackEnvelope {
    public static let rate = 60.0
    public var peaks: [Float]
    public var duration: Double
    public init(_ pcm: PCM) {
        duration = pcm.duration
        let stride = Int(PCM.rate / Self.rate)
        peaks = [Float](repeating: 0, count: (pcm.count+stride-1)/stride)
        pcm.left.withUnsafeBufferPointer { left in
            pcm.right.withUnsafeBufferPointer { right in
                guard let l = left.baseAddress, let r = right.baseAddress else { return }
                for index in peaks.indices {
                    let offset = index*stride, count = vDSP_Length(min(stride, pcm.count-offset))
                    var a: Float = 0, b: Float = 0
                    vDSP_maxmgv(l+offset, 1, &a, count); vDSP_maxmgv(r+offset, 1, &b, count)
                    peaks[index] = max(a, b)
                }
            }
        }
    }
    public init(notes: [Note], clock: MusicClock) {
        duration = clock.seconds
        peaks = [Float](repeating: 0, count: Int(ceil(duration*Self.rate)))
        for note in notes where note.velocity > 0 {
            let start = max(0, Int(floor(clock.seconds(at: note.beat)*Self.rate)))
            let end = min(peaks.count, Int(ceil(clock.seconds(at: note.beat+note.length)*Self.rate)))
            if start < end { for i in start..<end { peaks[i] = max(peaks[i], Float(note.velocity)/127) } }
        }
    }
    public func level(at seconds: Double) -> Double {
        guard seconds.isFinite, seconds >= 0, seconds < duration else { return 0 }
        let index = min(peaks.count-1, Int(seconds*Self.rate))
        return index >= 0 ? Double(peaks[index]) : 0
    }
}

public struct OccurrenceVisualization {
    public var nodes: [ID: PlaybackEnvelope] = [:]
    public var section: PlaybackEnvelope?
    public init() {}
}

public struct PlaybackAnalysis {
    public var occurrences: [ID: OccurrenceVisualization] = [:]
    public var signals: [ID: PlaybackEnvelope] = [:]
    public var master: PlaybackEnvelope?
    public init() {}

    public static func connectedSignals(_ graph: SignalGraph) -> Set<ID> {
        var frontier = graph.nodes.filter { $0.kind == .master }.map(\.id), result = Set<ID>()
        while let id = frontier.popLast() {
            guard result.insert(id).inserted else { continue }
            frontier += graph.edges.filter { $0.to == id && $0.gain > 0 }.map(\.from)
        }
        return result
    }

    /// Exclude storage branches and paths silenced before reaching an audible track output.
    public static func audibleNodes(_ plan: SectionSignalPlan, tracks: [Track]) -> Set<ID> {
        let nodes = Dictionary(uniqueKeysWithValues: plan.orderedNodes.map { ($0.id, $0) })
        let audibleTracks = Set(tracks.filter { !$0.muted && $0.gain > 0 }.map(\.id))
        var frontier = plan.orderedNodes.compactMap { node -> ID? in
            if case .output(let track) = node.content, audibleTracks.contains(track) { return node.id }
            return nil
        }
        var result = Set<ID>()
        while let id = frontier.popLast() {
            guard let node = nodes[id], !node.muted, node.gain > 0, result.insert(id).inserted else { continue }
            frontier += plan.graph.edges.filter { $0.to == id && $0.gain > 0 }.map(\.from)
        }
        return result
    }
}
