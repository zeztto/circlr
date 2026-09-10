import Foundation

public enum CompositionKind: String, Codable, CaseIterable {
    case song, movement
    public var label: String { self == .song ? "곡" : "악장" }
}

/// A composition owns either child compositions or alternative arrangements.
/// Array order is musical order; canvas coordinates are independent.
public struct Composition: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var name: String
    public var kind: CompositionKind
    public var children: [ID] = []
    public var arrangementIDs: [ID] = []
    public var selectedArrangementID: ID?
    public var settings = ContextSettings()
    public var repeatCount = 1
    public var layout = Layout()
    public init(name: String, kind: CompositionKind = .song, arrangementID: ID? = nil) {
        self.name = name; self.kind = kind
        if let arrangementID { arrangementIDs = [arrangementID]; selectedArrangementID = arrangementID }
    }
}

public struct Album: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var children: [ID] = []
    public var compositions: [Composition] = []
    public var layout = Layout()
    public init() {}
    public func composition(_ id: ID) -> Composition? { compositions.first { $0.id == id } }
    public func owner(of arrangementID: ID) -> Composition? { compositions.first { $0.arrangementIDs.contains(arrangementID) } }
    public func parent(of id: ID) -> ID? { compositions.first { $0.children.contains(id) }?.id }

    public func path(to id: ID) throws -> [Composition] {
        var path: [Composition] = [], current: ID? = id, seen = Set<ID>()
        while let next = current {
            guard seen.insert(next).inserted, seen.count <= 64 else { throw CirclrError("앨범 포함 관계가 순환하거나 너무 깊습니다") }
            guard let node = composition(next) else { throw CirclrError("곡·악장 서클을 찾을 수 없습니다") }
            path.append(node); current = parent(of: next)
        }
        guard let root = path.last, children.contains(root.id) else { throw CirclrError("앨범에 연결되지 않은 곡·악장입니다") }
        return path.reversed()
    }

    public func validate(arrangements: [Arrangement]) throws {
        let ids = compositions.map(\.id)
        guard !id.isEmpty, !ids.isEmpty, ids.count <= 10_000,
              ids.allSatisfy({ !$0.isEmpty && $0 != id }), Set(ids).count == ids.count else { throw CirclrError("앨범 서클 ID가 비어 있거나 중복되었습니다") }
        let allChildren = children + compositions.flatMap(\.children)
        guard Set(allChildren) == Set(ids), allChildren.count == ids.count else { throw CirclrError("모든 곡·악장은 하나의 부모에만 포함되어야 합니다") }
        let owned = compositions.flatMap(\.arrangementIDs)
        guard Set(arrangements.map(\.id)).count == arrangements.count,
              Set(owned) == Set(arrangements.map(\.id)), owned.count == arrangements.count else { throw CirclrError("모든 편곡안은 한 곡·악장에만 속해야 합니다") }
        for node in compositions {
            guard (1...256).contains(node.repeatCount) else { throw CirclrError("곡·악장의 반복은 1–256회로 지정하세요") }
            let container = !node.children.isEmpty
            guard container ? (node.arrangementIDs.isEmpty && node.selectedArrangementID == nil) :
                (!node.arrangementIDs.isEmpty && node.selectedArrangementID.map(node.arrangementIDs.contains) == true)
            else { throw CirclrError("\(node.name): 하위 곡·악장과 편곡안을 동시에 담을 수 없습니다") }
            _ = try path(to: node.id)
            try AlbumEditing.validateLayout(node.layout)
        }
        try AlbumEditing.validateLayout(layout)
    }
}

public extension ContextResolver {
    static func inheriting(global: MusicContext, parent: MusicContext, settings: ContextSettings) throws -> MusicContext {
        func field<T>(_ global: T, _ parent: T, _ setting: Setting<T>) throws -> T {
            switch setting.source {
            case .inherit: return parent
            case .global: return global
            case .local:
                guard let value = setting.value else { throw CirclrError("개별 음악 설정값이 없습니다") }
                return value
            }
        }
        var result = MusicContext()
        result.tempo = try field(global.tempo, parent.tempo, settings.tempo)
        result.meter = try field(global.meter, parent.meter, settings.meter)
        result.scale = try field(global.scale, parent.scale, settings.scale)
        result.beatGrid = try field(global.beatGrid, parent.beatGrid, settings.beatGrid)
        result.rhythm = try field(global.rhythm, parent.rhythm, settings.rhythm)
        try validate(result)
        return result
    }
}

