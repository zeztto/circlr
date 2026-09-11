import Foundation

/// One atomic command shared by direct controls, pointer gestures and future agent requests.
public enum CircleConnectionEditing {
    @discardableResult public static func connect(_ first: CirclePortEndpoint, _ second: CirclePortEndpoint,
        firstOctant: PortOctant, secondOctant: PortOctant, replacing: CircleConnectionID? = nil,
        original: Bool = false, in project: inout Project) throws -> CircleConnectionID {
        let connection = try CirclePortCatalog.normalize(first, second, in: project)
        let from = connection.from, to = connection.to
        let firstLogical = try GroupPortEditing.resolve(first,in:project)
        let placement = CircleConnectionPlacement(from: from == firstLogical ? firstOctant : secondOctant,
                                                   to: to == firstLogical ? firstOctant : secondOctant)
        let all = try CirclePortCatalog.connections(in: project)
        if let replacing, !all.contains(where: { $0.id == replacing }) { throw CirclrError("재연결할 원래 케이블이 없습니다") }
        if let duplicate = all.first(where: { $0.from == from && $0.to == to }) {
            if replacing == nil || duplicate.id == replacing { return duplicate.id }
            throw CirclrError("이미 연결된 포트입니다. 기존 케이블을 유지합니다")
        }
        var candidate = project
        let active = candidate.activeArrangementID
        let id: CircleConnectionID
        switch (from.node, to.node) {
        case let (.music(ai, ui, source), .music(_, _, target)):
            candidate.activeArrangementID = ai
            guard let use = candidate.active.uses.first(where: { $0.id == ui }),
                  let section = candidate.sections.first(where: { $0.id == use.sectionID }),
                  var graph = try SectionGraphEditing.effective(section: section, use: use) else { throw CirclrError("음악 그래프가 없습니다") }
            var old: MusicConnection?
            if let replacing {
                guard case .music(ai, ui, _) = replacing.from, case .music(ai, ui, _) = replacing.to,
                      let found = graph.edges.first(where: { $0.id == replacing.edgeID }) else { throw CirclrError("같은 음악 그래프 안에서 재연결하세요") }
                old = found; graph.edges.removeAll { $0.id == found.id }
            }
            try SectionGraphEditing.connect(from: source, to: target, fromPortID: from.portID, toPortID: to.portID, in: &graph)
            if let old { graph.edges[graph.edges.count - 1].id = old.id; graph.edges[graph.edges.count - 1].gain = old.gain }
            let edge = graph.edges[graph.edges.count - 1]
            try SectionGraphEditing.set(graph, useID: ui, original: original, in: &candidate)
            id = .init(edgeID: edge.id, from: from.node, to: to.node)
        case let (.signal(source), .signal(target)):
            var edge = SignalEdge(from: source, to: target); edge.sidechain = connection.sidechain
            if let replacing {
                guard case .signal = replacing.from, case .signal = replacing.to,
                      let old = candidate.signal.edges.first(where: { $0.id == replacing.edgeID }) else { throw CirclrError("같은 사운드 그래프의 케이블을 선택하세요") }
                edge.id = old.id; edge.gain = old.gain; candidate.signal.edges.removeAll { $0.id == old.id }
            }
            candidate.signal.edges.append(edge)
            _ = try SignalValidator.sorted(candidate.signal, tracks: candidate.tracks)
            id = .init(edgeID: edge.id, from: from.node, to: to.node)
        case let (.section(ai, source), .section(_, target)):
            candidate.activeArrangementID = ai
            var old: FlowEdge?
            if let replacing {
                guard case .section(ai, _) = replacing.from, case .section(ai, _) = replacing.to,
                      let found = candidate.active.edges.first(where: { $0.id == replacing.edgeID }) else { throw CirclrError("같은 편곡안의 연결을 선택하세요") }
                old = found; candidate.arrangements[candidate.activeIndex].edges.removeAll { $0.id == found.id }
            }
            try ProjectEditing.connect(from: source, to: target, in: &candidate)
            let index = candidate.active.edges.count - 1
            if var old {
                let oldSource = old.from; old.from = source; old.to = target
                candidate.arrangements[candidate.activeIndex].edges[index] = old
                if candidate.active.chosenEdges[oldSource] == old.id {
                    candidate.arrangements[candidate.activeIndex].chosenEdges[oldSource] = nil
                    if candidate.active.chosenEdges[source] == nil { candidate.arrangements[candidate.activeIndex].chosenEdges[source] = old.id }
                }
                if oldSource != source, !candidate.active.edges.contains(where: { $0.from == oldSource }),
                   let i = candidate.active.uses.firstIndex(where: { $0.id == oldSource }) { candidate.arrangements[candidate.activeIndex].uses[i].isEnd = true }
            }
            id = .init(edgeID: candidate.active.edges[index].id, from: from.node, to: to.node)
        case let (.composition(source), .composition(target)):
            guard replacing == nil, let album = candidate.album else { throw CirclrError("곡·악장은 순서 연결로 편집하세요") }
            let parent = album.parent(of: source), siblings = parent.flatMap { album.composition($0)?.children } ?? album.children
            let remaining = siblings.filter { $0 != target }
            guard let index = remaining.firstIndex(of: source) else { throw CirclrError("연결할 곡을 찾을 수 없습니다") }
            try AlbumEditing.move(target, to: parent, index: index + 1, in: &candidate)
            id = .init(edgeID: "composition-flow:\(source):\(target)", from: from.node, to: to.node)
        default: throw CirclrError("같은 그래프의 호환 포트를 선택하세요")
        }
        candidate.activeArrangementID = active
        _ = try CirclePortLayoutEditing.apply([.init(id: id, placement: placement)], projectID: candidate.id,
            expectedMusicRevision: candidate.musicRevision, expectedLayoutRevision: candidate.portLayout?.revision ?? 0, in: &candidate)
        try ProjectStore.validateStructure(candidate)
        project = candidate; return id
    }

    public static func disconnect(_ id: CircleConnectionID, original: Bool = false, in project: inout Project) throws {
        guard try CirclePortCatalog.connections(in: project).contains(where: { $0.id == id }) else { throw CirclrError("해제할 케이블이 없습니다") }
        var candidate = project; let active = candidate.activeArrangementID
        switch id.from {
        case .music(let ai, let ui, _):
            candidate.activeArrangementID = ai
            guard let use = candidate.active.uses.first(where: { $0.id == ui }), let section = candidate.sections.first(where: { $0.id == use.sectionID }),
                  var graph = try SectionGraphEditing.effective(section: section, use: use) else { throw CirclrError("음악 그래프가 없습니다") }
            graph.edges.removeAll { $0.id == id.edgeID }
            try SectionGraphEditing.set(graph, useID: ui, original: original, in: &candidate)
        case .signal: candidate.signal.edges.removeAll { $0.id == id.edgeID }
        case .section(let ai, let source):
            candidate.activeArrangementID = ai
            candidate.arrangements[candidate.activeIndex].edges.removeAll { $0.id == id.edgeID }
            candidate.arrangements[candidate.activeIndex].chosenEdges = candidate.active.chosenEdges.filter { $0.value != id.edgeID }
            if !candidate.active.edges.contains(where: { $0.from == source }), let i = candidate.active.uses.firstIndex(where: { $0.id == source }) {
                candidate.arrangements[candidate.activeIndex].uses[i].isEnd = true
            }
        default: throw CirclrError("곡·악장은 순서를 이동해 연결을 편집하세요")
        }
        candidate.activeArrangementID = active
        try ProjectStore.validateStructure(candidate); project = candidate
    }
}
