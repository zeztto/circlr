import XCTest
@testable import CirclrCore

final class DemoCopyLeaseTests: XCTestCase {
    private func fixture() throws -> (URL, URL, Project) {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let root = parent.appendingPathComponent("demo.circlr")
        let project = try ProjectStarters.make(id: "blank")
        let saved = try ProjectStore.save(project, to: root, mediaRoot: nil)
        return (parent, root, saved)
    }
    func testReclaimsOnlyPristineOwnedCopyAndKeepsUntrackedNeighbor() throws {
        let (parent, root, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: parent) }
        let neighbor = parent.appendingPathComponent("untracked.circlr")
        try FileManager.default.createDirectory(at: neighbor, withIntermediateDirectories: true)
        let lease = try DemoCopyLease(root: root, project: project)
        var viewed = project
        viewed.hierarchyView = HierarchyViewport(camera: HierarchyCamera(), width: 1000, height: 700, selection: .album)
        XCTAssertTrue(lease.releaseIfPristine(project: viewed, recoveryPresent: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighbor.path))
        XCTAssertFalse(lease.releaseIfPristine(project: project, recoveryPresent: false))
    }
    func testRecoveryAndEditedProjectArePreserved() throws {
        for recovery in [false, true] {
            let (parent, root, project) = try fixture()
            defer { try? FileManager.default.removeItem(at: parent) }
            let lease = try DemoCopyLease(root: root, project: project)
            var edited = project
            if !recovery { edited.name = "사용자 편집" }
            XCTAssertFalse(lease.releaseIfPristine(project: edited, recoveryPresent: recovery))
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        }
    }
    func testExternalReaderPermanentlyRetainsCopy() throws {
        let (parent, root, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: parent) }
        let lease = try DemoCopyLease(root: root, project: project)
        try DemoCopyLease.retainIfManaged(root)
        try DemoCopyLease.retainIfManaged(root)
        XCTAssertFalse(lease.releaseIfPristine(project: project, recoveryPresent: false))
        XCTAssertEqual(try ProjectStore.load(root).project, project)
    }
    func testChangedOrAddedDiskContentIsPreserved() throws {
        let (parent, root, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: parent) }
        let lease = try DemoCopyLease(root: root, project: project)
        try Data("user-owned".utf8).write(to: root.appendingPathComponent("notes.txt"))
        XCTAssertFalse(lease.releaseIfPristine(project: project, recoveryPresent: false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }
    func testSymlinkAndDuplicateOwnershipAreRejected() throws {
        let (parent, root, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: parent) }
        let lease = try DemoCopyLease(root: root, project: project)
        XCTAssertThrowsError(try DemoCopyLease(root: root, project: project))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: parent)
        XCTAssertFalse(lease.releaseIfPristine(project: project, recoveryPresent: false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }
}