public extension Project {
    /// Existing IDs, media, alternatives and original/variant data remain intact.
    mutating func enableAlbum() {
        guard album == nil, (1...7).contains(schemaVersion) else { return }
        var node = Composition(name: name)
        node.arrangementIDs = arrangements.map(\.id); node.selectedArrangementID = activeArrangementID
        var value = Album(); value.children = [node.id]; value.compositions = [node]
        value.layout.positions[node.id] = Point()
        album = value; schemaVersion = max(2,schemaVersion)
    }
    func compositionContext(for arrangementID: ID) throws -> MusicContext {
        guard let album else { return global }
        guard let owner = album.owner(of: arrangementID) else { throw CirclrError("편곡안의 곡·악장을 찾을 수 없습니다") }
        return try album.path(to: owner.id).reduce(global) { try ContextResolver.inheriting(global: global, parent: $0, settings: $1.settings) }
    }
}

public enum AlbumEditing {
    static func validateLayout(_ layout: Layout) throws {
        guard layout.zoom.isFinite, (0.25...2.5).contains(layout.zoom),
              layout.pan.x.isFinite, layout.pan.y.isFinite,
              layout.spacing.isFinite, (12...256).contains(layout.spacing),
              layout.positions.values.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1e7 && abs($0.y) < 1e7 })
        else { throw CirclrError("앨범 캔버스 좌표를 확인하세요") }
    }

    @discardableResult public static func add(name: String, kind: CompositionKind, parentID: ID? = nil,
                                              at point: Point = Point(), in project: inout Project) throws -> ID {
        var candidate = project; candidate.enableAlbum()
        guard var album = candidate.album else { throw CirclrError("앨범이 없습니다") }
        let arrangement = Arrangement()
        let node = Composition(name: name, kind: kind, arrangementID: arrangement.id)
        if let parentID {
            guard let i = album.compositions.firstIndex(where: { $0.id == parentID }), album.compositions[i].arrangementIDs.isEmpty else {
                throw CirclrError("기존 섹션을 먼저 악장으로 묶은 뒤 하위 서클을 추가하세요")
            }
            album.compositions[i].children.append(node.id); album.compositions[i].layout.positions[node.id] = point
        } else { album.children.append(node.id); album.layout.positions[node.id] = point }
        album.compositions.append(node); candidate.arrangements.append(arrangement)
        candidate.album = album
        try album.validate(arrangements: candidate.arrangements)
        project = candidate
        return node.id
    }

    /// Explicitly moves a song's existing alternatives into its first movement.
    @discardableResult public static func wrapContents(of id: ID, name: String, in project: inout Project) throws -> ID {
        var candidate = project
        guard var album = candidate.album, let i = album.compositions.firstIndex(where: { $0.id == id }),
              album.compositions[i].children.isEmpty else { throw CirclrError("섹션을 담은 곡·악장을 선택하세요") }
        var movement = Composition(name: name, kind: .movement)
        movement.arrangementIDs = album.compositions[i].arrangementIDs
        movement.selectedArrangementID = album.compositions[i].selectedArrangementID
        album.compositions[i].arrangementIDs = []; album.compositions[i].selectedArrangementID = nil
        album.compositions[i].children = [movement.id]; album.compositions[i].layout.positions[movement.id] = Point()
        album.compositions.append(movement); candidate.album = album
        try album.validate(arrangements: candidate.arrangements)
        project = candidate
        return movement.id
    }

    public static func move(_ id: ID, to parentID: ID?, index: Int, in project: inout Project) throws {
        var candidate = project
        guard var album = candidate.album, album.composition(id) != nil else { throw CirclrError("이동할 서클이 없습니다") }
        if let parentID {
            guard parentID != id, let parent = album.composition(parentID), parent.arrangementIDs.isEmpty,
                  !(try album.path(to: parentID)).contains(where: { $0.id == id }) else { throw CirclrError("자신의 내부 또는 섹션이 있는 곡으로 이동할 수 없습니다") }
        }
        album.children.removeAll { $0 == id }
        for i in album.compositions.indices { album.compositions[i].children.removeAll { $0 == id } }
        if let parentID, let i = album.compositions.firstIndex(where: { $0.id == parentID }) {
            album.compositions[i].children.insert(id, at: max(0, min(index, album.compositions[i].children.count)))
        } else { album.children.insert(id, at: max(0, min(index, album.children.count))) }
        // Do not orphan an empty parent. Moving its last child requires moving the parent itself.
        try album.validate(arrangements: candidate.arrangements)
        candidate.album = album; project = candidate
    }

    public static func selectArrangement(_ id: ID, in project: inout Project) throws {
        guard let album = project.album else {
            guard project.arrangements.contains(where: { $0.id == id }) else { throw CirclrError("편곡안이 없습니다") }
            project.activeArrangementID = id; return
        }
        guard let i = album.compositions.firstIndex(where: { $0.arrangementIDs.contains(id) }) else { throw CirclrError("곡에 속하지 않은 편곡안입니다") }
        project.album?.compositions[i].selectedArrangementID = id; project.activeArrangementID = id
    }
}

