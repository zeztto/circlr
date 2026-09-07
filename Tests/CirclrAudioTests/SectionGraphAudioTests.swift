import XCTest
import CirclrCore
@testable import CirclrAudio

final class SectionGraphAudioTests: XCTestCase {
    func fixture(root: URL) throws -> Project {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var source = PCM(frames: 12_000)
        for i in 0..<source.count {
            source.left[i] = Float(sin(Double(i) * 2 * .pi * 220 / PCM.rate) * 0.16)
            source.right[i] = Float(sin(Double(i) * 2 * .pi * 330 / PCM.rate) * 0.11)
        }
        let url = root.appendingPathComponent("controlled-source.wav"); try source.writeWAV(url)
        var p = Project()
        for name in ["기타", "보컬"] { _ = p.addTrack(name: name) }
        _ = p.addSection(name: "오디오 섹션", at: Point(), bars: 1)
        p.global.tempo = 240
        let asset = Asset(name: "검증용 오디오", path: url.path, duration: source.duration, sampleRate: PCM.rate)
        p.assets = [asset]
        for i in p.sections[0].lanes.indices {
            var clip = AudioClip(assetID: asset.id, duration: source.duration, beat: Double(i))
            clip.gain = i == 0 ? 0.8 : 0.5
            p.sections[0].lanes[i].audio = [clip]
        }
        p.arrangements[0].uses[0].effects = [Effect(.drive, amount: 0.45), Effect(.lowpass, amount: 0.68)]
        return p
    }

