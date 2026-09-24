import Foundation
import XCTest
@testable import CirclrApp

private final class ExportCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    func check() throws {
        lock.lock()
        calls += 1
        let shouldCancel = calls >= 3
        lock.unlock()
        if shouldCancel { throw CancellationError() }
    }
}

final class TrustedExportPublisherTests: XCTestCase {
    private func fixture() throws -> (root: URL, folder: URL, stage: URL, output: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("circlr-export-publisher-\(UUID().uuidString)",
                                    isDirectory: true)
        let folder = root.appendingPathComponent("selected", isDirectory: true)
        let privateFolder = root.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: privateFolder,
                                                withIntermediateDirectories: true)
        let stage = privateFolder.appendingPathComponent("render.wav")
        try Data("RIFFtestWAVE".utf8).write(to: stage)
        return (root, folder, stage, folder.appendingPathComponent("render.wav"))
    }

    private func hiddenFiles(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(".circlr-agent-export-") }
    }

    func testPublishesExactBytesExclusivelyAndRemovesHiddenTemp() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let destination = try TrustedExportPublisher.capture(destination: f.output)
        XCTAssertEqual(destination.url, f.output)
        let prepared = try TrustedExportPublisher.prepare(source: f.stage,
                                                          destination: destination)
        var authorized = false
        try prepared.publish { authorized = true }
        XCTAssertTrue(authorized)
        XCTAssertEqual(try Data(contentsOf: f.output), Data("RIFFtestWAVE".utf8))
        XCTAssertTrue(try hiddenFiles(in: f.folder).isEmpty)
        prepared.discard()
        XCTAssertEqual(try Data(contentsOf: f.output), Data("RIFFtestWAVE".utf8))
    }

    func testReplacedParentAfterPreparationCannotPublishIntoReplacement() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let destination = try TrustedExportPublisher.capture(destination: f.output)
        let prepared = try TrustedExportPublisher.prepare(source: f.stage,
                                                          destination: destination)
        let renamed = f.root.appendingPathComponent("old-selected")
        try FileManager.default.moveItem(at: f.folder, to: renamed)
        try FileManager.default.createDirectory(at: f.folder,
                                                withIntermediateDirectories: false)
        XCTAssertThrowsError(try prepared.publish(authorize: {}))
        prepared.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.output.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: renamed.appendingPathComponent("render.wav").path))
        XCTAssertTrue(try hiddenFiles(in: renamed).isEmpty)
    }

    func testSymlinkReplacementOfSelectedParentIsRejected() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let destination = try TrustedExportPublisher.capture(destination: f.output)
        let other = f.root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other,
                                                withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: f.folder)
        try FileManager.default.createSymbolicLink(at: f.folder, withDestinationURL: other)
        XCTAssertThrowsError(try TrustedExportPublisher.prepare(source: f.stage,
                                                                 destination: destination))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: other.appendingPathComponent("render.wav").path))
        XCTAssertTrue(try hiddenFiles(in: other).isEmpty)
    }

    func testDestinationCollisionPreservesExistingFile() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let destination = try TrustedExportPublisher.capture(destination: f.output)
        let prepared = try TrustedExportPublisher.prepare(source: f.stage,
                                                          destination: destination)
        let existing = Data("existing song".utf8)
        try existing.write(to: f.output)
        XCTAssertThrowsError(try prepared.publish(authorize: {}))
        prepared.discard()
        XCTAssertEqual(try Data(contentsOf: f.output), existing)
        XCTAssertTrue(try hiddenFiles(in: f.folder).isEmpty)
    }

    func testCancellationDuringCopyRemovesOnlyOwnedTemp() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try Data(repeating: 0x7F, count: 2_200_000).write(to: f.stage)
        let destination = try TrustedExportPublisher.capture(destination: f.output)
        let gate = ExportCancellationGate()
        XCTAssertThrowsError(try TrustedExportPublisher.prepare(
            source: f.stage, destination: destination,
            checkCancellation: { try gate.check() })) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.output.path))
        XCTAssertTrue(try hiddenFiles(in: f.folder).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.stage.path))
    }
}
