import Foundation

public struct CirclrError: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public enum ContextResolver {
    public static func value<T>(_ global: T, _ definition: Setting<T>, _ use: Setting<T>) throws -> T where T: Codable & Equatable {
        switch use.source {
        case .local: guard let v = use.value else { throw CirclrError("개별 설정값이 없습니다") }; return v
        case .global: return global
        case .inherit:
            if definition.source == .local { guard let v = definition.value else { throw CirclrError("원본 설정값이 없습니다") }; return v }
            return global
        }
    }
    public static func resolve(_ global: MusicContext, _ definition: ContextSettings, _ use: ContextSettings) throws -> MusicContext {
        var c = MusicContext()
        c.tempo = try value(global.tempo, definition.tempo, use.tempo)
        c.scale = try value(global.scale, definition.scale, use.scale)
        c.meter = try value(global.meter, definition.meter, use.meter)
        c.beatGrid = try value(global.beatGrid, definition.beatGrid, use.beatGrid)
        c.rhythm = try value(global.rhythm, definition.rhythm, use.rhythm)
        try validate(c)
        return c
    }
    public static func validate(_ c: MusicContext) throws {
        guard c.tempo.isFinite, (1...999).contains(c.tempo) else { throw CirclrError("Tempo는 1–999 BPM으로 지정하세요") }
        try validate(c.meter)
        guard (0...11).contains(c.scale.root), !c.scale.intervals.isEmpty, c.scale.intervals.allSatisfy({ (0...11).contains($0) }) else { throw CirclrError("Scale의 root와 음 집합을 확인하세요") }
        guard (1...32).contains(c.beatGrid.subdivisions), c.beatGrid.swing.isFinite, (0...0.75).contains(c.beatGrid.swing), c.beatGrid.accents.count <= 64, c.beatGrid.accents.allSatisfy({ (1...64).contains($0) }) else { throw CirclrError("박 분할·강세·swing 설정을 확인하세요") }
    }
    public static func validate(_ m: Meter) throws {
        guard (1...64).contains(m.numerator), [1,2,4,8,16,32,64].contains(m.denominator) else { throw CirclrError("박자표의 분자와 분모를 확인하세요") }
    }
}
public struct MusicClock: Equatable {
    public let barStarts: [Double]
    /// First bar boundary at or after the clock end, before truncating a partial bar.
    /// Used by editor rulers only; beat/second conversion and playback are unchanged.
    public let barContinuationBeat: Double
    public let meters: [Meter]
    public let tempos: [TempoChange]
    /// Reconstitutes an exact clock, including inherited partial first/last bars.
    public init(barStarts: [Double], barContinuationBeat: Double, meters: [Meter], tempos: [TempoChange]) throws {
        guard (1...4096).contains(meters.count), barStarts.count == meters.count + 1,
              barStarts.first == 0, barStarts.allSatisfy({ $0.isFinite && $0 >= 0 }),
              zip(barStarts, barStarts.dropFirst()).allSatisfy({ $0 < $1 }),
              barContinuationBeat.isFinite, let end = barStarts.last,
              barContinuationBeat >= end, let lastStart = barStarts.dropLast().last,
              let lastMeter = meters.last, barContinuationBeat <= lastStart + lastMeter.quarters + 1e-8,
              !tempos.isEmpty, tempos.count <= 100_000, tempos.first?.beat == 0,
              tempos.allSatisfy({ $0.beat.isFinite && $0.beat >= 0 && $0.beat < end && $0.bpm.isFinite && (1...999).contains($0.bpm) }),
              zip(tempos, tempos.dropFirst()).allSatisfy({ $0.beat < $1.beat }) else {
            throw CirclrError("악기 렌더의 시간 지도를 확인하세요")
        }
        for (index, meter) in meters.enumerated() {
            try ContextResolver.validate(meter)
            guard barStarts[index+1] - barStarts[index] <= meter.quarters + 1e-8 else {
                throw CirclrError("악기 렌더의 마디 길이를 확인하세요")
            }
        }
        self.barStarts = barStarts; self.barContinuationBeat = barContinuationBeat
        self.meters = meters; self.tempos = tempos
    }
    public var beats: Double { barStarts.last ?? 0 }
    public var seconds: Double { seconds(at: beats) }
    public init(bars: Int, context: MusicContext, meterChanges: [MeterChange] = [], tempoChanges: [TempoChange] = []) throws {
        guard (1...4096).contains(bars) else { throw CirclrError("섹션 길이는 1–4096마디로 지정하세요") }
        try ContextResolver.validate(context)
        guard Set(meterChanges.map(\.bar)).count == meterChanges.count, meterChanges.allSatisfy({ $0.bar >= 0 && $0.bar < bars }) else { throw CirclrError("변박 위치가 겹치거나 섹션 밖에 있습니다") }
        var starts = [0.0], ms: [Meter] = [], current = context.meter
        for bar in 0..<bars {
            if let change = meterChanges.first(where: { $0.bar == bar }) { current = change.meter }
            try ContextResolver.validate(current)
            ms.append(current); starts.append(starts.last! + current.quarters)
        }
        barStarts = starts; meters = ms; barContinuationBeat = starts.last!
        guard tempoChanges.allSatisfy({ $0.beat.isFinite && $0.beat >= 0 && $0.beat < starts.last! && $0.bpm.isFinite && (1...999).contains($0.bpm) }), Set(tempoChanges.map(\.beat)).count == tempoChanges.count else { throw CirclrError("Tempo map의 위치와 BPM을 확인하세요") }
        var ts = tempoChanges.sorted { $0.beat < $1.beat }
        if ts.first?.beat != 0 { ts.insert(TempoChange(beat: 0, bpm: context.tempo), at: 0) }
        tempos = ts
    }
    public init(beats: Double, context: MusicContext, tempoChanges: [TempoChange] = []) throws {
        guard beats.isFinite, beats>0, context.meter.quarters>0 else { throw CirclrError("녹음 서클의 길이를 확인하세요") }
        let count=ceil(beats/context.meter.quarters)
        guard count<=4096 else { throw CirclrError("녹음 서클은 4096마디 이내로 지정하세요") }
        let full=try MusicClock(bars:max(1,Int(count)),context:context,tempoChanges:tempoChanges.filter{$0.beat<beats})
        barStarts=full.barStarts.filter{$0<beats}+[beats];meters=Array(full.meters.prefix(barStarts.count-1));tempos=full.tempos
        barContinuationBeat=full.barContinuationBeat
    }
    public func bpm(at beat: Double) -> Double { tempos.last(where: { $0.beat <= beat })?.bpm ?? tempos[0].bpm }
    public init(parent: MusicClock, start: Double, length: Double, context: MusicContext, inheritTempo: Bool, inheritMeter: Bool) throws {
        var resolved=context
        if inheritTempo {resolved.tempo=parent.bpm(at:start)}
        let changes=inheritTempo ? parent.tempos.filter{$0.beat>start && $0.beat<start+length}.map{TempoChange(beat:$0.beat-start,bpm:$0.bpm)}:[]
        let base=try MusicClock(beats:length,context:resolved,tempoChanges:changes)
        tempos=base.tempos
        guard inheritMeter else {barStarts=base.barStarts;meters=base.meters;barContinuationBeat=base.barContinuationBeat;return}
        var starts=[0.0],ms:[Meter]=[]
        var absolute=start,continuation=length
        while absolute<start+length-1e-9 {
            guard ms.count<4096 else {throw CirclrError("서클은 4096마디 이내로 지정하세요")}
            let meter=parent.meters[parent.bar(at:absolute)]
            let next=parent.barStarts.first{$0>absolute+1e-9} ?? absolute+meter.quarters
            continuation=(next==parent.beats ? parent.barContinuationBeat:next)-start
            absolute=min(start+length,next);starts.append(absolute-start);ms.append(meter)
        }
        barStarts=starts;meters=ms;barContinuationBeat=continuation
    }
    public func seconds(at beat: Double) -> Double {
        if beat <= 0 { return beat * 60 / tempos[0].bpm }
        var total = 0.0
        for i in tempos.indices {
            let start = tempos[i].beat
            if start >= beat { break }
            let end = min(beat, i + 1 < tempos.count ? tempos[i + 1].beat : beat)
            total += (end - start) * 60 / tempos[i].bpm
        }
        return total
    }
    public func beat(atSeconds time: Double) -> Double {
        if time <= 0 { return time * tempos[0].bpm / 60 }
        var remainder = time
        for i in tempos.indices {
            if i + 1 < tempos.count {
                let duration = (tempos[i+1].beat - tempos[i].beat) * 60 / tempos[i].bpm
                if remainder >= duration { remainder -= duration; continue }
            }
            return tempos[i].beat + remainder * tempos[i].bpm / 60
        }
        return beats
    }
    public func bar(at beat: Double) -> Int { max(0, min(meters.count - 1, (barStarts.lastIndex(where: { $0 <= beat }) ?? 0))) }
    public func beatAtBar(_ fractionalBar: Double) -> Double {
        let clamped = min(Double(meters.count), max(0, fractionalBar))
        let whole = Int(clamped)
        if whole == meters.count { return beats }
        return barStarts[whole] + (clamped - Double(whole)) * meters[whole].quarters
    }
    public func angle(at beat: Double) -> Double { beat / beats * 360 }
}
public struct Occurrence {
    public var signalPlan: SectionSignalPlan? = nil
    public var id: ID = newID()
    public var use: SectionUse
    public var section: Section
    public var iteration: Int
    public var context: MusicContext
    public var clock: MusicClock
    public var lanes: [Lane]
    public var start: Double
    public var duration: Double { clock.seconds }
    public var end: Double { start + duration }
}
public struct ScheduledTransition {
    public var edgeID: ID
    public var transition: Transition
    public var start: Double
    public var duration: Double
    public var sourceOccurrenceID: ID
    public var targetOccurrenceID: ID
    public var context: MusicContext
}
public struct ExecutionPlan {
    public var revision: Int
    public var arrangementID: ID
    public var occurrences: [Occurrence]
    public var transitions: [ScheduledTransition]
    public var duration: Double
    public var warnings: [String]
}
public enum ArrangementCompiler {
    public static func effectiveLanes(section: Section, use: SectionUse) throws -> [Lane] {
        let ids = Set(section.lanes.map(\.id))
        if use.laneOverrides.keys.contains(where: { !ids.contains($0) }) { throw CirclrError("\(use.name): 원본에서 삭제된 lane의 변형이 있습니다. 분리 또는 원본 적용이 필요합니다") }
        return section.lanes.filter { !use.excludedLaneIDs.contains($0.id) }.map { use.laneOverrides[$0.id] ?? $0 } + use.addedLanes
    }
    public static func context(project: Project, use: SectionUse, arrangementID: ID? = nil) throws -> (Section, MusicContext, MusicClock) {
        guard let section = project.sections.first(where: { $0.id == use.sectionID }) else { throw CirclrError("\(use.name)의 섹션 원본을 찾을 수 없습니다") }
        let ownerID = arrangementID ?? project.arrangements.first(where: { $0.uses.contains(where: { $0.id == use.id }) })?.id ?? project.activeArrangementID
        let parent = try project.compositionContext(for: ownerID)
        let definition = try ContextResolver.inheriting(global: project.global, parent: parent, settings: section.settings)
        var c = try ContextResolver.inheriting(global: project.global, parent: definition, settings: use.settings)
        // An explicit per-use/global tempo or meter replaces the definition's map.
        let tempoMap = use.tempoOverride?.changes ?? (use.settings.tempo.source == .inherit ? section.tempoChanges : [])
        if let mapOverride=use.tempoOverride {
            guard project.schemaVersion>=4 else{throw CirclrError("이번 사용 템포 맵에는 version 4 프로젝트가 필요합니다")}
            c.tempo=mapOverride.initialBPM
        }
        let meterMap = use.settings.meter.source == .inherit ? section.meterChanges : []
        let clock=try MusicClock(bars:use.barsOverride ?? section.bars,context:c,meterChanges:meterMap,tempoChanges:tempoMap)
        try use.tempoOverride?.validate(beats:clock.beats)
        return (section,c,clock)
    }
    public static func compile(_ project: Project, arrangementID: ID? = nil, onlyUseID: ID? = nil) throws -> ExecutionPlan {
        guard (1...6).contains(project.schemaVersion) else { throw CirclrError("이 프로젝트의 형식 버전을 지원하지 않습니다") }
        guard let a = project.arrangements.first(where: { $0.id == (arrangementID ?? project.activeArrangementID) }) else { throw CirclrError("편곡안을 찾을 수 없습니다") }
        if a.uses.isEmpty { return ExecutionPlan(revision: project.musicRevision, arrangementID: a.id, occurrences: [], transitions: [], duration: 0, warnings: []) }
        var flow = try ArrangementFlowCursor(a, onlyUseID: onlyUseID)
        var occurrences: [Occurrence] = [], transitions: [ScheduledTransition] = [], warnings: [String] = [], cursor = 0.0
        var pending: (FlowEdge, Occurrence)?
        var eventCount = 0
        while let use = try flow.next() {
            guard use.gain.isFinite && (0...4).contains(use.gain) else { throw CirclrError("서클 gain 값을 확인하세요") }
            let (section, context, clock) = try context(project: project, use: use, arrangementID: a.id)
            let lanes = try effectiveLanes(section: section, use: use)
            try validateLanes(lanes, project: project)
            let signalPlan = try SectionGraphCompiler.compile(project: project, section: section, use: use, context: context, clock: clock)
            if signalPlan == nil && lanes.contains(where: { $0.pitchBend != nil }) { throw CirclrError("피치 벤드 연주는 섹션 음악 그래프가 필요합니다") }
            for lane in lanes {
                if lane.notes.contains(where: { $0.beat + $0.length > clock.beats + 0.000001 }) { warnings.append("\(use.name): 섹션 끝에서 MIDI note를 종료합니다") }
            }
            if !context.beatGrid.accents.isEmpty && context.beatGrid.accents.reduce(0,+) != context.meter.numerator { warnings.append("\(use.name): 강세 설정 확인") }
            if let patternID = context.rhythm.patternID {
                guard let pattern = project.patterns.first(where: { $0.id == patternID }) else { throw CirclrError("\(use.name): 리듬 패턴을 찾을 수 없습니다") }
                try validatePattern(pattern, project: project)
                if pattern.meter != context.meter { warnings.append("\(use.name): 패턴 \(pattern.meter.label) / 서클 \(context.meter.label)") }
                if signalPlan == nil && pattern.pitchBend != nil { throw CirclrError("피치 벤드 패턴은 섹션 음악 그래프가 필요합니다") }
                if signalPlan == nil { eventCount += Int(ceil(clock.beats / pattern.length)) * (pattern.notes.count + pattern.audio.count) * use.repeatCount }
            }
            eventCount += (signalPlan?.eventCount ?? lanes.reduce(0) { $0 + $1.notes.count + $1.audio.count }) * use.repeatCount
            guard eventCount <= 1_000_000 else { throw CirclrError("재생 event가 너무 많습니다. 반복 범위를 줄여주세요") }
            for iteration in 0..<use.repeatCount {
                var occurrence = Occurrence(use: use, section: section, iteration: iteration, context: context, clock: clock, lanes: lanes, start: cursor)
                occurrence.signalPlan = signalPlan
                if iteration == 0, let (edge, source) = pending {
                    let t = edge.transition
                    let timing=try TransitionTiming(t,source:source.clock,target:clock)
                    let duration=timing.duration, start=source.end+timing.startOffset
                    occurrence.start += timing.targetOffset
                    if let p = t.patternID {
                        guard let pattern = project.patterns.first(where: { $0.id == p }) else { throw CirclrError("전환 패턴을 찾을 수 없습니다") }
                        try validatePattern(pattern, project: project)
                        guard pattern.pitchBend == nil else { throw CirclrError("전환 패턴의 피치 벤드 연주는 아직 지원하지 않습니다") }
                    }
                    if duration > 0 { transitions.append(ScheduledTransition(edgeID: edge.id, transition: t, start: start, duration: duration, sourceOccurrenceID: source.id, targetOccurrenceID: occurrence.id, context: source.context)) }
                    pending = nil
                }
                let active = occurrences.filter { $0.start < occurrence.start + 0.000001 && $0.end > occurrence.start + 0.000001 }
                guard active.count < 2 else { throw CirclrError("세 섹션이 동시에 겹칩니다. 전환 길이를 줄이세요") }
                occurrences.append(occurrence); cursor = occurrence.end
                guard occurrences.count <= 10_000, cursor <= 3600 else { throw CirclrError("한 번에 준비할 수 있는 1시간/10,000회 범위를 넘었습니다") }
            }
            if let edge = try flow.advance(after: use) { pending = (edge, occurrences.last!) }
        }
        _ = try SignalValidator.sorted(project.signal, tracks: project.tracks)
        return ExecutionPlan(revision: project.musicRevision, arrangementID: a.id, occurrences: occurrences, transitions: transitions, duration: occurrences.map(\.end).max() ?? 0, warnings: Array(Set(warnings)).sorted())
    }
    public static func validateNote(_ note: Note) throws {
        guard note.beat.isFinite, note.length.isFinite, note.beat >= 0, note.length > 0, (0...127).contains(note.pitch), (1...127).contains(note.velocity) else { throw CirclrError("MIDI note의 위치·길이·pitch·velocity를 확인하세요") }
    }
    public static func validateLanes(_ lanes: [Lane], project: Project) throws {
        for lane in lanes {
            guard project.tracks.contains(where: { $0.id == lane.trackID }) else { throw CirclrError("연주 트랙을 찾을 수 없습니다") }
            try lane.pitchBend?.validate()
            if lane.pitchBend != nil && project.schemaVersion < 5 { throw CirclrError("피치 벤드에는 version 5 프로젝트가 필요합니다") }
            for note in lane.notes { try validateNote(note) }
            for clip in lane.audio {
                guard project.assets.contains(where: { $0.id == clip.assetID }), clip.beat.isFinite, clip.beat >= 0, clip.duration.isFinite, clip.duration > 0, clip.sourceStart.isFinite, clip.sourceStart >= 0, clip.gain.isFinite, (0...4).contains(clip.gain), clip.sourceBPM.isFinite, clip.sourceBPM > 0 else { throw CirclrError("오디오 clip의 파일·위치·길이를 확인하세요") }
                if let asset=project.assets.first(where:{$0.id==clip.assetID}) {try clip.validateEditing(asset:asset,checkBounds:false)}
            }
        }
    }
    public static func validatePattern(_ pattern: RhythmPattern, project: Project) throws {
        guard pattern.length.isFinite, (1.0/1024...1_048_576).contains(pattern.length) else { throw CirclrError("패턴 길이를 확인하세요") }
        var lane = Lane(trackID: pattern.trackID); lane.notes = pattern.notes; lane.audio = pattern.audio; lane.pitchBend = pattern.pitchBend
        try validateLanes([lane], project: project)
        guard pattern.notes.allSatisfy({ $0.beat < pattern.length }) else { throw CirclrError("패턴 밖의 note 위치를 확인하세요") }
    }
}
public enum SignalValidator {
    public static func sorted(_ graph: SignalGraph, tracks: [Track]) throws -> [SignalNode] {
        guard Set(graph.nodes.map(\.id)).count == graph.nodes.count, graph.nodes.filter({ $0.kind == .master }).count == 1 else { throw CirclrError("사운드 그래프에는 중복 없는 노드와 출력 하나가 필요합니다") }
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        for edge in graph.edges {
            guard let from = nodes[edge.from], let to = nodes[edge.to], from.kind != .master, to.kind != .source, edge.gain.isFinite, (0...4).contains(edge.gain) else { throw CirclrError("사운드 포트 또는 연결 gain을 확인하세요") }
            if edge.sidechain && !(to.kind == .effect && to.effect.kind == .compressor) { throw CirclrError("Sidechain은 compressor 입력에만 연결할 수 있습니다") }
        }
        for node in graph.nodes where node.kind == .source {
            guard tracks.contains(where: { $0.id == node.trackID }) else { throw CirclrError("사운드 source의 트랙을 찾을 수 없습니다") }
        }
        var result: [SignalNode] = [], done = Set<ID>(), stack = Set<ID>()
        func visit(_ id: ID) throws {
            if done.contains(id) { return }
            guard stack.insert(id).inserted else { throw CirclrError("사운드 순환 연결을 발견했습니다") }
            for edge in graph.edges where edge.to == id { try visit(edge.from) }
            stack.remove(id); done.insert(id); if let n = nodes[id] { result.append(n) }
        }
        for node in graph.nodes { try visit(node.id) }
        return result
    }
}
