import Foundation

/// An explicit view alias for one implemented endpoint. It does not insert a processor or change clocks.
public struct GroupPortBinding: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var group: CircleAddress
    public var name: String
    public var target: CirclePortEndpoint
    public init(id: String = newID(), group: CircleAddress, name: String, target: CirclePortEndpoint) {
        self.id = id; self.group = group; self.name = name; self.target = target
    }
}

public enum GroupPortEditing {
    public static func members(of address: CircleAddress, in project: Project) throws -> [CircleAddress] {
        guard case .group(let parent, let id) = address,
              let group = try HierarchyEditing.layout(for: parent, in: project).groups.first(where: { $0.id == id }) else {
            throw CirclrError("실제 그룹 주소를 선택하세요")
        }
        return try group.members.map { member in
            switch parent {
            case .section(let ai, let ui): return .music(arrangementID: ai, useID: ui, nodeID: member)
            case .sound: return .signal(member)
            case .album: return member == "circlr:sound" ? .sound : .composition(member)
            case .composition(let id):
                guard let composition = project.album?.composition(id) else { throw CirclrError("그룹의 곡을 찾을 수 없습니다") }
                if !composition.children.isEmpty { return .composition(member) }
                guard let ai = composition.selectedArrangementID else { throw CirclrError("그룹의 편곡안을 찾을 수 없습니다") }
                return .section(arrangementID: ai, useID: member)
            default: throw CirclrError("일반 그래프의 그룹 주소를 사용하세요")
            }
        }
    }

    public static func bindings(at group: CircleAddress, in project: Project) -> [GroupPortBinding] {
        (project.portLayout?.bindings ?? []).filter { $0.group == group }
    }

    public static func descriptor(for binding: GroupPortBinding, in project: Project) throws -> CirclePort {
        guard try members(of: binding.group, in: project).contains(binding.target.node),
              let port = try CirclePortCatalog.ports(at: binding.target.node, in: project).first(where: { $0.id == binding.target.portID }) else {
            throw CirclrError("노출 포트의 내부 대상이 없거나 그룹에서 벗어났습니다")
        }
        return port
    }

    public static func ports(at group: CircleAddress, in project: Project) throws -> [CirclePort] {
        _ = try members(of: group, in: project)
        var inputs = 0, outputs = 0
        return bindings(at: group, in: project).compactMap { binding in
            guard var port = try? descriptor(for: binding, in: project) else { return nil }
            let input = port.direction == .input, index = input ? inputs : outputs
            if input { inputs += 1 } else { outputs += 1 }
            port = CirclePort(id: binding.id, direction: port.direction, signal: port.signal,
                              name: (input ? "IN " : "OUT ")+binding.name, policy: port.policy,
                              bindingTarget: binding.target, bindingIndex: index)
            return port
        }
    }

    public static func resolve(_ endpoint: CirclePortEndpoint, in project: Project) throws -> CirclePortEndpoint {
        guard case .group = endpoint.node else { return endpoint }
        guard let binding = bindings(at: endpoint.node, in: project).first(where: { $0.id == endpoint.portID }) else {
            throw CirclrError("그룹에 명시적으로 노출한 포트를 선택하세요")
        }
        _ = try descriptor(for: binding, in: project)
        return binding.target
    }

    /// Project a real endpoint to a valid alias on this group, without inventing bindings on collapse.
    public static func presented(_ endpoint: CirclePortEndpoint, at group: CircleAddress, in project: Project) -> CirclePortEndpoint? {
        guard let binding = bindings(at: group, in: project).first(where: { $0.target == endpoint }),
              (try? descriptor(for: binding, in: project)) != nil else { return nil }
        return .init(node: group, portID: binding.id)
    }

    @discardableResult public static func set(group: CircleAddress, target: CirclePortEndpoint, name: String, id: String? = nil,
        projectID: ID, expectedMusicRevision: Int, expectedLayoutRevision: Int, in project: inout Project) throws -> String {
        try check(projectID, expectedMusicRevision, expectedLayoutRevision, project)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 128 else { throw CirclrError("노출 포트 이름은 1–128자로 입력하세요") }
        let binding = GroupPortBinding(id: id ?? newID(), group: group, name: name, target: target)
        _ = try descriptor(for: binding, in: project)
        var layout = project.portLayout ?? CirclePortLayout(), bindings = layout.bindings ?? []
        if let id {
            guard let index = bindings.firstIndex(where: { $0.id == id && $0.group == group }), bindings[index].target == target else {
                throw CirclrError("기존 노출 포트의 target은 바꿀 수 없습니다. 새 포트로 노출하세요")
            }
            guard bindings[index] != binding else { return id }
            bindings[index] = binding
        } else {
            if let existing = bindings.first(where: { $0.group == group && $0.target == target }) { return existing.id }
            guard bindings.filter({ $0.group == group }).count < 64 else { throw CirclrError("한 그룹의 노출 포트는 최대 64개입니다") }
            bindings.append(binding)
        }
        layout.bindings = bindings; layout.revision += 1; try layout.validate()
        project.portLayout = layout; return binding.id
    }

    public static func remove(group: CircleAddress, portID: String, projectID: ID, expectedMusicRevision: Int,
        expectedLayoutRevision: Int, in project: inout Project) throws {
        try check(projectID, expectedMusicRevision, expectedLayoutRevision, project)
        var layout = project.portLayout ?? CirclePortLayout()
        guard layout.bindings?.contains(where: { $0.group == group && $0.id == portID }) == true else { throw CirclrError("해제할 노출 포트가 없습니다") }
        layout.bindings?.removeAll { $0.group == group && $0.id == portID }
        if layout.bindings?.isEmpty == true { layout.bindings = nil }
        layout.revision += 1; try layout.validate(); project.portLayout = layout
    }

    private static func check(_ id: ID, _ music: Int, _ layout: Int, _ project: Project) throws {
        guard id == project.id, music == project.musicRevision, layout == (project.portLayout?.revision ?? 0) else {
            throw CirclrError("stale_layout: 프로젝트·음악·배치 revision을 다시 확인하세요")
        }
        try project.portLayout?.validate()
    }
}
