import Foundation

public enum ProjectEditing {
    @discardableResult public static func reuse(_ id: ID, in project: inout Project, at point: Point) throws -> ID {
        let i = project.activeIndex
        guard var use = project.arrangements[i].uses.first(where: { $0.id == id }) else { throw CirclrError("다시 사용할 서클을 선택하세요") }
        use.id = newID(); use.name += " 재사용"; use.isEnd = true
        project.arrangements[i].uses.append(use)
        project.arrangements[i].layout.positions[use.id] = point
        return use.id
    }
    public static func detach(_ id: ID, in project: inout Project) throws {
        let i = project.activeIndex
        guard let ui = project.arrangements[i].uses.firstIndex(where: { $0.id == id }) else { throw CirclrError("분리할 서클을 선택하세요") }
        let use = project.arrangements[i].uses[ui]
        let (section, context, _) = try ArrangementCompiler.context(project: project, use: use)
        var new = section; new.id = newID(); new.name = use.name
        new.bars = use.barsOverride ?? section.bars
        new.lanes = try ArrangementCompiler.effectiveLanes(section: section, use: use)
        new.graph = try SectionGraphEditing.effective(section: section, use: use)
        new.settings.tempo = .local(context.tempo); new.settings.meter = .local(context.meter)
        new.settings.scale = .local(context.scale); new.settings.beatGrid = .local(context.beatGrid); new.settings.rhythm = .local(context.rhythm)
        if use.settings.tempo.source != .inherit { new.tempoChanges = [] }
        if use.settings.meter.source != .inherit { new.meterChanges = [] }
        project.sections.append(new)
        project.arrangements[i].uses[ui].sectionID = new.id
        project.arrangements[i].uses[ui].settings = ContextSettings()
        project.arrangements[i].uses[ui].graphEdits = nil
        project.arrangements[i].uses[ui].laneOverrides = [:]; project.arrangements[i].uses[ui].addedLanes = []; project.arrangements[i].uses[ui].excludedLaneIDs = []; project.arrangements[i].uses[ui].barsOverride = nil
    }
    public static func connect(from: ID, to: ID, in project: inout Project) throws {
        let i = project.activeIndex
        guard from != to, project.arrangements[i].uses.contains(where: { $0.id == from }), project.arrangements[i].uses.contains(where: { $0.id == to }) else { throw CirclrError("다른 서클의 입력에 연결하세요") }
        guard !project.arrangements[i].edges.contains(where: { $0.from == from && $0.to == to }) else { return }
        var adjacency: [ID: [ID]] = [:]
        for e in project.arrangements[i].edges { adjacency[e.from, default: []].append(e.to) }
        var stack = [to], seen = Set<ID>()
        while let n = stack.popLast() {
            if n == from { throw CirclrError("순환 연결 대신 서클의 반복 횟수를 지정하세요") }
            if seen.insert(n).inserted { stack += adjacency[n] ?? [] }
        }
        project.arrangements[i].edges.append(FlowEdge(from: from, to: to))
        if let index = project.arrangements[i].uses.firstIndex(where: { $0.id == from }) { project.arrangements[i].uses[index].isEnd = false }
    }
    public static func insert(useID: ID, on edgeID: ID, in project: inout Project) throws {
        let i = project.activeIndex
        guard let edge = project.arrangements[i].edges.first(where: { $0.id == edgeID }), edge.from != useID, edge.to != useID else { throw CirclrError("삽입할 연결을 선택하세요") }
        let attached = project.arrangements[i].edges.filter { $0.from == useID || $0.to == useID }
        guard attached.allSatisfy({ $0.transition.length == 0 }), attached.filter({ $0.from == useID }).count <= 1, attached.filter({ $0.to == useID }).count <= 1 else { throw CirclrError("전환 또는 분기가 있는 서클은 연결을 먼저 정리하세요") }
        guard edge.transition.length == 0 else { throw CirclrError("전환이 있는 연결은 전환을 먼저 정리하세요") }
        let incoming = attached.first(where: { $0.to == useID }), outgoing = attached.first(where: { $0.from == useID })
        var candidate = project
        candidate.arrangements[i].edges.removeAll { $0.id == edgeID || $0.from == useID || $0.to == useID }
        if let incoming, let outgoing { try connect(from: incoming.from, to: outgoing.to, in: &candidate) }
        else if let incoming, let index = candidate.arrangements[i].uses.firstIndex(where: { $0.id == incoming.from }) { candidate.arrangements[i].uses[index].isEnd = true }
        if candidate.arrangements[i].startID == useID { candidate.arrangements[i].startID = outgoing?.to ?? edge.from }
        try connect(from: edge.from, to: useID, in: &candidate)
        try connect(from: useID, to: edge.to, in: &candidate)
        candidate.arrangements[i].chosenEdges = candidate.arrangements[i].chosenEdges.filter { key, value in candidate.arrangements[i].edges.contains(where: { $0.id == value && $0.from == key }) }
        project = candidate
    }
    public static func removeUses(_ ids: Set<ID>, in project: inout Project) {
        let i = project.activeIndex
        project.arrangements[i].uses.removeAll { ids.contains($0.id) }
        project.arrangements[i].edges.removeAll { ids.contains($0.from) || ids.contains($0.to) }
        project.arrangements[i].chosenEdges = project.arrangements[i].chosenEdges.filter { key, value in !ids.contains(key) && project.arrangements[i].edges.contains(where: { $0.id == value }) }
        for id in ids { project.arrangements[i].layout.positions.removeValue(forKey: id) }
        for g in project.arrangements[i].layout.groups.indices { project.arrangements[i].layout.groups[g].members.removeAll { ids.contains($0) } }
        project.arrangements[i].layout.groups.removeAll { $0.members.isEmpty }
        if let start = project.arrangements[i].startID, ids.contains(start) { project.arrangements[i].startID = project.arrangements[i].uses.first?.id }
    }
    public static func duplicateArrangement(in project: inout Project, name: String) {
        let ownerIndex = project.album?.compositions.firstIndex(where: { $0.arrangementIDs.contains(project.activeArrangementID) })
        var a = project.active; a.id = newID(); a.name = name
        let map = Dictionary(uniqueKeysWithValues: a.uses.map { ($0.id, newID()) })
        a.uses = a.uses.map { u in var copy = u; copy.id = map[u.id]!; return copy }
        var edgeMap: [ID: ID] = [:]
        a.edges = a.edges.map { e in var copy = e; copy.id = newID(); edgeMap[e.id] = copy.id; copy.from = map[e.from] ?? e.from; copy.to = map[e.to] ?? e.to; return copy }
        a.chosenEdges = Dictionary(uniqueKeysWithValues: a.chosenEdges.compactMap { k,v in guard let key = map[k], let value = edgeMap[v] else { return nil }; return (key,value) })
        a.startID = a.startID.flatMap { map[$0] }
        a.layout.positions = Dictionary(uniqueKeysWithValues: a.layout.positions.map { (map[$0.key] ?? $0.key, $0.value) })
        a.layout.groups = a.layout.groups.map { g in var copy = g; copy.id = newID(); copy.members = g.members.compactMap { map[$0] }; return copy }
        project.arrangements.append(a); project.activeArrangementID = a.id
        if let ownerIndex {
            project.album?.compositions[ownerIndex].arrangementIDs.append(a.id)
            project.album?.compositions[ownerIndex].selectedArrangementID = a.id
        }
    }
    public static func setLane(_ lane: Lane, for useID: ID, original: Bool, in project: inout Project) throws {
        guard let previousUse = project.active.uses.first(where: { $0.id == useID }),
              let previousSection = project.sections.first(where: { $0.id == previousUse.sectionID }) else { throw CirclrError("섹션이 없습니다") }
        let previousLanes = original ? previousSection.lanes : try ArrangementCompiler.effectiveLanes(section: previousSection, use: previousUse)
        let previousLane = previousLanes.first { $0.id == lane.id }
        let previousClips = Set(previousLane?.audio.map(\.id) ?? [])
        var candidate = project
        try setLaneData(lane, for: useID, original: original, in: &candidate)
        guard let use = candidate.active.uses.first(where: { $0.id == useID }),
              let section = candidate.sections.first(where: { $0.id == use.sectionID }) else { throw CirclrError("섹션이 없습니다") }
        if var graph = original ? section.graph : try SectionGraphEditing.effective(section: section, use: use) {
            let validClips = Set(lane.audio.map(\.id))
            let removed = Set(graph.nodes.compactMap { node -> ID? in
                if case .audio(let laneID, let clipID) = node.content, laneID == lane.id, !validClips.contains(clipID) { return node.id }; return nil
            })
            SectionGraphEditing.remove(removed, from: &graph)
            let existing = Set(graph.nodes.map(\.id))
            let includeMIDI = !lane.notes.isEmpty || (previousLane == nil && lane.audio.isEmpty)
            let newMIDI = !lane.notes.isEmpty && previousLane?.notes.isEmpty != false && !existing.contains("midi:\(lane.id)")
            let defaults = SectionGraphMigration.graph(lanes: [lane], tracks: candidate.tracks.filter { $0.id == lane.trackID }, effects: [],includeMIDI:includeMIDI)
            let hasNewSource = previousLane == nil || newMIDI || lane.audio.contains { !previousClips.contains($0.id) }
            let added = Set(defaults.nodes.filter { node in
                guard !existing.contains(node.id), hasNewSource else { return false }
                switch node.content {
                case .midi: return previousLane == nil || newMIDI
                case .audio(_, let clip): return !previousClips.contains(clip)
                default: return true
                }
            }.map(\.id))
            SourceCircleEditing.merge(defaults,adding:added,into:&graph)
            try SectionGraphEditing.set(graph, useID: useID, original: original, in: &candidate)
        }
        project = candidate
    }
    private static func setLaneData(_ lane: Lane, for useID: ID, original: Bool, in project: inout Project) throws {
        let i = project.activeIndex
        guard let ui = project.arrangements[i].uses.firstIndex(where: { $0.id == useID }), let si = project.sections.firstIndex(where: { $0.id == project.arrangements[i].uses[ui].sectionID }) else { throw CirclrError("섹션을 찾을 수 없습니다") }
        if original {
            if let li = project.sections[si].lanes.firstIndex(where: { $0.id == lane.id }) { project.sections[si].lanes[li] = lane }
            else { project.sections[si].lanes.append(lane) }
        } else if project.sections[si].lanes.contains(where: { $0.id == lane.id }) { project.arrangements[i].uses[ui].laneOverrides[lane.id] = lane }
        else if let li = project.arrangements[i].uses[ui].addedLanes.firstIndex(where: { $0.id == lane.id }) { project.arrangements[i].uses[ui].addedLanes[li] = lane }
        else { project.arrangements[i].uses[ui].addedLanes.append(lane) }
    }
    public static func unfoldRepeats(_ useID: ID, in project: inout Project) throws {
        let i = project.activeIndex
        guard let index = project.arrangements[i].uses.firstIndex(where: { $0.id == useID }) else { return }
        let source = project.arrangements[i].uses[index]
        guard source.repeatCount > 1 else { return }
        let outgoing = project.arrangements[i].edges.filter { $0.from == useID }
        project.arrangements[i].edges.removeAll { $0.from == useID }
        project.arrangements[i].uses[index].repeatCount = 1
        let pos = project.arrangements[i].layout.positions[useID] ?? Point()
        var previous = useID
        for iteration in 1..<source.repeatCount {
            var u = source; u.id = newID(); u.repeatCount = 1; u.name = "\(source.name) \(iteration + 1)회"
            project.arrangements[i].uses.append(u); project.arrangements[i].layout.positions[u.id] = Point(pos.x + Double(iteration) * 230, pos.y)
            try connect(from: previous, to: u.id, in: &project); previous = u.id
        }
        for var edge in outgoing { edge.from = previous; project.arrangements[i].edges.append(edge) }
        if let chosen = project.arrangements[i].chosenEdges.removeValue(forKey: useID) { project.arrangements[i].chosenEdges[previous] = chosen }
    }
}

