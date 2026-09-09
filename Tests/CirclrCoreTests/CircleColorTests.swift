import XCTest
@testable import CirclrCore

final class CircleColorTests: XCTestCase {
    func fixture() throws -> Project {
        var project = Project()
        _ = project.addTrack(name: "건반")
        _ = project.addSection(name: "벌스", at: Point(), bars: 2)
        project.enableAlbum()
        return try SectionGraphMigration.migrate(project)
    }

    func testDefaultColorsDistinguishSongSectionMIDIAndEffects() throws {
        let project = try fixture()
        let scene = try HierarchySceneBuilder.build(project)
        let song = try XCTUnwrap(scene.nodes.first { $0.role == .song })
        let section = try XCTUnwrap(scene.nodes.first { $0.role == .section })
        let midi = try XCTUnwrap(scene.nodes.first { if case .midi = $0.music?.content { return true }; return false })
        XCTAssertEqual(song.baseColor, CircleColor.Preset.violet.color)
        XCTAssertEqual(section.baseColor, CircleColor.Preset.amber.color)
        XCTAssertEqual(midi.baseColor, CircleColor.Preset.mint.color)
        var audio = midi; audio.music?.content = .audio(laneID: "lane", clipID: "clip")
        var effect = midi; effect.music?.content = .effect(Effect(.gain))
        XCTAssertEqual(audio.baseColor, CircleColor.Preset.blue.color)
        XCTAssertEqual(effect.baseColor, CircleColor.Preset.coral.color)
        XCTAssertEqual(Set([song, section, midi, audio, effect].map { "\($0.baseColor)" }).count, 5)
    }

    func testCustomColorRoundTripIsScopedToCircleOccurrence() throws {
        var project = try fixture()
        let address = CircleAddress.section(arrangementID: project.activeArrangementID, useID: project.active.uses[0].id)
        let another = CircleAddress.section(arrangementID: project.activeArrangementID, useID: "another-use")
        let custom = CircleColor(red: 14, green: 83, blue: 216)
        project.circleColors = [address: custom, .album: CircleColor.Preset.rose.color]
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.circleColors?[address], custom)
        XCTAssertNil(decoded.circleColors?[another])
        XCTAssertEqual(decoded.musicRevision, project.musicRevision)
    }

    func testDefaultColorsCoverRhythmInstrumentSignalAndContainers() throws {
        let scene = try HierarchySceneBuilder.build(fixture())
        var node = try XCTUnwrap(scene.nodes.first { $0.music != nil })
        let musicCases: [(MusicCircleContent, CircleColor.Preset)] = [
            (.rhythmMIDI(trackID: "track"), .mint),
            (.rhythmAudio(trackID: "track"), .blue),
            (.instrument(trackID: "track"), .teal),
            (.mix, .silver),
            (.output(trackID: "track"), .silver)
        ]
        for (content, preset) in musicCases {
            node.music?.content = content
            XCTAssertEqual(node.baseColor, preset.color)
        }
        node.music = nil
        let signalCases: [(SignalKind, CircleColor.Preset)] = [
            (.source, .teal), (.effect, .coral), (.bus, .silver), (.master, .silver)
        ]
        for (kind, preset) in signalCases {
            node.signal = SignalNode(kind: kind, name: "색상 검증")
            XCTAssertEqual(node.baseColor, preset.color)
        }
        node.signal = nil
        let roleCases: [(CircleRole, CircleColor.Preset)] = [
            (.album, .rose), (.movement, .violet), (.group, .silver), (.sound, .silver)
        ]
        for (role, preset) in roleCases {
            node.role = role
            XCTAssertEqual(node.baseColor, preset.color)
        }
    }

    func testNestedOccurrenceColorsRoundTripAndLayoutUndoKeepsCurrentColors() throws {
        var saved = try fixture()
        let section = CircleAddress.section(arrangementID: saved.activeArrangementID, useID: saved.active.uses[0].id)
        let group = CircleAddress.group(parent: section, id: "nested-group")
        saved.circleColors = [group: CircleColor.Preset.amber.color]
        var current = saved
        current.circleColors = [group: CircleColor(red: 0, green: 255, blue: 127)]
        let data = try JSONEncoder().encode(current)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: data).circleColors, current.circleColors)
        let restored = try CircleHistory.restore(saved, layoutOnly: true, current: current)
        XCTAssertEqual(restored.circleColors, current.circleColors)
    }

    func testOldManifestWithoutColorsLoadsAndColorHistoryRestores() throws {
        let original = try fixture()
        let data = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["circleColors"])
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertNil(decoded.circleColors)
        var changed = decoded
        changed.circleColors = [.album: CircleColor.Preset.blue.color]
        let restored = try CircleHistory.restore(decoded, layoutOnly: false, current: changed, colorsOnly: true)
        XCTAssertNil(restored.circleColors)
        let redone = try CircleHistory.restore(changed, layoutOnly: false, current: restored, colorsOnly: true)
        XCTAssertEqual(redone.circleColors, changed.circleColors)
        XCTAssertEqual(restored.sections, decoded.sections)
        XCTAssertEqual(redone.signal, decoded.signal)
    }

    func testColorUndoAndRedoPreserveNewerMusicViewsAndPortRevision() throws {
        let saved = try fixture()
        var colored = saved
        colored.circleColors = [.album: CircleColor.Preset.blue.color]
        var current = colored
        current.name = "최근 음악"
        current.musicRevision = 19
        current.circleLayout = .freeform
        current.album?.layout.grid = false
        current.album?.layout.snap = false
        let cable = try XCTUnwrap(CirclePortCatalog.connections(in: current).first)
        try CirclePortLayoutEditing.apply([.init(id: cable.id, placement: .init(from: .north, to: .south))],
            projectID: current.id, expectedMusicRevision: 19, expectedLayoutRevision: 0, in: &current)
        var expected = current
        expected.circleColors = saved.circleColors
        let undone = try CircleHistory.restore(saved, layoutOnly: false, current: current, colorsOnly: true)
        XCTAssertEqual(undone, expected)

        var newer = undone
        newer.name = "실행 취소 이후 음악"
        newer.musicRevision = 20
        newer.circleLayout = .orbit
        let redone = try CircleHistory.restore(colored, layoutOnly: false, current: newer, colorsOnly: true)
        expected = newer
        expected.circleColors = colored.circleColors
        XCTAssertEqual(redone, expected)
    }

    func testColorHistoryRejectsAnotherProject() throws {
        let saved = try fixture()
        var current = try fixture()
        current.circleColors = [.album: CircleColor.Preset.coral.color]
        XCTAssertThrowsError(try CircleHistory.restore(saved, layoutOnly: false, current: current, colorsOnly: true))
    }
}
