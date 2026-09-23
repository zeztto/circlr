import XCTest
@testable import CirclrCore

final class AgentJobCommitLeaseTests: XCTestCase {
    func testOnlyTheOriginalRunningJobMayPublishItsResult() {
        let lease = AgentJobCommitLease(projectID: "song-A", revision: 8, generation: 4, jobID: "job-1")
        XCTAssertTrue(lease.permits(projectID: "song-A", revision: 8, generation: 4,
                                    jobID: "job-1", jobState: "running"))
        XCTAssertFalse(lease.permits(projectID: "song-B", revision: 8, generation: 4,
                                     jobID: "job-1", jobState: "running"))
        XCTAssertFalse(lease.permits(projectID: "song-A", revision: 9, generation: 4,
                                     jobID: "job-1", jobState: "running"))
        XCTAssertFalse(lease.permits(projectID: "song-A", revision: 8, generation: 5,
                                     jobID: "job-1", jobState: "running"))
        XCTAssertFalse(lease.permits(projectID: "song-A", revision: 8, generation: 4,
                                     jobID: "job-2", jobState: "running"))
        XCTAssertFalse(lease.permits(projectID: "song-A", revision: 8, generation: 4,
                                     jobID: "job-1", jobState: "cancelled"))
        XCTAssertFalse(lease.permits(projectID: "song-A", revision: 8, generation: 4,
                                     jobID: nil, jobState: nil))
    }
    func testStageWriterChecksBetweenChunksAndAfterFinalChunk() throws {
        var ranges:[Range<Int>]=[],checks=0
        try AgentStageChunks.process(totalFrames:10,chunkFrames:4,check: {checks+=1}) {ranges.append($0)}
        XCTAssertEqual(ranges,[0..<4,4..<8,8..<10])
        XCTAssertEqual(checks,4)

        ranges=[];checks=0
        XCTAssertThrowsError(try AgentStageChunks.process(totalFrames:10,chunkFrames:4,
                             check: {checks+=1;if checks==2 {throw CancellationError()}},
                             write: {ranges.append($0)}))
        XCTAssertEqual(ranges,[0..<4],"Cancellation must stop before the next audio chunk")

        ranges=[];checks=0
        XCTAssertThrowsError(try AgentStageChunks.process(totalFrames:4,chunkFrames:4,
                             check: {checks+=1;if checks==2 {throw CancellationError()}},
                             write: {ranges.append($0)}))
        XCTAssertEqual(ranges,[0..<4],"Cancellation after the last write must still fail staging")
    }
    func testCrashCleanupOnlyRecognizesPrivateBounceStageNames() {
        let id="77B8758C-D1D9-4A18-AC0D-4C1EABF23B91"
        XCTAssertTrue(AgentStageChunks.isPrivateBounceStageName(".circlr-agent-\(id).wav"))
        for name in [".circlr-agent-not-a-uuid.wav","circlr-agent-\(id).wav",
                     ".circlr-agent-\(id).mp3",".circlr-agent-\(id).wav.backup",
                     "user-bounce.wav"] {
            XCTAssertFalse(AgentStageChunks.isPrivateBounceStageName(name))
        }
    }
    func testSnapshotCommitRejectsLayoutOnlyChangesWithoutMusicRevision() throws {
        var baseline=Project()
        _=baseline.addTrack(name:"신스")
        _=baseline.addSection(name:"A",at:Point(),bars:1)
        baseline.enableAlbum()
        var current=baseline
        current.arrangements[current.activeIndex].layout.positions["extra"]=Point(40,20)
        XCTAssertEqual(current.musicRevision,baseline.musicRevision)
        XCTAssertNoThrow(try AgentJobCommitLease.requireUnchanged(current:baseline,snapshot:baseline))
        XCTAssertThrowsError(try AgentJobCommitLease.requireUnchanged(current:current,snapshot:baseline))
        XCTAssertEqual(current.arrangements[current.activeIndex].layout.positions["extra"],Point(40,20))
    }
    func testHeadroomScanChecksCancellationAndClippingOffMain() throws {
        var left=[Float](repeating:0.5,count:9000),right=left
        XCTAssertNoThrow(try AgentStageChunks.requireSafePCM(left:left,right:right,chunkFrames:4096,
                                                               check:{}))
        var checks=0
        XCTAssertThrowsError(try AgentStageChunks.requireSafePCM(left:left,right:right,chunkFrames:4096,
                             check:{checks+=1;if checks==2 {throw CancellationError()}}))
        XCTAssertEqual(checks,2)
        left[8000]=1.01
        XCTAssertThrowsError(try AgentStageChunks.requireSafePCM(left:left,right:right,chunkFrames:4096,
                                                                  check:{}))
        right[1] = .nan
        XCTAssertThrowsError(try AgentStageChunks.requireSafePCM(left:[Float](repeating:0.5,count:9000),
                                                                  right:right,chunkFrames:4096,check:{}))
    }
}