public struct CompositionOccurrence {
    public var compositionID: ID
    public var path: [ID]
    public var iterations: [Int]
    public var start: Double
    public var plan: ExecutionPlan
    public var end: Double { start + plan.duration }
}
public struct AlbumExecutionPlan {
    public var projectID: ID
    public var revision: Int
    public var compositions: [CompositionOccurrence]
    public var duration: Double
}
public enum AlbumCompiler {
    public static func compile(_ input: Project) throws -> AlbumExecutionPlan {
        guard (1...7).contains(input.schemaVersion) else { throw CirclrError("이 앨범의 형식 버전을 지원하지 않습니다") }
        var project = input; project.enableAlbum()
        guard let album = project.album else { throw CirclrError("앨범이 없습니다") }
        try album.validate(arrangements: project.arrangements)
        try ContextResolver.validate(project.global)
        var result: [CompositionOccurrence] = [], cursor = 0.0, events = 0
        func visit(_ id: ID, path: [ID], iterations: [Int], parentContext: MusicContext) throws {
            guard let node = album.composition(id) else { throw CirclrError("곡·악장이 없습니다") }
            let context = try ContextResolver.inheriting(global: project.global, parent: parentContext, settings: node.settings)
            for iteration in 0..<node.repeatCount {
                if node.children.isEmpty {
                    guard let arrangementID = node.selectedArrangementID else { throw CirclrError("재생할 편곡안을 선택하세요") }
                    let plan = try ArrangementCompiler.compile(project, arrangementID: arrangementID)
                    events += plan.occurrences.reduce(0) { total, occurrence in
                        total + (occurrence.signalPlan?.eventCount ?? occurrence.lanes.reduce(0) { $0 + $1.notes.count + $1.audio.count })
                    }
                    for occurrence in plan.occurrences {
                        if occurrence.signalPlan == nil, let patternID = occurrence.context.rhythm.patternID, let pattern = project.patterns.first(where: { $0.id == patternID }) {
                            events += Int(ceil(occurrence.clock.beats / pattern.length)) * (pattern.notes.count + pattern.audio.count)
                        }
                    }
                    result.append(CompositionOccurrence(compositionID: id, path: path + [id], iterations: iterations + [iteration], start: cursor, plan: plan))
                    cursor += plan.duration
                    guard result.count <= 10_000, cursor <= 86_400, events <= 1_000_000 else { throw CirclrError("앨범 실행 계획의 곡·event·시간 범위를 넘었습니다") }
                } else {
                    for child in node.children { try visit(child, path: path + [id], iterations: iterations + [iteration], parentContext: context) }
                }
            }
        }
        for id in album.children { try visit(id, path: [], iterations: [], parentContext: project.global) }
        return AlbumExecutionPlan(projectID: project.id, revision: project.musicRevision, compositions: result, duration: cursor)
    }

    /// Existing playback and export consume the same absolute-time plan for the whole album.
    public static func executionPlan(_ project: Project) throws -> ExecutionPlan {
        let album = try compile(project)
        var occurrences: [Occurrence] = [], transitions: [ScheduledTransition] = [], warnings: [String] = []
        for composition in album.compositions {
            for var occurrence in composition.plan.occurrences {
                occurrence.start += composition.start; occurrences.append(occurrence)
            }
            for var transition in composition.plan.transitions {
                transition.start += composition.start; transitions.append(transition)
            }
            warnings += composition.plan.warnings
        }
        return ExecutionPlan(revision: project.musicRevision, arrangementID: project.album?.id ?? project.activeArrangementID,
                             occurrences: occurrences, transitions: transitions, duration: album.duration,
                             warnings: Array(Set(warnings)).sorted())
    }
}
