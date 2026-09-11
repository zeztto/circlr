import Foundation

public struct ArrangementRouteStep: Identifiable, Equatable {
    public let id: ID
    public let name: String
    public let repeatCount: Int
}

/// Connection order only; this does not validate audio, timing, or render readiness.
public struct ArrangementRouteSummary: Equatable {
    public let steps: [ArrangementRouteStep]
    public let excluded: [ArrangementRouteStep]
    public let error: String?
    public let totalOccurrences: Int

    public static func make(_ arrangement: Arrangement) -> Self {
        do {
            var flow = try ArrangementFlowCursor(arrangement)
            var steps: [ArrangementRouteStep] = [], included = Set<ID>(), total = 0
            while let use = try flow.next() {
                total += use.repeatCount
                guard total <= 10_000 else { throw CirclrError("재생 경로가 10,000회를 넘습니다. 반복 범위를 줄이세요") }
                steps.append(step(use)); included.insert(use.id)
                _ = try flow.advance(after: use)
            }
            return Self(steps: steps, excluded: arrangement.uses.filter { !included.contains($0.id) }.map(step), error: nil, totalOccurrences: total)
        } catch {
            return Self(steps: [], excluded: [], error: error.localizedDescription, totalOccurrences: 0)
        }
    }
    private static func step(_ use: SectionUse) -> ArrangementRouteStep {
        ArrangementRouteStep(id: use.id, name: use.name, repeatCount: use.repeatCount)
    }
}

/// Advance only after the caller processes a use, preserving compiler error order.
struct ArrangementFlowCursor {
    private let arrangement: Arrangement
    private let uses: [ID: SectionUse]
    private let outgoing: [ID: [FlowEdge]]
    private let onlyUse: Bool
    private var current: ID?
    private var visited = Set<ID>()

    init(_ arrangement: Arrangement, onlyUseID: ID? = nil) throws {
        self.arrangement = arrangement; onlyUse = onlyUseID != nil
        if arrangement.uses.isEmpty {
            uses = [:]; outgoing = [:]; current = nil; return
        }
        guard let first = onlyUseID ?? arrangement.startID else { throw CirclrError("시작 서클을 지정하세요") }
        guard Set(arrangement.uses.map(\.id)).count == arrangement.uses.count else { throw CirclrError("서클 ID가 중복되었습니다") }
        uses = Dictionary(uniqueKeysWithValues: arrangement.uses.map { ($0.id, $0) })
        outgoing = Dictionary(grouping: arrangement.edges, by: \.from)
        current = first
    }
    mutating func next() throws -> SectionUse? {
        guard let current else { return nil }
        guard visited.insert(current).inserted else { throw CirclrError("순환 연결을 발견했습니다. 반복 횟수를 사용하세요") }
        guard let use = uses[current] else { throw CirclrError("연결된 서클을 찾을 수 없습니다") }
        guard (1...256).contains(use.repeatCount) else { throw CirclrError("\(use.name): 반복 횟수는 1–256회로 지정하세요") }
        return use
    }
    mutating func advance(after use: SectionUse) throws -> FlowEdge? {
        if onlyUse || use.isEnd { current = nil; return nil }
        let edges = outgoing[use.id] ?? []
        let edge: FlowEdge
        if edges.count == 1 { edge = edges[0] }
        else if edges.count > 1, let chosen = arrangement.chosenEdges[use.id], let selected = edges.first(where: { $0.id == chosen }) { edge = selected }
        else { throw CirclrError("\(use.name): 다음 연결을 선택하거나 끝으로 지정하세요") }
        current = edge.to; return edge
    }
}
