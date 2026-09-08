import Foundation

public enum MusicSignal: String, Codable, Sendable { case midi, audio }
public enum MusicCircleContent: Codable, Equatable {
    case midi(laneID: ID)
    case audio(laneID: ID, clipID: ID)
    case instrument(trackID: ID)
    case effect(Effect)
    case mix
    case router(AudioRouter)
    case output(trackID: ID)
    case rhythmMIDI(trackID: ID)
    case rhythmAudio(trackID: ID)

    public var input: MusicSignal? {
        switch self {
        case .instrument: return .midi
        case .effect, .mix, .router, .output: return .audio
        default: return nil
        }
    }
    public var output: MusicSignal? {
        switch self {
        case .midi, .rhythmMIDI: return .midi
        case .output: return nil
        default: return .audio
        }
    }
    public var label: String {
        switch self {
        case .midi: return "MIDI"
        case .audio: return "오디오"
        case .instrument: return "악기"
        case .effect: return "이펙터"
        case .mix: return "믹스"
        case .router: return "오디오 라우터"
        case .output: return "출력"
        case .rhythmMIDI, .rhythmAudio: return "리듬 패턴"
        }
    }
}

/// Notes and clips remain in their existing original/variant lanes.
/// This node owns musical context and routing, not a second copy of the media.
public struct MusicCircle: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var name: String
    public var content: MusicCircleContent
    public var settings = ContextSettings()
    public var startBeat: Double = 0
    public var lengthBeats: Double?
    public var repeatCount: Int = 1
    public var gain: Double = 1
    public var muted = false
    public var bounce: BounceSource?
    public var automation:[AutomationLane]?
    public init(name: String, content: MusicCircleContent) { self.name = name; self.content = content }
}

public struct MusicConnection: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var from: ID
    public var to: ID
    public var signal: MusicSignal
    public var gain: Double = 1
    public var sidechain = false
    public var fromPortID: String?
    public var toPortID: String?
    public var resolvedFromPortID: String { fromPortID ?? (signal == .midi ? CirclePort.midiOutput : CirclePort.audioOutput) }
    public var resolvedToPortID: String { toPortID ?? (sidechain ? CirclePort.sidechainInput : signal == .midi ? CirclePort.midiInput : CirclePort.audioInput) }
    public init(from: ID, to: ID, signal: MusicSignal) { self.from = from; self.to = to; self.signal = signal }
}

public struct SectionGraph: Codable, Equatable {
    public var nodes: [MusicCircle] = []
    public var edges: [MusicConnection] = []
    public var layout = Layout()
    public init() {}
}

/// Topology overrides use stable node/edge IDs, so unrelated original edits still propagate.
public struct SectionGraphEdits: Codable, Equatable {
    public var nodeOverrides: [ID: MusicCircle] = [:]
    public var addedNodes: [MusicCircle] = []
    public var removedNodeIDs: [ID] = []
    public var edgeOverrides: [ID: MusicConnection] = [:]
    public var addedEdges: [MusicConnection] = []
    public var removedEdgeIDs: [ID] = []
    public var layout: Layout?
    public init() {}
    public var isEmpty: Bool {
        nodeOverrides.isEmpty && addedNodes.isEmpty && removedNodeIDs.isEmpty &&
        edgeOverrides.isEmpty && addedEdges.isEmpty && removedEdgeIDs.isEmpty && layout == nil
    }
    public func applying(to original: SectionGraph) throws -> SectionGraph {
        let nodeIDs = Set(original.nodes.map(\.id)), edgeIDs = Set(original.edges.map(\.id))
        guard nodeOverrides.allSatisfy({ nodeIDs.contains($0.key) && $0.value.id == $0.key }),
              edgeOverrides.allSatisfy({ edgeIDs.contains($0.key) && $0.value.id == $0.key }),
              addedNodes.allSatisfy({ !nodeIDs.contains($0.id) }),
              addedEdges.allSatisfy({ !edgeIDs.contains($0.id) }),
              Set(removedNodeIDs).isDisjoint(with: nodeOverrides.keys),
              Set(removedEdgeIDs).isDisjoint(with: edgeOverrides.keys)
        else { throw CirclrError("원본에서 변경·삭제된 음악 서클 또는 연결의 변형이 있습니다") }
        var result = original
        result.nodes = original.nodes.filter { !removedNodeIDs.contains($0.id) }.map { nodeOverrides[$0.id] ?? $0 } + addedNodes
        result.edges = original.edges.filter { !removedEdgeIDs.contains($0.id) }.map { edgeOverrides[$0.id] ?? $0 } + addedEdges
        if let layout { result.layout = layout }
        return result
    }
    public static func difference(original: SectionGraph, edited: SectionGraph) -> SectionGraphEdits {
        var result = SectionGraphEdits()
        for node in edited.nodes {
            if let old = original.nodes.first(where: { $0.id == node.id }) {
                if old != node { result.nodeOverrides[node.id] = node }
            } else { result.addedNodes.append(node) }
        }
        for edge in edited.edges {
            if let old = original.edges.first(where: { $0.id == edge.id }) {
                if old != edge { result.edgeOverrides[edge.id] = edge }
            } else { result.addedEdges.append(edge) }
        }
        result.removedNodeIDs = original.nodes.filter { old in !edited.nodes.contains(where: { $0.id == old.id }) }.map(\.id)
        result.removedEdgeIDs = original.edges.filter { old in !edited.edges.contains(where: { $0.id == old.id }) }.map(\.id)
        if original.layout != edited.layout { result.layout = edited.layout }
        return result
    }
}

