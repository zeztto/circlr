import Foundation
import CirclrCore

public struct TailPlan: Codable, Equatable {
    public let requestedSeconds: Double?
    public let estimatedSeconds: Double
    public let effectiveSeconds: Double
    public let notices: [String]
}

/// Relative -80 dB decay estimates, not a guarantee of silence or lossless tails.
public enum RenderTailPlanner {
    public static let maximumTailSeconds: Double = 120
    private static let attenuation = 0.0001
    private struct Extent {
        var seconds = 0.0
        var preserved = 0.0
        var notices: [String] = []
        mutating func include(_ other: Self) {
            seconds = max(seconds, other.seconds); preserved = max(preserved, other.preserved)
            notices += other.notices
        }
    }

    public static func section(_ plan: SectionSignalPlan, project: Project, clock: MusicClock,
                               trackID: ID? = nil, requestedSeconds: Double? = nil) throws -> TailPlan {
        try validateRequest(requestedSeconds)
        let outputs = try sectionExtents(plan, project: project, clock: clock)
        var extent = Extent()
        if let trackID {
            guard let selected = outputs[trackID] else { throw CirclrError("잔향을 계산할 트랙 출력을 찾을 수 없습니다") }
            extent = selected
        } else { for value in outputs.values { extent.include(value) } }
        let result = try resolve(extent, requestedSeconds: requestedSeconds)
        let frames = try frameCount(bodySeconds: clock.seconds, tailSeconds: result.effectiveSeconds)
        guard Double(frames) * 8 * Double(SectionGraphRenderer.workingBufferCount(plan)) < 1_073_741_824 else {
            throw CirclrError("섹션 내부 오디오가 준비 가능한 메모리 범위를 넘습니다")
        }
        return result
    }

    public static func arrangement(project: Project, plan: ExecutionPlan, requestedSeconds: Double? = nil,
                                   includeStems: Bool = true, includeVisualization: Bool = false) throws -> TailPlan {
        try validateRequest(requestedSeconds)
        var tracks: [ID: Extent] = [:]
        for occurrence in plan.occurrences {
            var local: [ID: Extent]
            if let graph = occurrence.signalPlan {
                local = try sectionExtents(graph, project: project, clock: occurrence.clock)
            } else {
                local = [:]
                var effectiveLanes = occurrence.lanes
                if let patternID = occurrence.context.rhythm.patternID, let pattern = project.patterns.first(where: { $0.id == patternID }) {
                    effectiveLanes.append(ArrangementRenderer.expandPattern(pattern, length: occurrence.clock.beats, grid: occurrence.context.beatGrid))
                }
                for track in project.tracks {
                    let lanes = effectiveLanes.filter { $0.trackID == track.id }
                    var extent = try instrument(track.instrument, notes: lanes.flatMap(\.notes), project: project, clock: occurrence.clock)
                    for clip in lanes.flatMap(\.audio) where clip.preservesTail == true {
                        let node = MusicCircle(name: "오디오", content: .mix)
                        extent.include(try audio([clip], node: node, context: occurrence.context, clock: occurrence.clock))
                    }
                    local[track.id] = extent
                }
            }
            // Keep local tails even when an early occurrence ends before the arrangement body.
            // Section buffers need the same capacity as the global preparation policy.
            for (track, original) in local {
                var extent = original
                for effect in occurrence.use.effects { try append(effect, to: &extent) }
                var value = tracks[track] ?? Extent(); value.include(extent); tracks[track] = value
            }
        }
        let ordered = try SignalValidator.sorted(project.signal, tracks: project.tracks)
        var global: [ID: Extent] = [:]
        for node in ordered {
            var extent = Extent()
            if node.kind == .source { extent = node.trackID.flatMap { tracks[$0] } ?? Extent() }
            else {
                for edge in project.signal.edges where edge.to == node.id { extent.include(global[edge.from] ?? Extent()) }
                if node.kind == .effect { try append(node.effect, to: &extent) }
            }
            global[node.id] = extent
        }
        var result = Extent()
        for node in ordered where node.kind == .master { result.include(global[node.id] ?? Extent()) }
        let resolved = try resolve(result, requestedSeconds: requestedSeconds)
        _ = try ArrangementRenderer.preparationFrames(project: project, plan: plan, tailSeconds: resolved.effectiveSeconds,
                                                       includeStems: includeStems, includeVisualization: includeVisualization)
        return resolved
    }

