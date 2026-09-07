import Foundation
import CirclrCore

public enum SectionGraphRenderer {
    public static func render(_ plan: SectionSignalPlan, project: Project, root: URL?,
                              clock: MusicClock, tail: Double, applyOutputGain: Bool = true,
                              observe: ((ID, PCM) -> Void)? = nil) async throws -> [ID: PCM] {
        let frames = Int(ceil((clock.seconds + tail) * PCM.rate))
        guard Double(frames) * 8 * Double(plan.orderedNodes.count + 3) < 1_073_741_824 else {
            throw CirclrError("섹션 내부 오디오가 준비 가능한 메모리 범위를 넘습니다")
        }
        var buffers: [ID: PCM] = [:], outputs: [ID: PCM] = [:]
        var needed=Set(plan.orderedNodes.filter{if case .output = $0.content{return true};return false}.map(\.id))
        var frontier=Array(needed)
        while let id=frontier.popLast() {for edge in plan.graph.edges where edge.to==id {if needed.insert(edge.from).inserted {frontier.append(edge.from)}}}
        for node in plan.orderedNodes where needed.contains(node.id) {
            try Task.checkCancellation()
            if node.content.output == .midi { continue }
            var local = PCM(frames: frames)
            if !node.muted {
                switch node.content {
                case .instrument(let trackID):
                    guard let track = project.tracks.first(where: { $0.id == trackID }) else { throw CirclrError("서클의 악기를 찾을 수 없습니다") }
                    let notes = plan.graph.edges.filter { $0.to == node.id && $0.signal == .midi }.flatMap { plan.midi[$0.from] ?? [] }
                    let overrideHost = node.settings.tempo.source != .inherit || node.settings.meter.source != .inherit
                    local = try await ProductionInstrument.render(notes, instrument: track.instrument, project: project, root: root, clock: clock, tail: tail,
                                                               hostContext: overrideHost ? plan.contexts[node.id] : nil)
                case .audio, .rhythmAudio:
                    for clip in plan.audio[node.id] ?? [] {
                        try await mixClip(clip, node: node, context: plan.contexts[node.id], project: project, root: root, clock: clock, into: &local)
                    }
                case .effect, .mix, .output:
                    var sidechain = PCM(frames: frames), hasSidechain = false
                    for edge in plan.graph.edges where edge.to == node.id && edge.signal == .audio {
                        guard let source = buffers[edge.from] else { continue }
                        if edge.sidechain { sidechain.mix(source, gain: edge.gain); hasSidechain = true }
                        else { local.mix(source, gain: edge.gain) }
                    }
                    if case .effect(let effect) = node.content {
                        local = try await ArrangementRenderer.apply(local, effect: effect, sidechain: hasSidechain ? sidechain : nil)
                    }
                case .midi, .rhythmMIDI: break
                }
                let isOutput:Bool = {if case .output = node.content{return true};return false}()
                if node.gain != 1 && (applyOutputGain || !isOutput) { local.multiply(node.gain) }
            }
            observe?(node.id, local)
            if case .output(let trackID) = node.content {
                if outputs[trackID] == nil { outputs[trackID] = local }
                else { outputs[trackID]?.mix(local) }
            } else { buffers[node.id] = local }
        }
        return outputs
    }

    private static func mixClip(_ clip: AudioClip, node: MusicCircle, context: MusicContext?, project: Project,
                                root: URL?, clock: MusicClock, into output: inout PCM) async throws {
        guard let asset = project.assets.first(where: { $0.id == clip.assetID }) else { throw CirclrError("오디오 원본을 찾을 수 없습니다") }
        let ownTempo = node.settings.tempo.source != .inherit
        let tempo = context?.tempo ?? clock.bpm(at: node.startBeat)
        func time(_ beat: Double) -> Double {
            ownTempo ? clock.seconds(at: node.startBeat) + beat*60/tempo : clock.seconds(at: node.startBeat+beat)
        }
        let start = time(clip.beat)
        guard start < clock.seconds else { return }
        if clip.followsTempo && !ownTempo && clock.tempos.count > 1 { throw CirclrError("Tempo map이 변하는 오디오는 구간을 나누거나 서클 tempo를 지정하세요") }
        let bpm = ownTempo ? tempo : clock.bpm(at: clip.beat + node.startBeat)
        let rate = clip.followsTempo ? bpm / clip.sourceBPM : 1
        guard rate.isFinite, rate > 0 else { throw CirclrError("오디오 tempo 추종 비율을 확인하세요") }
        let period = clip.duration / rate
        guard period.isFinite, period > 0 else { throw CirclrError("오디오 서클의 길이를 확인하세요") }
        let url = try ProjectStore.assetURL(asset, root: root)
        for iteration in 0..<node.repeatCount {
            try Task.checkCancellation()
            let position: Double, end: Double
            if let length = node.lengthBeats {
                guard clip.beat < length else { break }
                position = time(Double(iteration)*length + clip.beat)
                end = min(clock.seconds, time(Double(iteration+1)*length))
            } else { position = start + Double(iteration)*period; end = clip.preservesTail == true ? output.duration : clock.seconds }
            guard position < clock.seconds else { break }
            let remaining = max(0, end-position)
            if remaining <= 0 { continue }
            var part = try PCM.read(url, start: clip.sourceStart, duration: min(clip.duration, remaining * rate))
            if clip.followsTempo { part = try AudioUnitHost.stretch(part, rate: rate) }
            part = part.slice(0..<min(part.count, Int((remaining * PCM.rate).rounded())))
            if clip.preservesTail != true {part.fadeInOut()}
            output.mix(part, at: Int((position * PCM.rate).rounded()), gain: clip.gain)
        }
    }
}
