import Foundation
import AVFAudio
import CirclrCore

public struct PreparedAudio {
    public var plan: ExecutionPlan
    public var mix: PCM
    public var stems: [ID: PCM]
    public var tailSeconds: Double
    public var visualization: PlaybackAnalysis? = nil
    public var peak: Float { mix.peak }
}
public enum ArrangementRenderer {
    public static func render(project: Project, root: URL?, plan: ExecutionPlan, tailSeconds: Double = 2, includeStems: Bool = true, includeVisualization: Bool = false, progress: @escaping (String, Double) -> Void = { _,_ in }) async throws -> PreparedAudio {
        guard plan.duration > 0 else { throw CirclrError("먼저 섹션을 만들고 시작 서클을 지정하세요") }
        guard tailSeconds.isFinite, (0...30).contains(tailSeconds) else { throw CirclrError("잔향 길이를 확인하세요") }
        let frames = Int(ceil((plan.duration + tailSeconds)*PCM.rate))
        let estimate = Double(frames) * 8 * Double(project.tracks.count * (includeStems ? 2 : 1) + project.signal.nodes.filter { $0.kind != .source }.count + 5)
        var graphEstimate = 0.0
        for occurrence in plan.occurrences {
            guard let graph = occurrence.signalPlan else { continue }
            let localFrames = (occurrence.duration + tailSeconds) * PCM.rate
            let bytes = localFrames * 8.0 * Double(graph.orderedNodes.count + 3)
            graphEstimate = max(graphEstimate, bytes)
        }
        guard estimate + graphEstimate < 1_073_741_824 else { throw CirclrError("준비 오디오가 1 GB 작업 한도를 넘습니다. 구간을 나누어 내보내세요") }
        var tracks = Dictionary(uniqueKeysWithValues: project.tracks.map { ($0.id,PCM(frames: frames)) })
        var visualization = PlaybackAnalysis()
        for (index, occurrence) in plan.occurrences.enumerated() {
            try Task.checkCancellation()
            progress("\(occurrence.use.name) · \(occurrence.iteration+1)/\(occurrence.use.repeatCount)회 준비",0.78*Double(index)/Double(max(1,plan.occurrences.count)))
            var lanes = occurrence.lanes
            var visual = OccurrenceVisualization()
            var sectionAudio = includeVisualization ? PCM(frames: Int(ceil((occurrence.duration+tailSeconds)*PCM.rate))) : PCM(frames: 0)
            let graphAudio: [ID: PCM]?
            if let signal = occurrence.signalPlan {
                let audible = includeVisualization && occurrence.use.gain > 0 ? PlaybackAnalysis.audibleNodes(signal, tracks: project.tracks) : []
                if includeVisualization {
                    for (id, notes) in signal.midi where audible.contains(id) {
                        visual.nodes[id] = PlaybackEnvelope(notes: notes, clock: occurrence.clock)
                    }
                }
                graphAudio = try await SectionGraphRenderer.render(signal, project: project, root: root, clock: occurrence.clock, tail: tailSeconds,
                    observe: includeVisualization ? { id, pcm in
                        if audible.contains(id) { visual.nodes[id] = PlaybackEnvelope(pcm) }
                    } : nil)
            } else { graphAudio = nil }
            if graphAudio == nil, let patternID = occurrence.context.rhythm.patternID, let pattern = project.patterns.first(where: { $0.id == patternID }) {
                lanes.append(expandPattern(pattern, length: occurrence.clock.beats, grid: occurrence.context.beatGrid))
            }
            for track in project.tracks where !track.muted {
                let matching = lanes.filter { $0.trackID == track.id }
                let notes = matching.flatMap(\.notes)
                let clips = matching.flatMap(\.audio)
                var local: PCM
                if let graphAudio {
                    guard let rendered = graphAudio[track.id] else { continue }
                    local = rendered
                } else {
                    if notes.isEmpty && clips.isEmpty { continue }
                    local = try await ProductionInstrument.render(notes, instrument: track.instrument, project: project, root: root, clock: occurrence.clock, tail: tailSeconds)
                    for clip in clips {
                        let audio = try loadClip(clip, project: project, root: root, clock: occurrence.clock)
                        local.mix(audio,at:Int((occurrence.clock.seconds(at:clip.beat)*PCM.rate).rounded()),gain:clip.gain)
                    }
                }
                for effect in occurrence.use.effects { local = try await apply(local,effect:effect) }
                local.multiply(occurrence.use.gain * track.gain)
                for transition in plan.transitions where transition.sourceOccurrenceID == occurrence.id {
                    let offset = Int(((transition.start-occurrence.start)*PCM.rate).rounded()), count = Int((transition.duration*PCM.rate).rounded())
                    if transition.transition.mode == .within {
                        if transition.transition.replaceTrackID == track.id {
                            zero(&local,range:offset..<(offset+count))
                        } else if transition.transition.replaceTrackID == nil {
                            let processed = try await apply(local.slice(offset..<(offset+count)),effect:transition.transition.effect)
                            replace(&local,at:offset,with:processed,blend:true)
                        }
                    } else if transition.transition.mode == .overlap {
                        fade(&local,start:offset,count:count,incoming:false)
                    }
                }
                for transition in plan.transitions where transition.targetOccurrenceID == occurrence.id && transition.transition.mode == .overlap {
                    fade(&local,start:0,count:Int((transition.duration*PCM.rate).rounded()),incoming:true)
                }
                tracks[track.id]?.mix(local,at:Int((occurrence.start*PCM.rate).rounded()))
                if includeVisualization { sectionAudio.mix(local) }
            }
            if includeVisualization {
                visual.section = PlaybackEnvelope(sectionAudio)
                visualization.occurrences[occurrence.id] = visual
            }
        }
        for transition in plan.transitions {
            guard let patternID = transition.transition.patternID, let pattern = project.patterns.first(where: { $0.id == patternID }), let track = project.tracks.first(where: { $0.id == pattern.trackID }), !track.muted else { continue }
            let beats = transition.duration * transition.context.tempo/60
            let bars = max(1,Int(ceil(beats/transition.context.meter.quarters)))
            let clock = try MusicClock(bars: bars, context: transition.context)
            let lane = expandPattern(pattern,length:beats,grid:transition.context.beatGrid)
            var part = try await ProductionInstrument.render(lane.notes,instrument:track.instrument,project:project,root:root,clock:clock,tail:0)
            for clip in lane.audio { part.mix(try loadClip(clip,project:project,root:root,clock:clock),at:Int((clock.seconds(at:clip.beat)*PCM.rate).rounded()),gain:clip.gain) }
            part = part.slice(0..<Int((transition.duration*PCM.rate).rounded()))
            if transition.transition.mode == .insert { part = try await apply(part,effect:transition.transition.effect) }
            part.fadeInOut(); tracks[track.id]?.mix(part,at:Int((transition.start*PCM.rate).rounded()),gain:track.gain)
        }
        progress("사운드 노드 처리",0.8)
        let full = try await renderSignal(project.signal,tracks:project.tracks,sources:tracks,frames:frames)
        guard let master = project.signal.nodes.first(where: { $0.kind == .master }), let mix = full[master.id] else { throw CirclrError("출력 노드가 없습니다") }
        if includeVisualization {
            let connected = PlaybackAnalysis.connectedSignals(project.signal)
            visualization.signals = full.filter { connected.contains($0.key) }.mapValues { PlaybackEnvelope($0) }
            visualization.master = visualization.signals[master.id]
        }
        var stems: [ID: PCM] = [:]
        for (index,track) in (includeStems ? project.tracks : []).enumerated() {
            try Task.checkCancellation()
            progress("\(track.name) stem 준비",0.8+0.19*Double(index)/Double(max(1,project.tracks.count)))
            let isolated = tracks.mapValues { _ in PCM(frames: frames) }.merging([track.id: tracks[track.id] ?? PCM(frames:frames)]) { _,new in new }
            let result = try await renderSignal(project.signal,tracks:project.tracks,sources:isolated,frames:frames,sidechainReference:full)
            stems[track.id] = result[master.id]
        }
        guard mix.left.allSatisfy(\.isFinite),mix.right.allSatisfy(\.isFinite) else { throw CirclrError("유효하지 않은 오디오 출력입니다") }
        progress("재생 준비 완료",1)
        return PreparedAudio(plan:plan,mix:mix,stems:stems,tailSeconds:tailSeconds,visualization:includeVisualization ? visualization : nil)
    }
    public static func expandPattern(_ pattern: RhythmPattern, length: Double, grid: BeatGrid) -> Lane {
        var lane = Lane(trackID:pattern.trackID), offset = 0.0
        guard pattern.length > 0 else { return lane }
        let step = 1/Double(max(1,grid.subdivisions))
        while offset < length - 0.000001 {
            for var note in pattern.notes {
                note.id = newID(); let stepIndex = Int((note.beat/step).rounded())
                let swung = note.beat + (stepIndex%2 == 1 ? grid.swing*step : 0)
                note.beat = offset + swung
                if note.beat < length { note.length = min(note.length,length-note.beat); lane.notes.append(note) }
            }
            for var clip in pattern.audio { clip.id = newID(); clip.beat += offset; if clip.beat < length { lane.audio.append(clip) } }
            offset += pattern.length
        }
        return lane
    }
    static func loadClip(_ clip: AudioClip, project: Project, root: URL?, clock: MusicClock) throws -> PCM {
        guard let asset = project.assets.first(where: { $0.id == clip.assetID }) else { throw CirclrError("오디오 원본을 찾을 수 없습니다") }
        let url = try ProjectStore.assetURL(asset,root:root)
        guard FileManager.default.fileExists(atPath:url.path) else { throw CirclrError("\(asset.name)을 다시 연결하세요") }
        let remaining = max(0,clock.seconds-clock.seconds(at:clip.beat))
        if remaining == 0 { return PCM(frames:0) }
        let sourceDuration = min(clip.duration,remaining*(clip.followsTempo ? clock.bpm(at:clip.beat)/clip.sourceBPM:1))
        var part = try PCM.read(url,start:clip.sourceStart,duration:sourceDuration)
        if clip.followsTempo {
            guard clock.tempos.count == 1 else { throw CirclrError("Tempo map이 변하는 오디오 clip은 구간을 나누어 tempo 추종을 적용하세요") }
            part = try AudioUnitHost.stretch(part,rate:clock.bpm(at:clip.beat)/clip.sourceBPM)
        }
        let maximum = max(0,Int(((clock.seconds-clock.seconds(at:clip.beat))*PCM.rate).rounded()))
        part = part.slice(0..<min(part.count,maximum)); part.fadeInOut(); return part
    }
    static func apply(_ input: PCM, effect: Effect, sidechain: PCM? = nil) async throws -> PCM {
        if effect.kind == .audioUnit {
            guard let plugin = effect.plugin else { throw CirclrError("Effect Audio Unit을 선택하세요") }
            let unit = try await AudioUnitHost.instantiate(plugin)
            return try AudioUnitHost.process(input,unit:unit)
        }
        return try NativeDSP.process(input,effect:effect,sidechain:sidechain)
    }
    static func renderSignal(_ graph: SignalGraph, tracks: [Track], sources: [ID:PCM], frames: Int, sidechainReference: [ID:PCM]? = nil) async throws -> [ID:PCM] {
        let sorted = try SignalValidator.sorted(graph,tracks:tracks)
        var buffers: [ID:PCM] = [:]
        for node in sorted {
            try Task.checkCancellation()
            if node.kind == .source { buffers[node.id] = node.trackID.flatMap { sources[$0] } ?? PCM(frames:frames); continue }
            var input = PCM(frames:frames), sidechain = PCM(frames:frames), hasSidechain = false
            for edge in graph.edges where edge.to == node.id {
                if edge.sidechain { if let source = sidechainReference?[edge.from] ?? buffers[edge.from] { sidechain.mix(source,gain:edge.gain); hasSidechain = true } }
                else if let source = buffers[edge.from] { input.mix(source,gain:edge.gain) }
            }
            buffers[node.id] = node.kind == .effect ? try await apply(input,effect:node.effect,sidechain:hasSidechain ? sidechain : nil) : input
        }
        return buffers
    }
    static func zero(_ pcm: inout PCM,range:Range<Int>) { let start = max(0,range.lowerBound),end = min(pcm.count,range.upperBound); if end > start { for i in start..<end { pcm.left[i] = 0; pcm.right[i] = 0 } } }
    static func replace(_ pcm: inout PCM,at offset:Int,with part:PCM,blend:Bool) {
        for j in 0..<part.count {
            let i = offset+j; guard i >= 0 && i < pcm.count else { continue }
            let wet = blend ? Float(min(1,Double(min(j,part.count-j-1))/120)) : 1
            pcm.left[i] = pcm.left[i]*(1-wet)+part.left[j]*wet; pcm.right[i] = pcm.right[i]*(1-wet)+part.right[j]*wet
        }
    }
    static func fade(_ pcm: inout PCM,start:Int,count:Int,incoming:Bool) {
        guard count > 0 else { return }
        for i in max(0,start)..<pcm.count {
            let f = Float(min(1,max(0,Double(i-start)/Double(count))))
            let g = incoming ? f : 1-f
            pcm.left[i] *= g; pcm.right[i] *= g
            if incoming && i >= start+count { break }
        }
    }
}
