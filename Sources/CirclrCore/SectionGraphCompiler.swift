import Foundation

public struct SectionSignalPlan {
    public var graph: SectionGraph
    public var orderedNodes: [MusicCircle]
    public var contexts: [ID: MusicContext]
    /// Event positions are expressed on the parent section's clock after local timing is resolved.
    public var midi: [ID: [Note]]
    public var audio: [ID: [AudioClip]]
    public var midiPerformances: [ID: [MIDIPerformanceStream]] = [:]
    public var connections: [MusicBusConnection] = []
    public var automation:[ID:[AutomationPlan]] = [:]
    public var eventCount: Int {
        midiPerformances.values.reduce(0) { $0 + $1.reduce(0) { $0 + 1 + $1.pitchBendStates.count } } +
        automation.values.reduce(0){$0+$1.reduce(0){$0+$1.spans.count}} + midi.values.reduce(0) { $0 + $1.count } +
        orderedNodes.reduce(0) { $0 + (audio[$1.id]?.count ?? 0) * $1.repeatCount }
    }
}

public enum SectionGraphCompiler {
    public static func compile(project: Project, section: Section, use: SectionUse,
                               context: MusicContext, clock: MusicClock) throws -> SectionSignalPlan? {
        guard let graph = try SectionGraphEditing.effective(section: section, use: use) else { return nil }
        guard use.effects.isEmpty else { throw CirclrError("이 섹션의 이펙트는 내부 음악 그래프에서 편집하세요") }
        let ordered = try SectionGraphValidator.sorted(graph)
        let lanes = try ArrangementCompiler.effectiveLanes(section: section, use: use)
        try ArrangementCompiler.validateLanes(lanes, project: project)
        var plan = SectionSignalPlan(graph: graph, orderedNodes: ordered, contexts: [:], midi: [:], audio: [:])
        plan.connections = graph.edges.map(MusicBusConnection.init)
        for node in ordered {
            try AutomationCompiler.validate(node,project:project)
            let resolved = try ContextResolver.inheriting(global: project.global, parent: context, settings: node.settings)
            plan.contexts[node.id] = resolved
            guard node.startBeat.isFinite, node.startBeat >= 0, node.gain.isFinite, (0...4).contains(node.gain),
                  (1...256).contains(node.repeatCount), node.lengthBeats.map({ $0.isFinite && $0 > 0 && $0 <= 1_048_576 }) ?? true
            else { throw CirclrError("\(node.name): 시작·길이·반복·gain을 확인하세요") }
            if node.content.output == .midi, node.gain != 1 { throw CirclrError("MIDI의 세기는 note velocity로 편집하세요") }
            switch node.content {
            case .instrument, .effect, .mix, .router, .output:
                guard node.startBeat == 0, node.lengthBeats == nil, node.repeatCount == 1 else { throw CirclrError("처리 서클에는 연주 시작·길이·반복을 지정하지 않습니다") }
            default: break
            }
            plan.automation[node.id]=try AutomationCompiler.compile(node,context:resolved,clock:clock)
            guard plan.eventCount<=1_000_000 else{throw CirclrError("섹션 내부의 오토메이션 구간이 너무 많습니다")}
            switch node.content {
            case .midi(let laneID):
                guard let lane = lanes.first(where: { $0.id == laneID }) else { throw CirclrError("\(node.name)의 MIDI 연주 원본을 찾을 수 없습니다") }
                plan.midi[node.id] = try scheduledNotes(lane.notes, node: node, context: resolved, parentClock: clock)
                if let bend = lane.pitchBend {
                    plan.midiPerformances[node.id] = try performanceStreams(notes: lane.notes, sequence: bend, grid: resolved.beatGrid, node: node, context: resolved, parentClock: clock)
                }
            case .audio(let laneID, let clipID):
                guard let clip = lanes.first(where: { $0.id == laneID })?.audio.first(where: { $0.id == clipID }) else { throw CirclrError("\(node.name)의 오디오 clip을 찾을 수 없습니다") }
                plan.audio[node.id] = [clip]
            case .instrument(let trackID), .output(let trackID):
                guard project.tracks.contains(where: { $0.id == trackID }) else { throw CirclrError("\(node.name)의 악기·출력 트랙을 찾을 수 없습니다") }
            case .effect(let effect):
                guard effect.amount.isFinite, effect.secondary.isFinite else { throw CirclrError("이펙트 parameter를 확인하세요") }
            case .mix: break
            case .router(let router): try router.validate()
            case .rhythmMIDI(let trackID), .rhythmAudio(let trackID):
                guard project.tracks.contains(where: { $0.id == trackID }) else { throw CirclrError("리듬 패턴의 트랙을 찾을 수 없습니다") }
                guard let patternID = resolved.rhythm.patternID else { continue }
                guard let pattern = project.patterns.first(where: { $0.id == patternID }) else { throw CirclrError("리듬 패턴을 찾을 수 없습니다") }
                try ArrangementCompiler.validatePattern(pattern, project: project)
                guard pattern.trackID == trackID else { continue }
                let expanded = try expandedPatternNotesOnly(pattern, length: clock.beats, grid: resolved.beatGrid)
                if case .rhythmMIDI = node.content {
                    plan.midi[node.id] = try scheduledNotes(expanded.notes, node: node, context: resolved, parentClock: clock)
                    if let bend = pattern.pitchBend {
                        plan.midiPerformances[node.id] = try performanceStreams(notes: pattern.notes, sequence: bend, patternLength: pattern.length, grid: resolved.beatGrid, node: node, context: resolved, parentClock: clock)
                    }
                } else { plan.audio[node.id] = expanded.audio }
            }
            guard plan.eventCount <= 1_000_000 else { throw CirclrError("섹션 내부의 재생 event가 너무 많습니다") }
        }
        return plan
    }

