import Foundation
import Darwin
import XCTest
@testable import CirclrCore

final class ProjectDiskFullTests: XCTestCase {
    private func volume() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["CIRCLR_DISK_FULL_TEST_VOLUME"] else {
            throw XCTSkip("Requires dedicated <= 80 MiB mounted QA disk image")
        }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard url.path.contains("/.build/r130-disk-full/"), url.lastPathComponent == "mount" else {
            throw NSError(domain: "UnsafeDiskFullFixture", code: 1)
        }
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        let size = try XCTUnwrap(attributes[.systemSize] as? NSNumber).int64Value
        guard size > 0, size <= 80 * 1024 * 1024 else { throw NSError(domain: "UnsafeDiskFullFixture", code: 2) }
        return url
    }

    /// Consume only the bounded mounted image. Return the actual kernel write errno,
    /// not an injected failure. Product preparation resumes after this function.
    private func fill(_ url: URL) throws -> (Int64, Int32) {
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { _ = Darwin.close(fd) }
        let bytes = [UInt8](repeating: 0xD7, count: 65536)
        var total: Int64 = 0
        var chunkSize = bytes.count
        while total < 80 * 1024 * 1024 {
            let count = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, chunkSize) }
            if count < 0 {
                if errno == EINTR { continue }
                if errno == ENOSPC, chunkSize > 1 { chunkSize = max(1, chunkSize / 16); continue }
                return (total, errno)
            }
            guard count > 0 else { throw NSError(domain: "DiskFullFixture", code: 3) }
            total += Int64(count)
        }
        throw NSError(domain: "UnsafeDiskFullFixture", code: 4)
    }

    private func isNoSpace(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC) { return true }
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isNoSpace(underlying) }
        return false
    }

    func testKernelDiskFullDuringCopyAndManifestPreservesPreviousPackageThenRetries() throws {
        let mount = try volume()
        for phase in ["copy", "manifest"] {
            let root = mount.appendingPathComponent("fixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("source.wav")
            let bytes = Data(repeating: 0x51, count: 2_097_153)
            try bytes.write(to: source)
            var project = try ProjectStarters.make(id: "blank")
            project.assets = [Asset(name: "source", path: source.path, duration: 1, sampleRate: 48000)]
            let target = root.appendingPathComponent("song.circlr")
            _ = try ProjectStore.save(project, to: target, mediaRoot: nil)
            let oldManifest = try Data(contentsOf: target.appendingPathComponent("manifest.json"))
            let oldProject = try ProjectStore.load(target).project
            project.name = "successful retry \(phase)"
            if phase == "manifest" { project.name += String(repeating: "m", count: 65536) }
            let filler = root.appendingPathComponent("filler.bin")
            var filled = false, filledBytes: Int64 = 0, fillerErrno: Int32 = 0
            var productFailure: NSError?
            do {
                let stage = try ProjectStore.prepareSessionSave(project, to: target, mediaRoot: nil, checkCancellation: {
                    guard !filled else { return }
                    let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                        .filter { $0.lastPathComponent.hasPrefix(".circlr-save-") }
                    guard let folder = folders.first,
                          let media = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("media"), includingPropertiesForKeys: nil).first else { return }
                    let size = (try FileManager.default.attributesOfItem(atPath: media.path)[.size] as? NSNumber)?.intValue ?? -1
                    guard phase == "copy" ? size == 0 : size == bytes.count else { return }
                    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path))
                    filled = true
                    (filledBytes, fillerErrno) = try self.fill(filler)
                    // No throw here: the next real product write must encounter ENOSPC.
                })
                ProjectStore.discard(stage)
                XCTFail("Product write unexpectedly succeeded on full image: \(phase)")
            } catch { productFailure = error as NSError }
            XCTAssertTrue(filled)
            XCTAssertEqual(fillerErrno, ENOSPC)
            XCTAssertTrue(isNoSpace(try XCTUnwrap(productFailure)), "\(String(describing: productFailure))")
            XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("manifest.json")), oldManifest)
            XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(oldProject.assets[0], root: target)), bytes)
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            try FileManager.default.removeItem(at: filler)
            let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".circlr-") }
            if !remaining.isEmpty {
                let retained = try XCTUnwrap(productFailure?.userInfo["CirclrRetainedStageURL"] as? URL)
                XCTAssertTrue(productFailure?.localizedDescription.contains(retained.path) == true)
                XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
                XCTAssertTrue(remaining.contains(retained.lastPathComponent))
                XCTAssertThrowsError(try ProjectStore.load(retained), "Incomplete retained stage must not load as success")
                let retainedMedia = try FileManager.default.contentsOfDirectory(at: retained.appendingPathComponent("media"), includingPropertiesForKeys: nil)
                XCTAssertFalse(retainedMedia.isEmpty)
            }
            let retry = try ProjectStore.prepareSessionSave(project, to: target, mediaRoot: nil)
            _ = try ProjectStore.publishSessionSaveReportingCleanup(retry) { XCTFail($0) }
            let reopened = try ProjectStore.load(target).project
            XCTAssertEqual(reopened.name, project.name)
            XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(reopened.assets[0], root: target)), bytes)
            let observation: [String: Any] = ["phase": phase, "filler_bytes": filledBytes, "filler_errno": Int(fillerErrno), "product_error_domain": productFailure?.domain ?? "none", "product_error_code": productFailure?.code ?? 0, "source_bytes": bytes.count, "retry": "PASS", "stage_cleanup": remaining.isEmpty ? "PASS" : "RETAINED_WITH_VISIBLE_ERROR", "retained_stages": remaining]
            print("R130_DISK_FULL_OBSERVATION " + String(decoding: try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys]), as: UTF8.self))
        }
    }
    func testRestartedSaveAfterPublicationCrashPreservesAbandonedForeignData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-restarted-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldBytes = Data(repeating: 0x31, count: 8193), newBytes = Data(repeating: 0x72, count: 16385)
        let oldSource = root.appendingPathComponent("old.wav"), newSource = root.appendingPathComponent("new.wav")
        try oldBytes.write(to: oldSource); try newBytes.write(to: newSource)
        var original = try ProjectStarters.make(id: "blank")
        original.assets = [Asset(name: "original", path: oldSource.path, duration: 1, sampleRate: 48000)]
        let target = root.appendingPathComponent("song.circlr")
        _ = try ProjectStore.save(original, to: target, mediaRoot: nil)
        let oldManifest = try Data(contentsOf: target.appendingPathComponent("manifest.json"))
        let child = try StorageProcessFixture.launch(root: root, mode: "after-publication", test: "CirclrCoreTests.ProjectPublicationProcessTests/testPublicationChildHarness")
        defer { StorageProcessFixture.killAndWait(child) }
        try StorageProcessFixture.awaitMarker("publication-ready", root: root, process: child)
        StorageProcessFixture.killAndWait(child)
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGKILL)
        let orphan = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".circlr-save-") })
        let foreign = Data("foreign data retained across restarted subsequent save".utf8)
        try foreign.write(to: orphan.appendingPathComponent("foreign.txt"))
        let restarted = try StorageProcessFixture.launch(root: root, mode: "resave", test: "CirclrCoreTests.ProjectDiskFullTests/testRestartedSaveHarness")
        defer { StorageProcessFixture.killAndWait(restarted) }
        try StorageProcessFixture.finish(restarted)
        XCTAssertEqual(try Data(contentsOf: orphan.appendingPathComponent("foreign.txt")), foreign)
        XCTAssertEqual(try Data(contentsOf: orphan.appendingPathComponent("manifest.json")), oldManifest)
        let reopened = try ProjectStore.load(target).project
        XCTAssertEqual(reopened.name, "saved by fresh process")
        XCTAssertEqual(try Data(contentsOf: ProjectStore.assetURL(reopened.assets[0], root: target)), newBytes)
        XCTAssertEqual(try Data(contentsOf: oldSource), oldBytes)
        XCTAssertEqual(try Data(contentsOf: newSource), newBytes)
        print("R130_RESTARTED_SAVE_OBSERVATION foreign_preserved=true orphan_cleanup=not_implemented subsequent_save=PASS")
    }

    func testRestartedSaveHarness() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[StorageProcessFixture.rootKey], environment[StorageProcessFixture.modeKey] == "resave" else {
            throw XCTSkip("Child-only restarted save harness")
        }
        let target = URL(fileURLWithPath: path).appendingPathComponent("song.circlr")
        var project = try ProjectStore.load(target).project
        project.name = "saved by fresh process"
        _ = try ProjectStore.save(project, to: target, mediaRoot: target)
        XCTAssertEqual(try ProjectStore.load(target).project.name, project.name)
    }

    func testUnsupportedHFSOverwritePreservesOriginalAndAllowsNewLocationSave() throws {
        guard ProcessInfo.processInfo.environment["CIRCLR_DISK_FULL_HFS"] == "1" else { throw XCTSkip("HFS+ compatibility opt-in") }
        let mount = try volume()
        let root = mount.appendingPathComponent("hfs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var project = try ProjectStarters.make(id: "blank")
        let target = root.appendingPathComponent("original.circlr")
        _ = try ProjectStore.save(project, to: target, mediaRoot: nil)
        let bytes = try Data(contentsOf: target.appendingPathComponent("manifest.json"))
        project.name = "save as supported"
        do { _ = try ProjectStore.save(project, to: target, mediaRoot: nil); XCTFail("HFS+ overwrite should fail safely") }
        catch {
            let failure = error as NSError
            XCTAssertEqual(failure.domain, NSPOSIXErrorDomain)
            XCTAssertTrue([Int(ENOTSUP), Int(EINVAL)].contains(failure.code))
            XCTAssertTrue(failure.localizedDescription.contains("새 위치"))
            print("R130_HFS_OBSERVATION overwrite_errno=\(failure.code) source_preserved=true")
        }
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("manifest.json")), bytes)
        let alternate = root.appendingPathComponent("new-location.circlr")
        _ = try ProjectStore.save(project, to: alternate, mediaRoot: nil)
        XCTAssertEqual(try ProjectStore.load(alternate).project.name, project.name)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("manifest.json")), bytes)
    }

}
