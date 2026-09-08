import Foundation

public struct AgentPortConnection: Codable {
    public var connection: CirclePortConnection
    public var placement: CircleConnectionPlacement
    public var canReconnect: Bool
    public var canDisconnect: Bool
}

public struct AgentPortSnapshot: Codable {
    public var projectID: ID
    public var revision: Int
    public var layoutRevision: Int
    public var node: CircleAddress
    public var ports: [CirclePort]
    public var connections: [AgentPortConnection]
    public var bindings: [GroupPortBinding]?
}

public struct AgentPortEditResult {
    public var project: Project
    public var connectionID: CircleConnectionID?
    public var portID: String?
}

/// Agent commands share the GUI's atomic Core edits. The app owns revision increments and Undo.
public enum AgentPortEditing {
    public static func snapshot(at node: CircleAddress, in project: Project) throws -> AgentPortSnapshot {
        try supported(node)
        let ports = try CirclePortCatalog.ports(at: node, in: project)
        let targets=Set(ports.compactMap(\.bindingTarget))
        let members=(try? GroupPortEditing.members(of:node,in:project)) ?? []
        let connections = try CirclePortCatalog.connections(in: project).filter {
            if case .group = node {return (targets.contains($0.from) && !members.contains($0.to.node)) || (targets.contains($0.to) && !members.contains($0.from.node))}
            return $0.from.node == node || $0.to.node == node
        }
        return .init(projectID: project.id, revision: project.musicRevision,
                     layoutRevision: project.portLayout?.revision ?? 0, node: node, ports: ports,
                     connections: connections.map {
            let editable: Bool
            if case .composition = $0.from.node { editable = false } else { editable = true }
            return .init(connection: $0, placement: project.portLayout?.placement(for: $0.id) ?? .init(),
                         canReconnect: editable, canDisconnect: editable)
        }, bindings: { if case .group = node {return GroupPortEditing.bindings(at:node,in:project)};return nil }())
    }

    public static func checkLayout(_ expected: Int?, project: Project) throws {
        guard let expected, expected >= 0, expected == (project.portLayout?.revision ?? 0) else {
            throw CirclrError("stale_layout: expectedLayoutRevision이 현재 배치와 다릅니다. ports를 다시 읽으세요")
        }
    }

    public static func apply(_ request: AgentRequest, to input: Project) throws -> AgentPortEditResult {
        try AgentProjectEditing.check(request, project: input)
        let args = request.arguments ?? AgentArguments()
        try checkLayout(args.expectedLayoutRevision, project: input)
        var project = input
        var id: CircleConnectionID?
        var portID: String?
        switch request.method {
        case "set_group_port":
            guard let group=args.node,let target=args.target,let name=args.name else {throw CirclrError("그룹 node·target endpoint·name이 필요합니다")}
            portID=try GroupPortEditing.set(group:group,target:target,name:name,id:args.portID,projectID:input.id,
                expectedMusicRevision:input.musicRevision,expectedLayoutRevision:args.expectedLayoutRevision!,in:&project)
        case "remove_group_port":
            guard let group=args.node,let target=args.portID else {throw CirclrError("그룹 node와 portID가 필요합니다")}
            try GroupPortEditing.remove(group:group,portID:target,projectID:input.id,expectedMusicRevision:input.musicRevision,
                expectedLayoutRevision:args.expectedLayoutRevision!,in:&project)
            portID=target
        case "connect_ports", "reconnect_ports":
            guard let first = args.first, let second = args.second,
                  let firstOctant = args.firstOctant, let secondOctant = args.secondOctant else {
                throw CirclrError("first·second endpoint와 각 octant가 필요합니다")
            }
            try supported(first.node); try supported(second.node)
            guard (request.method == "reconnect_ports") == (args.connectionID != nil) else {
                throw CirclrError("reconnect_ports에만 원래 connectionID를 지정하세요")
            }
            id = try CircleConnectionEditing.connect(first, second, firstOctant: firstOctant,
                secondOctant: secondOctant, replacing: args.connectionID, in: &project)
        case "disconnect_ports":
            guard let connection = args.connectionID else { throw CirclrError("connectionID가 필요합니다") }
            try CircleConnectionEditing.disconnect(connection, in: &project)
            id = connection
        case "move_ports":
            guard let moves = args.moves else { throw CirclrError("moves가 필요합니다") }
            try CirclePortLayoutEditing.apply(moves, projectID: input.id, expectedMusicRevision: input.musicRevision,
                expectedLayoutRevision: args.expectedLayoutRevision!, in: &project)
        default: throw CirclrError("지원하지 않는 port method: \(request.method)")
        }
        return .init(project: project, connectionID: id, portID:portID)
    }

    private static func supported(_ address: CircleAddress) throws {
        switch address {
        case .signal, .music, .section, .composition, .group: break
        default: throw CirclrError("실제 음악·섹션·곡·사운드 노드 또는 그룹 주소를 사용하세요")
        }
    }
}
