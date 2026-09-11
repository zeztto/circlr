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

    /// Independent buses must not cancel each other in a node's activity meter.
    mutating func formPeakUnion(_ other: Self) {
        duration = max(duration, other.duration)
        if peaks.count < other.peaks.count { peaks += repeatElement(0, count: other.peaks.count-peaks.count) }
        for i in other.peaks.indices { peaks[i] = max(peaks[i], other.peaks[i]) }
    }
}

public struct OccurrenceVisualization {
    public var nodes: [ID: PlaybackEnvelope] = [:]
    public var ports: [MusicBusEndpoint: PlaybackEnvelope] = [:]
    public var connections: [ID: MusicBusConnection] = [:]
    public var section: PlaybackEnvelope?
    public init() {}

    /// Level on this logical cable, after its gain and before downstream processing.
    public func edgeLevel(_ id: ID, at seconds: Double) -> Double {
        guard let edge = connections[id], let envelope = ports[edge.from] else { return 0 }
        return envelope.level(at: seconds) * edge.gain
    }

    mutating func observe(_ endpoint: MusicBusEndpoint, envelope: PlaybackEnvelope) {
        ports[endpoint] = envelope
        if nodes[endpoint.nodeID] == nil { nodes[endpoint.nodeID] = envelope }
        else { nodes[endpoint.nodeID]?.formPeakUnion(envelope) }
    }
}

public struct PlaybackSignalPaths {
    public var nodes: Set<ID> = []
    public var outputs: Set<MusicBusEndpoint> = []
    public var connections: [ID: MusicBusConnection] = [:]
}

public struct PlaybackAnalysis {
    public var occurrences: [ID: OccurrenceVisualization] = [:]
    public var signals: [ID: PlaybackEnvelope] = [:]
    public var master: PlaybackEnvelope?
    public init() {}

    /// Use the original connection addresses even when the canvas folds them into groups.
    public func edgeLevel(_ connection: CircleConnectionID, at seconds: Double, plan: ExecutionPlan, tail: Double) -> Double {
        guard seconds.isFinite,
              case .music(let arrangement, let use, let from) = connection.from,
              case .music(let targetArrangement, let targetUse, let to) = connection.to,
              arrangement == targetArrangement, use == targetUse else { return 0 }
        var level = 0.0
        for occurrence in plan.occurrences where occurrence.use.id == use && occurrence.start <= seconds && seconds < occurrence.end+tail {
            guard let data = occurrences[occurrence.id], let edge = data.connections[connection.edgeID],
                  edge.from.nodeID == from, edge.to.nodeID == to else { continue }
            level = max(level, data.edgeLevel(connection.edgeID, at: seconds-occurrence.start)*occurrence.use.gain)
        }
        return level
    }

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
        audiblePaths(plan, tracks: tracks).nodes
    }

    /// Walk ports, not just nodes: reaching OUT 1 does not activate an unrelated IN 2.
    public static func audiblePaths(_ plan: SectionSignalPlan, tracks: [Track]) -> PlaybackSignalPaths {
        let nodes = Dictionary(uniqueKeysWithValues: plan.orderedNodes.map { ($0.id, $0) })
        let incoming = Dictionary(grouping: plan.connections, by: \.to)
        let audibleTracks = Set(tracks.filter { !$0.muted && $0.gain > 0 }.map(\.id))
        var frontier = plan.orderedNodes.compactMap { node -> MusicBusEndpoint? in
            if case .output(let track) = node.content, audibleTracks.contains(track) {
                return .init(nodeID: node.id, portID: CirclePort.audioInput)
            }
            return nil
        }
        var visited = Set<MusicBusEndpoint>(), result = PlaybackSignalPaths()
        while let endpoint = frontier.popLast() {
            guard let node = nodes[endpoint.nodeID], !node.muted, node.gain > 0,
                  visited.insert(endpoint).inserted,
                  let port = CirclePort.ports(for: node.content).first(where: { $0.id == endpoint.portID }) else { continue }
            result.nodes.insert(node.id)
            if port.direction == .input {
                for edge in incoming[endpoint] ?? [] where edge.gain > 0 {
                    guard let source = nodes[edge.from.nodeID], !source.muted, source.gain > 0 else { continue }
                    result.connections[edge.id] = edge
                    frontier.append(edge.from)
                }
            } else {
                result.outputs.insert(endpoint)
                if case .router(let router) = node.content {
                    frontier += router.routes.filter { $0.output == endpoint.portID && $0.gain > 0 }
                        .map { .init(nodeID: node.id, portID: $0.input) }
                } else {
                    frontier += CirclePort.ports(for: node.content).filter { $0.direction == .input }
                        .map { .init(nodeID: node.id, portID: $0.id) }
                }
            }
        }
        return result
    }

    /// Conservative envelope storage bound; fan-out cables share their source envelope.
    static func estimatedBytes(plan: ExecutionPlan, signal: SignalGraph, tail: Double) -> Double {
        let floatBytes = Double(MemoryLayout<Float>.stride)
        var bytes = ceil((plan.duration+tail)*PlaybackEnvelope.rate) * floatBytes * Double(signal.nodes.count)
        for occurrence in plan.occurrences {
            let nodes = occurrence.signalPlan?.orderedNodes ?? []
            let ports = nodes.reduce(0) { count, node in
                count + CirclePort.ports(for: node.content).filter { $0.direction == .output }.count
            }
            bytes += ceil((occurrence.duration+tail)*PlaybackEnvelope.rate) * floatBytes * Double(nodes.count+ports+1)
        }
        return bytes
    }
}
