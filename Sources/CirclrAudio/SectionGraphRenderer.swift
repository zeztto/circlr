import Foundation
import CirclrCore

public enum SectionGraphRenderer {
    public static func render(_ plan:SectionSignalPlan,project:Project,root:URL?,clock:MusicClock,tail:Double,
                              applyOutputGain:Bool=true,observe:((ID,PCM)->Void)?=nil,
                              observeOutput:((MusicBusEndpoint,PCM)->Void)?=nil) async throws->[ID:PCM] {
        try await render(plan,project:project,root:root,clock:clock,tail:tail,applyOutputGain:applyOutputGain,
                         audibleTrackIDs:nil,observe:observe,observeOutput:observeOutput)
    }
    /// The arrangement owner limits validation to outputs actually included in its mix/stems.
    static func render(_ plan: SectionSignalPlan, project: Project, root: URL?,
                              clock: MusicClock, tail: Double, applyOutputGain: Bool = true,
                              audibleTrackIDs:Set<ID>?,
                              observe: ((ID, PCM) -> Void)? = nil,
                              observeOutput: ((MusicBusEndpoint, PCM) -> Void)? = nil) async throws -> [ID: PCM] {
        try validatePitchBendSupport(plan,project:project,applyOutputGain:applyOutputGain,outputTracks:audibleTrackIDs)
        let expressionTargets=audibleExpressionInstruments(plan,project:project,applyOutputGain:applyOutputGain,outputTracks:audibleTrackIDs)
        let frames = try RenderTailPlanner.frameCount(bodySeconds: clock.seconds, tailSeconds: tail)
        guard Double(frames) * 8 * Double(workingBufferCount(plan)) < 1_073_741_824 else {
            throw CirclrError("섹션 내부 오디오가 준비 가능한 메모리 범위를 넘습니다")
        }
        var buffers: [MusicBusEndpoint: PCM] = [:], outputs: [ID: PCM] = [:]
        let needed=audibleAncestors(plan)
        var consumers=audioConsumers(plan,needed:needed)
        for node in plan.orderedNodes where needed.contains(node.id) {
            try Task.checkCancellation()
            if node.content.output == .midi { continue }
            let incoming = plan.connections.filter { $0.to.nodeID == node.id && $0.signal == .audio }
            if case .router(let router) = node.content {
                var inputs: [String: PCM] = [:]
                if !node.muted {
                    for edge in incoming {
                        guard let source = buffers[edge.from] else { continue }
                        if inputs[edge.to.portID] == nil { inputs[edge.to.portID] = PCM(frames: frames) }
                        inputs[edge.to.portID]?.mix(source, gain: edge.gain)
                    }
                }
                var visual = observe == nil ? nil : PCM(frames: frames)
                for portID in AudioRouter.outputs {
                    try Task.checkCancellation()
                    let endpoint = MusicBusEndpoint(nodeID: node.id, portID: portID)
                    guard consumers[endpoint, default: 0] > 0 || observe != nil || observeOutput != nil else { continue }
                    var bus = PCM(frames: frames)
                    if !node.muted {
                        for route in router.routes where route.output == portID {
                            if let input = inputs[route.input] { bus.mix(input, gain: route.gain) }
                        }
                        if node.gain != 1 { bus.multiply(node.gain) }
                        try AutomationDSP.apply(plan.automation[node.id] ?? [], to: &bus)
                    }
                    // Aggregate only for the legacy node meter, never for routing.
                    visual?.mix(bus)
                    observeOutput?(endpoint, bus)
                    if consumers[endpoint, default: 0] > 0 { buffers[endpoint] = bus }
                }
                if let visual { observe?(node.id, visual) }
                release(incoming, consumers: &consumers, buffers: &buffers)
                continue
            }
            var local = PCM(frames: frames)
            let isOutput:Bool = {if case .output = node.content{return true};return false}()
            // A pre-output bounce preserves destination mute, gain and automation for playback.
            // Upstream mute remains part of the captured sound.
            if !node.muted || (isOutput && !applyOutputGain) {
                switch node.content {
                case .instrument(let trackID):
                    guard let track = project.tracks.first(where: { $0.id == trackID }) else { throw CirclrError("서클의 악기를 찾을 수 없습니다") }
                    let midiInputs=plan.connections.filter { $0.to.nodeID == node.id && $0.signal == .midi }
                    let notes=midiInputs.flatMap { plan.midi[$0.from.nodeID] ?? [] }
                    let performances=midiInputs.flatMap { plan.midiPerformances[$0.from.nodeID] ?? [] }
                    let overrideHost = node.settings.tempo.source != .inherit || node.settings.meter.source != .inherit
                    if performances.isEmpty || track.instrument.kind == .synthesizer || expressionTargets.contains(node.id) {
                    local = try await ProductionInstrument.render(notes, instrument: track.instrument, project: project, root: root, clock: clock, tail: tail,
                                                               hostContext: overrideHost ? plan.contexts[node.id] : nil,automation:plan.automation[node.id] ?? [],performances:performances)
                    }
                case .audio, .rhythmAudio:
                    for clip in plan.audio[node.id] ?? [] {
                        try await mixClip(clip, node: node, context: plan.contexts[node.id], project: project, root: root, clock: clock, into: &local)
                    }
                case .effect, .mix, .output:
                    var sidechain = PCM(frames: frames), hasSidechain = false
                    for edge in incoming {
                        guard let source = buffers[edge.from] else { continue }
                        if edge.sidechain { sidechain.mix(source, gain: edge.gain); hasSidechain = true }
                        else { local.mix(source, gain: edge.gain) }
                    }
                    if case .effect(let effect) = node.content {
                        local = try await ArrangementRenderer.apply(local, effect: effect, sidechain: hasSidechain ? sidechain : nil)
                    }
                case .midi, .rhythmMIDI, .router: break
                }
                if node.gain != 1 && (applyOutputGain || !isOutput) { local.multiply(node.gain) }
                if applyOutputGain || !isOutput {try AutomationDSP.apply(plan.automation[node.id] ?? [],to:&local)}
            }
            observe?(node.id, local)
            if case .output(let trackID) = node.content {
                if outputs[trackID] == nil { outputs[trackID] = local }
                else { outputs[trackID]?.mix(local) }
            } else {
                let endpoint = MusicBusEndpoint(nodeID: node.id, portID: CirclePort.audioOutput)
                observeOutput?(endpoint, local)
                if consumers[endpoint, default: 0] > 0 { buffers[endpoint] = local }
            }
            // A fan-out/sidechain source stays alive until its final consumer has rendered.
            release(incoming, consumers: &consumers, buffers: &buffers)
        }
        return outputs
    }