    func testMigratedAudioAndNonlinearPerTrackEffectsMatchLegacySamples() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-graph-audio-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = try fixture(root: root)
        let converted = try SectionGraphMigration.migrate(legacy)
        let before = try await ArrangementRenderer.render(project: legacy, root: nil, plan: ArrangementCompiler.compile(legacy), tailSeconds: 0)
        let after = try await ArrangementRenderer.render(project: converted, root: nil, plan: ArrangementCompiler.compile(converted), tailSeconds: 0)
        XCTAssertGreaterThan(after.mix.peak, 0.1)
        XCTAssertEqual(after.mix.left, before.mix.left)
        XCTAssertEqual(after.mix.right, before.mix.right)
        for track in legacy.tracks {
            XCTAssertEqual(after.stems[track.id]?.left, before.stems[track.id]?.left)
            XCTAssertEqual(after.stems[track.id]?.right, before.stems[track.id]?.right)
        }
    }

    func testAudioCircleRepeatsAndRoutingEditsChangeRenderedResult() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-graph-routing-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var p = try SectionGraphMigration.migrate(fixture(root: root))
        let use = p.active.uses[0]
        var graph = try XCTUnwrap(SectionGraphEditing.effective(section: p.sections[0], use: use))
        let audioIndex = try XCTUnwrap(graph.nodes.firstIndex { if case .audio = $0.content { return true }; return false })
        let outputID = "output:\(p.tracks[0].id)"
        graph.nodes[audioIndex].repeatCount = 3
        // Explicit route directly to output: the nonlinear effect chain is no longer used by this clip.
        graph.edges.removeAll { $0.from == graph.nodes[audioIndex].id }
        try SectionGraphEditing.connect(from: graph.nodes[audioIndex].id, to: outputID, in: &graph)
        try SectionGraphEditing.set(graph, useID: use.id, original: false, in: &p)
        let rendered = try await ArrangementRenderer.render(project: p, root: nil, plan: ArrangementCompiler.compile(p), tailSeconds: 0)
        let stem = try XCTUnwrap(rendered.stems[p.tracks[0].id])
        XCTAssertGreaterThan(stem.slice(2_000..<10_000).rms, 0.02)
        XCTAssertGreaterThan(stem.slice(26_000..<34_000).rms, 0.02)
        XCTAssertEqual(stem.slice(38_000..<47_000).peak, 0)
        graph.nodes[audioIndex].muted = true
        try SectionGraphEditing.set(graph, useID: use.id, original: false, in: &p)
        let muted = try await ArrangementRenderer.render(project: p, root: nil, plan: ArrangementCompiler.compile(p), tailSeconds: 0)
        XCTAssertEqual(muted.stems[p.tracks[0].id]?.peak, 0)
        XCTAssertGreaterThan(muted.stems[p.tracks[1].id]?.peak ?? 0, 0.1)
    }

    func testWholeAlbumGraphRenderAndWAVExportKeepBothSongsInOrder() async throws {
        let requestedRoot = ProcessInfo.processInfo.environment["CIRCLR_GRAPH_QA_OUTPUT"].map { URL(fileURLWithPath: $0) }
        let root = requestedRoot ?? FileManager.default.temporaryDirectory.appendingPathComponent("circlr-album-render-\(newID())")
        defer { if requestedRoot == nil { try? FileManager.default.removeItem(at: root) } }
        var p = try SectionGraphMigration.migrate(fixture(root: root)); p.enableAlbum()
        p.name = "검증용 앨범"
        let songID = try AlbumEditing.add(name: "두 번째 곡", kind: .song, in: &p)
        let arrangement = try XCTUnwrap(p.album?.composition(songID)?.selectedArrangementID)
        try AlbumEditing.selectArrangement(arrangement, in: &p)
        _ = p.addSection(name: "두 번째 섹션", at: Point(), bars: 1)
        let si = p.sections.count - 1
        var clip = AudioClip(assetID: p.assets[0].id, duration: 0.25, beat: 2)
        clip.gain = 0.2
        p.sections[si].lanes[0].audio = [clip]
        p = try SectionGraphMigration.migrate(p)
        let albumPlan = try AlbumCompiler.executionPlan(p)
        XCTAssertEqual(albumPlan.occurrences.map(\.start), [0, 1])
        XCTAssertEqual(albumPlan.duration, 2)
        let audio = try await ArrangementRenderer.render(project: p, root: nil, plan: albumPlan, tailSeconds: 0)
        XCTAssertEqual(audio.mix.count, 96_000)
        XCTAssertGreaterThan(audio.mix.slice(1_000..<10_000).rms, 0.02)
        XCTAssertEqual(audio.mix.slice(50_000..<70_000).peak, 0)
        XCTAssertGreaterThan(audio.mix.slice(74_000..<82_000).rms, 0.01)
        let wav = root.appendingPathComponent("album-export.wav")
        try AudioExport.save(audio, to: wav)
        let decoded = try PCM.read(wav)
        XCTAssertEqual(decoded.count, audio.mix.count)
        XCTAssertEqual(decoded.rms, audio.mix.rms, accuracy: 0.000001)
        let waveform = try WaveformOverview.read(wav, bins: 2000)
        XCTAssertEqual(waveform.duration, 2)
        XCTAssertGreaterThan(waveform.peak(at: 0.1), 0.1)
        XCTAssertEqual(waveform.peak(at: 1.2), 0)
        XCTAssertGreaterThan(waveform.peak(at: 1.6), 0.01)
        let package = root.appendingPathComponent("album-graph.circlr")
        let saved = try ProjectStore.save(p, to: package, mediaRoot: nil)
        XCTAssertEqual(try ProjectStore.load(package).project, saved)
        if requestedRoot != nil {
            let report: [String: Any] = ["seconds": decoded.duration, "frames": decoded.count, "rms": decoded.rms,
                                        "peak": decoded.peak, "compositionCount": p.album?.compositions.count ?? 0,
                                        "sections": albumPlan.occurrences.map { $0.use.name }, "starts": albumPlan.occurrences.map(\.start),
                                        "sampleRate": PCM.rate, "source": "controlled test audio; no hardware playback claim"]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("report.json"))
        }
    }
    func testAudioLocalClockAndExplicitCircleLengthScheduleAndTrimEachRepeat() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-audio-clock-\(newID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var p = try SectionGraphMigration.migrate(fixture(root: root))
        let use = p.active.uses[0]
        var graph = try XCTUnwrap(SectionGraphEditing.effective(section: p.sections[0], use: use))
        let index = try XCTUnwrap(graph.nodes.firstIndex { if case .audio = $0.content { return true }; return false })
        graph.nodes[index].settings.tempo = .local(120)
        graph.nodes[index].startBeat = 1
        graph.nodes[index].lengthBeats = 0.25
        graph.nodes[index].repeatCount = 3
        graph.edges.removeAll { $0.from == graph.nodes[index].id }
        try SectionGraphEditing.connect(from: graph.nodes[index].id, to: "output:\(p.tracks[0].id)", in: &graph)
        try SectionGraphEditing.set(graph, useID: use.id, original: false, in: &p)
        let audio = try await ArrangementRenderer.render(project: p, root: nil, plan: ArrangementCompiler.compile(p), tailSeconds: 0)
        let stem = try XCTUnwrap(audio.stems[p.tracks[0].id])
        // Parent 240 BPM starts at 0.25s; local 120 BPM repeats every 0.125s, ending at 0.625s.
        XCTAssertEqual(stem.slice(0..<12000).peak, 0)
        XCTAssertGreaterThan(stem.slice(13000..<17000).rms, 0.01)
        XCTAssertGreaterThan(stem.slice(25000..<29000).rms, 0.01)
        XCTAssertEqual(stem.slice(30000..<48000).peak, 0)
    }

}
