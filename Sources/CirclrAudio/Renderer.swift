import Foundation
import AVFAudio
import CirclrCore

public struct PreparedAudio {
    public var plan: ExecutionPlan
    public var mix: PCM
    public var stems: [ID: PCM]
    public var tailSeconds: Double
    public var tailPlan: TailPlan? = nil
    public var visualization: PlaybackAnalysis? = nil
    public var peak: Float { mix.peak }
}
public enum ArrangementRenderer {
    /// Bound whole-song preparation to at most a quarter of RAM, capped at 2 GiB.
    /// 15-track club arrangements need more than the previous fixed 1 GiB allowance.
    static var preparationByteLimit:Double {min(2_147_483_648,Double(ProcessInfo.processInfo.physicalMemory)/4)}
    public static func render(project: Project, root: URL?, plan: ExecutionPlan, tailSeconds: Double? = nil, includeStems: Bool = true, includeVisualization: Bool = false, progress: @escaping (String, Double) -> Void = { _,_ in }) async throws -> PreparedAudio {
        try await renderPrepared(project:project,root:root,plan:plan,tailSeconds:tailSeconds,
                                 includeStems:includeStems,includeVisualization:includeVisualization,stemSink:nil,progress:progress)
    }
    /// Stems are delivered one at a time; the caller must persist each before the next render.
    static func renderStems(project:Project,root:URL?,plan:ExecutionPlan,
                            progress:@escaping (String,Double)->Void,
                            stemSink:@escaping (ID,PCM)throws->Void) async throws -> PreparedAudio {
        try await renderPrepared(project:project,root:root,plan:plan,tailSeconds:nil,
                                 includeStems:false,includeVisualization:false,stemSink:stemSink,progress:progress)
    }
    private static func renderPrepared(project: Project, root: URL?, plan: ExecutionPlan, tailSeconds: Double?,
                                       includeStems: Bool, includeVisualization: Bool,
                                       stemSink: ((ID,PCM)throws->Void)?,
                                       progress: @escaping (String, Double) -> Void) async throws -> PreparedAudio {
        guard plan.duration > 0 else { throw CirclrError("먼저 섹션을 만들고 시작 서클을 지정하세요") }
        try validatePitchBendSupport(project:project,plan:plan)
        let tailPlan = try RenderTailPlanner.arrangement(project:project,plan:plan,requestedSeconds:tailSeconds,
                                                        includeStems:includeStems,includeVisualization:includeVisualization,
                                                        streamStems:stemSink != nil)
        let tailSeconds = tailPlan.effectiveSeconds
        let frames = try RenderTailPlanner.frameCount(bodySeconds:plan.duration,tailSeconds:tailSeconds)
        var tracks = Dictionary(uniqueKeysWithValues: project.tracks.map { ($0.id,PCM(frames: frames)) })
        var visualization = PlaybackAnalysis()
        let connected=PlaybackAnalysis.connectedSignals(project.signal)
        let connectedTracks=Set(project.signal.nodes.compactMap{node -> ID? in
            node.kind == .source && connected.contains(node.id) ? node.trackID:nil
        })
        let masterTracks=Set(project.tracks.filter{!$0.muted && $0.gain>0 && connectedTracks.contains($0.id)}.map(\.id))
        for (index, occurrence) in plan.occurrences.enumerated() {
            try Task.checkCancellation()
            progress("\(occurrence.use.name) · \(occurrence.iteration+1)/\(occurrence.use.repeatCount)회 준비",0.78*Double(index)/Double(max(1,plan.occurrences.count)))
            var lanes = occurrence.lanes
            var visual = OccurrenceVisualization()
            var sectionAudio = includeVisualization ? PCM(frames: Int(ceil((occurrence.duration+tailSeconds)*PCM.rate))) : PCM(frames: 0)
            let graphAudio: [ID: PCM]?
            if let signal = occurrence.signalPlan {
                let audible = includeVisualization && occurrence.use.gain > 0 ? PlaybackAnalysis.audiblePaths(signal, tracks: project.tracks) : PlaybackSignalPaths()
                if includeVisualization {
                    visual.connections = audible.connections
                    for (id, notes) in signal.midi {
                        let endpoint = MusicBusEndpoint(nodeID: id, portID: CirclePort.midiOutput)
                        if audible.outputs.contains(endpoint) {
                            visual.observe(endpoint, envelope: PlaybackEnvelope(notes: notes, clock: occurrence.clock))
                        }
                    }
                }
                let outputNodes = Set(signal.orderedNodes.filter { if case .output = $0.content { return true }; return false }.map(\.id))
                graphAudio = try await SectionGraphRenderer.render(signal, project: project, root: root, clock: occurrence.clock, tail: tailSeconds,
                    audibleTrackIDs:occurrence.use.gain>0 ? masterTracks:[],
                    observe: includeVisualization ? { id, pcm in
                        if outputNodes.contains(id), audible.nodes.contains(id) { visual.nodes[id] = PlaybackEnvelope(pcm) }
                    } : nil,
                    observeOutput: includeVisualization ? { endpoint, pcm in
                        if audible.outputs.contains(endpoint) { visual.observe(endpoint, envelope: PlaybackEnvelope(pcm)) }
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
                        let audio = try loadClip(clip, project: project, root: root, clock: occurrence.clock, tailSeconds: tailSeconds)
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
        var full = try await renderSignal(project.signal,tracks:project.tracks,sources:tracks,frames:frames)
        guard let master = project.signal.nodes.first(where: { $0.kind == .master }), let mix = full[master.id] else { throw CirclrError("출력 노드가 없습니다") }
        if includeVisualization {
            let connected = PlaybackAnalysis.connectedSignals(project.signal)
            visualization.signals = full.filter { connected.contains($0.key) }.mapValues { PlaybackEnvelope($0) }
            visualization.master = visualization.signals[master.id]
        }
        // Only sidechain senders need their original full-mix signal for stems.
        // Release other graph buffers before rendering the first stem.
        let sidechainSenders=Set(project.signal.edges.filter(\.sidechain).map(\.from))
        let sidechainReference=full.filter{sidechainSenders.contains($0.key)}
        full.removeAll(keepingCapacity:false)
        var stems: [ID: PCM] = [:]
        for (index,track) in ((includeStems || stemSink != nil) ? project.tracks : []).enumerated() {
            try Task.checkCancellation()
            progress("\(track.name) stem 준비",0.8+0.19*Double(index)/Double(max(1,project.tracks.count)))
            // Missing source IDs share one read-only silence buffer in renderSignal.
            let isolated = [track.id: tracks[track.id] ?? PCM(frames:frames)]
            let result = try await renderSignal(project.signal,tracks:project.tracks,sources:isolated,frames:frames,sidechainReference:sidechainReference)
            guard let stem = result[master.id] else { throw CirclrError("Stem 출력 노드가 없습니다") }
            if let stemSink { try stemSink(track.id,stem) }
            else { stems[track.id] = stem }
            tracks.removeValue(forKey:track.id)
        }
        guard mix.left.allSatisfy(\.isFinite),mix.right.allSatisfy(\.isFinite) else { throw CirclrError("유효하지 않은 오디오 출력입니다") }
        progress("재생 준비 완료",1)
        return PreparedAudio(plan:plan,mix:mix,stems:stems,tailSeconds:tailSeconds,tailPlan:tailPlan,visualization:includeVisualization ? visualization : nil)
    }
    /// Check the entire requested arrangement before any instrument/effect helper can run.
    /// Unused storage, muted tracks and disconnected master paths are not render failures.
    static func validatePitchBendSupport(project:Project,plan:ExecutionPlan)throws {
        let connected=PlaybackAnalysis.connectedSignals(project.signal)
        let connectedTracks=Set(project.signal.nodes.compactMap{node -> ID? in
            node.kind == .source && connected.contains(node.id) ? node.trackID:nil
        })
        let audibleTracks=Set(project.tracks.filter{!$0.muted && $0.gain>0 && connectedTracks.contains($0.id)}.map(\.id))
        for occurrence in plan.occurrences where occurrence.use.gain>0 {
            if let graph=occurrence.signalPlan {
                try SectionGraphRenderer.validatePitchBendSupport(graph,project:project,outputTracks:audibleTracks)
            } else {
                for lane in occurrence.lanes where audibleTracks.contains(lane.trackID) && (lane.pitchBend != nil || lane.sustain != nil) {
                    if lane.notes.contains(where:{$0.beat<occurrence.clock.beats}) {throw CirclrError("이 연주 경로는 MIDI 피치 벤드·서스테인 표현을 지원하지 않습니다")}
                }
                if let id=occurrence.context.rhythm.patternID,let pattern=project.patterns.first(where:{$0.id==id}),
                   audibleTracks.contains(pattern.trackID),(pattern.pitchBend != nil || pattern.sustain != nil),
                   pattern.notes.contains(where:{$0.beat<min(pattern.length,occurrence.clock.beats)}) {
                    throw CirclrError("이 연주 경로는 MIDI 피치 벤드·서스테인 표현을 지원하지 않습니다")
                }
            }
        }
        for transition in plan.transitions where transition.duration>0 {
            if let id=transition.transition.patternID,let pattern=project.patterns.first(where:{$0.id==id}),
               audibleTracks.contains(pattern.trackID),(pattern.pitchBend != nil || pattern.sustain != nil),
               pattern.notes.contains(where:{$0.beat<min(pattern.length,transition.duration*transition.context.tempo/60)}) {
                throw CirclrError("이 연주 경로는 MIDI 피치 벤드·서스테인 표현을 지원하지 않습니다")
            }
        }
    }

    /// Shared by render and preflight, before jobs or PCM allocations begin.
    static func preparationFrames(project: Project, plan: ExecutionPlan, tailSeconds: Double,
                                  includeStems: Bool, includeVisualization: Bool, streamStems:Bool = false) throws -> Int {
        let frames = try RenderTailPlanner.frameCount(bodySeconds: plan.duration, tailSeconds: tailSeconds)
        let processorCount = project.signal.nodes.filter { $0.kind != .source }.count
        let estimate = Double(frames) * 8 * Double(project.tracks.count * (includeStems ? 2 : 1)
            + processorCount * (streamStems ? 2 : 1) + 5)
        var graphEstimate = 0.0
        for occurrence in plan.occurrences {
            let localFrames = try RenderTailPlanner.frameCount(bodySeconds: occurrence.duration, tailSeconds: tailSeconds)
            guard let graph = occurrence.signalPlan else { continue }
            let bytes = Double(localFrames) * 8 * Double(SectionGraphRenderer.workingBufferCount(graph))
            guard bytes < 1_073_741_824 else { throw CirclrError("섹션 내부 오디오가 준비 가능한 메모리 범위를 넘습니다") }
            graphEstimate = max(graphEstimate, bytes)
        }
        let visualEstimate = includeVisualization ? PlaybackAnalysis.estimatedBytes(plan: plan, signal: project.signal, tail: tailSeconds) : 0
        // Section graph buffers are gone before the full signal/stem pass.
        // Streaming keeps only one stem graph, so budget the larger phase peak.
        let sectionEstimate = Double(frames) * 8 * Double(project.tracks.count + 5) + graphEstimate
        let workingEstimate = streamStems ? max(estimate,sectionEstimate) : estimate + graphEstimate
        guard workingEstimate + visualEstimate < preparationByteLimit else { throw CirclrError("준비 오디오가 메모리 작업 한도를 넘습니다. 구간을 나누어 내보내세요") }
        return frames
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
            for var clip in pattern.audio { clip.id = newID(); clip.beat += offset; if clip.renderWindow != nil { clip.renderWindow?.cycleBeat += offset }; if clip.beat < length { lane.audio.append(clip) } }
            offset += pattern.length
        }
        return lane
    }
    static func loadClip(_ clip: AudioClip, project: Project, root: URL?, clock: MusicClock, tailSeconds: Double = 0) throws -> PCM {
        guard let asset = project.assets.first(where: { $0.id == clip.assetID }) else { throw CirclrError("오디오 원본을 찾을 수 없습니다") }
        let url = try ProjectStore.assetURL(asset,root:root)
        guard FileManager.default.fileExists(atPath:url.path) else { throw CirclrError("\(asset.name)을 다시 연결하세요") }
        let remaining = max(0,clock.seconds+(clip.preservesTail == true ? tailSeconds:0)-clock.seconds(at:clip.beat))
        if remaining == 0 { return PCM(frames:0) }
        let node=MusicCircle(name:"",content:.audio(laneID:"",clipID:clip.id))
        try AudioClipTiming(node:node,context:project.global,clock:clock).validateTempoFollowing(
            clip,renderEndSeconds:clock.seconds+(clip.preservesTail == true ? tailSeconds:0))
        return try ClipAudioRenderer.read(clip,url:url,rate:clip.followsTempo ? clock.bpm(at:clip.beat)/clip.sourceBPM:1,remaining:remaining,legacyTail:false)
    }
    static func apply(_ input: PCM, effect: Effect, sidechain: PCM? = nil) async throws -> PCM {
        if effect.kind == .audioUnit {
            guard let plugin = effect.plugin else { throw CirclrError("Effect Audio Unit을 선택하세요") }
            return try await AUEffectWorkerProcess().process(input: input, plugin: plugin)
        }
        return try NativeDSP.process(input,effect:effect,sidechain:sidechain)
    }
    static func renderSignal(_ graph: SignalGraph, tracks: [Track], sources: [ID:PCM], frames: Int, sidechainReference: [ID:PCM]? = nil) async throws -> [ID:PCM] {
        let sorted = try SignalValidator.sorted(graph,tracks:tracks)
        var buffers: [ID:PCM] = [:]
        var silence: PCM?
        for node in sorted {
            try Task.checkCancellation()
            if node.kind == .source {
                if let source = node.trackID.flatMap({ sources[$0] }) { buffers[node.id] = source }
                else { if silence == nil { silence = PCM(frames:frames) }; buffers[node.id] = silence }
                continue
            }
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
