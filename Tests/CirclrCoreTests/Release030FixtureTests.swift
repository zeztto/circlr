import Foundation
import XCTest
@testable import CirclrCore

/// QA-only authoring contract. Python generates in a unique temporary directory;
/// Core validates/compiles/saves it without opening the app or an audio device.
final class Release030FixtureTests: XCTestCase {
    func testAuthoredFixtureCompilesAndRoundTrips() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-r30-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let fixture = temporary.appendingPathComponent("release030.circlr")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", root.appendingPathComponent("qa/r30-create-fixture.py").path, "--output", fixture.path]
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        try process.run(); process.waitUntilExit()
        let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, log)
        guard process.terminationStatus == 0 else { return }
        let project = try ProjectStore.load(fixture).project
        XCTAssertEqual(project.id, "R30-project")
        XCTAssertEqual(project.schemaVersion, 2)
        XCTAssertEqual(project.sections.map(\.name), ["Intro", "Verse", "Chorus"])
        XCTAssertEqual(project.tracks.count, 3)
        XCTAssertEqual(project.patterns.count, 1)
        XCTAssertEqual(project.patterns[0].notes.count, 8)
        let plan = try ArrangementCompiler.compile(project)
        XCTAssertEqual(plan.duration, 12, accuracy: 0.000001)
        XCTAssertEqual(plan.occurrences.map(\.start), [0, 4, 8])
        XCTAssertEqual(plan.occurrences.map { $0.clock.beats }, [8, 8, 8])
        let original = try XCTUnwrap(project.sections[1].lanes.first { $0.trackID == "R30-track-synth" })
        let variant = try XCTUnwrap(plan.occurrences[1].lanes.first { $0.trackID == "R30-track-synth" })
        XCTAssertEqual(original.notes.map(\.pitch), [48, 51, 55, 58])
        XCTAssertEqual(variant.notes.map(\.pitch), [60, 51, 55, 58])
        XCTAssertFalse(project.active.uses[0].isVariant)
        XCTAssertTrue(project.active.uses[1].isVariant)
        XCTAssertFalse(project.active.uses[2].isVariant)
        let shared = project.sections.flatMap { $0.graph?.nodes ?? [] }.filter {
            if case .rhythmMIDI = $0.content { return true }; return false
        }
        XCTAssertEqual(shared.map(\.id), ["R30-Verse-drums-source", "R30-Chorus-drums-source"])
        XCTAssertTrue(shared.allSatisfy { $0.settings.rhythm.value?.patternID == "R30-shared-drums" })
        let automated = project.sections.flatMap { $0.graph?.nodes ?? [] }.filter { !($0.automation ?? []).isEmpty }
        XCTAssertEqual(automated.count, 3)
        XCTAssertTrue(automated.allSatisfy { $0.automation?.first?.parameter == .gain })
        let effects = project.sections.flatMap { $0.graph?.nodes ?? [] }.filter {
            if case .effect = $0.content { return true }; return false
        }
        XCTAssertEqual(effects.count, 3)
        let asset = try XCTUnwrap(project.assets.first)
        XCTAssertEqual(asset.checksum, "269e81783fe346377a519df0aec19da84c026f2fadd5a282a40379f9c603aed0")
        XCTAssertEqual(try ProjectStore.checksum(ProjectStore.assetURL(asset, root: fixture)), asset.checksum)
        let savedURL = temporary.appendingPathComponent("roundtrip.circlr")
        let saved = try ProjectStore.save(project, to: savedURL, mediaRoot: fixture)
        let reopened = try ProjectStore.load(savedURL).project
        XCTAssertEqual(reopened, saved)
        XCTAssertEqual(reopened.sections, project.sections)
        XCTAssertEqual(reopened.patterns, project.patterns)
        XCTAssertEqual(reopened.arrangements, project.arrangements)
        XCTAssertEqual(try ArrangementCompiler.compile(reopened).duration, plan.duration, accuracy: 0.000001)
        XCTAssertEqual(try ProjectStore.checksum(ProjectStore.assetURL(reopened.assets[0], root: savedURL)), asset.checksum)
    }
}
