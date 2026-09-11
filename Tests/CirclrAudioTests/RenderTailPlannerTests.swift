import XCTest
@testable import CirclrCore
@testable import CirclrAudio

final class RenderTailPlannerTests: XCTestCase {
    private func fixture(_ root: URL) throws -> Project {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var pcm = PCM(frames: 48_000)
        for i in 43_200..<43_680 { pcm.left[i] = 0.2; pcm.right[i] = 0.2 }
        let url = root.appendingPathComponent("impulse.wav"); try pcm.writeWAV(url)
        var p = Project(); _ = p.addTrack(name: "지연"); p.global.tempo = 240
        _ = p.addSection(name: "한 초", at: Point(), bars: 1)
        let asset = Asset(name: "impulse", path: url.path, duration: 1, sampleRate: PCM.rate)
        p.assets = [asset]; p.sections[0].lanes[0].audio = [AudioClip(assetID: asset.id, duration: 1)]
        return try SectionGraphMigration.migrate(p)
    }
    private func plan(_ p: Project) throws -> (SectionSignalPlan, MusicClock) {
        let use = p.active.uses[0], (s, c, k) = try ArrangementCompiler.context(project: p, use: use)
        return (try XCTUnwrap(SectionGraphCompiler.compile(project: p, section: s, use: use, context: c, clock: k)), k)
    }
    private func addEffect(_ effect: Effect, to p: inout Project, trackIndex: Int = 0) throws {
        var graph = try XCTUnwrap(p.sections[0].graph)
        let output = try XCTUnwrap(graph.nodes.first { if case .output(let id) = $0.content { return id == p.tracks[trackIndex].id }; return false })
        try SectionGraphEditing.insertEffectBeforeOutput(MusicCircle(name: "잔향", content: .effect(effect)), before: output.id, in: &graph)
        p.sections[0].graph = graph
    }
    private func temporary(_ label: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("circlr-tail-\(label)-\(newID())") }

    func testAutomaticDelayKeepsPreviouslyLostEchoAndBouncedAudioAfterSaveReopen() async throws {
        let root = temporary("delay"); defer { try? FileManager.default.removeItem(at: root) }
        var p = try fixture(root)
        try addEffect(Effect(.delay, amount: 1, secondary: 0.8), to: &p)
        let before = p, (graph, clock) = try plan(p), track = p.tracks[0].id
        let tail = try RenderTailPlanner.section(graph, project: p, clock: clock, trackID: track)
        XCTAssertGreaterThan(tail.effectiveSeconds, 40); XCTAssertLessThan(tail.effectiveSeconds, 45)
        XCTAssertTrue(tail.notices.isEmpty); XCTAssertNil(tail.requestedSeconds)
        let shortBuffers = try await SectionGraphRenderer.render(graph, project: p, root: nil, clock: clock, tail: 2, applyOutputGain: false)
        let fullBuffers = try await SectionGraphRenderer.render(graph, project: p, root: nil, clock: clock, tail: tail.effectiveSeconds, applyOutputGain: false)
        let short = try XCTUnwrap(shortBuffers[track]), full = try XCTUnwrap(fullBuffers[track])
        XCTAssertEqual(short.left, Array(full.left.prefix(short.count)))
        XCTAssertGreaterThan(full.slice(short.count..<min(full.count, 6 * 48_000)).peak, 0.1)
        XCTAssertLessThan(full.slice(max(0, full.count - 48_000)..<full.count).peak, 0.0001)
        let execution = try ArrangementCompiler.compile(p)
        let reference = try await ArrangementRenderer.render(project: p, root: nil, plan: execution, includeStems: false)
        XCTAssertEqual(p, before)
        let url = root.appendingPathComponent("bounce.wav"); try full.writeWAV(url)
        _ = try BounceEditing.apply(asset: Asset(name: "긴 잔향", path: url.path, duration: full.duration, sampleRate: PCM.rate),
                                    trackID: track, useID: p.active.uses[0].id, bodySeconds: clock.seconds, tailSeconds: tail.effectiveSeconds, in: &p)
        let saved = root.appendingPathComponent("tail.circlr")
        _ = try ProjectStore.save(p, to: saved, mediaRoot: nil)
        let loaded = try ProjectStore.load(saved), restoredPlan = try ArrangementCompiler.compile(loaded.project)
        let restored = try await ArrangementRenderer.render(project: loaded.project, root: loaded.root, plan: restoredPlan, includeStems: false)
        XCTAssertEqual(restoredPlan.duration, execution.duration)
        XCTAssertEqual(restoredPlan.occurrences.map(\.start), execution.occurrences.map(\.start))
        XCTAssertEqual(restored.mix.count, reference.mix.count)
        XCTAssertGreaterThan(restored.mix.slice(3 * 48_000..<6 * 48_000).peak, 0.01)
        for (actual, expected) in [(restored.mix.left, reference.mix.left), (restored.mix.right, reference.mix.right)] {
            XCTAssertLessThanOrEqual(zip(actual, expected).map { abs($0 - $1) }.max() ?? 1, 1.0 / 8_388_608)
        }
    }

