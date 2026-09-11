import XCTest
import CirclrCore
@testable import CirclrAudio

extension AudioRouterAudioTests {
    func visualized(_ project: Project, tail: Double = 0) async throws -> (PreparedAudio, OccurrenceVisualization) {
        let plan = try ArrangementCompiler.compile(project)
        let rendered = try await ArrangementRenderer.render(project: project, root: nil, plan: plan,
            tailSeconds: tail, includeStems: false, includeVisualization: true)
        return (rendered, try XCTUnwrap(rendered.visualization?.occurrences[plan.occurrences[0].id]))
    }

    func testOutputObserverMeasuresPostGainAutomationWithoutChangingStereoPCM() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-port-observer-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root); var p = f.project
        let index = try XCTUnwrap(p.sections[0].graph?.nodes.firstIndex { $0.id == f.router })
        p.sections[0].graph?.nodes[index].gain = 0.5
        p.sections[0].graph?.nodes[index].automation = [.init(parameter: .gain, points: [.init(beat: 0, value: 0.5)])]
        let plain = try await render(p)
        var buses: [MusicBusEndpoint: PCM] = [:]
        let observed = try await render(p, observeOutput: { buses[$0] = $1 })
        for n in 0..<2 {
            let track = p.tracks[n].id
            try assertPCM(plain[track], observed[track])
            try assertPCM(plain[track], buses[.init(nodeID: f.router, portID: AudioRouter.outputs[n])])
        }
        let (prepared, visual) = try await visualized(p)
        let without = try await ArrangementRenderer.render(project: p, root: nil, plan: prepared.plan, tailSeconds: 0, includeStems: false)
        try assertPCM(prepared.mix, without.mix)
        for n in 0..<2 {
            XCTAssertEqual(visual.ports[.init(nodeID: f.router, portID: AudioRouter.outputs[n])]?.peaks,
                           PlaybackEnvelope(try XCTUnwrap(plain[p.tracks[n].id])).peaks)
        }
    }

    func testIndependentOutputEnvelopesDoNotShareTimeOrCancelOppositePhase() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-port-time-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root), p = f.project
        for opposite in [false, true] {
            for n in 0..<2 {
                var pcm = PCM(frames: 48_000)
                for i in 0..<pcm.count where opposite || (n == 0 ? i < 24_000 : i >= 24_000) {
                    pcm.left[i] = opposite && n == 1 ? -0.25 : 0.25
                    pcm.right[i] = opposite && n == 1 ? -0.125 : 0.125
                }
                try pcm.writeWAV(URL(fileURLWithPath: p.assets[n].path))
            }
            let (rendered, visual) = try await visualized(p)
            let a = try XCTUnwrap(visual.ports[.init(nodeID: f.router, portID: AudioRouter.output1)])
            let b = try XCTUnwrap(visual.ports[.init(nodeID: f.router, portID: AudioRouter.output2)])
            XCTAssertEqual(a.level(at: 0.2), 0.25, accuracy: 0.000001)
            XCTAssertEqual(b.level(at: 0.7), 0.25, accuracy: 0.000001)
            if opposite {
                XCTAssertEqual(rendered.mix.peak, 0)
                XCTAssertEqual(visual.nodes[f.router]?.level(at: 0.2), 0.25)
                XCTAssertEqual(a.peaks, b.peaks)
            } else {
                XCTAssertEqual(b.level(at: 0.2), 0)
                XCTAssertEqual(a.level(at: 0.7), 0)
            }
            for edge in try XCTUnwrap(p.sections[0].graph).edges where edge.from == f.router {
                XCTAssertEqual(visual.edgeLevel(edge.id, at: 0.2), edge.resolvedFromPortID == AudioRouter.output1 ? a.level(at: 0.2) : b.level(at: 0.2))
            }
        }
    }

    func testPortTraversalExcludesInactiveMatrixInputAndMutedOutputBranches() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-port-paths-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root)
        for mode in 0..<6 {
            var p = f.project, g = try XCTUnwrap(p.sections[0].graph)
            let index = try XCTUnwrap(g.nodes.firstIndex { $0.id == f.router })
            switch mode {
            case 0: p.tracks[1].muted = true
            case 1: p.tracks[1].gain = 0
            case 2: g.edges.removeAll { $0.to == f.outputs[1] }
            case 3: g.nodes[index].content = .router(.init(routes: [
                .init(input: AudioRouter.input1, output: AudioRouter.output1),
                .init(input: AudioRouter.input2, output: AudioRouter.output2, gain: 0)
            ]))
            case 4: g.nodes[g.nodes.firstIndex { $0.id == f.outputs[1] }!].muted = true
            default: g.edges[g.edges.firstIndex { $0.to == f.outputs[1] }!].gain = 0
            }
            p.sections[0].graph = g
            let (_, visual) = try await visualized(p)
            XCTAssertNil(visual.nodes[f.sources[1]], "mode \(mode)")
            XCTAssertNil(visual.ports[.init(nodeID: f.sources[1], portID: CirclePort.audioOutput)], "mode \(mode)")
            XCTAssertGreaterThan(visual.nodes[f.sources[0]]?.level(at: 0.2) ?? 0, 0.1)
            for edge in g.edges where edge.from == f.sources[1] || (edge.from == f.router && edge.resolvedFromPortID == AudioRouter.output2) {
                XCTAssertEqual(visual.edgeLevel(edge.id, at: 0.2), 0, "mode \(mode)")
            }
        }
    }

    func testCrossedMatrixTraversesTheInputOfTheAudibleOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-port-cross-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root); var p = f.project
        p.tracks[1].muted = true
        let index = try XCTUnwrap(p.sections[0].graph?.nodes.firstIndex { $0.id == f.router })
        p.sections[0].graph?.nodes[index].content = .router(.init(routes: [
            .init(input: AudioRouter.input2, output: AudioRouter.output1, gain: 0.5),
            .init(input: AudioRouter.input1, output: AudioRouter.output2)
        ]))
        let (_, visual) = try await visualized(p)
        XCTAssertNil(visual.nodes[f.sources[0]])
        XCTAssertGreaterThan(visual.nodes[f.sources[1]]?.level(at: 0.2) ?? 0, 0.1)
        XCTAssertEqual(visual.ports[.init(nodeID: f.router, portID: AudioRouter.output1)]?.level(at: 0.2) ?? 0,
                       (visual.nodes[f.sources[1]]?.level(at: 0.2) ?? 1)*0.5, accuracy: 0.000001)
    }

    func testFanOutAndSidechainUseTheirOwnEdgeGainAndSectionGainOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-port-gain-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root); var p = f.project, g = try XCTUnwrap(p.sections[0].graph)
        let comp = MusicCircle(name: "사이드체인", content: .effect(Effect(.compressor, amount: 0.7)))
        g.nodes.append(comp); g.edges.removeAll { $0.to == f.outputs[0] }
        try SectionGraphEditing.connect(from: f.router, to: comp.id, fromPortID: AudioRouter.output1, in: &g)
        g.edges[g.edges.count-1].gain = 0.5
        try SectionGraphEditing.connect(from: f.router, to: comp.id, fromPortID: AudioRouter.output2, toPortID: CirclePort.sidechainInput, in: &g)
        g.edges[g.edges.count-1].gain = 0.25
        try SectionGraphEditing.connect(from: comp.id, to: f.outputs[0], in: &g)
        p.sections[0].graph = g; p.arrangements[0].uses[0].gain = 0.5
        let (rendered, visual) = try await visualized(p), analysis = try XCTUnwrap(rendered.visualization)
        for edge in g.edges where edge.from == f.router {
            let port = try XCTUnwrap(visual.ports[.init(nodeID: f.router, portID: edge.resolvedFromPortID)])
            let expected = port.level(at: 0.2)*edge.gain
            XCTAssertEqual(visual.edgeLevel(edge.id, at: 0.2), expected, accuracy: 0.000001)
            let id = CircleConnectionID(edgeID: edge.id,
                from: .music(arrangementID: p.active.id, useID: p.active.uses[0].id, nodeID: edge.from),
                to: .music(arrangementID: p.active.id, useID: p.active.uses[0].id, nodeID: edge.to))
            XCTAssertEqual(analysis.edgeLevel(id, at: 0.2, plan: rendered.plan, tail: 0), expected*0.5, accuracy: 0.000001)
            XCTAssertEqual(analysis.edgeLevel(id, at: rendered.plan.duration, plan: rendered.plan, tail: 0), 0)
        }
        XCTAssertEqual(visual.edgeLevel("missing", at: 0.2), 0)
    }

    func testEnvelopeMemoryEstimateCoversRetainedPeaksAndGrowsWithOccurrences() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-port-memory-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root), (rendered, visual) = try await visualized(f.project, tail: 0.13)
        let analysis = try XCTUnwrap(rendered.visualization)
        let arrays = Array(visual.nodes.values) + Array(visual.ports.values) + Array(analysis.signals.values) + [try XCTUnwrap(visual.section)]
        let bytes = arrays.reduce(0) { $0 + $1.peaks.count*MemoryLayout<Float>.stride }
        let estimated = PlaybackAnalysis.estimatedBytes(plan: rendered.plan, signal: f.project.signal, tail: 0.13)
        XCTAssertGreaterThanOrEqual(estimated, Double(bytes))
        var p = f.project; p.arrangements[0].uses[0].repeatCount = 4
        let repeated = try ArrangementCompiler.compile(p)
        XCTAssertGreaterThan(PlaybackAnalysis.estimatedBytes(plan: repeated, signal: p.signal, tail: 0.13), estimated*3)
    }

    func testFoldedGroupAndRepeatedSectionUseLogicalCableWithLocalTime() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-port-group-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root); var p = f.project, graph = try XCTUnwrap(p.sections[0].graph)
        let edge = try XCTUnwrap(graph.edges.first { $0.from == f.router && $0.resolvedFromPortID == AudioRouter.output1 })
        var group = CanvasGroup(name: "독립 출력 묶음", members: [f.router]); group.collapsed = true
        graph.layout.groups.append(group); p.sections[0].graph = graph
        p.arrangements[0].uses[0].repeatCount = 2
        p.enableAlbum()
        let scene = try HierarchySceneBuilder.build(p)
        let shown = try XCTUnwrap(scene.edges.first { $0.connectionID?.edgeID == edge.id })
        let id = try XCTUnwrap(shown.connectionID)
        XCTAssertNotEqual(shown.from, id.from)
        let (rendered, visual) = try await visualized(p), analysis = try XCTUnwrap(rendered.visualization)
        let expected = visual.edgeLevel(edge.id, at: 0.2)
        XCTAssertGreaterThan(expected, 0.1)
        XCTAssertEqual(rendered.plan.occurrences.count, 2)
        XCTAssertEqual(analysis.edgeLevel(id, at: rendered.plan.occurrences[1].start+0.2, plan: rendered.plan, tail: 0), expected)
        XCTAssertEqual(analysis.edgeLevel(id, at: .nan, plan: rendered.plan, tail: 0), 0)
        var stale = id; stale.from = .music(arrangementID: p.active.id, useID: p.active.uses[0].id, nodeID: "removed")
        XCTAssertEqual(analysis.edgeLevel(stale, at: 0.2, plan: rendered.plan, tail: 0), 0)
    }
}

