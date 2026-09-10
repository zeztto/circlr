import Foundation

public enum SectionGraphMigration {
    /// Explicit, transactional migration; the caller controls when to save the resulting document.
    public static func migrate(_ input: Project) throws -> Project {
        guard (1...6).contains(input.schemaVersion) else { throw CirclrError("지원하지 않는 음악 문서 형식입니다") }
        var result = input
        let migrating = Set(input.sections.filter { $0.graph == nil }.map(\.id))
        for i in result.sections.indices where migrating.contains(result.sections[i].id) {
            result.sections[i].graph = graph(lanes: result.sections[i].lanes, tracks: result.tracks, effects: [])
        }
        for ai in result.arrangements.indices {
            for ui in result.arrangements[ai].uses.indices {
                let use = result.arrangements[ai].uses[ui]
                guard migrating.contains(use.sectionID),
                      let section = result.sections.first(where: { $0.id == use.sectionID }), let base = section.graph else { continue }
                let effective = try ArrangementCompiler.effectiveLanes(section: section, use: use)
                let edited = graph(lanes: effective, tracks: result.tracks, effects: use.effects)
                let patch = SectionGraphEdits.difference(original: base, edited: edited)
                result.arrangements[ai].uses[ui].graphEdits = patch.isEmpty ? nil : patch
                result.arrangements[ai].uses[ui].effects = []
            }
        }
        result.schemaVersion = max(2,result.schemaVersion)
        try ProjectStore.validateStructure(result)
        return result
    }

    /// The old renderer combined a track's notes and clips before its per-use effects.
    /// Preserve that exact processing order, including the inherited rhythm source.
    public static func graph(lanes: [Lane], tracks: [Track], effects: [Effect], includeMIDI:Bool = true) -> SectionGraph {
        var graph = SectionGraph()
        func add(_ id: ID, _ name: String, _ content: MusicCircleContent, _ x: Double, _ y: Double) {
            var node = MusicCircle(name: name, content: content); node.id = id
            graph.nodes.append(node); graph.layout.positions[id] = Point(x, y)
        }
        func connect(_ from: ID, _ to: ID, _ signal: MusicSignal) {
            var edge = MusicConnection(from: from, to: to, signal: signal)
            edge.id = "\(from)>\(to)"; graph.edges.append(edge)
        }
        var y = 0.0
        for track in tracks {
            let instrument = "instrument:\(track.id)", mix = "mix:\(track.id)", output = "output:\(track.id)"
            if includeMIDI {add(instrument, track.name, .instrument(trackID: track.id), -80, y)}
            add(mix, "\(track.name) 믹스", .mix, 170, y)
            if includeMIDI {connect(instrument, mix, .audio)}
            var sourceIndex = 0
            for lane in lanes where lane.trackID == track.id {
                let midi = "midi:\(lane.id)"
                if includeMIDI {
                    add(midi, "\(track.name) MIDI", .midi(laneID: lane.id), -350, y + Double(sourceIndex) * 200)
                    sourceIndex += 1; connect(midi, instrument, .midi)
                }
                for clip in lane.audio {
                    let audio = "audio:\(clip.id)"
                    add(audio, "오디오", .audio(laneID: lane.id, clipID: clip.id), -350, y + Double(sourceIndex) * 200)
                    sourceIndex += 1; connect(audio, mix, .audio)
                }
            }
            let rhythmMIDI = "rhythm-midi:\(track.id)", rhythmAudio = "rhythm-audio:\(track.id)"
            if includeMIDI {add(rhythmMIDI, "상속한 MIDI 리듬", .rhythmMIDI(trackID: track.id), -350, y - 140)}
            add(rhythmAudio, "상속한 오디오 리듬", .rhythmAudio(trackID: track.id), -80, y - 140)
            if includeMIDI {connect(rhythmMIDI, instrument, .midi)}
            connect(rhythmAudio, mix, .audio)
            var previous = mix
            for (index, effect) in effects.enumerated() {
                let id = "effect:\(track.id):\(index)"
                add(id, effect.kind.rawValue, .effect(effect), 410 + Double(index) * 220, y)
                connect(previous, id, .audio); previous = id
            }
            add(output, "\(track.name) 출력", .output(trackID: track.id), 410 + Double(effects.count) * 220, y)
            connect(previous, output, .audio)
            y += max(1, Double(sourceIndex)) * 200 + 240
        }
        return graph
    }
}
