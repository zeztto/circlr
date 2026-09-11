import Foundation

/// Layout-only edits never alter containment ownership, execution order, or musical payloads.
public enum HierarchyEditing {
    public static func scope(of address: CircleAddress, in project: Project) throws -> CircleAddress {
        switch address {
        case .album, .sound: return .album
        case .signal: return .sound
        case .composition(let id): return project.album?.parent(of: id).map(CircleAddress.composition) ?? .album
        case .section(let arrangement, _):
            guard let id = project.album?.owner(of: arrangement)?.id else { throw CirclrError("편곡안의 곡을 찾을 수 없습니다") }
            return .composition(id)
        case .music(let arrangement, let use, _): return .section(arrangementID: arrangement, useID: use)
        case .group(let parent, _): return parent
        }
    }
    public static func memberID(_ address: CircleAddress) -> ID? {
        switch address {
        case .composition(let id), .section(_,let id), .music(_,_,let id), .signal(let id): return id
        case .sound: return "circlr:sound"
        default: return nil
        }
    }
    public static func layout(for scope: CircleAddress, in project: Project) throws -> Layout {
        switch scope {
        case .sound: return project.signal.layout
        case .signal: throw CirclrError("사운드 서클 안에 일반 그룹을 만들 수 없습니다")
        case .album:
            guard let layout = project.album?.layout else { throw CirclrError("앨범이 없습니다") }; return layout
        case .composition(let id):
            guard let composition = project.album?.composition(id) else { throw CirclrError("곡·악장이 없습니다") }
            if !composition.children.isEmpty { return composition.layout }
            guard let arrangement = project.arrangements.first(where: { $0.id == composition.selectedArrangementID }) else { throw CirclrError("편곡안이 없습니다") }
            return arrangement.layout
        case .section(let arrangement,let use):
            guard let usage = project.arrangements.first(where: { $0.id == arrangement })?.uses.first(where: { $0.id == use }),
                  let section = project.sections.first(where: { $0.id == usage.sectionID }),
                  let graph = try SectionGraphEditing.effective(section: section, use: usage) else { throw CirclrError("섹션 그래프가 없습니다") }
            return graph.layout
        case .group(let parent, _): return try layout(for: parent, in: project)
        case .music: throw CirclrError("음악 서클 안에 일반 그룹을 만들 수 없습니다")
        }
    }
    public static func editLayout(_ scope: CircleAddress, in project: inout Project, _ edit: (inout Layout) throws -> Void) throws {
        var value = try layout(for: scope, in: project); try edit(&value); try AlbumEditing.validateLayout(value)
        var candidate = project
        switch scope {
        case .album: candidate.album?.layout = value
        case .sound: candidate.signal.layout = value
        case .signal: throw CirclrError("배치 대상이 아닙니다")
        case .composition(let id):
            guard let i = candidate.album?.compositions.firstIndex(where: { $0.id == id }) else { throw CirclrError("곡·악장이 없습니다") }
            if candidate.album!.compositions[i].children.isEmpty {
                guard let ai = candidate.arrangements.firstIndex(where: { $0.id == candidate.album!.compositions[i].selectedArrangementID }) else { throw CirclrError("편곡안이 없습니다") }
                candidate.arrangements[ai].layout = value
            } else { candidate.album?.compositions[i].layout = value }
        case .section(let arrangement, let use):
            guard let usage = candidate.arrangements.first(where: { $0.id == arrangement })?.uses.first(where: { $0.id == use }),
                  let section = candidate.sections.first(where: { $0.id == usage.sectionID }),
                  var graph = try SectionGraphEditing.effective(section: section, use: usage) else { throw CirclrError("섹션 그래프가 없습니다") }
            graph.layout = value
            let active = candidate.activeArrangementID; candidate.activeArrangementID = arrangement
            try SectionGraphEditing.set(graph, useID: use, original: false, in: &candidate)
            candidate.activeArrangementID = active
        case .group(let parent, _): try editLayout(parent, in: &candidate) { $0 = value }
        case .music: throw CirclrError("배치 대상이 아닙니다")
        }
        project = candidate
    }
    public static func timedMembers(in scope: CircleAddress, project: Project) throws -> Set<ID> {
        if case .group(let parent, _) = scope { return try timedMembers(in:parent,project:project) }
        // Recorded before visual grouping, including hidden members and compiler off-path state.
        return try HierarchySceneBuilder.build(project).timedMembersByOwner[scope] ?? []
    }
    public static func position(_ address: CircleAddress, in project: Project) throws -> Point {
        let scope = try scope(of: address, in: project)
        let value = try layout(for: scope, in: project)
        let positions = project.usesOrbits ? OrbitLayoutOffsets.positions(in:value,timed:try timedMembers(in:scope,project:project)) : value.positions
        if case .group(_,let id) = address {
            guard let group = value.groups.first(where: { $0.id == id }) else { throw CirclrError("그룹이 없습니다") }
            let points = group.members.compactMap { positions[$0] ?? (project.usesOrbits ? Point() : nil) }
            guard !points.isEmpty else { return Point() }
            return Point(points.map(\.x).reduce(0,+)/Double(points.count), points.map(\.y).reduce(0,+)/Double(points.count))
        }
        if address == .sound,!project.usesOrbits,value.positions["circlr:sound"] == nil,let node=try HierarchySceneBuilder.build(project).node(.sound) { return Point(node.center.x/node.scale,node.center.y/node.scale) }
        return memberID(address).flatMap { positions[$0] } ?? Point()
    }
    public static func move(_ address: CircleAddress, to point: Point, in project: inout Project) throws {
        let scope = try scope(of: address, in: project), old = try position(address, in: project)
        let orbit = project.usesOrbits
        let timed = orbit ? try timedMembers(in:scope,project:project) : []
        try editLayout(scope, in: &project) { layout in
            if orbit { OrbitLayoutOffsets.materialize(&layout,timed:timed) }
            var positions = orbit ? (layout.orbitPositions ?? [:]) : layout.positions
            if case .group(_,let id) = address, let group = layout.groups.first(where: { $0.id == id }) {
                for member in group.members {
                    if let p = positions[member] ?? (orbit ? Point() : nil) {
                        positions[member] = Point(p.x+point.x-old.x,p.y+point.y-old.y)
                    }
                }
            } else if let id = memberID(address) { positions[id] = point }
            if orbit { layout.orbitPositions = positions } else { layout.positions = positions }
        }
    }
    @discardableResult public static func group(_ addresses: Set<CircleAddress>, name: String, in project: inout Project) throws -> CircleAddress {
        guard let first = addresses.first, addresses.count >= 2 else { throw CirclrError("그룹으로 묶을 서클을 두 개 이상 선택하세요") }
        let scope = try scope(of: first, in: project)
        guard try addresses.allSatisfy({ try self.scope(of: $0, in: project) == scope }), addresses.allSatisfy({ memberID($0) != nil }) else { throw CirclrError("같은 부모 안의 서클을 선택하세요") }
        let ids = Set(addresses.compactMap(memberID)), group = CanvasGroup(name: name, members: ids.sorted())
        try editLayout(scope, in: &project) { layout in
            for i in layout.groups.indices { layout.groups[i].members.removeAll { ids.contains($0) } }
            layout.groups.removeAll { $0.members.isEmpty }; layout.groups.append(group)
        }
        return .group(parent: scope, id: group.id)
    }
    public static func align(_ addresses: Set<CircleAddress>, mode: Int, in project: inout Project) throws {
        guard addresses.count >= 2, let first = addresses.first else { return }
        let scope = try scope(of: first, in: project)
        guard try addresses.allSatisfy({ try self.scope(of: $0, in: project) == scope }) else { throw CirclrError("같은 부모 안의 서클만 정렬하세요") }
        let scene = project.usesOrbits ? try HierarchySceneBuilder.build(project) : nil
        let pairs = try addresses.map { address in
            (address, try scene?.node(address)?.center ?? position(address, in: project))
        }.sorted { $0.1.x < $1.1.x }
        let x = pairs.map { $0.1.x }.reduce(0,+)/Double(pairs.count), y = pairs.map { $0.1.y }.reduce(0,+)/Double(pairs.count)
        var candidate = project
        for (i,pair) in pairs.enumerated() {
            var point = pair.1
            if mode == 0 { point.y = y } else if mode == 1 { point.x = x }
            else { point.x = pairs.first!.1.x+Double(i)*(pairs.last!.1.x-pairs.first!.1.x)/Double(pairs.count-1) }
            if let node = scene?.node(pair.0) {
                let offset = try position(pair.0,in:project)
                point = Point(offset.x+(point.x-node.center.x)/node.scale,offset.y+(point.y-node.center.y)/node.scale)
            }
            try move(pair.0, to: point, in: &candidate)
        }
        project = candidate
    }
}
