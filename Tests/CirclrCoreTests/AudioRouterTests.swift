import XCTest
@testable import CirclrCore

final class AudioRouterTests: XCTestCase {
    func fixture() throws -> (Project, SectionGraph, MusicCircle, MusicCircle, MusicCircle) {
        var p = Project(); _ = p.addTrack(name: "첫 악기"); _ = p.addTrack(name: "둘째 악기")
        _ = p.addSection(name: "라우팅", at: Point(), bars: 1); p.enableAlbum()
        p = try SectionGraphMigration.migrate(p)
        var graph = try XCTUnwrap(p.sections[0].graph)
        let sources = graph.nodes.filter { if case .instrument = $0.content { return true }; return false }
        let router = MusicCircle(name: "스테레오 라우터", content: .router(AudioRouter()))
        graph.nodes.append(router)
        return (p, graph, sources[0], sources[1], router)
    }

    func testExplicitBusesStayDistinctAndImplicitAmbiguousRequestsAreAtomic() throws {
        var (_, g, a, b, r) = try fixture(); let before = g
        XCTAssertThrowsError(try SectionGraphEditing.connect(from: a.id, to: r.id, in: &g))
        XCTAssertEqual(g, before)
        try SectionGraphEditing.connect(from: a.id, to: r.id, toPortID: AudioRouter.input1, in: &g)
        try SectionGraphEditing.connect(from: a.id, to: r.id, toPortID: AudioRouter.input2, in: &g)
        try SectionGraphEditing.connect(from: b.id, to: r.id, toPortID: AudioRouter.input2, in: &g)
        XCTAssertEqual(g.edges.filter { $0.to == r.id }.count, 3)
        let connected = g
        try SectionGraphEditing.connect(from: a.id, to: r.id, toPortID: AudioRouter.input1, in: &g)
        XCTAssertEqual(g, connected)
        let output = g.nodes.first { if case .output = $0.content { return true }; return false }!
        for (fromPort, toPort) in [(nil, nil), ("out.audio.unknown", nil), (AudioRouter.input1, nil), (AudioRouter.output1, CirclePort.sidechainInput)] as [(String?, String?)] {
            XCTAssertThrowsError(try SectionGraphEditing.connect(from: r.id, to: output.id, fromPortID: fromPort, toPortID: toPort, in: &g))
            XCTAssertEqual(g, connected)
        }
        try SectionGraphEditing.connect(from: r.id, to: output.id, fromPortID: AudioRouter.output1, in: &g)
        try SectionGraphEditing.connect(from: r.id, to: output.id, fromPortID: AudioRouter.output2, in: &g)
        XCTAssertEqual(g.edges.filter { $0.from == r.id }.count, 2)
        let good = g
        XCTAssertThrowsError(try SectionGraphEditing.connect(from: r.id, to: r.id, fromPortID: AudioRouter.output1, toPortID: AudioRouter.input1, in: &g))
        XCTAssertEqual(g, good)
    }

    func testRawDocumentsRejectInvalidRoutesAndContradictoryPorts() throws {
        let (_, graph, a, _, r) = try fixture()
        for routes in [
            [.init(input: AudioRouter.input1, output: AudioRouter.output1, gain: -1)],
            [.init(input: AudioRouter.input1, output: AudioRouter.output1, gain: .nan)],
            [.init(input: AudioRouter.input1, output: AudioRouter.output1, gain: 4.1)],
            [.init(input: "unknown", output: AudioRouter.output1)],
            [.init(input: AudioRouter.input1, output: AudioRouter.output1), .init(input: AudioRouter.input1, output: AudioRouter.output1)]
        ] as [[AudioBusRoute]] {
            var invalid = graph; invalid.nodes[invalid.nodes.count - 1].content = .router(AudioRouter(routes: routes))
            XCTAssertThrowsError(try SectionGraphValidator.sorted(invalid))
        }
        var invalid = graph; invalid.edges.append(MusicConnection(from: a.id, to: r.id, signal: .audio))
        XCTAssertThrowsError(try SectionGraphValidator.sorted(invalid))
        invalid.edges[invalid.edges.count - 1].toPortID = AudioRouter.input1
        XCTAssertNoThrow(try SectionGraphValidator.sorted(invalid))
        invalid.edges[invalid.edges.count - 1].sidechain = true
        XCTAssertThrowsError(try SectionGraphValidator.sorted(invalid))
        var empty = graph; empty.nodes[empty.nodes.count - 1].content = .router(AudioRouter(routes: []))
        XCTAssertNoThrow(try SectionGraphValidator.sorted(empty))
    }

