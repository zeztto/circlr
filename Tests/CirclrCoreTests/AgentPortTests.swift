import XCTest
@testable import CirclrCore

final class AgentPortTests: XCTestCase {
    func fixture() throws -> Project {
        var p = Project(); _ = p.addTrack(name: "신스")
        _ = p.addSection(name: "첫 섹션", at: Point(), bars: 1)
        _ = p.addSection(name: "둘째 섹션", at: Point(300, 0), bars: 1)
        p.enableAlbum(); p = try SectionGraphMigration.migrate(p)
        for i in p.sections.indices {
            p.sections[i].graph!.nodes.append(MusicCircle(name: "라우터", content: .router(AudioRouter())))
            p.sections[i].graph!.nodes.append(MusicCircle(name: "컴프레서", content: .effect(Effect(.compressor))))
        }
        return p
    }
    func endpoint(_ p: Project, use: Int = 0, _ match: (MusicCircleContent) -> Bool, _ port: String) throws -> CirclePortEndpoint {
        let graph = try XCTUnwrap(SectionGraphEditing.effective(section: p.sections[use], use: p.active.uses[use]))
        let node = try XCTUnwrap(graph.nodes.first { match($0.content) })
        return .init(node: .music(arrangementID: p.active.id, useID: p.active.uses[use].id, nodeID: node.id), portID: port)
    }
    func pair(_ p: Project) throws -> AgentArguments {
        var args = AgentArguments()
        args.first = try endpoint(p, { if case .instrument = $0 { return true }; return false }, CirclePort.audioOutput)
        args.second = try endpoint(p, { if case .router = $0 { return true }; return false }, AudioRouter.inputs[0])
        args.firstOctant = .northeast; args.secondOctant = .southwest
        return args
    }
    func request(_ method: String, _ p: Project, _ args: AgentArguments) -> AgentRequest {
        var r = AgentRequest(method: method); r.projectID = p.id; r.expectedRevision = p.musicRevision
        r.arguments = args; r.arguments?.expectedLayoutRevision = p.portLayout?.revision ?? 0
        return r
    }
    func testPortSnapshotMatchesActualBusAndLogicalConnections() throws {
        let p = try fixture(), args = try pair(p)
        let edit = try AgentPortEditing.apply(request("connect_ports", p, args), to: p)
        let snapshot = try AgentPortEditing.snapshot(at: args.second!.node, in: edit.project)
        XCTAssertEqual(snapshot.ports.map(\.id), AudioRouter.inputs + AudioRouter.outputs)
        XCTAssertEqual(snapshot.connections.count, 1)
        XCTAssertEqual(snapshot.connections[0].connection.id, edit.connectionID)
        XCTAssertEqual(snapshot.connections[0].placement, .init(from: .northeast, to: .southwest))
        XCTAssertTrue(snapshot.connections[0].canReconnect); XCTAssertTrue(snapshot.connections[0].canDisconnect)
        XCTAssertEqual(snapshot.projectID, p.id); XCTAssertEqual(snapshot.revision, p.musicRevision)
        XCTAssertEqual(snapshot.layoutRevision, 1)
        XCTAssertThrowsError(try AgentPortEditing.snapshot(at: .album, in: p))
        XCTAssertThrowsError(try AgentPortEditing.snapshot(at: .signal("missing"), in: p))
        XCTAssertThrowsError(try AgentPortEditing.snapshot(at: .group(parent: .album, id: "missing"), in: p))
        XCTAssertEqual(edit.project.activeArrangementID, p.activeArrangementID)
    }
    func testReverseConnectRoundTripAndDuplicateAreOneCommandOrNoOp() throws {
        let p = try fixture(); var args = try pair(p)
        swap(&args.first, &args.second); swap(&args.firstOctant, &args.secondOctant)
        let encoded = try JSONEncoder().encode(request("connect_ports", p, args))
        let decoded = try JSONDecoder().decode(AgentRequest.self, from: encoded)
        let edit = try AgentPortEditing.apply(decoded, to: p)
        let connection = try XCTUnwrap(CirclePortCatalog.connections(in: edit.project).first { $0.id == edit.connectionID })
        XCTAssertEqual(connection.from, args.second); XCTAssertEqual(connection.to, args.first)
        XCTAssertEqual(edit.project.portLayout?.placement(for: connection.id), .init(from: .northeast, to: .southwest))
        args.firstOctant = .north
        let duplicate = try AgentPortEditing.apply(request("connect_ports", edit.project, args), to: edit.project)
        XCTAssertEqual(duplicate.project, edit.project); XCTAssertEqual(duplicate.connectionID, edit.connectionID)
        XCTAssertEqual(edit.project.musicRevision, p.musicRevision) // App owns the single increment.
    }
    func testReconnectKeepsIdentityGainAndDisconnectLeavesOtherUse() throws {
        let p = try fixture(); var args = try pair(p)
        let initial = try AgentPortEditing.apply(request("connect_ports", p, args), to: p)
        let id = try XCTUnwrap(initial.connectionID)
        var current = initial.project
        var graph = try XCTUnwrap(SectionGraphEditing.effective(section: current.sections[0], use: current.active.uses[0]))
        graph.edges[graph.edges.firstIndex { $0.id == id.edgeID }!].gain = 0.35
        try SectionGraphEditing.set(graph, useID: current.active.uses[0].id, original: false, in: &current)
        let untouched = current.active.uses[1]
        args.connectionID = id; args.second?.portID = AudioRouter.inputs[1]
        let reconnected = try AgentPortEditing.apply(request("reconnect_ports", current, args), to: current)
        let edge = try XCTUnwrap(CirclePortCatalog.connections(in: reconnected.project).first { $0.id == reconnected.connectionID })
        XCTAssertEqual(edge.id.edgeID, id.edgeID); XCTAssertEqual(edge.to.portID, AudioRouter.inputs[1]); XCTAssertEqual(edge.gain, 0.35)
        var disconnect = AgentArguments(); disconnect.connectionID = reconnected.connectionID
        let removed = try AgentPortEditing.apply(request("disconnect_ports", reconnected.project, disconnect), to: reconnected.project)
        XCTAssertFalse(try CirclePortCatalog.connections(in: removed.project).contains { $0.id == edge.id })
        XCTAssertEqual(removed.project.active.uses[1], untouched)
        XCTAssertThrowsError(try AgentPortEditing.apply(request("disconnect_ports", removed.project, disconnect), to: removed.project))
    }
    func testEveryWriteRequiresBothRevisionsAndExactProject() throws {
        let p = try fixture(), args = try pair(p)
        for method in ["connect_ports", "reconnect_ports", "disconnect_ports", "move_ports"] {
            for mismatch in 0..<4 {
                var r = request(method, p, args)
                if mismatch == 0 { r.projectID = "another" }
                if mismatch == 1 { r.expectedRevision = p.musicRevision + 1 }
                if mismatch == 2 { r.arguments?.expectedLayoutRevision = 1 }
                if mismatch == 3 { r.arguments?.expectedLayoutRevision = nil }
                XCTAssertThrowsError(try AgentPortEditing.apply(r, to: p)) { error in
                    XCTAssertTrue(error.localizedDescription.contains(mismatch < 2 ? "stale_revision" : "stale_layout"))
                }
            }
        }
    }
    func testLayoutBatchIsAtomicNoOpAndHistoryPreservesMusic() throws {
        let original = try fixture(), pair = try pair(original)
        let edit = try AgentPortEditing.apply(request("connect_ports", original, pair), to: original)
        let p = edit.project, id = try XCTUnwrap(edit.connectionID)
        var args = AgentArguments(); args.moves = [.init(id: id, placement: .init(from: .north, to: .south))]
        let moved = try AgentPortEditing.apply(request("move_ports", p, args), to: p).project
        XCTAssertEqual(moved.musicRevision, p.musicRevision); XCTAssertEqual(moved.arrangements, p.arrangements)
        XCTAssertEqual(moved.portLayout!.revision, p.portLayout!.revision + 1)
        XCTAssertEqual(try AgentPortEditing.apply(request("move_ports", moved, args), to: moved).project, moved)
        var missing = id; missing.edgeID = "missing"
        args.moves!.append(.init(id: missing, placement: .init(from: .east, to: .west)))
        XCTAssertThrowsError(try AgentPortEditing.apply(request("move_ports", p, args), to: p))
        args.moves = [args.moves![0], args.moves![0]]
        XCTAssertThrowsError(try AgentPortEditing.apply(request("move_ports", p, args), to: p))
        var concurrent = moved; concurrent.name = "최신 음악"; concurrent.musicRevision += 1
        let restored = try CircleHistory.restore(p, layoutOnly: true, current: concurrent)
        XCTAssertEqual(restored.name, concurrent.name); XCTAssertEqual(restored.musicRevision, concurrent.musicRevision)
        XCTAssertEqual(restored.portLayout?.placement(for: id), p.portLayout?.placement(for: id))
        XCTAssertEqual(restored.portLayout!.revision, moved.portLayout!.revision + 1)
    }
    func testIncompatibleAmbiguousCrossScopeAndStaleConnectionAreRejected() throws {
        let p = try fixture(); let args = try pair(p)
        var invalid = args; invalid.second?.portID = CirclePort.audioInput
        XCTAssertThrowsError(try AgentPortEditing.apply(request("connect_ports", p, invalid), to: p))
        invalid = args; invalid.second = args.first
        XCTAssertThrowsError(try AgentPortEditing.apply(request("connect_ports", p, invalid), to: p))
        invalid = args; invalid.second = try endpoint(p, use: 1, { if case .router = $0 { return true }; return false }, AudioRouter.inputs[0])
        XCTAssertThrowsError(try AgentPortEditing.apply(request("connect_ports", p, invalid), to: p))
        invalid = args; invalid.connectionID = .init(edgeID: "missing", from: args.first!.node, to: args.second!.node)
        XCTAssertThrowsError(try AgentPortEditing.apply(request("reconnect_ports", p, invalid), to: p))
        XCTAssertThrowsError(try AgentPortEditing.apply(request("connect_ports", p, invalid), to: p))
        XCTAssertThrowsError(try AgentPortEditing.apply(request("reconnect_ports", p, args), to: p))
    }
    func testMIDIAndSidechainAndFlowUseRealPortSemantics() throws {
        let p = try fixture(); var args = try pair(p)
        args.second = try endpoint(p, { if case .effect = $0 { return true }; return false }, CirclePort.sidechainInput)
        let sidechain = try AgentPortEditing.apply(request("connect_ports", p, args), to: p)
        XCTAssertTrue(try XCTUnwrap(CirclePortCatalog.connections(in: sidechain.project).first { $0.id == sidechain.connectionID }).sidechain)
        args.first = try endpoint(p, { if case .midi = $0 { return true }; return false }, CirclePort.midiOutput)
        args.second = try endpoint(p, { if case .instrument = $0 { return true }; return false }, CirclePort.midiInput)
        let midi = try AgentPortEditing.apply(request("connect_ports", p, args), to: p)
        XCTAssertEqual(try XCTUnwrap(CirclePortCatalog.connections(in: midi.project).first { $0.id == midi.connectionID }).signal, .midi)
        args.first = .init(node: .section(arrangementID: p.active.id, useID: p.active.uses[0].id), portID: CirclePort.flowOutput)
        args.second = .init(node: .section(arrangementID: p.active.id, useID: p.active.uses[1].id), portID: CirclePort.flowInput)
        let flow = try AgentPortEditing.apply(request("connect_ports", p, args), to: p)
        XCTAssertEqual(try XCTUnwrap(CirclePortCatalog.connections(in: flow.project).first { $0.id == flow.connectionID }).signal, .flow)
    }
    func testWireRejectsOutOfRangeOctantsAndWrongTypes() throws {
        let p = try fixture(), request = request("connect_ports", p, try pair(p))
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for invalid: Any in [8, -1, true, "north"] {
            var packet = object, args = packet["arguments"] as! [String: Any]
            args["firstOctant"] = invalid; packet["arguments"] = args
            XCTAssertThrowsError(try JSONDecoder().decode(AgentRequest.self, from: JSONSerialization.data(withJSONObject: packet)))
        }
    }
}