    func testSerialEffectsAddParallelRouterBusesStayIndependentAndGlobalEffectAdds() throws {
        let root = temporary("router"); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try AudioRouterAudioTests().fixture(root); var p = fixture.project
        try addEffect(Effect(.delay, amount: 1, secondary: 0.8), to: &p, trackIndex: 0)
        let (firstGraph, clock) = try plan(p)
        let first = try RenderTailPlanner.section(firstGraph, project: p, clock: clock, trackID: p.tracks[0].id)
        XCTAssertEqual(try RenderTailPlanner.section(firstGraph, project: p, clock: clock, trackID: p.tracks[1].id).effectiveSeconds, 2)
        try addEffect(Effect(.delay, amount: 1, secondary: 0.8), to: &p, trackIndex: 0)
        let (serial, _) = try plan(p)
        XCTAssertEqual(try RenderTailPlanner.section(serial, project: p, clock: clock, trackID: p.tracks[0].id).estimatedSeconds, first.estimatedSeconds * 2)
        // The full arrangement adds a downstream global effect without moving occurrences.
        let master = try XCTUnwrap(p.signal.nodes.first { $0.kind == .master })
        let effect = SignalNode(kind: .effect, name: "전역 지연")
        var globalEffect = effect; globalEffect.effect = Effect(.delay, amount: 1, secondary: 0.8)
        for index in p.signal.edges.indices where p.signal.edges[index].to == master.id { p.signal.edges[index].to = globalEffect.id }
        p.signal.nodes.append(globalEffect); p.signal.edges.append(SignalEdge(from: globalEffect.id, to: master.id))
        let arrangement = try RenderTailPlanner.arrangement(project: p, plan: ArrangementCompiler.compile(p))
        XCTAssertEqual(arrangement.estimatedSeconds, first.estimatedSeconds * 3)
        XCTAssertEqual(arrangement.effectiveSeconds, 120); XCTAssertFalse(arrangement.notices.isEmpty)
        var editedPlan = try ArrangementCompiler.compile(p)
        // Renderer also supports already-built plans carrying occurrence-level effects.
        editedPlan.occurrences[0].use.effects = [Effect(.delay, amount: 1, secondary: 0.8)]
        XCTAssertEqual(try RenderTailPlanner.arrangement(project: p, plan: editedPlan).estimatedSeconds, first.estimatedSeconds * 4)
    }

