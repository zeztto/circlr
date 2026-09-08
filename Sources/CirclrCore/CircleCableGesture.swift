import Foundation

/// Captures a cable edit at pointer-down. Preview never mutates the document.
public struct CircleCableGesture: Sendable {
    public enum Mode: String, Sendable { case reconnect, placement }
    public let mode: Mode
    public let direction: CirclePortDirection
    public let connection: CirclePortConnection
    public let placement: CircleConnectionPlacement
    private let projectID: ID
    private let musicRevision: Int
    private let layoutRevision: Int

    public init(id: CircleConnectionID, direction: CirclePortDirection, mode: Mode, project: Project) throws {
        guard let connection = try CirclePortCatalog.connections(in: project).first(where: { $0.id == id }) else {
            throw CirclrError("편집할 케이블이 없습니다")
        }
        if mode == .reconnect, case .composition = connection.from.node { throw CirclrError("곡·악장은 순서 연결로 편집하세요") }
        self.connection = connection; self.mode = mode; self.direction = direction
        placement = project.portLayout?.placement(for: id) ?? .init()
        projectID = project.id; musicRevision = project.musicRevision; layoutRevision = project.portLayout?.revision ?? 0
    }

    public var moving: CirclePortEndpoint { direction == .output ? connection.from : connection.to }
    public var fixed: CirclePortEndpoint { direction == .output ? connection.to : connection.from }
    public var fixedOctant: PortOctant { direction == .output ? placement.to : placement.from }

    @discardableResult public func apply(to target: CirclePortEndpoint, octant: PortOctant, original: Bool = false,
                                        in project: inout Project) throws -> CircleConnectionID {
        guard project.id == projectID, project.musicRevision == musicRevision,
              (project.portLayout?.revision ?? 0) == layoutRevision,
              try CirclePortCatalog.connections(in: project).contains(connection) else {
            throw CirclrError("드래그 중 음악·배치가 변경되었습니다. 다시 연결하세요")
        }
        if mode == .placement {
            guard target == moving else { throw CirclrError("위치 이동은 원래 서클 둘레에 놓으세요") }
            var next = placement
            if direction == .output { next.from = octant } else { next.to = octant }
            try CirclePortLayoutEditing.apply([.init(id: connection.id, placement: next)], projectID: projectID,
                expectedMusicRevision: musicRevision, expectedLayoutRevision: layoutRevision, in: &project)
            return connection.id
        }
        return try CircleConnectionEditing.connect(target, fixed, firstOctant: octant, secondOctant: fixedOctant,
            replacing: connection.id, original: original, in: &project)
    }
}
