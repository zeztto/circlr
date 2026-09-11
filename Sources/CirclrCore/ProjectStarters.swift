import Foundation

public struct ProjectStarter: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
}

/// Editable arrangements, not prerecorded music. No external assets or plug-ins are required.
public enum ProjectStarters {
    public static let catalog: [ProjectStarter] = [
        .init(id: "blank", title: "새 곡", detail: "건반 1트랙 · 4마디 섹션 · 120 BPM"),
        .init(id: "electronic", title: "전자음악", detail: "드럼·베이스·패드·플럭·리드 · 4섹션 · 120 BPM"),
        .init(id: "piano", title: "피아노", detail: "피아노·스트링 · 3섹션 · 80 BPM"),
        .init(id: "band", title: "밴드", detail: "드럼·베이스·기타·EP·오르간 · 4섹션 · 110 BPM")
    ]

    public static func make(id: String, name: String? = nil) throws -> Project {
        guard let starter = catalog.first(where: { $0.id == id }) else {
            throw CirclrError("시작 템플릿을 찾을 수 없습니다")
        }
        var project = Project()
        let suppliedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        project.name = suppliedName.flatMap { $0.isEmpty ? nil : $0 } ?? (id == "blank" ? "새 곡" : "\(starter.title) 곡")
        project.global.scale = Scale(root: 0, name: "major", intervals: [0, 2, 4, 5, 7, 9, 11])
        project.global.beatGrid = BeatGrid(subdivisions: 4, accents: [4])
        let tracks: [(String, Instrument, CircleColor.Preset)]
        let sections: [(String, Int)]
        switch id {
        case "electronic":
            project.global.scale = Scale(root: 9)
            tracks = [("드럼", Instrument(drums: true), .coral), ("베이스", .synthesizer(.bass), .amber),
                      ("패드", .synthesizer(.pad), .violet), ("플럭", .synthesizer(.pluck), .teal),
                      ("리드", .synthesizer(.lead), .rose)]
            sections = [("인트로", 8), ("벌스", 16), ("코러스", 16), ("아웃트로", 8)]
        case "piano":
            project.global.tempo = 80
            tracks = [("피아노", Instrument(program: 0), .blue), ("스트링", .synthesizer(.strings), .violet)]
            sections = [("주제", 8), ("전개", 8), ("재현", 8)]
        case "band":
            project.global.tempo = 110
            tracks = [("드럼", Instrument(drums: true), .coral), ("베이스", Instrument(program: 33), .amber),
                      ("기타", Instrument(program: 27), .teal), ("EP", .synthesizer(.electricPiano), .blue),
                      ("오르간", .synthesizer(.organ), .violet)]
            sections = [("인트로", 4), ("벌스", 8), ("코러스", 8), ("브리지", 8)]
        default:
            tracks = [("건반", .synthesizer(.keys), .blue)]
            sections = [("섹션 1", 4)]
        }
        for (title, instrument, _) in tracks {
            let trackID = project.addTrack(name: title)
            if let index = project.tracks.firstIndex(where: { $0.id == trackID }) {
                project.tracks[index].instrument = instrument
                project.tracks[index].gain = 0.6
            }
        }
        for (index, section) in sections.enumerated() {
            _ = project.addSection(name: section.0, at: Point(Double(index) * 480, 0), bars: section.1)
        }
        let ai = project.activeIndex
        for index in project.arrangements[ai].uses.indices.dropLast() {
            let edge = FlowEdge(from: project.arrangements[ai].uses[index].id, to: project.arrangements[ai].uses[index + 1].id)
            project.arrangements[ai].uses[index].isEnd = false
            project.arrangements[ai].edges.append(edge)
            project.arrangements[ai].chosenEdges[edge.from] = edge.id
        }
        // Minimal real signal chains keep an empty writing workspace legible.
        for index in project.sections.indices {
            var graph = SectionGraph()
            for (trackIndex, lane) in project.sections[index].lanes.enumerated() {
                let title = project.tracks[trackIndex].name
                let midi = MusicCircle(name: "\(title) MIDI", content: .midi(laneID: lane.id))
                let instrument = MusicCircle(name: title, content: .instrument(trackID: lane.trackID))
                let output = MusicCircle(name: "\(title) 출력", content: .output(trackID: lane.trackID))
                graph.nodes += [midi, instrument, output]
                graph.edges += [MusicConnection(from: midi.id, to: instrument.id, signal: .midi),
                                MusicConnection(from: instrument.id, to: output.id, signal: .audio)]
                for (column, node) in [midi, instrument, output].enumerated() {
                    graph.layout.positions[node.id] = Point(Double(column) * 240, Double(trackIndex) * 240)
                }
            }
            project.sections[index].graph = graph
        }
        project.enableAlbum()
        var colors: [CircleAddress: CircleColor] = [:]
        let sectionPalette: [CircleColor.Preset] = [.teal, .blue, .rose, .amber]
        for (index, use) in project.active.uses.enumerated() {
            colors[.section(arrangementID: project.activeArrangementID, useID: use.id)] = sectionPalette[index % sectionPalette.count].color
            for node in project.sections[index].graph?.nodes ?? [] {
                if case .instrument(let trackID) = node.content,
                   let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID }) {
                    colors[.music(arrangementID: project.activeArrangementID, useID: use.id, nodeID: node.id)] = tracks[trackIndex].2.color
                }
            }
        }
        project.circleColors = colors
        try ProjectStore.validateStructure(project)
        _ = try ArrangementCompiler.compile(project)
        return project
    }
}
