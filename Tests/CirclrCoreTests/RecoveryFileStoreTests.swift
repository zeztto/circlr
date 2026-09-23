import XCTest
import Foundation
import Darwin
@testable import CirclrCore

final class RecoveryFileStoreTests: XCTestCase {
    private func makeSparseFile(at url:URL,size:off_t) throws {
        let fd=Darwin.open(url.path,O_CREAT | O_EXCL | O_WRONLY,mode_t(0o600))
        XCTAssertGreaterThanOrEqual(fd,0)
        guard fd >= 0 else{return}
        defer{_ = Darwin.close(fd)}
        XCTAssertEqual(Darwin.ftruncate(fd,size),0)
    }

    private func makeFIFO(at url:URL) {
        XCTAssertEqual(Darwin.mkfifo(url.path,mode_t(0o600)),0)
    }
    private func isFIFO(_ url:URL) -> Bool {
        var info=stat()
        return Darwin.lstat(url.path,&info) == 0 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFIFO)
    }

    func testOnlyProductionBundleIDUsesProductionDirectory() {
        XCTAssertEqual(RecoveryFileStore.storageDirectoryName(for:"com.circlr.desktop"),"circlr")
        XCTAssertEqual(RecoveryFileStore.storageDirectoryName(for:"com.circlr.build201qa"),"circlr-build201-qa")
        XCTAssertNotEqual(RecoveryFileStore.storageDirectoryName(for:nil),"circlr")
        let malformed=RecoveryFileStore.storageDirectoryName(for:"com.circlr.??qa")
        XCTAssertEqual(malformed,RecoveryFileStore.storageDirectoryName(for:"com.circlr.??qa"))
        XCTAssertNotEqual(malformed,RecoveryFileStore.storageDirectoryName(for:"com.circlr.!!qa"))
        XCTAssertNotEqual(malformed,"circlr")
        XCTAssertNotEqual(RecoveryFileStore.storageDirectoryName(for:"com.other.app"),"circlr")
    }

    func testRecoveryReadsRejectOversizedAndSpecialFilesWithoutChangingThem() throws {
        let url=try temporaryRecoveryURL()
        let store=try RecoveryFileStore(url:url)
        try makeSparseFile(at:url,size:64 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try store.read())
        XCTAssertThrowsError(try store.write(Data("new".utf8)))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.int64Value,64 * 1024 * 1024 + 1)
        try FileManager.default.removeItem(at:url)

        let target=url.deletingLastPathComponent().appendingPathComponent("original.json")
        let original=Data("original user bytes".utf8)
        try original.write(to:target)
        try FileManager.default.createSymbolicLink(at:url,withDestinationURL:target)
        XCTAssertThrowsError(try store.read())
        XCTAssertThrowsError(try store.write(Data("new".utf8)))
        XCTAssertEqual(try Data(contentsOf:target),original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath:url.path),target.path)
        try FileManager.default.removeItem(at:url)

        makeFIFO(at:url)
        XCTAssertThrowsError(try store.read())
        XCTAssertThrowsError(try store.write(Data("new".utf8)))
        XCTAssertTrue(isFIFO(url))
    }

    func testOversizedAutosaveWriteLeavesOwnedRecoveryUntouched() throws {
        let url=try temporaryRecoveryURL()
        let store=try RecoveryFileStore(url:url)
        let original=Data("owned recovery".utf8)
        XCTAssertTrue(try store.write(original))
        XCTAssertThrowsError(try store.write(Data(count:64 * 1024 * 1024 + 1)))
        XCTAssertEqual(try store.read(),original)
        XCTAssertTrue(try store.removeOwned())
    }

    func testLegacyAndAcknowledgementReadsAreBoundedAndPreserved() throws {
        let url=try temporaryRecoveryURL()
        let store=try RecoveryFileStore(url:url)
        let legacy=store.legacyURL
        let ack=url.deletingLastPathComponent().appendingPathComponent("legacy-recovery-ack.json")
        try makeSparseFile(at:legacy,size:64 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try store.pendingLegacy())
        XCTAssertTrue(store.legacyMayReference(url))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:legacy.path)[.size] as? NSNumber)?.int64Value,64 * 1024 * 1024 + 1)
        try FileManager.default.removeItem(at:legacy)
        let original=Data("legacy bytes".utf8)
        try original.write(to:legacy)
        try makeSparseFile(at:ack,size:4 * 1024 + 1)
        XCTAssertThrowsError(try store.pendingLegacy())
        XCTAssertEqual(try Data(contentsOf:legacy),original)
        try FileManager.default.removeItem(at:ack)
        let target=url.deletingLastPathComponent().appendingPathComponent("ack-target.json")
        try Data("do not touch".utf8).write(to:target)
        try FileManager.default.createSymbolicLink(at:ack,withDestinationURL:target)
        XCTAssertThrowsError(try store.pendingLegacy())
        XCTAssertEqual(try Data(contentsOf:target),Data("do not touch".utf8))
        try FileManager.default.removeItem(at:ack)
        makeFIFO(at:ack)
        XCTAssertThrowsError(try store.pendingLegacy())
        XCTAssertTrue(isFIFO(ack))

        try FileManager.default.removeItem(at:legacy)
        makeFIFO(at:legacy)
        XCTAssertThrowsError(try store.pendingLegacy())
        XCTAssertTrue(store.legacyMayReference(url))
        XCTAssertTrue(isFIFO(legacy))
    }

    func testSymlinkedStorageDirectoryCannotReachProductionRecovery() throws {
        let url=try temporaryRecoveryURL()
        let parent=url.deletingLastPathComponent()
        let production=parent.appendingPathComponent("production",isDirectory:true)
        try FileManager.default.createDirectory(at:production,withIntermediateDirectories:true)
        let recovery=production.appendingPathComponent("recovery-v2.json")
        let original=Data("production recovery".utf8)
        try original.write(to:recovery)
        let qa=parent.appendingPathComponent("qa",isDirectory:true)
        try FileManager.default.createSymbolicLink(at:qa,withDestinationURL:production)
        XCTAssertThrowsError(try RecoveryFileStore(url:qa.appendingPathComponent("recovery-v2.json")))
        XCTAssertEqual(try Data(contentsOf:recovery),original)
    }

    private func temporaryRecoveryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("circlr-recovery-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("recovery-v2.json")
    }

    func testSecondLiveInstanceCannotClaimActiveRecovery() throws {
        let url = try temporaryRecoveryURL()
        var first: RecoveryFileStore? = try RecoveryFileStore(url: url)
        XCTAssertTrue(try XCTUnwrap(first).write(Data("first".utf8)))
        XCTAssertThrowsError(try RecoveryFileStore(url: url)) { error in
            guard case RecoveryFileStore.StoreError.alreadyInUse = error else {
                return XCTFail("Unexpected lock error: \(error)")
            }
        }
        first = nil
        let second = try RecoveryFileStore(url: url)
        XCTAssertEqual(try second.read(), Data("first".utf8))
        XCTAssertFalse(try second.write(Data("second".utf8)))
        XCTAssertTrue(try second.adopt(Data("first".utf8)))
        XCTAssertTrue(try second.write(Data("second".utf8)))
        XCTAssertTrue(try second.removeOwned())
        XCTAssertNil(try second.read())
    }

    func testExternalReplacementCannotBeDeletedOrOverwritten() throws {
        let url = try temporaryRecoveryURL()
        let store = try RecoveryFileStore(url: url)
        XCTAssertTrue(try store.write(Data("ours".utf8)))
        try Data("other instance".utf8).write(to: url, options: .atomic)
        XCTAssertFalse(try store.removeOwned())
        XCTAssertFalse(try store.write(Data("ours again".utf8)))
        XCTAssertEqual(try store.read(), Data("other instance".utf8))
    }

    func testLegacyRecoveryRequiresExplicitAdoptionOrDiscard() throws {
        let url = try temporaryRecoveryURL()
        let legacy = Data("legacy without owner".utf8)
        try legacy.write(to: url)
        let store = try RecoveryFileStore(url: url)
        XCTAssertEqual(try store.read(), legacy)
        XCTAssertFalse(try store.removeOwned())
        XCTAssertFalse(try store.write(Data("new".utf8)))
        XCTAssertFalse(try store.removeUnchanged(Data("stale prompt".utf8)))
        XCTAssertEqual(try store.read(), legacy)
        XCTAssertTrue(try store.adopt(legacy))
        XCTAssertTrue(try store.removeOwned())
    }

    func testUnreadableRecoveryIsPreservedBeforeNewAutosave() throws {
        let url = try temporaryRecoveryURL()
        let unreadable = Data("not a recovery JSON".utf8)
        try unreadable.write(to: url)
        let store = try RecoveryFileStore(url: url)
        XCTAssertNil(try store.quarantineUnchanged(Data("stale".utf8)))
        XCTAssertEqual(try store.read(), unreadable)
        let preserved = try XCTUnwrap(store.quarantineUnchanged(unreadable))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: preserved), unreadable)
        XCTAssertTrue(try store.write(Data("new recovery".utf8)))
        XCTAssertEqual(try Data(contentsOf: preserved), unreadable)
    }

    func testFailedMigrationSnapshotCannotQuarantineAReplacedRecovery() throws {
        let url = try temporaryRecoveryURL()
        let selected = Data(#"{"project":"older format","root":null}"#.utf8)
        let replacement = Data(#"{"project":"newer edit","root":null}"#.utf8)
        try selected.write(to: url)
        let store = try RecoveryFileStore(url: url)
        XCTAssertEqual(try store.read(), selected)
        try replacement.write(to: url, options: .atomic) // Old app ignores our lock.
        XCTAssertNil(try store.quarantineUnchanged(selected))
        XCTAssertEqual(try store.read(), replacement)
        XCTAssertFalse(try store.write(Data("blank project".utf8)))
    }

    func testLegacyRecoverCopiesIntoV2ThenAcknowledgesWithoutChangingLegacy() throws {
        let url = try temporaryRecoveryURL()
        let legacyURL = url.deletingLastPathComponent().appendingPathComponent("recovery.json")
        let legacy = Data(#"{"project":"old song"}"#.utf8)
        try legacy.write(to: legacyURL)
        let store = try RecoveryFileStore(url: url)
        let snapshot = try XCTUnwrap(store.pendingLegacy())
        XCTAssertTrue(try store.write(snapshot.data))
        XCTAssertTrue(try store.acknowledgeLegacy(snapshot))
        XCTAssertEqual(try Data(contentsOf: url), legacy)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacy)
        XCTAssertNil(try store.pendingLegacy())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("lock").path))
    }

    func testLegacyDiscardOnlyAcknowledgesAndNewHashIsOfferedAgain() throws {
        let url = try temporaryRecoveryURL()
        let legacyURL = url.deletingLastPathComponent().appendingPathComponent("recovery.json")
        let first = Data("old backup".utf8)
        let next = Data("older app wrote a new backup".utf8)
        try first.write(to: legacyURL)
        let store = try RecoveryFileStore(url: url)
        let snapshot = try XCTUnwrap(store.pendingLegacy())
        XCTAssertTrue(try store.acknowledgeLegacy(snapshot))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: legacyURL), first)
        XCTAssertNil(try store.pendingLegacy())
        try next.write(to: legacyURL, options: .atomic)
        let changed = try XCTUnwrap(store.pendingLegacy())
        XCTAssertNotEqual(changed.sha256, snapshot.sha256)
        XCTAssertEqual(changed.data, next)
    }

    func testOldWriterChangesLegacyWithoutReplacingCurrentV2() throws {
        let url = try temporaryRecoveryURL()
        let legacyURL = url.deletingLastPathComponent().appendingPathComponent("recovery.json")
        let current = Data("current v2 session".utf8)
        let old = Data("older app session".utf8)
        try old.write(to: legacyURL)
        let store = try RecoveryFileStore(url: url)
        XCTAssertTrue(try store.write(current))
        let updatedOld = Data("older app kept working".utf8)
        try updatedOld.write(to: legacyURL, options: .atomic)
        XCTAssertEqual(try store.read(), current)
        XCTAssertEqual(try Data(contentsOf: legacyURL), updatedOld)
        XCTAssertEqual(try store.pendingLegacy()?.data, updatedOld)
    }

    func testAcknowledgedUnrelatedLegacyDoesNotPinPristineDemoCopy() throws {
        struct Snapshot: Encodable {let project:Project;let root:URL?;let date:Date}
        let url = try temporaryRecoveryURL()
        let legacyURL = url.deletingLastPathComponent().appendingPathComponent("recovery.json")
        let demoRoot = url.deletingLastPathComponent().appendingPathComponent("current-demo")
        let otherRoot = url.deletingLastPathComponent().appendingPathComponent("older-demo")
        let store = try RecoveryFileStore(url: url)
        let unrelated = try JSONEncoder().encode(Snapshot(project:Project(),root:otherRoot,date:Date()))
        try unrelated.write(to: legacyURL)
        XCTAssertTrue(try store.acknowledgeLegacy(XCTUnwrap(store.pendingLegacy())))
        XCTAssertFalse(store.legacyMayReference(demoRoot))
        XCTAssertEqual(try Data(contentsOf:legacyURL),unrelated)

        let matching = try JSONEncoder().encode(Snapshot(project:Project(),root:demoRoot,date:Date()))
        try matching.write(to:legacyURL,options:.atomic)
        XCTAssertTrue(store.legacyMayReference(demoRoot))
        let rootless = try JSONEncoder().encode(Snapshot(project:Project(),root:nil,date:Date()))
        try rootless.write(to:legacyURL,options:.atomic)
        XCTAssertFalse(store.legacyMayReference(demoRoot))
        try Data("not decodable".utf8).write(to:legacyURL,options:.atomic)
        XCTAssertTrue(store.legacyMayReference(demoRoot))
    }

    func testCommittedSwitchClearsOwnedV2BeforeReclaimingPristineDemo() throws {
        struct Snapshot: Encodable {let project:Project;let root:URL?;let date:Date}
        let url = try temporaryRecoveryURL()
        let parent = url.deletingLastPathComponent()
        let demoRoot = parent.appendingPathComponent("managed-demo.circlr")
        let targetRoot = parent.appendingPathComponent("next-project.circlr")
        let project = try ProjectStore.save(ProjectStarters.make(id:"blank"),to:demoRoot,mediaRoot:nil)
        let lease = try DemoCopyLease(root:demoRoot,project:project)
        let store = try RecoveryFileStore(url:url)
        XCTAssertTrue(try store.write(Data("current autosave".utf8)))

        // A cancelled or failed target load must leave both recovery and demo intact.
        XCTAssertThrowsError(try ProjectStore.load(parent.appendingPathComponent("missing.circlr")))
        XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:demoRoot.path))

        _ = try ProjectStore.save(ProjectStarters.make(id:"blank"),to:targetRoot,mediaRoot:nil)
        _ = try ProjectStore.load(targetRoot)
        let unrelated=try JSONEncoder().encode(Snapshot(project:project,root:targetRoot,date:Date()))
        try unrelated.write(to:store.legacyURL)
        XCTAssertTrue(try store.acknowledgeLegacy(XCTUnwrap(store.pendingLegacy())))
        XCTAssertTrue(try store.removeOwned())
        let nextAutosave=try JSONEncoder().encode(Snapshot(project:project,root:targetRoot,date:Date()))
        XCTAssertTrue(try store.write(nextAutosave))
        let stillReferenced=store.currentMayReference(demoRoot) || store.legacyMayReference(demoRoot)
        XCTAssertFalse(stillReferenced)
        XCTAssertTrue(lease.releaseIfPristine(project:project,recoveryPresent:stillReferenced))
        XCTAssertFalse(FileManager.default.fileExists(atPath:demoRoot.path))
        XCTAssertEqual(try Data(contentsOf:url),nextAutosave)
        XCTAssertEqual(try Data(contentsOf:store.legacyURL),unrelated)
    }

    func testForeignV2KeepsManagedDemoAfterCurrentSessionCleanupAttempt() throws {
        let url = try temporaryRecoveryURL()
        let demoRoot = url.deletingLastPathComponent().appendingPathComponent("managed-demo.circlr")
        let project = try ProjectStore.save(ProjectStarters.make(id:"blank"),to:demoRoot,mediaRoot:nil)
        let lease = try DemoCopyLease(root:demoRoot,project:project)
        let store = try RecoveryFileStore(url:url)
        XCTAssertTrue(try store.write(Data("ours".utf8)))
        try Data("other owner".utf8).write(to:url,options:.atomic)
        XCTAssertFalse(try store.removeOwned())
        XCTAssertTrue(store.currentMayReference(demoRoot))
        XCTAssertFalse(lease.releaseIfPristine(project:project,recoveryPresent:store.currentMayReference(demoRoot)))
        XCTAssertTrue(FileManager.default.fileExists(atPath:demoRoot.path))
    }
}