    /// Validate floating-point inputs and representability before converting to Int.
    static func frameCount(bodySeconds: Double, tailSeconds: Double) throws -> Int {
        try validateRequest(tailSeconds)
        let count = ceil((bodySeconds + tailSeconds) * PCM.rate)
        guard bodySeconds.isFinite, bodySeconds >= 0, count.isFinite, count >= 0, count < Double(Int.max / 8) else {
            throw CirclrError("오디오 렌더 길이를 확인하세요")
        }
        return Int(count)
    }
    private static func validateRequest(_ seconds: Double?) throws {
        if let seconds, !seconds.isFinite || !(0...maximumTailSeconds).contains(seconds) {
            throw CirclrError("잔향 길이는 0–120초로 지정하세요")
        }
    }
    private static func resolve(_ extent: Extent, requestedSeconds: Double?) throws -> TailPlan {
        guard extent.seconds.isFinite, extent.preserved.isFinite else { throw CirclrError("잔향 길이를 계산할 수 없습니다") }
        let estimated = max(2, extent.seconds)
        var notices = extent.notices
        let effective: Double
        if let requestedSeconds {
            effective = requestedSeconds
            if requestedSeconds + 1 / PCM.rate < estimated { notices.append("직접 지정한 길이가 자동 추정보다 짧아 잔향이 잘릴 수 있습니다") }
        } else {
            guard extent.preserved <= maximumTailSeconds else { throw CirclrError("저장된 오디오 잔향이 120초를 넘습니다. 구간을 나누거나 잔향 길이를 직접 지정하세요") }
            effective = min(maximumTailSeconds, estimated)
            if estimated > maximumTailSeconds { notices.append("자동 잔향 추정이 120초 한도를 넘었습니다. 잔향이 잘릴 수 있습니다") }
        }
        return TailPlan(requestedSeconds: requestedSeconds, estimatedSeconds: estimated, effectiveSeconds: effective,
                        notices: Array(Set(notices)).sorted())
    }