    func testReverbVersionsGetEnoughDecayAndUnknownPluginReportsFallback() async throws {
        let root = temporary("reverb"); defer { try? FileManager.default.removeItem(at: root) }
        let base = try fixture(root)
        for version in [1, 2] {
            var p = base, reverb = Effect(.reverb, amount: 1, secondary: 0.8); reverb.renderVersion = version
            try addEffect(reverb, to: &p)
            let (graph, clock) = try plan(p), tail = try RenderTailPlanner.section(graph, project: p, clock: clock)
            let buffers = try await SectionGraphRenderer.render(graph, project: p, root: nil, clock: clock, tail: tail.effectiveSeconds)
            let pcm = try XCTUnwrap(buffers[p.tracks[0].id])
            XCTAssertLessThan(pcm.slice(max(0, pcm.count - 24_000)..<pcm.count).peak, 0.0001)
            if version == 2 { XCTAssertGreaterThan(tail.effectiveSeconds, 4) }
        }
        var unknown = base; try addEffect(Effect(.audioUnit), to: &unknown)
        let (graph, clock) = try plan(unknown), tail = try RenderTailPlanner.section(graph, project: unknown, clock: clock)
        XCTAssertGreaterThanOrEqual(tail.effectiveSeconds, 10)
        XCTAssertTrue(tail.notices.contains { $0.contains("Audio Unit") })
    }

    func testManualCropAndInvalidLengthsRejectBeforeAllocation() async throws {
        let root = temporary("limits"); defer { try? FileManager.default.removeItem(at: root) }
        var p = try fixture(root); try addEffect(Effect(.delay, amount: 1, secondary: 0.8), to: &p)
        let (graph, clock) = try plan(p), execution = try ArrangementCompiler.compile(p)
        for value in [Double.nan, .infinity, -.infinity, -1, 120.1] {
            XCTAssertThrowsError(try RenderTailPlanner.section(graph, project: p, clock: clock, requestedSeconds: value))
            XCTAssertThrowsError(try RenderTailPlanner.arrangement(project: p, plan: execution, requestedSeconds: value))
            do { _ = try await SectionGraphRenderer.render(graph, project: p, root: nil, clock: clock, tail: value); XCTFail("Invalid section tail accepted") } catch {}
            XCTAssertThrowsError(try ProductionInstrument.synth([], patch: SynthPatch(), clock: clock, tail: value))
        }
        let manual = try RenderTailPlanner.section(graph, project: p, clock: clock, requestedSeconds: 0)
        XCTAssertEqual(manual.effectiveSeconds, 0); XCTAssertFalse(manual.notices.isEmpty)
        XCTAssertEqual(try RenderTailPlanner.section(graph, project: p, clock: clock, requestedSeconds: 120).effectiveSeconds, 120)
        let longClock = try MusicClock(bars: 4096, context: MusicContext())
        XCTAssertThrowsError(try RenderTailPlanner.section(graph, project: p, clock: longClock))
        var oversized = execution; oversized.duration = 1_000_000
        for stems in [false, true] {
            for visual in [false, true] {
                XCTAssertThrowsError(try RenderTailPlanner.arrangement(project: p, plan: oversized,
                    includeStems: stems, includeVisualization: visual))
            }
        }
    }

