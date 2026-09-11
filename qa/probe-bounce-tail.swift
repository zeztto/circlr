import Foundation
import CirclrCore
import CirclrAudio

/// Offline evidence probe only. It does not change the product's two-second tail policy.
@main struct BounceTailProbe {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw CirclrError("출력 디렉토리가 필요합니다") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let url = root.appendingPathComponent("impulse.wav")
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CirclrError("기존 impulse.wav를 덮어쓸 수 없습니다") }
        var input = PCM(frames: 48_000)
        for i in 43_200..<43_680 { input.left[i] = 0.2; input.right[i] = 0.2 }
        try input.writeWAV(url)
        var project = Project()
        let track = project.addTrack(name: "Tail probe")
        project.global.tempo = 240
        _ = project.addSection(name: "Body one second", at: Point(), bars: 1)
        let asset = Asset(name: "impulse", path: url.path, duration: 1, sampleRate: 48_000)
        project.assets = [asset]
        project.sections[0].lanes[0].audio = [AudioClip(assetID: asset.id, duration: 1)]
        project = try SectionGraphMigration.migrate(project)
        guard var graph = project.sections[0].graph,
              let output = graph.nodes.first(where: { if case .output = $0.content { return true }; return false })
        else { throw CirclrError("검증 출력이 없습니다") }
        let delay = MusicCircle(name: "One second feedback delay", content: .effect(Effect(.delay, amount: 1, secondary: 0.8)))
        try SectionGraphEditing.insertEffectBeforeOutput(delay, before: output.id, in: &graph)
        project.sections[0].graph = graph
        let use = project.active.uses[0]
        let (section, context, clock) = try ArrangementCompiler.context(project: project, use: use)
        guard let plan = try SectionGraphCompiler.compile(project: project, section: section, use: use, context: context, clock: clock)
        else { throw CirclrError("검증 graph가 없습니다") }
        let shortBuffers = try await SectionGraphRenderer.render(plan, project: project, root: nil, clock: clock, tail: 2, applyOutputGain: false)
        let longBuffers = try await SectionGraphRenderer.render(plan, project: project, root: nil, clock: clock, tail: 5, applyOutputGain: false)
        guard let short = shortBuffers[track], let long = longBuffers[track], long.count > short.count
        else { throw CirclrError("비교할 PCM 출력이 없습니다") }
        let lost = long.slice(short.count..<long.count)
        let report: [String: Any] = [
            "bodySeconds": clock.seconds, "shortSeconds": short.duration, "longSeconds": long.duration,
            "lostPeak": lost.peak, "lostRMS": lost.rms,
            "prefixMatches": short.left == Array(long.left.prefix(short.count)) && short.right == Array(long.right.prefix(short.count))
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
