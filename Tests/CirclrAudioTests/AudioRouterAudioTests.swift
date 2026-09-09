import XCTest
import CirclrCore
@testable import CirclrAudio

final class AudioRouterAudioTests: XCTestCase {
    struct Fixture {
        var project: Project
        var sources: [ID]
        var outputs: [ID]
        var router: ID
    }
    func fixture(_ root: URL) throws -> Fixture {
        var p = Project(); _ = p.addTrack(name: "베이스"); _ = p.addTrack(name: "패드")
        p.global.tempo = 240; _ = p.addSection(name: "두 bus", at: Point(), bars: 1)
        for n in 0..<2 {
            var pcm = PCM(frames: 48_000)
            for i in 0..<pcm.count {
                pcm.left[i] = Float(sin(Double(i) * 2 * .pi * Double(n == 0 ? 220 : 550) / PCM.rate)) * (n == 0 ? 0.2 : 0.1)
                pcm.right[i] = Float(cos(Double(i) * 2 * .pi * Double(n == 0 ? 330 : 770) / PCM.rate)) * (n == 0 ? 0.1 : 0.2)
            }
            let url = root.appendingPathComponent("source-\(n).wav"); try pcm.writeWAV(url)
            let asset = Asset(name: "독립 입력 \(n)", path: url.path, duration: 1, sampleRate: PCM.rate)
            p.assets.append(asset); var clip = AudioClip(assetID: asset.id, duration: 1); clip.preservesTail = true
            p.sections[0].lanes[n].audio = [clip]
        }
        p = try SectionGraphMigration.migrate(p)
        var g = try XCTUnwrap(p.sections[0].graph)
        let sources = g.nodes.filter { if case .audio = $0.content { return true }; return false }.map(\.id)
        let outputs = g.nodes.filter { if case .output = $0.content { return true }; return false }.map(\.id)
        g.edges.removeAll { outputs.contains($0.to) }
        let router = MusicCircle(name: "두 스테레오 bus", content: .router(AudioRouter()))
        g.nodes.append(router)
        for n in 0..<2 {
            try SectionGraphEditing.connect(from: sources[n], to: router.id, toPortID: AudioRouter.inputs[n], in: &g)
            try SectionGraphEditing.connect(from: router.id, to: outputs[n], fromPortID: AudioRouter.outputs[n], in: &g)
        }
        p.sections[0].graph = g; try ProjectStore.validateStructure(p)
        return .init(project: p, sources: sources, outputs: outputs, router: router.id)
    }
    func render(_ p: Project, root: URL? = nil, observe: ((ID, PCM) -> Void)? = nil,
                observeOutput: ((MusicBusEndpoint, PCM) -> Void)? = nil) async throws -> [ID: PCM] {
        let u = p.active.uses[0], (s, c, k) = try ArrangementCompiler.context(project: p, use: u)
        let plan = try XCTUnwrap(SectionGraphCompiler.compile(project: p, section: s, use: u, context: c, clock: k))
        return try await SectionGraphRenderer.render(plan, project: p, root: root, clock: k, tail: 0, observe: observe, observeOutput: observeOutput)
    }
    func direct(_ f: Fixture) throws -> Project {
        var p = f.project, g = try XCTUnwrap(p.sections[0].graph)
        g.edges.removeAll { $0.from == f.router || $0.to == f.router }
        for n in 0..<2 { try SectionGraphEditing.connect(from: f.sources[n], to: f.outputs[n], in: &g) }
        p.sections[0].graph = g; return p
    }
    func assertPCM(_ a: PCM?, _ b: PCM?, file: StaticString = #filePath, line: UInt = #line) throws {
        let a = try XCTUnwrap(a, file: file, line: line), b = try XCTUnwrap(b, file: file, line: line)
        XCTAssertEqual(a.left, b.left, file: file, line: line); XCTAssertEqual(a.right, b.right, file: file, line: line)
    }