    func testPreservedClipUsesCurrentTrimTempoAndRepeatAndRejectsOverCapAutomatically() throws {
        let root = temporary("clip"); defer { try? FileManager.default.removeItem(at: root) }
        var p = try fixture(root)
        p.assets[0].duration = 300
        p.sections[0].lanes[0].audio[0].duration = 8
        p.sections[0].lanes[0].audio[0].preservesTail = true
        var (graph, clock) = try plan(p)
        XCTAssertEqual(try RenderTailPlanner.section(graph, project: p, clock: clock).effectiveSeconds, 7)
        p.sections[0].lanes[0].audio[0].sourceStart = 5
        p.sections[0].lanes[0].audio[0].duration = 3
        p.sections[0].lanes[0].audio[0].renderWindow = AudioRenderWindow(sourceStart: 0, duration: 8, cycleBeat: 0, automaticEdges: false, envelopes: [])
        (graph, clock) = try plan(p)
        XCTAssertEqual(try RenderTailPlanner.section(graph, project: p, clock: clock).effectiveSeconds, 2)
        p.sections[0].lanes[0].audio[0].renderWindow = nil
        p.sections[0].lanes[0].audio[0].sourceStart = 0
        p.sections[0].lanes[0].audio[0].duration = 10
        p.sections[0].lanes[0].audio[0].followsTempo = true
        p.sections[0].lanes[0].audio[0].sourceBPM = 120
        (graph, clock) = try plan(p)
        XCTAssertEqual(try RenderTailPlanner.section(graph, project: p, clock: clock).effectiveSeconds, 4)
        var repeated = p
        repeated.global.tempo = 60
        repeated.sections[0].lanes[0].audio[0].followsTempo = false
        repeated.sections[0].lanes[0].audio[0].duration = 3.5
        let audioIndex = try XCTUnwrap(repeated.sections[0].graph?.nodes.firstIndex { if case .audio = $0.content { return true }; return false })
        repeated.sections[0].graph!.nodes[audioIndex].repeatCount = 2
        let (repeatedGraph, repeatedClock) = try plan(repeated)
        XCTAssertEqual(repeatedClock.seconds, 4)
        XCTAssertEqual(try RenderTailPlanner.section(repeatedGraph, project: repeated, clock: repeatedClock).effectiveSeconds, 3)
        p.sections[0].lanes[0].audio[0].followsTempo = false
        p.sections[0].lanes[0].audio[0].duration = 123
        (graph, clock) = try plan(p)
        XCTAssertThrowsError(try RenderTailPlanner.section(graph, project: p, clock: clock))
        let crop = try RenderTailPlanner.section(graph, project: p, clock: clock, requestedSeconds: 120)
        XCTAssertEqual(crop.effectiveSeconds, 120); XCTAssertFalse(crop.notices.isEmpty)
    }
    func testSynthReleaseIsEstimatedAndExplicitLongTailIsAccepted() throws {
        let root = temporary("synth"); defer { try? FileManager.default.removeItem(at: root) }
        var p = try fixture(root)
        p.tracks[0].instrument = .synthesizer(.pluck)
        p.tracks[0].instrument.synth?.release = 6
        p.sections[0].lanes[0].notes = [Note(beat: 3, length: 1, pitch: 60)]
        let (graph, clock) = try plan(p)
        XCTAssertEqual(try RenderTailPlanner.section(graph, project: p, clock: clock).effectiveSeconds, 6)
        XCTAssertEqual(try ProductionInstrument.frameCount(clock: clock, tail: 120), 121 * 48_000)
    }
    func testUnmappedSamplerZoneAndOutOfBodyNotesDoNotExtendSilence() async throws {
        let root = temporary("zones"); defer { try? FileManager.default.removeItem(at: root) }
        var p = try fixture(root)
        let asset = p.assets[0]
        p.assets[0].duration = 300
        p.tracks[0].instrument = .sampler(assetID: asset.id)
        p.tracks[0].instrument.sample?.zones = [SampleZone(60, assetID: asset.id)]
        p.sections[0].lanes[0].audio = []
        let audioIDs = Set(p.sections[0].graph!.nodes.filter { if case .audio = $0.content { return true }; return false }.map(\.id))
        p.sections[0].graph!.nodes.removeAll { audioIDs.contains($0.id) }
        p.sections[0].graph!.edges.removeAll { audioIDs.contains($0.from) || audioIDs.contains($0.to) }
        p.sections[0].lanes[0].notes = [Note(beat: 0, pitch: 0), Note(beat: 4, pitch: 60)]
        let (graph, clock) = try plan(p)
        let tail = try RenderTailPlanner.section(graph, project: p, clock: clock)
        XCTAssertEqual(tail.effectiveSeconds, 2); XCTAssertTrue(tail.notices.isEmpty)
        let rendered = try await SectionGraphRenderer.render(graph, project: p, root: nil, clock: clock, tail: tail.effectiveSeconds)
        XCTAssertEqual(rendered[p.tracks[0].id]?.peak, 0)
    }
}