    private static func release(_ incoming: [MusicBusConnection], consumers: inout [MusicBusEndpoint: Int],
                                buffers: inout [MusicBusEndpoint: PCM]) {
        for edge in incoming {
            consumers[edge.from, default: 0] -= 1
            if consumers[edge.from] == 0 { buffers[edge.from] = nil }
        }
    }

    /// Only the built-in synth consumes expression packets; other backends must reject them.
    /// Walk actual ports so muted, disconnected and unused router branches remain usable archives.
    static func validatePitchBendSupport(_ plan:SectionSignalPlan,project:Project,applyOutputGain:Bool=true,
                                         outputTracks:Set<ID>?=nil)throws {
        let needed=audibleExpressionInstruments(plan,project:project,applyOutputGain:applyOutputGain,outputTracks:outputTracks)
        for node in plan.orderedNodes where needed.contains(node.id) {
            if case .instrument(let trackID)=node.content,
               project.tracks.first(where:{$0.id==trackID})?.instrument.kind != .synthesizer {throw unsupportedPitchBend()}
        }
    }
    private static func audibleExpressionInstruments(_ plan:SectionSignalPlan,project:Project,applyOutputGain:Bool,
                                                     outputTracks:Set<ID>?)->Set<ID> {
        var audiblePlan=plan,tracks=project.tracks
        // This renderer returns pre-track PCM. Track mute/gain belong to its arrangement caller.
        for i in tracks.indices {tracks[i].muted=false;tracks[i].gain=1}
        if !applyOutputGain {
            for i in audiblePlan.orderedNodes.indices {
                if case .output=audiblePlan.orderedNodes[i].content {
                    audiblePlan.orderedNodes[i].muted=false;audiblePlan.orderedNodes[i].gain=1
                }
            }
        }
        if let outputTracks {tracks=tracks.filter{outputTracks.contains($0.id)}}
        let paths=PlaybackAnalysis.audiblePaths(audiblePlan,tracks:tracks)
        let instruments=Set(plan.orderedNodes.compactMap{node -> ID? in
            if case .instrument=node.content {return node.id};return nil
        })
        var result=Set<ID>()
        for edge in paths.connections.values where edge.signal == .midi && instruments.contains(edge.to.nodeID) {
            if !(plan.midiPerformances[edge.from.nodeID] ?? []).isEmpty {result.insert(edge.to.nodeID)}
        }
        return result
    }
    static func unsupportedPitchBend()->CirclrError {
        CirclrError("이 악기 또는 연주 경로는 피치 벤드 오디오 렌더를 아직 지원하지 않습니다.")
    }

