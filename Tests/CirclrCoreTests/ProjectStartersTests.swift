import XCTest
@testable import CirclrCore

final class ProjectStartersTests: XCTestCase {
    func testCatalogIsStableAndUnknownIDFails() throws {
        XCTAssertEqual(ProjectStarters.catalog.map(\.id), ["blank", "electronic", "piano", "band"])
        XCTAssertTrue(ProjectStarters.catalog.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
        XCTAssertThrowsError(try ProjectStarters.make(id: "missing"))
    }

    func testEveryStarterHasAnEditableSongAndCompleteFlow() throws {
        for starter in ProjectStarters.catalog {
            let project = try ProjectStarters.make(id: starter.id)
            let song = try XCTUnwrap(project.album?.compositions.first)
            XCTAssertEqual(song.kind, .song)
            XCTAssertEqual(song.name, project.name)
            XCTAssertEqual(song.selectedArrangementID, project.activeArrangementID)
            let plan = try ArrangementCompiler.compile(project)
            XCTAssertEqual(plan.occurrences.count, project.sections.count)
            XCTAssertGreaterThan(plan.duration, 0)
            XCTAssertEqual(project.global.beatGrid.accents, [4])
            XCTAssertEqual(project.global.beatGrid.accents.reduce(0, +), project.global.meter.numerator)
            XCTAssertEqual(project.active.edges.count, project.sections.count - 1)
            XCTAssertEqual(project.active.uses.last?.isEnd, true)
            XCTAssertTrue(project.active.uses.dropLast().allSatisfy { !$0.isEnd })
            XCTAssertTrue(project.assets.isEmpty)
            XCTAssertTrue(project.tracks.allSatisfy { $0.instrument.plugin == nil && $0.instrument.sample == nil })
            XCTAssertTrue(project.sections.flatMap(\.lanes).allSatisfy { $0.notes.isEmpty && $0.audio.isEmpty })
            XCTAssertEqual(project.musicRevision, 0)
        }
    }

    func testAllLanesAreConnectedToTheirOwnInstrumentAndOutput() throws {
        for starter in ProjectStarters.catalog {
            let project = try ProjectStarters.make(id: starter.id)
            for section in project.sections {
                let graph = try XCTUnwrap(section.graph)
                XCTAssertEqual(section.lanes.count, project.tracks.count)
                XCTAssertEqual(graph.nodes.count, project.tracks.count * 3)
                for lane in section.lanes {
                    let midi = try XCTUnwrap(graph.nodes.first { $0.content == .midi(laneID: lane.id) })
                    let instrument = try XCTUnwrap(graph.nodes.first { $0.content == .instrument(trackID: lane.trackID) })
                    let output = try XCTUnwrap(graph.nodes.first { $0.content == .output(trackID: lane.trackID) })
                    XCTAssertTrue(graph.edges.contains { $0.from == midi.id && $0.to == instrument.id && $0.signal == .midi })
                    XCTAssertTrue(graph.edges.contains { $0.from == instrument.id && $0.to == output.id && $0.signal == .audio })
                }
            }
        }
    }

    func testEachCreationHasIndependentIdentityAndName() throws {
        let first = try ProjectStarters.make(id: "electronic", name: "  나의 곡  ")
        let second = try ProjectStarters.make(id: "electronic")
        XCTAssertEqual(first.name, "나의 곡")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.album?.id, second.album?.id)
        XCTAssertTrue(Set(first.tracks.map(\.id)).isDisjoint(with: second.tracks.map(\.id)))
        XCTAssertTrue(Set(first.sections.map(\.id)).isDisjoint(with: second.sections.map(\.id)))
        XCTAssertEqual(try ProjectStarters.make(id: "blank", name: " \n").name, "새 곡")
    }

    func testColorOverridesResolveAndKeepMIDITypeColor() throws {
        for starter in ProjectStarters.catalog {
            let project = try ProjectStarters.make(id: starter.id)
            let scene = try HierarchySceneBuilder.build(project)
            let addresses = Set(scene.nodes.map(\.id))
            XCTAssertTrue(Set((project.circleColors ?? [:]).keys).isSubset(of: addresses))
            XCTAssertEqual(project.circleColors?.count, project.sections.count * (project.tracks.count + 1))
            for node in scene.nodes {
                if case .midi = node.music?.content {
                    XCTAssertNil(project.circleColors?[node.id])
                    XCTAssertEqual(node.baseColor, CircleColor.Preset.mint.color)
                }
            }
        }
    }

    func testPortableProjectStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for starter in ProjectStarters.catalog {
            let project = try ProjectStarters.make(id: starter.id)
            let url = root.appendingPathComponent(starter.id).appendingPathExtension("circlr")
            let saved = try ProjectStore.save(project, to: url, mediaRoot: nil)
            let reopened = try ProjectStore.load(url).project
            XCTAssertEqual(reopened, saved)
            XCTAssertEqual(try ArrangementCompiler.compile(reopened).duration, try ArrangementCompiler.compile(project).duration)
            XCTAssertTrue(reopened.assets.isEmpty)
        }
    }
}
