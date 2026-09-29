import Darwin
import Foundation
import XCTest
@testable import CirclrCore

final class ProjectStorageFailureTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let destination: URL
        let source: URL
        let target: URL
        let project: Project
        let manifest: Data
        let bytes: Data
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.wav")
        let bytes = Data(repeating: 0x6A, count: 3_145_729)
        try bytes.write(to: source)
        var project = try ProjectStarters.make(id: "blank")
        project.assets = [Asset(name: "storage bytes", path: source.path, duration: 1, sampleRate: 48_000)]
        let target = destination.appendingPathComponent("song.circlr")
        _ = try ProjectStore.save(project, to: target, mediaRoot: nil)
        return Fixture(root: root, destination: destination, source: source, target: target,
                       project: project, manifest: try Data(contentsOf: target.appendingPathComponent("manifest.json")), bytes: bytes)
    }

    private func stages(_ item: Fixture) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: item.destination, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".circlr-save-") }
    }

    private func copiedBytes(_ item: Fixture) throws -> Int {
        var total = 0
        for stage in try stages(item) {
            for file in try FileManager.default.contentsOfDirectory(at: stage.appendingPathComponent("media"), includingPropertiesForKeys: nil) {
                total += (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
            }
        }
        return total
    }

    private func assertOldPackage(_ item: Fixture, sourceExists: Bool = true) throws {
        XCTAssertEqual(try Data(contentsOf: item.target.appendingPathComponent("manifest.json")), item.manifest)
        let loaded = try ProjectStore.load(item.target).project
        XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(loaded.assets[0], root: item.target)), item.bytes)
        if sourceExists { XCTAssertEqual(try Data(contentsOf: item.source), item.bytes) }
    }

    func testPreparePermissionDeniedPreservesOldPackageThenRetrySucceeds() throws {
        try XCTSkipIf(geteuid() == 0, "root bypasses permission fixture")
        let item = try fixture()
        defer { chmod(item.destination.path, 0o700); try? FileManager.default.removeItem(at: item.root) }
        XCTAssertEqual(chmod(item.destination.path, 0o500), 0)
        XCTAssertThrowsError(try ProjectStore.prepareSessionSave(item.project, to: item.target, mediaRoot: nil))
        XCTAssertEqual(chmod(item.destination.path, 0o700), 0)
        try assertOldPackage(item)
        XCTAssertTrue(try stages(item).isEmpty)
        let retry = try ProjectStore.prepareSessionSave(item.project, to: item.target, mediaRoot: nil)
        _ = try ProjectStore.publishSessionSaveReportingCleanup(retry) { XCTFail($0) }
        try assertOldPackage(item)
    }

    func testPublicationPermissionLossPreservesOldPackageAndCanRetry() throws {
        try XCTSkipIf(geteuid() == 0, "root bypasses permission fixture")
        let item = try fixture()
        defer { chmod(item.destination.path, 0o700); try? FileManager.default.removeItem(at: item.root) }
        var edited = item.project
        edited.name = "updated"
        let staged = try ProjectStore.prepareSessionSave(edited, to: item.target, mediaRoot: nil)
        XCTAssertEqual(chmod(item.destination.path, 0o500), 0)
        XCTAssertThrowsError(try ProjectStore.publishSessionSaveReportingCleanup(staged) { XCTFail($0) })
        XCTAssertEqual(chmod(item.destination.path, 0o700), 0)
        try assertOldPackage(item)
        let retry = try ProjectStore.prepareSessionSave(edited, to: item.target, mediaRoot: nil)
        _ = try ProjectStore.publishSessionSaveReportingCleanup(retry) { XCTFail($0) }
        XCTAssertEqual(try ProjectStore.load(item.target).project.name, "updated")
        XCTAssertEqual(try Data(contentsOf: item.source), item.bytes)
    }

    func testInjectedNoSpaceAfterPartialCopyCleansStageAndPreservesOldPackage() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.root) }
        var injected = false
        XCTAssertThrowsError(try ProjectStore.prepareSessionSave(item.project, to: item.target, mediaRoot: nil, checkCancellation: {
            if try self.copiedBytes(item) >= 1_048_576 {
                injected = true
                // Error propagation/cleanup proof only, not a kernel-full volume test.
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
            }
        })) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(ENOSPC))
        }
        XCTAssertTrue(injected)
        try assertOldPackage(item)
        XCTAssertTrue(try stages(item).isEmpty)
        let retry = try ProjectStore.prepareSessionSave(item.project, to: item.target, mediaRoot: nil)
        _ = try ProjectStore.publishSessionSaveReportingCleanup(retry) { XCTFail($0) }
    }

    func testSourceDisappearsAfterPreflightPreservesOldPackage() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.root) }
        var removed = false
        XCTAssertThrowsError(try ProjectStore.prepareSessionSave(item.project, to: item.target, mediaRoot: nil, checkCancellation: {
            if !removed, !(try self.stages(item)).isEmpty {
                try FileManager.default.removeItem(at: item.source)
                removed = true
            }
        }))
        XCTAssertTrue(removed)
        try assertOldPackage(item, sourceExists: false)
        XCTAssertTrue(try stages(item).isEmpty)
        try item.bytes.write(to: item.source)
        let retry = try ProjectStore.prepareSessionSave(item.project, to: item.target, mediaRoot: nil)
        _ = try ProjectStore.publishSessionSaveReportingCleanup(retry) { XCTFail($0) }
    }

    func testCancelNewDestinationAfterPartialCopyPublishesNothing() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.root) }
        let newTarget = item.destination.appendingPathComponent("new.circlr")
        var cancelled = false
        XCTAssertThrowsError(try ProjectStore.prepareSessionSave(item.project, to: newTarget, mediaRoot: nil, checkCancellation: {
            if try self.copiedBytes(item) >= 1_048_576 { cancelled = true; throw CancellationError() }
        })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertTrue(cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newTarget.path))
        XCTAssertTrue(try stages(item).isEmpty)
        try assertOldPackage(item)
    }
    func testForeignMarkerAfterPublicationPreservesNewTargetAndWarnsWithoutDeletingMarker() throws {
        let item = try fixture()
        defer { try? FileManager.default.removeItem(at: item.root) }
        var edited = item.project
        edited.name = "published despite cleanup warning"
        let staged = try ProjectStore.prepareSessionSave(edited, to: item.target, mediaRoot: nil)
        let oldStage = try XCTUnwrap(try stages(item).first)
        let markerBytes = Data("foreign data must survive cleanup".utf8)
        var inserted = false
        var warnings: [String] = []
        let result = try ProjectStore.publishSessionSaveReportingCleanup(staged, onCleanupWarning: { warnings.append($0) }, afterPublication: {
            do {
                try markerBytes.write(to: oldStage.appendingPathComponent("foreign.txt"))
                inserted = true
            } catch { XCTFail("Failed to insert foreign cleanup marker: \(error)") }
        })
        XCTAssertTrue(inserted)
        XCTAssertEqual(result.name, edited.name)
        XCTAssertEqual(warnings.count, 1)
        let published = try ProjectStore.load(item.target).project
        XCTAssertEqual(published.name, edited.name)
        XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(published.assets[0], root: item.target)), item.bytes)
        XCTAssertEqual(try Data(contentsOf: item.source), item.bytes)
        let leftovers = try FileManager.default.contentsOfDirectory(at: item.destination, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".circlr-backup-") || $0.lastPathComponent.hasPrefix(".circlr-save-") }
        XCTAssertEqual(leftovers.count, 1)
        let preserved = try XCTUnwrap(leftovers.first)
        XCTAssertEqual(try Data(contentsOf: preserved.appendingPathComponent("foreign.txt")), markerBytes)
        XCTAssertEqual(try Data(contentsOf: preserved.appendingPathComponent("manifest.json")), item.manifest)
        let warning = try XCTUnwrap(warnings.first)
        let prefix = "저장은 완료됐습니다. 이전 곡 사본의 일부가 "
        let suffix = "에 남아 있을 수 있습니다"
        XCTAssertTrue(warning.hasPrefix(prefix), "Unexpected cleanup warning: \(warning)")
        XCTAssertTrue(warning.hasSuffix(suffix), "Unexpected cleanup warning: \(warning)")
        let reportedPath = String(warning.dropFirst(prefix.count).dropLast(suffix.count))
        let reported = URL(fileURLWithPath: reportedPath)
        // Foundation enumeration may expand /var to /private/var on macOS.
        // Verify the reported location resolves to the actual retained directory
        // and that it can read the protected bytes, rather than comparing spellings.
        XCTAssertEqual(reported.standardizedFileURL.resolvingSymlinksInPath().path,
                       preserved.standardizedFileURL.resolvingSymlinksInPath().path,
                       "Warning: \(warning); enumerated backup: \(preserved.path)")
        XCTAssertEqual(try Data(contentsOf: reported.appendingPathComponent("foreign.txt")), markerBytes)
        XCTAssertEqual(try Data(contentsOf: reported.appendingPathComponent("manifest.json")), item.manifest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.target.appendingPathComponent("foreign.txt").path))
    }

}