    public static func scheduledNotes(_ notes: [Note], node: MusicCircle, context: MusicContext, parentClock: MusicClock) throws -> [Note] {
        if node.muted { return [] }
        let length = node.lengthBeats ?? parentClock.beats
        guard length.isFinite, length > 0, (1...256).contains(node.repeatCount) else { throw CirclrError("MIDI 서클의 길이·반복을 확인하세요") }
        var output: [Note] = []
        let ownTempo = node.settings.tempo.source != .inherit
        let offset = parentClock.seconds(at: node.startBeat)
        for iteration in 0..<node.repeatCount {
            for note in notes {
                try ArrangementCompiler.validateNote(note)
                guard note.beat < length else { continue }
                let startQ = Double(iteration) * length + note.beat
                let endQ = Double(iteration) * length + min(length, note.beat + note.length)
                let start = ownTempo ? offset + startQ * 60 / context.tempo : parentClock.seconds(at: node.startBeat + startQ)
                let end = min(parentClock.seconds, ownTempo ? offset + endQ * 60 / context.tempo : parentClock.seconds(at: node.startBeat + endQ))
                guard start < end else { continue }
                var copy = note
                copy.id = "\(node.id):\(note.id):\(iteration)"
                copy.beat = parentClock.beat(atSeconds: start)
                copy.length = parentClock.beat(atSeconds: end) - copy.beat
                output.append(copy)
                guard output.count <= 1_000_000 else { throw CirclrError("MIDI 서클의 event가 너무 많습니다") }
            }
        }
        return output
    }

    public static func expandedPattern(_ pattern: RhythmPattern, length: Double, grid: BeatGrid) throws -> Lane {
        guard pattern.pitchBend == nil else { throw CirclrError("피치 벤드 패턴은 독립 MIDI 연주 stream으로 준비해야 합니다") }
        return try expandedPatternNotesOnly(pattern, length: length, grid: grid)
    }

    private static func expandedPatternNotesOnly(_ pattern: RhythmPattern, length: Double, grid: BeatGrid) throws -> Lane {
        guard pattern.length.isFinite, pattern.length > 0, length.isFinite, length > 0 else { throw CirclrError("리듬 패턴의 길이를 확인하세요") }
        let repeats = ceil(length / pattern.length)
        guard repeats * Double(pattern.notes.count + pattern.audio.count) <= 1_000_000 else { throw CirclrError("리듬 패턴의 event가 너무 많습니다") }
        var lane = Lane(trackID: pattern.trackID), offset = 0.0
        if pattern.notes.isEmpty && pattern.audio.isEmpty { return lane }
        let step = 1 / Double(max(1, grid.subdivisions))
        while offset < length - 0.000001 {
            for var note in pattern.notes {
                let stepIndex = Int((note.beat / step).rounded())
                note.beat += offset + (stepIndex % 2 == 1 ? grid.swing * step : 0)
                if note.beat < length { note.length = min(note.length, length - note.beat); lane.notes.append(note) }
            }
            for var clip in pattern.audio { clip.beat += offset; if clip.renderWindow != nil { clip.renderWindow?.cycleBeat += offset }; if clip.beat < length { lane.audio.append(clip) } }
            offset += pattern.length
        }
        return lane
    }
}
