import Foundation
import XCTest
@testable import CirclrCore

final class ProjectDiagnosticsTests: XCTestCase {
    func testDiagnosticAllowlistExcludesPrivateNamesPathsIDsAndMetadata() throws {
        var project = Project()
        project.name = "PRIVATE_PROJECT_TEXT"
        project.id = "PRIVATE_PROJECT_ID"
        _ = project.addTrack(name: "PRIVATE_TRACK_TEXT")
        _ = project.addSection(name: "PRIVATE_SECTION_TEXT", at: Point(), bars: 1)
        project.assets = [Asset(name: "PRIVATE_MEDIA_TEXT", path: "/missing/private-credential-token.wav", duration: 1, sampleRate: 48000)]
        project.assets[0].id = "PRIVATE_ASSET_ID"
        let runtime = ProjectDiagnostics.Runtime(playbackPlaying: true, midiRecording: true, jobKind: .bounce, jobState: .running)
        let report = try ProjectDiagnostics(project: project, mediaRoot: nil, appVersion: "1.3.0", appBuild: "254", runtime: runtime)
        let data = try report.encoded(), text = String(decoding: data, as: UTF8.self)
        for forbidden in ["PRIVATE_", "/missing", "credential", "token", "checksum", "displayName", "path", "message", "accessToken"] {
            XCTAssertFalse(text.contains(forbidden), "Diagnostic leaked \(forbidden)")
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["format", "appVersion", "appBuild", "projectSchema", "musicRevision", "counts", "mediaHealth", "issues", "runtime"])
        XCTAssertEqual(report.counts.tracks, 1); XCTAssertEqual(report.counts.sections, 1)
        XCTAssertEqual(report.mediaHealth.issues, 1); XCTAssertTrue(report.issues.contains(.mediaSourceIssue))
        XCTAssertEqual(report.runtime.jobKind, .bounce); XCTAssertEqual(report.runtime.jobState, .running)
        XCTAssertEqual(report.appVersion, "1.3.0"); XCTAssertEqual(report.appBuild, "254")
    }
    func testReadableMissingAndNonRegularMediaUseAggregateCodesOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("private.wav")
        try Data([1, 2, 3]).write(to: file)
        var project = Project()
        project.assets = [Asset(name: "PRIVATE", path: file.path, duration: 1, sampleRate: 48000),
            Asset(name: "PRIVATE", path: root.appendingPathComponent("missing.wav").path, duration: 1, sampleRate: 48000),
            Asset(name: "PRIVATE", path: root.path, duration: 1, sampleRate: 48000)]
        let report = try ProjectDiagnostics(project: project, mediaRoot: nil, appVersion: "1.3.0", appBuild: "254")
        XCTAssertEqual(report.mediaHealth.healthy, 1); XCTAssertEqual(report.mediaHealth.issues, 2)
        XCTAssertEqual(report.mediaHealth.check, "media_source_inspection")
        let text = String(decoding: try report.encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains(root.path)); XCTAssertFalse(text.contains("private.wav"))
        XCTAssertEqual(report.issues.filter { $0 == .mediaSourceIssue }.count, 1)
    }
    func testUnexpectedMetadataAndStructuralErrorsNeverSerializeRawStrings() throws {
        var project = Project(); project.schemaVersion = -1
        let report = try ProjectDiagnostics(project: project, mediaRoot: nil,
            appVersion: "private-user-authored-text", appBuild: "Bearer private-token")
        XCTAssertEqual(report.appVersion, "unknown"); XCTAssertEqual(report.appBuild, "unknown")
        XCTAssertTrue(report.issues.contains(.structureInvalid))
        XCTAssertEqual(report.mediaHealth.healthy, 0); XCTAssertEqual(report.mediaHealth.issues, 0)
        XCTAssertEqual(report.runtime.jobKind, .none); XCTAssertEqual(report.runtime.jobState, .idle)
        let text = String(decoding: try report.encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("Bearer")); XCTAssertFalse(text.contains("private-user"))
    }
    func testCancellationStopsDiagnosticConstructionBeforeExport() throws {
        var checks = 0
        XCTAssertThrowsError(try ProjectDiagnostics(project: Project(), mediaRoot: nil,
            appVersion: "1.3.0", appBuild: "254", checkCancellation: {
                checks += 1; throw CancellationError()
            })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(checks, 1)
    }

    func testJSONSizeDoesNotGrowWithPrivateNamesOrMusicEvents() throws {
        var project = Project()
        _ = project.addTrack(name: "track")
        _ = project.addSection(name: "section", at: Point(), bars: 4)
        let baseline = try ProjectDiagnostics(project: project, mediaRoot: nil,
            appVersion: "1.3.0", appBuild: "254").encoded()
        let privateText = String(repeating: "PRIVATE_AUTHORED_MUSIC_TEXT", count: 40_000)
        project.name = privateText
        project.tracks[0].name = privateText
        project.sections[0].name = privateText
        project.arrangements[0].name = privateText
        project.sections[0].lanes[0].notes = (0..<10_000).map {
            Note(beat: Double($0 % 64) / 4, length: 0.125, pitch: 60 + $0 % 12, velocity: 80)
        }
        let manifest = try JSONEncoder().encode(project)
        let expanded = try ProjectDiagnostics(project: project, mediaRoot: nil,
            appVersion: "1.3.0", appBuild: "254").encoded()
        XCTAssertGreaterThan(manifest.count, 4_000_000)
        XCTAssertLessThan(expanded.count, 4096)
        XCTAssertEqual(expanded, baseline, "Names and musical event payloads must not enter the support projection")
        XCTAssertFalse(String(decoding: expanded, as: UTF8.self).contains("PRIVATE_AUTHORED"))
    }

}