public enum SectionGraphEditing {
    public static func effective(section: Section, use: SectionUse) throws -> SectionGraph? {
        guard let original = section.graph else {
            guard use.graphEdits == nil || use.graphEdits?.isEmpty == true else { throw CirclrError("음악 그래프 원본이 없습니다") }
            return nil
        }
        return try use.graphEdits?.applying(to: original) ?? original
    }
    public static func set(_ graph: SectionGraph, useID: ID, original: Bool, in project: inout Project) throws {
        let ai = project.activeIndex
        guard let ui = project.arrangements[ai].uses.firstIndex(where: { $0.id == useID }),
              let si = project.sections.firstIndex(where: { $0.id == project.arrangements[ai].uses[ui].sectionID }),
              let base = project.sections[si].graph else { throw CirclrError("음악 그래프를 찾을 수 없습니다") }
        var candidate = project
        if original { candidate.sections[si].graph = graph }
        else {
            let patch = SectionGraphEdits.difference(original: base, edited: graph)
            candidate.arrangements[ai].uses[ui].graphEdits = patch.isEmpty ? nil : patch
        }
        // Validate every use affected by a shared edit before committing the transaction.
        for arrangement in candidate.arrangements {
            for use in arrangement.uses where use.sectionID == candidate.sections[si].id {
                let (section, context, clock) = try ArrangementCompiler.context(project: candidate, use: use, arrangementID: arrangement.id)
                _ = try SectionGraphCompiler.compile(project: candidate, section: section, use: use, context: context, clock: clock)
            }
        }
        project = candidate
    }
    public static func connect(from: ID, to: ID, sidechain: Bool = false,
                               fromPortID: String? = nil, toPortID: String? = nil, in graph: inout SectionGraph) throws {
        guard let source = graph.nodes.first(where: { $0.id == from }), let target = graph.nodes.first(where: { $0.id == to }),
              let signal = source.content.output, signal == target.content.input else { throw CirclrError("같은 종류의 MIDI 또는 오디오 포트에 연결하세요") }
        let outputs = CirclePort.ports(for: source.content).filter { $0.direction == .output &&
            (fromPortID == nil || $0.id == fromPortID) }
        let inputs = CirclePort.ports(for: target.content).filter { port in port.direction == .input &&
            (toPortID.map { port.id == $0 } ?? (port.isSidechain == sidechain)) }
        guard outputs.count == 1, inputs.count == 1, let output = outputs.first, let input = inputs.first,
              output.signal == input.signal, !sidechain || input.isSidechain
        else { throw CirclrError("호환되는 입력·출력 포트를 하나씩 지정하세요. 다중 bus는 port ID가 필요합니다") }
        if graph.edges.contains(where: { $0.from == from && $0.to == to &&
            $0.resolvedFromPortID == output.id && $0.resolvedToPortID == input.id }) { return }
        var candidate = graph
        var edge = MusicConnection(from: from, to: to, signal: signal); edge.sidechain = input.isSidechain
        // Keep existing implicit single-port documents byte-compatible when no IDs were requested.
        edge.fromPortID = fromPortID; edge.toPortID = toPortID
        candidate.edges.append(edge)
        _ = try SectionGraphValidator.sorted(candidate)
        graph = candidate
    }
    /// Insert one effect on one output bus without merging other buses or moving sidechains.
    public static func insertEffect(_ node: MusicCircle, from: ID, fromPortID: String? = nil,
                                    in graph: inout SectionGraph) throws {
        guard case .effect = node.content, let source = graph.nodes.first(where: { $0.id == from }) else {
            throw CirclrError("오디오 출력 서클과 새 이펙터를 선택하세요")
        }
        let ports = CirclePort.ports(for: source.content).filter {
            $0.direction == .output && $0.signal == .audio && (fromPortID == nil || $0.id == fromPortID)
        }
        guard ports.count == 1, let port = ports.first else { throw CirclrError("이펙터를 삽입할 출력 bus를 지정하세요") }
        var candidate = graph
        for i in candidate.edges.indices where candidate.edges[i].from == from &&
            candidate.edges[i].resolvedFromPortID == port.id && !candidate.edges[i].sidechain {
            candidate.edges[i].from = node.id
            if candidate.edges[i].fromPortID != nil { candidate.edges[i].fromPortID = CirclePort.audioOutput }
        }
        candidate.nodes.append(node)
        try connect(from: from, to: node.id, fromPortID: fromPortID, in: &candidate)
        graph = candidate
    }
    public static func insertEffectBeforeOutput(_ node:MusicCircle,before outputID:ID,in graph:inout SectionGraph)throws {
        guard case .effect=node.content,let output=graph.nodes.first(where:{$0.id==outputID}),case .output=output.content else {throw CirclrError("이펙터를 넣을 트랙 출력을 선택하세요")}
        var candidate=graph
        candidate.nodes.append(node)
        for i in candidate.edges.indices where candidate.edges[i].to==outputID {
            candidate.edges[i].to=node.id
            if candidate.edges[i].toPortID != nil {candidate.edges[i].toPortID=CirclePort.audioInput}
        }
        try connect(from:node.id,to:outputID,in:&candidate)
        graph=candidate
    }
    public static func remove(_ ids: Set<ID>, from graph: inout SectionGraph) {
        graph.nodes.removeAll { ids.contains($0.id) }
        graph.edges.removeAll { ids.contains($0.from) || ids.contains($0.to) }
        graph.layout.positions = graph.layout.positions.filter { !ids.contains($0.key) }
    }
}

