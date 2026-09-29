import Foundation
import Darwin
import XCTest
@testable import CirclrCore

final class ProjectPublicationProcessTests: XCTestCase {
    func testKillBeforeAndImmediatelyAfterAtomicPublicationLeavesCompleteProject() throws {
        for mode in ["before-publication", "after-publication"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-publish-process-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let oldBytes = Data(repeating: 0x31, count: 8193)
            let newBytes = Data(repeating: 0x72, count: 16385)
            let oldSource = root.appendingPathComponent("old.wav")
            let newSource = root.appendingPathComponent("new.wav")
            try oldBytes.write(to: oldSource); try newBytes.write(to: newSource)
            var old = try ProjectStarters.make(id: "blank")
            old.name = "old complete"
            old.assets = [Asset(name: "audio", path: oldSource.path, duration: 1, sampleRate: 48000)]
            let target = root.appendingPathComponent("song.circlr")
            let saved = try ProjectStore.save(old, to: target, mediaRoot: nil)
            let oldManifest = try Data(contentsOf: target.appendingPathComponent("manifest.json"))
            let child = try StorageProcessFixture.launch(root: root, mode: mode,
                test: "CirclrCoreTests.ProjectPublicationProcessTests/testPublicationChildHarness")
            defer { StorageProcessFixture.killAndWait(child) }
            try StorageProcessFixture.awaitMarker("publication-ready", root: root, process: child)
            StorageProcessFixture.killAndWait(child)
            XCTAssertEqual(child.terminationReason, .uncaughtSignal)
            XCTAssertEqual(child.terminationStatus, SIGKILL)

            let reopened = try ProjectStore.load(target).project
            XCTAssertEqual(reopened.id, saved.id)
            let asset = try XCTUnwrap(reopened.assets.first)
            let media = try Data(contentsOf: ProjectStore.assetURL(asset, root: target))
            if mode == "before-publication" {
                XCTAssertEqual(reopened.name, "old complete")
                XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("manifest.json")), oldManifest)
                XCTAssertEqual(media, oldBytes)
            } else {
                XCTAssertEqual(reopened.name, "new complete")
                XCTAssertEqual(media, newBytes)
                // RENAME_SWAP retains the complete previous package at the stage path.
                let stages = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix(".circlr-save-") }
                XCTAssertEqual(stages.count, 1)
                let previousURL = try XCTUnwrap(stages.first)
                let previous = try ProjectStore.load(previousURL).project
                XCTAssertEqual(previous.name, "old complete")
                XCTAssertEqual(try Data(contentsOf: previousURL.appendingPathComponent("manifest.json")), oldManifest)
                XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(previous.assets[0], root: previousURL)), oldBytes)
            }
            XCTAssertEqual(try Data(contentsOf: oldSource), oldBytes)
            XCTAssertEqual(try Data(contentsOf: newSource), newBytes)
        }
    }

    func testKillDuringPartialMediaCopyLeavesOldPublicPackageComplete() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-midcopy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldBytes = Data(repeating: 0x31, count: 8193)
        let newBytes = Data(repeating: 0x72, count: 6_291_457)
        let oldSource = root.appendingPathComponent("old.wav"), newSource = root.appendingPathComponent("new.wav")
        try oldBytes.write(to: oldSource); try newBytes.write(to: newSource)
        var project = try ProjectStarters.make(id: "blank")
        project.assets = [Asset(name: "audio", path: oldSource.path, duration: 1, sampleRate: 48000)]
        let target = root.appendingPathComponent("song.circlr")
        _ = try ProjectStore.save(project, to: target, mediaRoot: nil)
        let manifest = try Data(contentsOf: target.appendingPathComponent("manifest.json"))
        let child = try StorageProcessFixture.launch(root: root, mode: "midcopy",
            test: "CirclrCoreTests.ProjectPublicationProcessTests/testPublicationChildHarness")
        defer { StorageProcessFixture.killAndWait(child) }
        try StorageProcessFixture.awaitMarker("midcopy-ready", root: root, process: child)
        StorageProcessFixture.killAndWait(child)
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGKILL)
        let reopened = try ProjectStore.load(target).project
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("manifest.json")), manifest)
        XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(reopened.assets[0], root: target)), oldBytes)
        XCTAssertEqual(try Data(contentsOf: oldSource), oldBytes)
        XCTAssertEqual(try Data(contentsOf: newSource), newBytes)
        let stages = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".circlr-save-") }
        XCTAssertEqual(stages.count, 1)
        let stage = try XCTUnwrap(stages.first)
        let partial = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: stage.appendingPathComponent("media"), includingPropertiesForKeys: nil).first)
        let count = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? NSNumber).intValue
        XCTAssertGreaterThanOrEqual(count, 1_048_576)
        XCTAssertLessThan(count, newBytes.count)
        XCTAssertThrowsError(try ProjectStore.load(stage), "Unfinished private stage must not load as a complete project")
    }

    func testPublicationChildHarness() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[StorageProcessFixture.rootKey],
              let mode = environment[StorageProcessFixture.modeKey] else { throw XCTSkip("Child-only publication fixture") }
        let root = URL(fileURLWithPath: path), target = root.appendingPathComponent("song.circlr")
        var project = try ProjectStore.load(target).project
        project.name = "new complete"
        let replacement = root.appendingPathComponent("new.wav")
        project.assets[0].path = replacement.path
        project.assets[0].checksum = try ProjectStore.checksum(replacement)
        if mode == "midcopy" {
            _ = try ProjectStore.prepareSessionSave(project, to: target, mediaRoot: target, checkCancellation: {
                let stages = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.hasPrefix(".circlr-save-") }
                for stage in stages {
                    for file in try FileManager.default.contentsOfDirectory(at: stage.appendingPathComponent("media"), includingPropertiesForKeys: nil) {
                        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
                        if size >= 1_048_576 && size < 6_291_457 {
                            try StorageProcessFixture.hold(marker: "midcopy-ready", root: root)
                        }
                    }
                }
            })
            XCTFail("Midcopy child unexpectedly completed")
            return
        }
        let staged = try ProjectStore.prepareSessionSave(project, to: target, mediaRoot: target)
        if mode == "before-publication" {
            try StorageProcessFixture.hold(marker: "publication-ready", root: root)
        } else if mode == "after-publication" {
            _ = try ProjectStore.publishSessionSaveReportingCleanup(staged, onCleanupWarning: { _ in }, afterPublication: {
                do { try StorageProcessFixture.hold(marker: "publication-ready", root: root) }
                catch { XCTFail("Publication child barrier failed: \(error)") }
            })
        } else { XCTFail("Unexpected child mode") }
    }
}