extension PlaybackAnalysisTests {
    func testMIDIAndEffectTailCableLevelsFollowActualScheduledSignal() async throws {
        let p = try fixture(), plan = try AlbumCompiler.executionPlan(p)
        let rendered = try await ArrangementRenderer.render(project: p, root: nil, plan: plan,
            tailSeconds: 0.5, includeStems: false, includeVisualization: true)
        let visual = try XCTUnwrap(rendered.visualization?.occurrences[plan.occurrences[0].id])
        let signal = try XCTUnwrap(plan.occurrences[0].signalPlan)
        XCTAssertTrue(signal.connections.contains { $0.signal == .midi && !(signal.midi[$0.from.nodeID] ?? []).isEmpty })
        for edge in signal.connections where edge.signal == .midi {
            XCTAssertEqual(visual.edgeLevel(edge.id, at: 0.5), 0)
            let expected = (signal.midi[edge.from.nodeID] ?? []).isEmpty ? 0 : 100.0/127
            XCTAssertEqual(visual.edgeLevel(edge.id, at: 0.9), expected, accuracy: 0.000001)
            XCTAssertEqual(visual.edgeLevel(edge.id, at: 1.1), 0)
        }
        let fx = try XCTUnwrap(signal.orderedNodes.first { if case .effect = $0.content { return true }; return false })
        let edge = try XCTUnwrap(signal.connections.first { $0.from.nodeID == fx.id })
        XCTAssertGreaterThan(visual.edgeLevel(edge.id, at: 1.12), 0.001)
    }
}
