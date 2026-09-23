import XCTest
@testable import CirclrCore

final class AgentRunLeaseTests: XCTestCase {
    private let section=AgentRunTarget.section(arrangementID:"arrangement",useID:"use")
    private let lane=AgentRunTarget.lane(arrangementID:"arrangement",useID:"use",laneID:"lane")

    private func binding(_ project:Project,_ path:String?=nil)->AgentRunDocumentBinding {
        AgentRunDocumentBinding(projectID:project.id,
            projectURL:path.map{URL(fileURLWithPath:$0)},mediaRoot:nil)
    }

    private func request(_ method:String,_ project:Project) -> AgentRequest {
        var request=AgentRequest(method:method)
        request.projectID=project.id
        request.expectedRevision=project.musicRevision
        return request
    }

    private func notes(_ project:Project) -> AgentRequest {
        var request=request("apply",project)
        var args=AgentArguments()
        var operation=AgentOperation("set_notes")
        operation.arrangementID="arrangement";operation.useID="use";operation.laneID="lane"
        operation.notes=[Note(beat:0,pitch:60)]
        args.operations=[operation];request.arguments=args
        return request
    }

    func testScopedTurnAcceptsExactMIDITargetButNotOtherLaneOrStaleRevision() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        var controller=AgentRunLeaseController()
        let document=binding(project)
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                       methods:["apply"],targets:[section,lane],ttl:60,now:now)
        let request=notes(project)
        XCTAssertNoThrow(try controller.authorize(request,lease:lease,project:project,document:document,now:now))

        var other=request
        other.arguments?.operations?[0].laneID="another-lane"
        XCTAssertThrowsError(try controller.authorize(other,lease:lease,project:project,document:document,now:now))
        var stale=request
        stale.expectedRevision=project.musicRevision+1
        XCTAssertThrowsError(try controller.authorize(stale,lease:lease,project:project,document:document,now:now))
        XCTAssertThrowsError(try controller.authorize(request,lease:lease,project:project,document:document,
                                                      now:now.addingTimeInterval(60)))
    }

    func testStopAndNewTurnInvalidateOldLeaseAndCompletedTurnCannotStartWrites() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        var controller=AgentRunLeaseController()
        let document=binding(project)
        let first=try controller.issue(sessionID:"session",turnID:"one",document:document,
                                       methods:["apply","bounce"],targets:[section,lane,.track("track")],
                                       ttl:60,now:now)
        try controller.complete(first)
        XCTAssertThrowsError(try controller.authorize(notes(project),lease:first,project:project,document:document,now:now))
        XCTAssertTrue(controller.permitsCommit(first,document:document,now:now))
        controller.revoke()
        XCTAssertFalse(controller.permitsCommit(first,document:document,now:now))
        let second=try controller.issue(sessionID:"session",turnID:"two",document:document,
                                        methods:["apply"],targets:[section,lane],ttl:60,now:now)
        XCTAssertNotEqual(first.generation,second.generation)
        XCTAssertThrowsError(try controller.authorize(notes(project),lease:first,project:project,document:document,now:now))
        XCTAssertNoThrow(try controller.authorize(notes(project),lease:second,project:project,document:document,now:now))
        XCTAssertFalse(controller.permitsCommit(second,document:AgentRunDocumentBinding(projectID:"new-project",projectURL:nil,mediaRoot:nil),now:now))
    }

    func testBounceRequiresExactSectionAndTrackAndNeverAcceptsFilePath() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        var controller=AgentRunLeaseController()
        let document=binding(project)
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                       methods:["bounce"],targets:[section,.track("track")],
                                       ttl:60,now:now)
        var request=request("bounce",project)
        var args=AgentArguments()
        args.arrangementID="arrangement";args.useID="use";args.trackID="track"
        request.arguments=args
        XCTAssertNoThrow(try controller.authorize(request,lease:lease,project:project,document:document,now:now))
        request.arguments?.trackID="other-track"
        XCTAssertThrowsError(try controller.authorize(request,lease:lease,project:project,document:document,now:now))
        request.arguments?.trackID="track"
        request.arguments?.path="/Users/example/export.wav"
        XCTAssertThrowsError(try controller.authorize(request,lease:lease,project:project,document:document,now:now))
    }

    func testUnknownAndSharedEditsFailClosed() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        var controller=AgentRunLeaseController()
        let document=binding(project)
        XCTAssertThrowsError(try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                                  methods:["save"],targets:[section],ttl:60,now:now))
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                       methods:["apply","snapshot"],targets:[section,lane],ttl:60,now:now)
        var request=notes(project)
        request.arguments?.operations?[0].original=true
        XCTAssertThrowsError(try controller.authorize(request,lease:lease,project:project,document:document,now:now))
        request=notes(project)
        request.arguments?.operations?[0].kind="edit_shared_audio"
        XCTAssertThrowsError(try controller.authorize(request,lease:lease,project:project,document:document,now:now))
        request=notes(project)
        request.arguments?.operations?[0].trackID="track-outside-scope"
        XCTAssertThrowsError(try controller.authorize(request,lease:lease,project:project,document:document,now:now))
        var snapshot=AgentRequest(method:"snapshot")
        XCTAssertNoThrow(try controller.authorize(snapshot,lease:lease,project:project,document:document,now:now))
        snapshot.projectID="another-project"
        XCTAssertThrowsError(try controller.authorize(snapshot,lease:lease,project:project,document:document,now:now))
        snapshot.projectID=nil
        snapshot.arguments=AgentArguments()
        XCTAssertThrowsError(try controller.authorize(snapshot,lease:lease,project:project,document:document,now:now))
    }

    func testSnapshotNeverEncodesAssetPathOrFullProject() throws {
        var project=Project()
        let secret="/Users/private-session/secret-source.wav"
        project.assets=[Asset(name:"source",path:secret,duration:2,sampleRate:48000)]
        let data=try JSONEncoder().encode(AgentRunSnapshot(project))
        let text=String(decoding:data,as:UTF8.self)
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("\"path\""))
        XCTAssertTrue(text.contains("source"))
        XCTAssertTrue(text.contains("projectID"))
    }

    func testStoppedTurnRejectsStagedBounceCommitWhileMusicJobGuardRemainsValid() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        var controller=AgentRunLeaseController()
        let document=binding(project)
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                       methods:["bounce"],targets:[section,.track("track")],ttl:60,now:now)
        let job=AgentJobCommitLease(projectID:project.id,revision:project.musicRevision,
                                    generation:5,jobID:"job")
        XCTAssertTrue(job.permits(projectID:project.id,revision:project.musicRevision,
                                  generation:5,jobID:"job",jobState:"running"))
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let stage=folder.appendingPathComponent(".circlr-agent-\(UUID().uuidString).wav")
        let output=folder.appendingPathComponent("published.wav")
        try Data([0x52,0x49,0x46,0x46]).write(to:stage)
        controller.revoke() // user AI STOP while the encoder's stage already exists
        if controller.permitsCommit(lease,document:document,now:now) {
            try FileManager.default.moveItem(at:stage,to:output)
        } else {
            try FileManager.default.removeItem(at:stage)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath:output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:stage.path))
    }

    func testRequestReplayReturnsOriginalResultAndNeverEvictsWithinLease() throws {
        var ledger=AgentRunReplayLedger<String>(limit:2)
        XCTAssertNil(try ledger.replay(id:"bounce-1",fingerprint:"payload-A"))
        try ledger.remember(id:"bounce-1",fingerprint:"payload-A",value:"job-1")
        XCTAssertEqual(try ledger.replay(id:"bounce-1",fingerprint:"payload-A"),"job-1")
        XCTAssertThrowsError(try ledger.replay(id:"bounce-1",fingerprint:"payload-B"))
        try ledger.remember(id:"bounce-2",fingerprint:"payload-B",value:"job-2")
        XCTAssertThrowsError(try ledger.replay(id:"bounce-3",fingerprint:"payload-C"))
        XCTAssertEqual(try ledger.replay(id:"bounce-1",fingerprint:"payload-A"),"job-1")
    }

    func testSaveAsWithSameProjectIDAndRevisionInvalidatesDocumentBinding() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        let original=binding(project,"/tmp/original.circlr")
        let savedAs=binding(project,"/tmp/saved-as.circlr")
        var controller=AgentRunLeaseController()
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:original,
                                       methods:["apply","bounce"],targets:[section,lane,.track("track")],
                                       ttl:60,now:now)
        XCTAssertNoThrow(try controller.authorize(notes(project),lease:lease,project:project,
                                                   document:original,now:now))
        XCTAssertThrowsError(try controller.authorize(notes(project),lease:lease,project:project,
                                                      document:savedAs,now:now))
        XCTAssertFalse(controller.permitsCommit(lease,document:savedAs,now:now))
        let mediaMoved=AgentRunDocumentBinding(projectID:project.id,
            projectURL:URL(fileURLWithPath:"/tmp/original.circlr"),
            mediaRoot:URL(fileURLWithPath:"/tmp/new-media"))
        XCTAssertFalse(controller.permitsCommit(lease,document:mediaMoved,now:now))
    }

    func testTrustedWriteProjectionAndFailureNeverReturnNestedNativePaths() throws {
        let project=Project(),secret="/Users/private-session/secret-source.wav"
        let unsafe:[String:Any]=["jobID":"job-1","path":secret,
                                  "assets":[["path":secret]],
                                  "nested":["recoveryPath":secret]]
        let applied=try AgentRunReplyProjection.afterWrite(method:"apply",native:unsafe,
                                                            project:project)
        let bounced=try AgentRunReplyProjection.afterWrite(method:"bounce",native:unsafe,
                                                            project:project)
        for reply in [applied,bounced] {
            let data=try JSONSerialization.data(withJSONObject:reply)
            let text=String(decoding:data,as:UTF8.self)
            XCTAssertFalse(text.contains(secret))
            XCTAssertFalse(text.contains("path"))
        }
        XCTAssertEqual(applied["state"] as? String,"applied")
        XCTAssertEqual(bounced["jobID"] as? String,"job-1")
        XCTAssertEqual(AgentRunReplyProjection.safeFailure(CirclrError(secret)),
                       "trusted_run_execution_failed")
    }

    func testCapturedTrustedJobLeaseCannotFallThroughWhenOwnerPointerChanges() throws {
        let project=Project()
        let actual=AgentRunDocumentBinding(projectID:project.id,projectURL:nil,mediaRoot:nil)
        let now=Date(timeIntervalSince1970:100)
        var controller=AgentRunLeaseController()
        let old=try controller.issue(sessionID:"session",turnID:"old",document:actual,
                                     methods:["bounce"],targets:[section,.track("track")],ttl:60,now:now)
        XCTAssertTrue(controller.permitsOwnedJobCommit(old,jobID:"old-job",
            ownedLease:old,ownedJobID:"old-job",document:actual,now:now))
        XCTAssertFalse(controller.permitsOwnedJobCommit(old,jobID:"old-job",
            ownedLease:nil,ownedJobID:nil,document:actual,now:now))
        let new=try controller.issue(sessionID:"session",turnID:"new",document:actual,
                                     methods:["bounce"],targets:[section,.track("track")],ttl:60,now:now)
        let native=AgentJobCommitLease(projectID:project.id,revision:project.musicRevision,
                                       generation:8,jobID:"old-job")
        XCTAssertTrue(native.permits(projectID:project.id,revision:project.musicRevision,
                                      generation:8,jobID:"old-job",jobState:"running"))
        XCTAssertFalse(controller.permitsOwnedJobCommit(old,jobID:"old-job",
            ownedLease:new,ownedJobID:"new-job",document:actual,now:now))
        XCTAssertFalse(controller.permitsOwnedJobCommit(old,jobID:"old-job",
            ownedLease:nil,ownedJobID:nil,document:actual,now:now))
    }
}
