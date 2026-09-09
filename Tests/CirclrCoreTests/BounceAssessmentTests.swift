import XCTest
@testable import CirclrCore

final class BounceAssessmentTests: XCTestCase {
    private func fixture() throws -> Project { try BounceTargetTests().fixture() }
    private func assess(_ p: Project, selected: ID? = nil) -> BounceAssessment {
        BounceAssessment.make(trackID: p.tracks[0].id, useID: p.active.uses[0].id, selectedNodeID: selected, in: p)
    }
    func testTargetParityMembershipAndProjectPreservation() throws {
        let p = try fixture(), before = p
        let target = try BounceEditing.target(trackID: p.tracks[0].id, useID: p.active.uses[0].id, in: p)
        let graph = try XCTUnwrap(p.sections[0].graph)
        let midi = try XCTUnwrap(graph.nodes.first { if case .midi = $0.content { return true }; return false })
        XCTAssertEqual(assess(p).target, target); XCTAssertEqual(assess(p).membership, .notSelected)
        XCTAssertEqual(assess(p, selected: midi.id).membership, .mainPath)
        XCTAssertEqual(assess(p, selected: target.outputNodeID).membership, .output)
        XCTAssertEqual(assess(p, selected: "missing").membership, .missingNode)
        XCTAssertEqual(p, before)
        for destination in assess(p).destinations {
            switch destination.id {
            case .section(let a, let u): XCTAssertEqual(a, p.active.id); XCTAssertEqual(u, p.active.uses[0].id)
            case .music(let a, let u, let n): XCTAssertEqual(a, p.active.id); XCTAssertEqual(u, p.active.uses[0].id); XCTAssertTrue(graph.nodes.contains { $0.id == n })
            default: XCTFail("Unexpected recovery destination")
            }
        }
    }
    func testTypedTargetFailuresPreserveExistingMessages() throws {
        let p = try fixture(), track = p.tracks[0].id, use = p.active.uses[0].id
        XCTAssertEqual(BounceAssessment.make(trackID: "missing", useID: use, in: p).issue, .missingTrack)
        XCTAssertEqual(BounceAssessment.make(trackID: track, useID: "missing", in: p).issue, .missingSection)
        let output = try XCTUnwrap(p.sections[0].graph?.nodes.first { if case .output = $0.content { return true }; return false })
        var none = p; none.sections[0].graph!.nodes.removeAll { $0.id == output.id }
        var many = p; var copy = output; copy.id = newID(); many.sections[0].graph!.nodes.append(copy)
        var disconnected = p; disconnected.sections[0].graph!.edges.removeAll { $0.to == output.id }
        for (candidate, issue) in [(none, BounceIssue.noOutput), (many, .multipleOutputs), (disconnected, .noInputs)] {
            let result = assess(candidate)
            XCTAssertNil(result.target); XCTAssertEqual(result.issue, issue)
            XCTAssertThrowsError(try BounceEditing.target(trackID: track, useID: use, in: candidate)) { XCTAssertEqual($0.localizedDescription, issue.message) }
        }
        XCTAssertEqual(assess(many).destinations.filter { $0.kind == .output }.count, 2)
        XCTAssertEqual(assess(none).destinations.filter { $0.kind == .output }.count, 0)
    }
    func testRouterMembershipFollowsSpecificBusRoutesIncludingCrossRoute() throws {
        var p = try fixture(); let track2 = p.addTrack(name: "두 번째")
        let source1 = MusicCircle(name: "첫 악기", content: .instrument(trackID: p.tracks[0].id))
        let source2 = MusicCircle(name: "둘째 악기", content: .instrument(trackID: track2))
        let router = MusicCircle(name: "독립 bus", content: .router(AudioRouter()))
        let output1 = MusicCircle(name: "출력 1", content: .output(trackID: p.tracks[0].id))
        let output2 = MusicCircle(name: "출력 2", content: .output(trackID: track2))
        var graph = SectionGraph(); graph.nodes = [source1, source2, router, output1, output2]
        for (source, input, output, target) in [(source1.id, AudioRouter.input1, AudioRouter.output1, output1.id), (source2.id, AudioRouter.input2, AudioRouter.output2, output2.id)] {
            var a = MusicConnection(from: source, to: router.id, signal: .audio); a.toPortID = input
            var b = MusicConnection(from: router.id, to: target, signal: .audio); b.fromPortID = output
            graph.edges += [a, b]
        }
        _ = try SectionGraphValidator.sorted(graph); p.sections[0].graph = graph
        XCTAssertEqual(assess(p, selected: source1.id).membership, .mainPath)
        XCTAssertEqual(assess(p, selected: source2.id).membership, .outsidePath)
        p.sections[0].graph!.nodes[2].content = .router(AudioRouter(routes: [.init(input: AudioRouter.input2, output: AudioRouter.output1)]))
        XCTAssertEqual(assess(p, selected: source1.id).membership, .outsidePath)
        XCTAssertEqual(assess(p, selected: source2.id).membership, .mainPath)
        // Structural membership is retained despite zero gain or mute.
        p.sections[0].graph!.nodes[1].muted = true; p.sections[0].graph!.edges[2].gain = 0
        XCTAssertEqual(assess(p, selected: source2.id).membership, .mainPath)
    }
    func testSidechainOnlyIsNotMainPathAndDisconnectedSelectionDoesNotBlockTarget() throws {
        var p = try fixture(); var graph = try XCTUnwrap(p.sections[0].graph)
        let output = try XCTUnwrap(graph.nodes.first { if case .output = $0.content { return true }; return false })
        let detector = MusicCircle(name: "검출 입력", content: .instrument(trackID: p.tracks[0].id))
        let outside = MusicCircle(name: "분리", content: .instrument(trackID: p.tracks[0].id))
        let compressor = MusicCircle(name: "압축", content: .effect(Effect(.compressor)))
        graph.nodes += [detector, outside, compressor]
        for index in graph.edges.indices where graph.edges[index].to == output.id { graph.edges[index].to = compressor.id }
        graph.edges.append(MusicConnection(from: compressor.id, to: output.id, signal: .audio))
        var sidechain = MusicConnection(from: detector.id, to: compressor.id, signal: .audio); sidechain.sidechain = true
        graph.edges.append(sidechain); p.sections[0].graph = graph
        XCTAssertEqual(assess(p, selected: detector.id).membership, .sidechainOnly)
        XCTAssertEqual(assess(p, selected: outside.id).membership, .outsidePath)
        XCTAssertNotNil(assess(p, selected: outside.id).target)
        p.sections[0].graph!.edges.append(MusicConnection(from: detector.id, to: compressor.id, signal: .audio))
        XCTAssertEqual(assess(p, selected: detector.id).membership, .mainPath)
    }
    func testCorruptGraphFailsClosedAndExplicitArrangementIgnoresActive() throws {
        var p = try fixture(); let source = p.active, track = p.tracks[0].id
        let expected = assess(p)
        let other = Arrangement(name: "다른 안"); p.arrangements.append(other); p.activeArrangementID = other.id
        XCTAssertEqual(BounceAssessment.make(trackID: track, useID: source.uses[0].id, arrangementID: source.id, in: p), expected)
        p.activeArrangementID = source.id
        let duplicate = p.sections[0].graph!.nodes[0]; p.sections[0].graph!.nodes.append(duplicate)
        let result = assess(p, selected: duplicate.id)
        guard case .invalidGraph = result.issue else { return XCTFail("Expected corrupt graph issue") }
        XCTAssertNil(result.target); XCTAssertEqual(result.membership, .unavailable)
    }
}
