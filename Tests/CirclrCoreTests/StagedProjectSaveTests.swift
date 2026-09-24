import Foundation
import XCTest
@testable import CirclrCore

final class StagedProjectSaveTests: XCTestCase {
    private func fixture() throws -> (parent: URL, target: URL, source: URL, oldManifest: Data, oldMedia: Data) {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let source = parent.appendingPathComponent("source.wav")
        let oldMedia = Data((0..<65_543).map { UInt8($0 % 251) })
        try oldMedia.write(to: source)
        var old = try ProjectStarters.make(id: "blank")
        old.name = "저장 전"
        old.assets = [Asset(name: "take", path: source.path, duration: 1, sampleRate: 48_000)]
        let target = parent.appendingPathComponent("song.circlr")
        _ = try ProjectStore.save(old, to: target, mediaRoot: nil)
        return (parent, target, source,
                try Data(contentsOf: target.appendingPathComponent("manifest.json")), oldMedia)
    }

    private func stagedNames(in parent: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: parent.path)
            .filter { $0.hasPrefix(".circlr-save-") || $0.hasPrefix(".circlr-backup-") }
    }

    func testPrepareAndDiscardLeaveExistingManifestAndMediaUntouched() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.parent) }
        let old = try ProjectStore.load(item.target).project
        let oldMediaURL = try ProjectStore.assetURL(old.assets[0], root: item.target)
        var edited = old
        edited.name = "준비만 한 편집"
        let staged = try ProjectStore.prepareSessionSave(edited, to: item.target, mediaRoot: item.target)
        XCTAssertEqual(try Data(contentsOf: item.target.appendingPathComponent("manifest.json")), item.oldManifest)
        XCTAssertEqual(try Data(contentsOf: oldMediaURL), item.oldMedia)
        XCTAssertEqual(try stagedNames(in: item.parent).count, 1)
        ProjectStore.discard(staged)
        XCTAssertEqual(try Data(contentsOf: item.target.appendingPathComponent("manifest.json")), item.oldManifest)
        XCTAssertEqual(try Data(contentsOf: oldMediaURL), item.oldMedia)
        XCTAssertTrue(try stagedNames(in: item.parent).isEmpty)
        XCTAssertThrowsError(try ProjectStore.publishSessionSaveReportingCleanup(staged) { _ in })
    }

    func testPublishPreservesPortableMediaAndSessionLocalReference() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.parent) }
        let replacement = Data((0..<131_073).map { UInt8(($0 * 7) % 253) })
        try replacement.write(to: item.source)
        var edited = try ProjectStore.load(item.target).project
        edited.name = "저장 후"
        edited.assets = [Asset(name: "new take", path: item.source.path, duration: 2, sampleRate: 48_000)]
        let staged = try ProjectStore.prepareSessionSave(edited, to: item.target, mediaRoot: item.target)
        XCTAssertEqual(try Data(contentsOf: item.target.appendingPathComponent("manifest.json")), item.oldManifest)
        let session = try ProjectStore.publishSessionSaveReportingCleanup(staged) { warning in
            XCTFail("정상 저장에 정리 경고가 없어야 합니다: \(warning)")
        }
        XCTAssertEqual(session.assets[0].path, item.source.path)
        let loaded = try ProjectStore.load(item.target).project
        XCTAssertEqual(loaded.name, "저장 후")
        XCTAssertTrue(loaded.assets[0].path.hasPrefix("media/"))
        XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(loaded.assets[0], root: item.target)), replacement)
        XCTAssertEqual(try Data(contentsOf: item.source), replacement)
        XCTAssertTrue(try stagedNames(in: item.parent).isEmpty)
    }

    func testPublishRejectsTargetChangedDuringPreparation() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.parent) }
        var edited = try ProjectStore.load(item.target).project
        edited.name = "준비된 편집"
        let staged = try ProjectStore.prepareSessionSave(edited, to: item.target, mediaRoot: item.target)
        let manifest = item.target.appendingPathComponent("manifest.json")
        var external = try ProjectStore.load(item.target).project
        external.name = "외부 편집"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let externalBytes = try encoder.encode(external)
        try externalBytes.write(to: manifest, options: .atomic)
        XCTAssertThrowsError(try ProjectStore.publishSessionSaveReportingCleanup(staged) { _ in }) { error in
            XCTAssertTrue(error.localizedDescription.contains("변경"), error.localizedDescription)
        }
        XCTAssertEqual(try Data(contentsOf: manifest), externalBytes)
        XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(external.assets[0], root: item.target)), item.oldMedia)
        XCTAssertTrue(try stagedNames(in: item.parent).isEmpty)
    }

    func testPublishRejectsMissingStagedMediaWithoutTouchingTarget() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.parent) }
        let old = try ProjectStore.load(item.target).project
        let staged = try ProjectStore.prepareSessionSave(old, to: item.target, mediaRoot: item.target)
        let stage = item.parent.appendingPathComponent(try XCTUnwrap(stagedNames(in: item.parent).first))
        let stagedMedia = try ProjectStore.assetURL(staged.savedProject.assets[0], root: stage)
        try FileManager.default.removeItem(at: stagedMedia)
        XCTAssertThrowsError(try ProjectStore.publishSessionSaveReportingCleanup(staged) { _ in })
        XCTAssertEqual(try Data(contentsOf: item.target.appendingPathComponent("manifest.json")), item.oldManifest)
        XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(old.assets[0], root: item.target)), item.oldMedia)
        XCTAssertTrue(try stagedNames(in: item.parent).isEmpty)
    }

    func testNewTargetAppearingAfterPreparationIsNeverReplaced() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.parent) }
        let newTarget = item.parent.appendingPathComponent("other.circlr")
        let project = try ProjectStore.load(item.target).project
        let staged = try ProjectStore.prepareSessionSave(project, to: newTarget, mediaRoot: item.target)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newTarget.path))
        let external = try ProjectStore.save(project, to: newTarget, mediaRoot: item.target)
        let externalManifest = try Data(contentsOf: newTarget.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try ProjectStore.publishSessionSaveReportingCleanup(staged) { _ in })
        XCTAssertEqual(try Data(contentsOf: newTarget.appendingPathComponent("manifest.json")), externalManifest)
        XCTAssertEqual(try ProjectStore.load(newTarget).project, external)
        XCTAssertTrue(try stagedNames(in: item.parent).isEmpty)
    }

    func testCancellationDuringMediaCopyLeavesTargetAndSourceUntouched() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.parent) }
        let largeSource = item.parent.appendingPathComponent("large.wav")
        let largeBytes = Data(repeating: 0xA7, count: 6_000_000)
        try largeBytes.write(to: largeSource)
        var edited = try ProjectStore.load(item.target).project
        edited.name = "취소되어야 할 편집"
        edited.assets = [Asset(name: "large take", path: largeSource.path,
                               duration: 3, sampleRate: 48_000)]
        var checks = 0
        XCTAssertThrowsError(try ProjectStore.prepareSessionSave(edited, to: item.target,
                              mediaRoot: item.target, checkCancellation: {
            checks += 1
            if checks == 7 { throw CancellationError() }
        })) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertGreaterThanOrEqual(checks, 7, "복사 루프가 시작된 뒤 취소되어야 합니다")
        XCTAssertEqual(try Data(contentsOf: item.target.appendingPathComponent("manifest.json")), item.oldManifest)
        XCTAssertEqual(try Data(contentsOf: largeSource), largeBytes)
        XCTAssertTrue(try stagedNames(in: item.parent).isEmpty)
    }

    func testDiscardDoesNotDeleteReplacementAtStagePath() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.parent) }
        let project = try ProjectStore.load(item.target).project
        let staged = try ProjectStore.prepareSessionSave(project, to: item.target, mediaRoot: item.target)
        let stage = item.parent.appendingPathComponent(try XCTUnwrap(stagedNames(in: item.parent).first))
        let movedStage = item.parent.appendingPathComponent("held-stage")
        try FileManager.default.moveItem(at: stage, to: movedStage)
        let nested = stage.appendingPathComponent("user-data")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let marker = nested.appendingPathComponent("do-not-delete.txt")
        let markerBytes = Data("external replacement".utf8)
        try markerBytes.write(to: marker)
        ProjectStore.discard(staged)
        XCTAssertEqual(try Data(contentsOf: marker), markerBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedStage.path))
        XCTAssertEqual(try Data(contentsOf: item.target.appendingPathComponent("manifest.json")), item.oldManifest)
    }

    func testFailedPublishDoesNotDeleteReplacementAtStagePath() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.parent) }
        let project = try ProjectStore.load(item.target).project
        let staged = try ProjectStore.prepareSessionSave(project, to: item.target, mediaRoot: item.target)
        let stage = item.parent.appendingPathComponent(try XCTUnwrap(stagedNames(in: item.parent).first))
        try FileManager.default.moveItem(at: stage, to: item.parent.appendingPathComponent("held-stage"))
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let marker = stage.appendingPathComponent("do-not-delete.txt")
        let markerBytes = Data("external replacement".utf8)
        try markerBytes.write(to: marker)
        XCTAssertThrowsError(try ProjectStore.publishSessionSaveReportingCleanup(staged) { _ in })
        XCTAssertEqual(try Data(contentsOf: marker), markerBytes)
        XCTAssertEqual(try Data(contentsOf: item.target.appendingPathComponent("manifest.json")), item.oldManifest)
    }
}