    static func audibleAncestors(_ plan:SectionSignalPlan)->Set<ID> {
        var needed=Set(plan.orderedNodes.filter{if case .output=$0.content{return true};return false}.map(\.id)),frontier:[ID]=[]
        frontier=Array(needed)
        while let id=frontier.popLast(){for edge in plan.graph.edges where edge.to==id {if needed.insert(edge.from).inserted {frontier.append(edge.from)}}}
        return needed
    }
    static func audioConsumers(_ plan:SectionSignalPlan,needed:Set<ID>)->[MusicBusEndpoint:Int] {
        var result:[MusicBusEndpoint:Int]=[:]
        for edge in plan.connections where edge.signal == .audio && needed.contains(edge.to.nodeID) {result[edge.from,default:0]+=1}
        return result
    }
    static func workingBufferCount(_ plan:SectionSignalPlan)->Int {
        let needed=audibleAncestors(plan);var consumers=audioConsumers(plan,needed:needed)
        var live=Set<MusicBusEndpoint>(),outputs=Set<ID>(),maximum=5
        for node in plan.orderedNodes where needed.contains(node.id) && node.content.output != .midi {
            // Current input, output, sidechain and DSP scratch space, plus retained buffers.
            let scratch: Int = { if case .router = node.content { return 9 }; return 5 }()
            maximum=max(maximum,live.count+outputs.count+scratch)
            if case .output(let track)=node.content {outputs.insert(track)}else{
                for port in CirclePort.ports(for: node.content) where port.direction == .output && port.signal == .audio {
                    let endpoint = MusicBusEndpoint(nodeID: node.id, portID: port.id)
                    if consumers[endpoint, default: 0] > 0 { live.insert(endpoint) }
                }
            }
            for edge in plan.connections where edge.to.nodeID==node.id && edge.signal == .audio {
                consumers[edge.from,default:0]-=1;if consumers[edge.from]==0{live.remove(edge.from)}
            }
        }
        return maximum
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
        let bpm = ownTempo ? tempo : clock.bpm(at: clip.beat + node.startBeat)
        let rate = clip.followsTempo ? bpm / clip.sourceBPM : 1
        guard rate.isFinite, rate > 0 else { throw CirclrError("오디오 tempo 추종 비율을 확인하세요") }
        let period = clip.loopSourceDuration / rate
        guard period.isFinite, period > 0 else { throw CirclrError("오디오 서클의 길이를 확인하세요") }
        let url = try ProjectStore.assetURL(asset, root: root)
        let timing=AudioClipTiming(node:node,context:context ?? project.global,clock:clock)
        try timing.validateTempoFollowing(clip,renderEndSeconds:output.duration)
        for iteration in 0..<node.repeatCount {
            try Task.checkCancellation()
            let position: Double, end: Double
            if let length = node.lengthBeats {
                guard clip.beat < length else { break }
                position = timing.position(clip,iteration:iteration)
                end = min(clock.seconds, time(Double(iteration+1)*length))
            } else { position = start + Double(iteration)*period; end = clip.preservesTail == true ? output.duration : clock.seconds }
            guard position < clock.seconds else { break }
            let remaining = max(0, end-position)
            if remaining <= 0 { continue }
            let part=try ClipAudioRenderer.read(clip,url:url,rate:rate,remaining:remaining)
            output.mix(part, at: Int((position * PCM.rate).rounded()), gain: clip.gain)
        }
    }
}