    func testCompilerCatalogSceneAndJSONPreserveExplicitBusIdentity() throws {
        var (p, g, a, _, r) = try fixture()
        let output = g.nodes.first { if case .output = $0.content { return true }; return false }!
        try SectionGraphEditing.connect(from: a.id, to: r.id, toPortID: AudioRouter.input2, in: &g)
        try SectionGraphEditing.connect(from: r.id, to: output.id, fromPortID: AudioRouter.output2, in: &g)
        try SectionGraphEditing.set(g, useID: p.active.uses[0].id, original: false, in: &p)
        let (s, c, k) = try ArrangementCompiler.context(project: p, use: p.active.uses[0])
        let plan = try XCTUnwrap(SectionGraphCompiler.compile(project: p, section: s, use: p.active.uses[0], context: c, clock: k))
        XCTAssertTrue(plan.connections.contains { $0.from == MusicBusEndpoint(nodeID: r.id, portID: AudioRouter.output2) })
        XCTAssertTrue(try CirclePortCatalog.connections(in: p).contains { $0.to.portID == AudioRouter.input2 })
        XCTAssertTrue(try HierarchySceneBuilder.build(p).edges.contains { $0.fromPortID == AudioRouter.output2 })
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p)), p)
        let legacy = MusicConnection(from: "old-a", to: "old-b", signal: .audio)
        let data = try JSONEncoder().encode(legacy), object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(object["fromPortID"]); XCTAssertNil(object["toPortID"])
        let loaded = try JSONDecoder().decode(MusicConnection.self, from: data)
        XCTAssertEqual(loaded.resolvedFromPortID, CirclePort.audioOutput)
        XCTAssertEqual(loaded.resolvedToPortID, CirclePort.audioInput)
    }

    func testEffectInsertionChoosesOneBusAndKeepsOtherBusAndSidechain() throws {
        var (_, g, _, _, r) = try fixture()
        let outputs = g.nodes.filter { if case .output = $0.content { return true }; return false }
        let comp = MusicCircle(name: "검출", content: .effect(Effect(.compressor)))
        let effect = MusicCircle(name: "드라이브", content: .effect(Effect(.drive)))
        g.nodes.append(comp)
        try SectionGraphEditing.connect(from: r.id, to: outputs[0].id, fromPortID: AudioRouter.output1, in: &g)
        try SectionGraphEditing.connect(from: r.id, to: outputs[1].id, fromPortID: AudioRouter.output2, in: &g)
        try SectionGraphEditing.connect(from: r.id, to: comp.id, fromPortID: AudioRouter.output1, toPortID: CirclePort.sidechainInput, in: &g)
        let before = g
        XCTAssertThrowsError(try SectionGraphEditing.insertEffect(effect, from: r.id, in: &g)); XCTAssertEqual(g, before)
        try SectionGraphEditing.insertEffect(effect, from: r.id, fromPortID: AudioRouter.output1, in: &g)
        for edge in before.edges where edge.from == r.id && (edge.resolvedFromPortID == AudioRouter.output2 || edge.sidechain) {
            XCTAssertTrue(g.edges.contains(edge))
        }
        let moved = try XCTUnwrap(g.edges.first { $0.from == effect.id })
        XCTAssertEqual(moved.to, outputs[0].id); XCTAssertEqual(moved.resolvedFromPortID, CirclePort.audioOutput)
        XCTAssertNoThrow(try SectionGraphValidator.sorted(g))
    }

    func testFourPortsAcrossEightOctantsHaveSeparateVisibleHits() throws {
        let ports = CirclePort.ports(for: .router(AudioRouter()))
        XCTAssertEqual(ports.filter { $0.direction == .input }.count, 2)
        XCTAssertEqual(ports.filter { $0.direction == .output }.count, 2)
        var handles: [CirclePortHandle] = []
        for octant in PortOctant.allCases { for port in ports {
            handles.append(.init(endpoint: .init(node: .signal("router"), portID: port.id), octant: octant,
                point: try CirclePortGeometry.anchor(center: Point(400, 400), radius: 20, port: port, octant: octant)))
        } }
        XCTAssertEqual(handles.count, 32)
        for h in handles {
            XCTAssertEqual(CirclePortGeometry.hit(h.point, visibleHandles: handles), h)
            XCTAssertNil(CirclePortGeometry.hit(h.point, visibleHandles: handles.filter { $0 != h }))
        }
    }
}