public extension ProjectEditing {
    static func activateTake(_ take: RecordedTake, in project: inout Project) throws {
        guard let ai=project.arrangements.firstIndex(where:{ a in
            (take.arrangementID == nil || a.id == take.arrangementID) && a.uses.contains{$0.id==take.useID}
        }),let use=project.arrangements[ai].uses.first(where:{$0.id==take.useID}),let section=project.sections.first(where:{$0.id==use.sectionID}) else { throw CirclrError("Take의 서클을 찾을 수 없습니다") }
        let lanes=try ArrangementCompiler.effectiveLanes(section:section,use:use)
        let target=take.targetLaneID.flatMap{id in lanes.first{$0.id==id}} ?? (take.targetLaneID == nil ? lanes.first{$0.trackID==take.lane.trackID}:nil)
        if take.targetLaneID != nil,target == nil { throw CirclrError("녹음 대상 서클이 삭제되었습니다") }
        var lane=target ?? take.lane
        if !take.lane.notes.isEmpty { lane.notes=take.lane.notes }
        if !take.lane.audio.isEmpty { lane.audio=take.lane.audio }
        var candidate=project;let active=candidate.activeArrangementID;candidate.activeArrangementID=candidate.arrangements[ai].id
        try setLane(lane,for:take.useID,original:false,in:&candidate)
        candidate.activeArrangementID=active;project=candidate
    }
}
