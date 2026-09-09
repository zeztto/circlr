import Foundation

public enum BounceIssue: Error, LocalizedError, Equatable {
    case missingTrack, missingSection, noOutput, multipleOutputs, noInputs
    case invalidGraph(String)
    public var message: String {
        switch self {
        case .missingTrack: return "바운스할 트랙을 찾을 수 없습니다"
        case .missingSection: return "바운스할 섹션을 찾을 수 없습니다"
        case .noOutput, .multipleOutputs: return "바운스할 트랙의 출력 서클을 하나로 연결하세요"
        case .noInputs: return "출력에 연결된 연주가 없습니다"
        case .invalidGraph(let message): return message
        }
    }
    public var errorDescription: String? { message }
}
public enum BounceMembership: Equatable {
    case notSelected, missingNode, output, mainPath, sidechainOnly, outsidePath
    /// A corrupt graph or unavailable target prevents a reliable path assessment.
    case unavailable
}
public struct BounceRecoveryDestination: Identifiable, Equatable {
    public enum Kind: Equatable { case section, output }
    public let id: CircleAddress
    public let name: String
    public let kind: Kind
}

/// Reports output preflight and structural connections, not audibility or render readiness.
/// Muted nodes and zero gains still have connections; router bus routes remain distinct.
public struct BounceAssessment: Equatable {
    public let target: BounceTarget?
    public let issue: BounceIssue?
    public let membership: BounceMembership
    public let destinations: [BounceRecoveryDestination]

    public static func make(trackID: ID, useID: ID, arrangementID: ID? = nil,
                            selectedNodeID: ID? = nil, in project: Project) -> Self {
        let arrangementID = arrangementID ?? project.activeArrangementID
        var destinations: [BounceRecoveryDestination] = []
        if let use = project.arrangements.first(where: { $0.id == arrangementID })?.uses.first(where: { $0.id == useID }),
           project.sections.contains(where: { $0.id == use.sectionID }) {
            destinations.append(.init(id: .section(arrangementID: arrangementID, useID: useID), name: use.name, kind: .section))
        }
        do {
            let graph = try BounceEditing.targetGraph(trackID: trackID, useID: useID, arrangementID: arrangementID, in: project)
            // Never offer ambiguous node IDs as navigation destinations.
            let counts = Dictionary(grouping: graph.nodes, by: \.id)
            for node in graph.nodes {
                if case .output(let track) = node.content, track == trackID, counts[node.id]?.count == 1 {
                    destinations.append(.init(id: .music(arrangementID: arrangementID, useID: useID, nodeID: node.id), name: node.name, kind: .output))
                }
            }
            // Preserve the target API's existing error precedence before membership validation.
            let target = try BounceEditing.target(trackID: trackID, graph: graph)
            _ = try SectionGraphValidator.sorted(graph)
            let membership = membership(selectedNodeID, target: target, graph: graph)
            return Self(target: target, issue: nil, membership: membership, destinations: destinations)
        } catch {
            return Self(target: nil, issue: (error as? BounceIssue) ?? .invalidGraph(error.localizedDescription),
                        membership: selectedNodeID == nil ? .notSelected : .unavailable, destinations: destinations)
        }
    }

    private struct Visit: Hashable {
        let endpoint: MusicBusEndpoint
        let sidechain: Bool
    }
    private static func membership(_ selected: ID?, target: BounceTarget, graph: SectionGraph) -> BounceMembership {
        guard let selected else { return .notSelected }
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        guard nodes[selected] != nil else { return .missingNode }
        if selected == target.outputNodeID { return .output }
        let incoming = Dictionary(grouping: graph.edges.map(MusicBusConnection.init), by: { $0.to.nodeID })
        // A visited endpoint denotes the particular output bus whose dependencies are needed.
        var pending = [Visit(endpoint: .init(nodeID: target.outputNodeID, portID: CirclePort.audioOutput), sidechain: false)]
        var visited = Set<Visit>(), viaSidechain = false
        while let visit = pending.popLast() {
            guard visited.insert(visit).inserted, let node = nodes[visit.endpoint.nodeID] else { continue }
            if node.id == selected {
                if !visit.sidechain { return .mainPath }
                viaSidechain = true
            }
            let allowedInputs: Set<String>?
            if case .router(let router) = node.content {
                allowedInputs = Set(router.routes.filter { $0.output == visit.endpoint.portID }.map(\.input))
            } else { allowedInputs = nil }
            for edge in incoming[node.id] ?? [] where allowedInputs == nil || allowedInputs!.contains(edge.to.portID) {
                pending.append(Visit(endpoint: edge.from, sidechain: visit.sidechain || edge.sidechain))
            }
        }
        return viaSidechain ? .sidechainOnly : .outsidePath
    }
}