    func testIndependentStereoBusesAndVisualizerNeverMixRouting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-router-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root), p = f.project, dry = try await render(direct(f))
        let wet = try await render(p)
        var meter: PCM?
        let observed = try await render(p, observe: { if $0 == f.router { meter = $1 } })
        for track in p.tracks { try assertPCM(wet[track.id], dry[track.id]); try assertPCM(observed[track.id], dry[track.id]) }
        var sum = try XCTUnwrap(dry[p.tracks[0].id]); sum.mix(try XCTUnwrap(dry[p.tracks[1].id]))
        try assertPCM(meter, sum)
        XCTAssertNotEqual(wet[p.tracks[0].id]?.left, wet[p.tracks[1].id]?.left)
        XCTAssertNotEqual(wet[p.tracks[0].id]?.left, wet[p.tracks[0].id]?.right)
        // The structural assessment uses the same independent buses proven by PCM above.
        for output in 0..<2 {
            for source in 0..<2 {
                let assessment = BounceAssessment.make(trackID: p.tracks[output].id, useID: p.active.uses[0].id,
                    selectedNodeID: f.sources[source], in: p)
                XCTAssertNil(assessment.issue)
                XCTAssertEqual(assessment.target?.outputNodeID, f.outputs[output])
                XCTAssertEqual(assessment.membership, source == output ? .mainPath : .outsidePath)
            }
        }
    }

    func testMatrixCrossesBusesAndFanInAppliesEachEdgeGainOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-router-matrix-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root); var p = f.project, g = try XCTUnwrap(p.sections[0].graph)
        let dry = try await render(direct(f)), a = try XCTUnwrap(dry[p.tracks[0].id]), b = try XCTUnwrap(dry[p.tracks[1].id])
        let i = try XCTUnwrap(g.nodes.firstIndex { $0.id == f.router })
        g.nodes[i].content = .router(AudioRouter(routes: [
            .init(input: AudioRouter.input1, output: AudioRouter.output2, gain: 0.5),
            .init(input: AudioRouter.input2, output: AudioRouter.output1, gain: 0.25)
        ]))
        p.sections[0].graph = g; let crossed = try await render(p)
        var halfA = a, quarterB = b; halfA.multiply(0.5); quarterB.multiply(0.25)
        try assertPCM(crossed[p.tracks[0].id], quarterB); try assertPCM(crossed[p.tracks[1].id], halfA)
        // Crossing the router matrix reverses membership along with the rendered PCM.
        for output in 0..<2 {
            for source in 0..<2 {
                let assessment = BounceAssessment.make(trackID: p.tracks[output].id, useID: p.active.uses[0].id,
                    selectedNodeID: f.sources[source], in: p)
                XCTAssertNil(assessment.issue)
                XCTAssertEqual(assessment.target?.outputNodeID, f.outputs[output])
                XCTAssertEqual(assessment.membership, source != output ? .mainPath : .outsidePath)
            }
        }
        // Fan-in belongs only to input 1, and input 2 remains independent.
        g.nodes[i].content = .router(AudioRouter())
        try SectionGraphEditing.connect(from: f.sources[1], to: f.router, toPortID: AudioRouter.input1, in: &g)
        g.edges[g.edges.count - 1].gain = 0.5
        p.sections[0].graph = g; let merged = try await render(p)
        var expected = a; expected.mix(b, gain: 0.5)
        try assertPCM(merged[p.tracks[0].id], expected); try assertPCM(merged[p.tracks[1].id], b)
        // Both inputs may explicitly feed both outputs through a matrix.
        g.nodes[i].content = .router(AudioRouter(routes: AudioRouter.inputs.flatMap { input in
            AudioRouter.outputs.map { .init(input: input, output: $0, gain: 0.25) }
        }))
        p.sections[0].graph = g; let matrix = try await render(p)
        var matrixExpected = PCM(frames: a.count); matrixExpected.mix(expected, gain: 0.25); matrixExpected.mix(b, gain: 0.25)
        for track in p.tracks { try assertPCM(matrix[track.id], matrixExpected) }
    }

    func testFanOutKeepsSidechainAndOtherOutputAliveUntilLastConsumer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-router-sidechain-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root); var p = f.project, g = try XCTUnwrap(p.sections[0].graph)
        let dry = try await render(p), a = try XCTUnwrap(dry[p.tracks[0].id]), b = try XCTUnwrap(dry[p.tracks[1].id])
        let fx = Effect(.compressor, amount: 0.7, secondary: 0.4)
        let comp = MusicCircle(name: "패드로 베이스 duck", content: .effect(fx))
        g.nodes.append(comp); g.edges.removeAll { $0.to == f.outputs[0] }
        try SectionGraphEditing.connect(from: f.router, to: comp.id, fromPortID: AudioRouter.output1, in: &g)
        try SectionGraphEditing.connect(from: f.router, to: comp.id, fromPortID: AudioRouter.output2, toPortID: CirclePort.sidechainInput, in: &g)
        try SectionGraphEditing.connect(from: comp.id, to: f.outputs[0], in: &g)
        p.sections[0].graph = g; let actual = try await render(p)
        let expected = try NativeDSP.process(a, effect: fx, sidechain: b)
        try assertPCM(actual[p.tracks[0].id], expected); try assertPCM(actual[p.tracks[1].id], b)
        XCTAssertNotEqual(expected.left, a.left)
    }

    func testGainAutomationMuteAndUnconnectedInputApplyPerBus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-router-controls-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root); var p = f.project, g = try XCTUnwrap(p.sections[0].graph)
        let dry = try await render(p), i = try XCTUnwrap(g.nodes.firstIndex { $0.id == f.router })
        g.nodes[i].gain = 0.5
        g.nodes[i].automation = [.init(parameter: .gain, points: [.init(beat: 0, value: 0.5)])]
        p.sections[0].graph = g; let gained = try await render(p)
        for track in p.tracks { var expected = try XCTUnwrap(dry[track.id]); expected.multiply(0.25); try assertPCM(gained[track.id], expected) }
        g.nodes[i].muted = true; p.sections[0].graph = g; let muted = try await render(p)
        for track in p.tracks { XCTAssertEqual(muted[track.id]?.peak, 0) }
        g.nodes[i].muted = false; g.edges.removeAll { $0.to == f.router && $0.resolvedToPortID == AudioRouter.input2 }
        p.sections[0].graph = g; let missing = try await render(p)
        try assertPCM(missing[p.tracks[0].id], gained[p.tracks[0].id]); XCTAssertEqual(missing[p.tracks[1].id]?.peak, 0)
    }

    func testTwoTrackBounceSaveReopenAndRestorePreservePortIDsAndPCM() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-router-bounce-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root); var p = f.project
        let dry = try await render(p), useID = p.active.uses[0].id
        var bounced: [ID] = []
        for track in p.tracks {
            let pcm = try XCTUnwrap(dry[track.id]), url = root.appendingPathComponent("\(track.id).wav")
            try pcm.writeWAV(url)
            bounced.append(try BounceEditing.apply(asset: Asset(name: track.name, path: url.path, duration: 1, sampleRate: PCM.rate),
                trackID: track.id, useID: useID, bodySeconds: 1, tailSeconds: 0, in: &p))
        }
        let bouncedPCM = try await render(p)
        for track in p.tracks {
            for pair in [(dry[track.id]!.left, bouncedPCM[track.id]!.left), (dry[track.id]!.right, bouncedPCM[track.id]!.right)] {
                XCTAssertLessThanOrEqual(zip(pair.0, pair.1).map { abs($0 - $1) }.max() ?? 1, 1 / 8_388_608)
            }
        }
        let package = root.appendingPathComponent("routing.circlr")
        let saved = try ProjectStore.save(p, to: package, mediaRoot: nil), loaded = try ProjectStore.load(package)
        XCTAssertEqual(saved, loaded.project); p = loaded.project
        for asset in f.project.assets { try FileManager.default.removeItem(atPath: asset.path) }
        for id in bounced { try BounceEditing.restore(nodeID: id, useID: useID, in: &p) }
        let restoredGraph = try XCTUnwrap(SectionGraphEditing.effective(section: p.sections[0], use: p.active.uses[0]))
        for edge in f.project.sections[0].graph!.edges where edge.from == f.router { XCTAssertTrue(restoredGraph.edges.contains(edge)) }
        let restored = try await render(p, root: loaded.root)
        for track in p.tracks { try assertPCM(restored[track.id], dry[track.id]) }
    }

    func testMIDIInputMergesPerformancesBeforeInstrumentAndBusRouting() async throws {
        var p = Project(); let track = p.addTrack(name: "합주 신스")
        p.tracks[0].instrument = .synthesizer(.pluck); p.global.tempo = 240
        _ = p.addSection(name: "MIDI 합류", at: Point(), bars: 1)
        p.sections[0].lanes[0].notes = [Note(beat: 0, length: 1, pitch: 60, velocity: 90)]
        var second = Lane(trackID: track); second.notes = [Note(beat: 1, length: 1, pitch: 67, velocity: 80)]
        p.sections[0].lanes.append(second); p = try SectionGraphMigration.migrate(p)
        var g = try XCTUnwrap(p.sections[0].graph)
        let instrument = g.nodes.first { if case .instrument = $0.content { return true }; return false }!
        let output = g.nodes.first { if case .output = $0.content { return true }; return false }!
        let router = MusicCircle(name: "MIDI 연주의 오디오", content: .router(AudioRouter()))
        g.nodes.append(router); g.edges.removeAll { $0.to == output.id }
        try SectionGraphEditing.connect(from: instrument.id, to: router.id, toPortID: AudioRouter.input2, in: &g)
        try SectionGraphEditing.connect(from: router.id, to: output.id, fromPortID: AudioRouter.output2, in: &g)
        // Explicit and legacy MIDI connections share the same merge policy.
        for i in g.edges.indices where g.edges[i].signal == .midi {
            g.edges[i].fromPortID = CirclePort.midiOutput; g.edges[i].toPortID = CirclePort.midiInput
        }
        p.sections[0].graph = g
        let u = p.active.uses[0], (s, c, k) = try ArrangementCompiler.context(project: p, use: u)
        let plan = try XCTUnwrap(SectionGraphCompiler.compile(project: p, section: s, use: u, context: c, clock: k))
        let notes = plan.connections.filter { $0.to.nodeID == instrument.id && $0.signal == .midi }.flatMap { plan.midi[$0.from.nodeID] ?? [] }
        XCTAssertEqual(notes.count, 2); XCTAssertEqual(Set(notes.map(\.pitch)), [60, 67])
        let expected = try await ProductionInstrument.render(notes, instrument: p.tracks[0].instrument, project: p, root: nil, clock: k, tail: 0)
        let actual = try await render(p); try assertPCM(actual[track], expected)
        XCTAssertGreaterThan(expected.peak, 0.01)
    }

    func testThirteenBranchesUseOneBusWithoutLeakingTheSecond() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-router-fanout-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root); var p = f.project, g = try XCTUnwrap(p.sections[0].graph)
        let dry = try await render(p), a = try XCTUnwrap(dry[p.tracks[0].id])
        g.edges.removeAll { $0.to == f.outputs[0] }
        for n in 0..<13 {
            let effect = MusicCircle(name: "분기 \(n)", content: .effect(Effect(.gain, amount: 0.0625)))
            g.nodes.append(effect)
            try SectionGraphEditing.connect(from: f.router, to: effect.id, fromPortID: AudioRouter.output1, in: &g)
            try SectionGraphEditing.connect(from: effect.id, to: f.outputs[0], in: &g)
        }
        p.sections[0].graph = g
        let actual = try await render(p); var expected = PCM(frames: a.count)
        for _ in 0..<13 { expected.mix(a, gain: 0.0625) }
        try assertPCM(actual[p.tracks[0].id], expected)
        try assertPCM(actual[p.tracks[1].id], dry[p.tracks[1].id])
    }

    func testLongTwoBusChainReleasesBuffersAndKeepsPCM() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-router-chain-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let f = try fixture(root); var p = f.project, g = try XCTUnwrap(p.sections[0].graph)
        let dry = try await render(p); g.edges.removeAll { f.outputs.contains($0.to) }
        var previous = f.router
        for _ in 0..<80 {
            let router = MusicCircle(name: "두 bus 유지", content: .router(AudioRouter())); g.nodes.append(router)
            for n in 0..<2 { try SectionGraphEditing.connect(from: previous, to: router.id, fromPortID: AudioRouter.outputs[n], toPortID: AudioRouter.inputs[n], in: &g) }
            previous = router.id
        }
        for n in 0..<2 { try SectionGraphEditing.connect(from: previous, to: f.outputs[n], fromPortID: AudioRouter.outputs[n], in: &g) }
        p.sections[0].graph = g
        let u = p.active.uses[0], (s, c, k) = try ArrangementCompiler.context(project: p, use: u)
        let plan = try XCTUnwrap(SectionGraphCompiler.compile(project: p, section: s, use: u, context: c, clock: k))
        XCTAssertLessThan(SectionGraphRenderer.workingBufferCount(plan), 16)
        let actual = try await render(p)
        for track in p.tracks { try assertPCM(actual[track.id], dry[track.id]) }
    }
}
