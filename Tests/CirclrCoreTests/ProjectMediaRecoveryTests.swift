import Foundation
import XCTest
import AVFoundation
@testable import CirclrCore

final class ProjectMediaRecoveryTests: XCTestCase {
    private func fixture() throws -> (URL, URL, Project) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("한글 소스.wav")
        try Data(repeating: 91, count: 8192).write(to: source)
        var project = try ProjectStarters.make(id: "blank")
        project.assets = [Asset(name: "take", path: source.path, duration: 1, sampleRate: 48000)]
        project.assets[0].checksum = try ProjectStore.checksum(source)
        return (root, source, project)
    }
    func testExplicitRelinkRejectsSameNameDifferentBytesAndPreservesProject() throws {
        let (root, source, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let moved = root.appendingPathComponent("이동.wav")
        try FileManager.default.moveItem(at: source, to: moved)
        XCTAssertEqual(try ProjectMediaRelink.diagnostics(project: project, root: nil).map(\.assetID), [project.assets[0].id])
        try Data(repeating: 17, count: 8192).write(to: source)
        XCTAssertThrowsError(try ProjectMediaRelink.relink(project: project, root: nil, assetID: project.assets[0].id, candidate: source))
        let repaired = try ProjectMediaRelink.relink(project: project, root: nil, assetID: project.assets[0].id, candidate: moved)
        XCTAssertEqual(repaired.assets[0].path, moved.path)
        XCTAssertEqual(project.assets[0].path, source.path)
    }
    func testRelinkedMissingPackageCanSaveOverOriginalAndReopen() throws {
        let (root, source, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("song.circlr")
        let stored = try ProjectStore.save(project, to: target, mediaRoot: nil)
        let missing = try ProjectStore.assetURL(stored.assets[0], root: target)
        try FileManager.default.removeItem(at: missing)
        let repaired = try ProjectMediaRelink.relink(project: stored, root: target, assetID: stored.assets[0].id, candidate: source)
        let saved = try ProjectStore.save(repaired, to: target, mediaRoot: target)
        XCTAssertEqual(try ProjectStore.load(target).project, saved)
        XCTAssertEqual(try ProjectStore.checksum(ProjectStore.assetURL(saved.assets[0], root: target)), project.assets[0].checksum)
    }
    func testMissingTargetAssetAppearingDuringStageRejectsAndPreservesIt() throws {
        let (root, source, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("song.circlr")
        let stored = try ProjectStore.save(project, to: target, mediaRoot: nil)
        let missing = try ProjectStore.assetURL(stored.assets[0], root: target)
        try FileManager.default.removeItem(at: missing)
        let repaired = try ProjectMediaRelink.relink(project: stored, root: target, assetID: stored.assets[0].id, candidate: source)
        let stage = try ProjectStore.prepareSave(repaired, to: target, mediaRoot: target)
        let external = Data([1, 2, 3])
        try external.write(to: missing)
        XCTAssertThrowsError(try ProjectStore.publishSessionSaveReportingCleanup(stage) { _ in })
        XCTAssertEqual(try Data(contentsOf: missing), external)
    }
    func testPortablePreflightCountsEveryAssetCopyRejectsMissingAndSymlink() throws {
        let (root, source, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var doubled = project
        var duplicate = project.assets[0]; duplicate.id = newID(); doubled.assets.append(duplicate)
        let info = try ProjectStore.portableCopyPreflight(project: doubled, mediaRoot: nil, destination: root.appendingPathComponent("copy.circlr"))
        XCTAssertEqual(info.assetCount, 2); XCTAssertEqual(info.mediaBytes, 16384)
        XCTAssertGreaterThan(info.requiredBytes, info.mediaBytes)
        let link = root.appendingPathComponent("link.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try ProjectMediaRelink.relink(project: project, root: nil, assetID: project.assets[0].id, candidate: link))
        try FileManager.default.removeItem(at: source)
        XCTAssertThrowsError(try ProjectStore.portableCopyPreflight(project: project, mediaRoot: nil, destination: root.appendingPathComponent("copy.circlr")))
    }
    func testLegacyCandidateRequiresExplicitConsentAndAudioValidation() throws {
        let (root, source, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var legacy = project; legacy.assets[0].checksum = ""
        XCTAssertThrowsError(try ProjectMediaRelink.relink(project: legacy, root: nil, assetID: legacy.assets[0].id, candidate: source))
        XCTAssertThrowsError(try ProjectMediaRelink.relink(project: legacy, root: nil, assetID: legacy.assets[0].id, candidate: source, allowUnverified: true))
    }
    func testLegacyExplicitAudioRelinkChecksDurationAndRecordsFingerprint() throws {
        let (root, _, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("valid.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            try file.write(from: buffer)
        }
        var project = original
        project.assets[0].checksum = ""; project.assets[0].duration = 0.01
        let relinked = try ProjectMediaRelink.relink(project: project, root: nil, assetID: project.assets[0].id, candidate: source, allowUnverified: true)
        XCTAssertEqual(relinked.assets[0].checksum, try ProjectStore.checksum(source))
        project.assets[0].duration = 2
        XCTAssertThrowsError(try ProjectMediaRelink.relink(project: project, root: nil, assetID: project.assets[0].id, candidate: source, allowUnverified: true))
    }
    func testDiagnosticsDetectsChangedBytesAndCancellationIsNotPartialSuccess() throws {
        let (root, source, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([99]).write(to: source)
        let issues = try ProjectMediaRelink.diagnostics(project: project, root: nil)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.reason, "미디어 내용이 저장된 원본과 다릅니다")
        XCTAssertThrowsError(try ProjectMediaRelink.diagnostics(project: project, root: nil, checkCancellation: { throw CancellationError() })) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertThrowsError(try ProjectStore.portableCopyPreflight(project: project, mediaRoot: nil, destination: root.appendingPathComponent("copy.circlr"), checkCancellation: { throw CancellationError() }))
    }

    func testPreparedRelinkRejectsCandidateReplacementBeforeCommit() throws {
        let (root, source, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try ProjectMediaRelink.prepareRelink(project: project, root: nil, assetID: project.assets[0].id, candidate: source)
        try receipt.validateCandidate()
        try Data(repeating: 91, count: 8192).write(to: source, options: .atomic)
        XCTAssertThrowsError(try receipt.validateCandidate())
    }
    func testSaveRejectsChangedKnownSourceAndPreservesExistingPackage() throws {
        let (root, source, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("song.circlr")
        _ = try ProjectStore.save(project, to: target, mediaRoot: nil)
        let manifest = try Data(contentsOf: target.appendingPathComponent("manifest.json"))
        try Data([7, 8, 9]).write(to: source)
        XCTAssertThrowsError(try ProjectStore.save(project, to: target, mediaRoot: nil))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("manifest.json")), manifest)
        XCTAssertEqual(try ProjectStore.load(target).project.assets[0].checksum, project.assets[0].checksum)
    }

    func testUnicodeAndCaseCandidateNamesUseContentNotFilename() throws {
        let (root, source, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try Data(contentsOf: source)
        try FileManager.default.removeItem(at: source)
        let names = ["Café.wav", "Cafe\u{301}.wav", "LEAD.WAV", "lead.wav"]
        XCTAssertNotEqual(Array(names[0].utf8), Array(names[1].utf8))
        for (index, name) in names.enumerated() {
            // Separate directories avoid claiming distinct same-directory files
            // on a normalization-insensitive or case-insensitive filesystem.
            let folder = root.appendingPathComponent("candidate-\(index)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let candidate = folder.appendingPathComponent(name)
            try data.write(to: candidate)
            let repaired = try ProjectMediaRelink.relink(project: project, root: nil, assetID: project.assets[0].id, candidate: candidate)
            XCTAssertEqual(repaired.assets[0].id, project.assets[0].id)
            XCTAssertEqual(try ProjectStore.checksum(URL(fileURLWithPath: repaired.assets[0].path)), project.assets[0].checksum)
            XCTAssertEqual(project.assets[0].path, source.path)
            // Even the explicitly selected normalization/case variant must fail
            // once its bytes differ. No name similarity grants authority.
            try Data([UInt8(index)]).write(to: candidate)
            XCTAssertThrowsError(try ProjectMediaRelink.relink(project: project, root: nil, assetID: project.assets[0].id, candidate: candidate))
        }
    }

    func testDuplicateSourceAssetsKeepIDsNamesAndIndependentPortablePaths() throws {
        let (root, source, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var project = original
        project.assets[0].name = "Café"
        var duplicate = project.assets[0]
        duplicate.id = newID(); duplicate.name = "Cafe\u{301}"
        project.assets.append(duplicate)
        let ids = project.assets.map(\.id)
        let names = project.assets.map { Array($0.name.utf8) }
        let sourceBytes = try Data(contentsOf: source)
        let moved = root.appendingPathComponent("MOVED.WAV")
        try FileManager.default.moveItem(at: source, to: moved)
        let one = try ProjectMediaRelink.relink(project: project, root: nil, assetID: ids[0], candidate: moved)
        XCTAssertEqual(one.assets[1], project.assets[1])
        XCTAssertEqual(try ProjectMediaRelink.diagnostics(project: one, root: nil).map(\.assetID), [ids[1]])
        let both = try ProjectMediaRelink.relink(project: one, root: nil, assetID: ids[1], candidate: moved)
        let target = root.appendingPathComponent("duplicate-source.circlr")
        _ = try ProjectStore.save(both, to: target, mediaRoot: nil)
        let reopened = try ProjectStore.load(target).project
        XCTAssertEqual(reopened.assets.map(\.id), ids)
        XCTAssertEqual(reopened.assets.map { Array($0.name.utf8) }, names)
        XCTAssertEqual(Set(reopened.assets.map(\.path)).count, 2)
        for asset in reopened.assets {
            XCTAssertFalse(asset.path.hasPrefix("/"))
            XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(asset, root: target)), sourceBytes)
            XCTAssertEqual(asset.checksum, original.assets[0].checksum)
        }
        XCTAssertEqual(try Data(contentsOf: moved), sourceBytes)
    }

    func testRecordActualFilesystemNormalizationAndCaseLookupBehavior() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nfc = root.appendingPathComponent("Café.wav")
        let nfd = root.appendingPathComponent("Cafe\u{301}.wav")
        let mixed = root.appendingPathComponent("Lead.WAV")
        let lower = root.appendingPathComponent("lead.wav")
        try Data([1, 2, 3]).write(to: nfc)
        try Data([4, 5, 6]).write(to: mixed)
        func sameFile(_ original: URL, _ alias: URL) throws -> Bool {
            guard FileManager.default.fileExists(atPath: alias.path) else { return false }
            let originalID = try FileManager.default.attributesOfItem(atPath: original.path)[.systemFileNumber] as? NSNumber
            let aliasID = try FileManager.default.attributesOfItem(atPath: alias.path)[.systemFileNumber] as? NSNumber
            XCTAssertNotNil(originalID); XCTAssertEqual(originalID, aliasID)
            XCTAssertEqual(try Data(contentsOf: original), try Data(contentsOf: alias))
            return originalID == aliasID
        }
        let observation: [String: Any] = [
            "nfc_nfd_lookup_same_inode": try sameFile(nfc, nfd),
            "case_variant_lookup_same_inode": try sameFile(mixed, lower),
            "created_file_count": try FileManager.default.contentsOfDirectory(atPath: root.path).count,
            "enumerated_filename_utf8": try FileManager.default.contentsOfDirectory(atPath: root.path).sorted().map { Array($0.utf8) }
        ]
        XCTAssertEqual(observation["created_file_count"] as? Int, 2)
        let bytes = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
        print("R130_MEDIA_PATH_OBSERVATION " + String(decoding: bytes, as: UTF8.self))
    }

}