public enum SectionGraphValidator {
    public static func sorted(_ graph: SectionGraph) throws -> [MusicCircle] {
        let ids = graph.nodes.map(\.id), edgeIDs = graph.edges.map(\.id)
        guard ids.count <= 2048, graph.edges.count <= 8192,
              ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count,
              edgeIDs.allSatisfy({ !$0.isEmpty }), Set(edgeIDs).count == edgeIDs.count else { throw CirclrError("음악 서클·연결의 ID 또는 개수를 확인하세요") }
        try AlbumEditing.validateLayout(graph.layout)
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        for node in graph.nodes { if case .router(let router) = node.content { try router.validate() } }
        var adjacency: [ID: [ID]] = [:], indegrees = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        for edge in graph.edges {
            guard let from = nodes[edge.from], let to = nodes[edge.to], edge.signal == from.content.output,
                  edge.signal == to.content.input, edge.gain.isFinite, (0...4).contains(edge.gain),
                  edge.signal != .midi || (edge.gain == 1 && !edge.sidechain) else { throw CirclrError("음악 연결의 신호 종류·대상·gain을 확인하세요") }
            if edge.sidechain {
                guard case .effect(let effect) = to.content, effect.kind == .compressor else { throw CirclrError("Sidechain은 compressor의 오디오 입력에 연결하세요") }
            }
            guard CirclePort.ports(for: from.content).contains(where: { $0.id == edge.resolvedFromPortID && $0.direction == .output }),
                  CirclePort.ports(for: to.content).contains(where: { $0.id == edge.resolvedToPortID && $0.direction == .input }),
                  edge.sidechain == (edge.resolvedToPortID == CirclePort.sidechainInput)
            else { throw CirclrError("음악 연결의 입력·출력 port ID와 sidechain 역할을 확인하세요") }
            adjacency[edge.from, default: []].append(edge.to); indegrees[edge.to, default: 0] += 1
        }
        var ready = ids.filter { indegrees[$0] == 0 }, cursor = 0, result: [MusicCircle] = []
        while cursor < ready.count {
            let id = ready[cursor]; cursor += 1
            if let node = nodes[id] { result.append(node) }
            for target in adjacency[id] ?? [] {
                indegrees[target, default: 0] -= 1
                if indegrees[target] == 0 { ready.append(target) }
            }
        }
        guard result.count == ids.count else { throw CirclrError("음악 신호의 순환 연결은 지원하지 않습니다") }
        return result
    }
}
