import XCTest
import CirclrCore
@testable import CirclrAudio

final class PlaybackAnalysisTests: XCTestCase {
    func fixture() throws -> Project {
        var p = Project(); _ = p.addTrack(name: "신스")
        p.tracks[0].instrument = .synthesizer(.pluck); p.global.tempo = 240
        _ = p.addSection(name: "후렴", at: Point(), bars: 1)
        p.sections[0].lanes[0].notes = [Note(beat: 3.5, length: 0.5, pitch: 66, velocity: 100)]
        p.arrangements[0].uses[0].effects = [Effect(.delay, amount: 0.2, secondary: 0.6)]
        p.enableAlbum(); return try SectionGraphMigration.migrate(p)
    }
    func testEnvelopeDetectsSingleSampleTransientAndLastPartialBucket() {
        var pcm = PCM(frames: 1701); pcm.left[301] = -0.8; pcm.right[1700] = 0.4
        let envelope = PlaybackEnvelope(pcm)
        XCTAssertEqual(envelope.peaks.count, 3)
        XCTAssertEqual(envelope.level(at: 0.005), 0.8, accuracy: 0.000001)
        XCTAssertEqual(envelope.level(at: 0.02), 0)
        XCTAssertEqual(envelope.level(at: 1700/PCM.rate), 0.4, accuracy: 0.000001)
        XCTAssertEqual(envelope.level(at: pcm.duration), 0)
        XCTAssertEqual(envelope.level(at: .nan), 0)
        XCTAssertEqual(PlaybackEnvelope(PCM(frames: 0)).level(at: 0), 0)
    }
    func testMIDIEnvelopeUsesTempoMapAndRealNoteBoundaries() throws {
        let clock = try MusicClock(bars: 2, context: MusicContext(), tempoChanges: [TempoChange(beat: 4, bpm: 60)])
        let envelope = PlaybackEnvelope(notes: [Note(beat: 4, length: 1, pitch: 60, velocity: 64)], clock: clock)
        XCTAssertEqual(envelope.level(at: 1.9), 0)
        XCTAssertEqual(envelope.level(at: 2.2), 64.0/127, accuracy: 0.000001)
        XCTAssertEqual(envelope.level(at: 3.01), 0)
    }
    func testVisualizationPreservesPCMAndIncludesEffectTail() async throws {
        let p = try fixture(), plan = try AlbumCompiler.executionPlan(p)
        let plain = try await ArrangementRenderer.render(project: p, root: nil, plan: plan, tailSeconds: 0.5, includeStems: false)
        let observed = try await ArrangementRenderer.render(project: p, root: nil, plan: plan, tailSeconds: 0.5, includeStems: false, includeVisualization: true)
        XCTAssertEqual(plain.mix.left, observed.mix.left); XCTAssertEqual(plain.mix.right, observed.mix.right)
        XCTAssertNil(plain.visualization)
        let visual = try XCTUnwrap(observed.visualization), occurrence = plan.occurrences[0]
        let data = try XCTUnwrap(visual.occurrences[occurrence.id])
        XCTAssertEqual(data.section?.level(at: 0.5), 0)
        XCTAssertGreaterThan(try XCTUnwrap(data.section?.level(at: 1.12)), 0.001)
        XCTAssertEqual(visual.master?.peaks, PlaybackEnvelope(observed.mix).peaks)
        let midi = try XCTUnwrap(occurrence.signalPlan?.orderedNodes.first { $0.content.output == .midi })
        XCTAssertEqual(data.nodes[midi.id]?.level(at: 0.5), 0)
        XCTAssertGreaterThan(try XCTUnwrap(data.nodes[midi.id]?.level(at: 0.9)), 0.5)
        XCTAssertEqual(data.nodes[midi.id]?.level(at: 1.1), 0)
    }
    func testMutedAndDisconnectedAndZeroGainRoutesHaveNoVisualSignal() async throws {
        for mode in 0..<4 {
            var p = try fixture(); let use = p.active.uses[0]
            var graph = try XCTUnwrap(SectionGraphEditing.effective(section: p.sections[0], use: use))
            if mode == 0 { p.tracks[0].muted = true }
            if mode == 1 { graph.edges.removeAll() }
            if mode == 2 { for i in graph.edges.indices where graph.edges[i].signal == .audio { graph.edges[i].gain = 0 } }
            if mode == 3 { let i = try XCTUnwrap(graph.nodes.firstIndex { if case .output = $0.content { return true }; return false }); graph.nodes[i].muted = true }
            try SectionGraphEditing.set(graph, useID: use.id, original: false, in: &p)
            let plan = try AlbumCompiler.executionPlan(p)
            let result = try await ArrangementRenderer.render(project: p, root: nil, plan: plan, tailSeconds: 0.1, includeStems: false, includeVisualization: true)
            XCTAssertEqual(result.mix.peak, 0, "mode \(mode)")
            let visual = try XCTUnwrap(result.visualization?.occurrences[plan.occurrences[0].id])
            XCTAssertTrue(visual.nodes.values.allSatisfy { $0.peaks.allSatisfy { $0 == 0 } }, "mode \(mode)")
        }
    }
    func testMasterAnalysisExcludesDisconnectedTrackAndZeroGainEdge() throws {
        var p = try fixture()
        let master = try XCTUnwrap(p.signal.nodes.first { $0.kind == .master })
        let source = try XCTUnwrap(p.signal.nodes.first { $0.kind == .source })
        XCTAssertTrue(PlaybackAnalysis.connectedSignals(p.signal).contains(source.id))
        for i in p.signal.edges.indices { p.signal.edges[i].gain = 0 }
        XCTAssertEqual(PlaybackAnalysis.connectedSignals(p.signal), [master.id])
        p.signal.edges.removeAll()
        XCTAssertEqual(PlaybackAnalysis.connectedSignals(p.signal), [master.id])
    }
}