    private static func sectionExtents(_ plan: SectionSignalPlan, project: Project, clock: MusicClock) throws -> [ID: Extent] {
        let incoming = Dictionary(grouping: plan.connections, by: { $0.to.nodeID })
        var buses: [MusicBusEndpoint: Extent] = [:], outputs: [ID: Extent] = [:]
        for node in plan.orderedNodes {
            let edges = incoming[node.id] ?? []
            if case .router(let router) = node.content {
                for output in AudioRouter.outputs {
                    let inputs = Set(router.routes.filter { $0.output == output }.map(\.input))
                    var extent = Extent()
                    for edge in edges where inputs.contains(edge.to.portID) { extent.include(buses[edge.from] ?? Extent()) }
                    buses[.init(nodeID: node.id, portID: output)] = extent
                }
                continue
            }
            var extent = Extent()
            for edge in edges { extent.include(buses[edge.from] ?? Extent()) }
            switch node.content {
            case .instrument(let trackID):
                guard let track = project.tracks.first(where: { $0.id == trackID }) else { throw CirclrError("악기 트랙을 찾을 수 없습니다") }
                let notes = edges.filter { $0.signal == .midi }.flatMap { plan.midi[$0.from.nodeID] ?? [] }
                extent.include(try instrument(track.instrument, notes: notes, project: project, clock: clock))
            case .audio, .rhythmAudio:
                extent.include(try audio(plan.audio[node.id] ?? [], node: node, context: plan.contexts[node.id] ?? project.global, clock: clock))
            case .effect(let effect): try append(effect, to: &extent)
            default: break
            }
            if case .output(let trackID) = node.content { var previous = outputs[trackID] ?? Extent(); previous.include(extent); outputs[trackID] = previous }
            else {
                let port = node.content.output == .midi ? CirclePort.midiOutput : CirclePort.audioOutput
                buses[.init(nodeID: node.id, portID: port)] = extent
            }
        }
        return outputs
    }
    private static func audio(_ clips: [AudioClip], node: MusicCircle, context: MusicContext, clock: MusicClock) throws -> Extent {
        var result = Extent()
        let timing = AudioClipTiming(node: node, context: context, clock: clock)
        for clip in clips where clip.preservesTail == true && node.lengthBeats == nil {
            let rate = timing.rate(clip)
            guard rate.isFinite, rate > 0 else { throw CirclrError("오디오 tempo 추종 비율을 확인하세요") }
            // The renderer only starts repetitions within the section body.
            for iteration in 0..<node.repeatCount {
                let start = timing.position(clip, iteration: iteration)
                guard start < clock.seconds else { break }
                let extra = max(0, start + clip.duration / rate - clock.seconds)
                guard extra.isFinite else { throw CirclrError("저장된 오디오의 잔향 길이를 확인하세요") }
                result.seconds = max(result.seconds, extra); result.preserved = max(result.preserved, extra)
            }
        }
        return result
    }
    private static func instrument(_ instrument: Instrument, notes: [Note], project: Project, clock: MusicClock) throws -> Extent {
        let notes = notes.filter { $0.beat < clock.beats }
        guard !notes.isEmpty else { return Extent() }
        switch instrument.kind {
        case .synthesizer:
            let release = instrument.synth?.release ?? SynthPatch().release
            guard release.isFinite, release >= 0 else { throw CirclrError("악기의 release를 확인하세요") }
            return Extent(seconds: release)
        case .sampler:
            guard let sample = instrument.sample else { throw CirclrError("샘플 악기의 원본을 선택하세요") }
            guard sample.oneShot else { return Extent() }
            var longest = 0.0
            for note in notes {
                let sources: [(ID, Int)]
                if let zones = sample.zones, !zones.isEmpty {
                    // The renderer skips unmapped notes rather than using the base sample.
                    sources = zones.filter { $0.pitch == note.pitch }.map { ($0.assetID, $0.pitch) }
                } else { sources = [(sample.assetID, sample.rootPitch)] }
                for (assetID, root) in sources {
                    guard let asset = project.assets.first(where: { $0.id == assetID }) else { throw CirclrError("샘플 악기 원본을 찾을 수 없습니다") }
                    let rate = pow(2, Double(note.pitch - root) / 12)
                    longest = max(longest, clock.seconds(at: note.beat) + asset.duration / rate - clock.seconds)
                }
            }
            return Extent(seconds: longest)
        case .audioUnit, .soundBank:
            return Extent(seconds: 10, notices: ["Audio Unit·SoundBank의 잔향은 확인할 수 없어 10초를 확보합니다. 필요하면 길이를 직접 지정하세요"])
        }
    }
    private static func append(_ effect: Effect, to extent: inout Extent) throws {
        guard effect.amount.isFinite, effect.secondary.isFinite else { throw CirclrError("이펙트 설정값을 확인하세요") }
        let a = min(1, max(0, effect.amount)), wet = min(0.95, max(0, effect.secondary))
        let extra: Double
        switch effect.kind {
        case .delay:
            guard wet > 0 else { return }
            let delay = Double(max(1, Int((0.03 + a * 0.97) * PCM.rate))) / PCM.rate
            let feedback = min(0.8, wet)
            let echoes = feedback > 0 ? max(1, ceil(log(attenuation / wet) / log(feedback)) + 1) : 1
            extra = delay * echoes
        case .reverb:
            guard wet > 0 else { return }
            if effect.renderVersion == 2 {
                // Comb RT60 scaled to -80 dB, plus pre-delay and all-pass decay.
                let rt60 = 0.45 + a * 3.2
                let diffusion = Double([563, 421, 281, 179].reduce(0, +) + 4 * 17) / PCM.rate
                extra = 864 / PCM.rate + rt60 * (80.0 / 60) + diffusion * ceil(log(attenuation) / log(0.55)) + 0.1
            } else {
                let delay = Double(max(1, Int(1867 * (0.5 + a * 2)))) / PCM.rate
                extra = delay * (ceil(log(attenuation) / log(0.45 + a * 0.38)) + 1)
            }
        case .lowpass:
            extra = -log(attenuation) / (2 * Double.pi * 40 * pow(500, a))
        case .audioUnit:
            extra = 10; extent.notices.append("Audio Unit의 잔향은 확인할 수 없어 10초를 추가합니다. 필요하면 길이를 직접 지정하세요")
        default: extra = 0
        }
        extent.seconds += extra
    }
}
