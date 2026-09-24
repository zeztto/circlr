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

    private func inspectFixture() -> Project {
        var project=Project()
        _=project.addTrack(name:"Lead")
        _=project.addTrack(name:"Bass")
        _=project.addSection(name:"Chorus",at:Point(),bars:2)
        project.sections[0].settings.tempo = .local(97)
        project.arrangements[0].uses[0].settings.tempo = .local(101)
        project.arrangements[0].uses[0].barsOverride=3
        let secret="/Users/private-session/source.wav"
        let asset=Asset(name:"source",path:secret,duration:4,sampleRate:48000)
        project.assets=[asset]
        project.sections[0].lanes[0].audio=[AudioClip(assetID:asset.id,duration:2)]
        project.tracks[0].instrument.kind = .audioUnit
        project.tracks[0].instrument.plugin=PluginDescriptor(name:"Private plugin",type:1,subtype:2,manufacturer:3,state:Data(secret.utf8))
        var variant=project.sections[0].lanes[0]
        variant.notes=[Note(beat:2,pitch:67),Note(beat:0,pitch:60),Note(beat:1,pitch:64)]
        project.arrangements[0].uses[0].laneOverrides[variant.id]=variant
        return project
    }

    private func inspectRequest(_ project:Project,laneID:ID?=nil,
                                offset:Int?=nil,limit:Int?=nil) -> AgentRequest {
        var request=request("inspect",project)
        var args=AgentArguments()
        args.arrangementID=project.activeArrangementID
        args.useID=project.active.uses[0].id
        args.laneID=laneID;args.offset=offset;args.limit=limit
        request.arguments=args
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

    func testJobStatusRequiresCurrentProjectAndOnlyAJobID() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        var controller=AgentRunLeaseController()
        let document=binding(project)
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                       methods:["job"],targets:[],ttl:60,now:now)
        var query=request("job",project)
        query.expectedRevision=nil // Progress reads are safe across unrelated music edits.
        var args=AgentArguments();args.jobID="owned-job"
        query.arguments=args
        XCTAssertNoThrow(try controller.authorize(query,lease:lease,project:project,document:document,now:now))

        var invalid=query;invalid.projectID=nil
        XCTAssertThrowsError(try controller.authorize(invalid,lease:lease,project:project,document:document,now:now))
        invalid=query;invalid.projectID="another-project"
        XCTAssertThrowsError(try controller.authorize(invalid,lease:lease,project:project,document:document,now:now))
        invalid=query;invalid.expectedRevision=project.musicRevision+1
        XCTAssertThrowsError(try controller.authorize(invalid,lease:lease,project:project,document:document,now:now))
        invalid=query;invalid.arguments?.jobID=""
        XCTAssertThrowsError(try controller.authorize(invalid,lease:lease,project:project,document:document,now:now))
        invalid=query;invalid.arguments?.path="/tmp/private.wav"
        XCTAssertThrowsError(try controller.authorize(invalid,lease:lease,project:project,document:document,now:now))

        for extra in ["unexpected","path"] {
            let wire:[String:Any]=["id":"job-query","method":"job","projectID":project.id,
                                   "arguments":["jobID":"owned-job",extra:NSNull()]]
            let decoded=try JSONDecoder().decode(AgentRequest.self,
                from:JSONSerialization.data(withJSONObject:wire))
            XCTAssertThrowsError(try controller.authorize(decoded,lease:lease,
                project:project,document:document,now:now))
        }
        let nullID:[String:Any]=["id":"job-query","method":"job","projectID":project.id,
                                 "arguments":["jobID":NSNull()]]
        let decodedNull=try JSONDecoder().decode(AgentRequest.self,
            from:JSONSerialization.data(withJSONObject:nullID))
        XCTAssertThrowsError(try controller.authorize(decodedNull,lease:lease,
            project:project,document:document,now:now))
        controller.revoke()
        XCTAssertThrowsError(try controller.authorize(query,lease:lease,project:project,document:document,now:now))
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

    func testSaveRequiresAppSelectedCurrentDocumentAndRejectsModelPaths() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        let unsaved=binding(project)
        XCTAssertThrowsError(try AgentRunFileGrant.saveCurrentProject(document:unsaved))
        let document=binding(project,"/tmp/song.circlr")
        let grant=try AgentRunFileGrant.saveCurrentProject(document:document)
        XCTAssertEqual(grant.destinationURL.path,document.projectURL)
        var controller=AgentRunLeaseController()
        XCTAssertThrowsError(try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                                   methods:["save"],targets:[],ttl:60,now:now))
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                       methods:["save"],targets:[],fileGrants:[grant],ttl:60,now:now)
        let save=request("save",project)
        XCTAssertEqual(try controller.authorizedFileDestination(for:save,lease:lease,
            project:project,document:document,now:now).path,"/tmp/song.circlr")

        var withPath=save;var args=AgentArguments();args.path="/tmp/other.circlr"
        withPath.arguments=args
        XCTAssertThrowsError(try controller.authorizedFileDestination(for:withPath,lease:lease,
            project:project,document:document,now:now))
        let nullPath=try JSONDecoder().decode(AgentRequest.self,
            from:Data("""
                {"id":"save-null","method":"save","projectID":"\(project.id)","expectedRevision":\(project.musicRevision),"arguments":{"path":null}}
                """.utf8))
        XCTAssertThrowsError(try controller.authorizedFileDestination(for:nullPath,lease:lease,
            project:project,document:document,now:now))

        let savedAs=binding(project,"/tmp/song-copy.circlr")
        XCTAssertThrowsError(try controller.authorizedFileDestination(for:save,lease:lease,
            project:project,document:savedAs,now:now))
        XCTAssertThrowsError(try controller.authorizedFileDestination(for:save,lease:lease,
            project:project,document:document,now:now.addingTimeInterval(60)))
        controller.revoke()
        XCTAssertThrowsError(try controller.authorizedFileDestination(for:save,lease:lease,
            project:project,document:document,now:now))
    }

    func testFileGrantFollowsCurrentObservedRevisionAfterOwnEditButRejectsStaleRevision() throws {
        var project=Project();let now=Date(timeIntervalSince1970:100)
        let document=binding(project,"/tmp/song.circlr")
        let grant=try AgentRunFileGrant.saveCurrentProject(document:document)
        var controller=AgentRunLeaseController()
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
            methods:["save"],targets:[],fileGrants:[grant],ttl:60,now:now)
        let stale=request("save",project)
        project.musicRevision += 1 // an earlier authorized apply committed in this turn
        XCTAssertThrowsError(try controller.authorizedFileDestination(for:stale,lease:lease,
            project:project,document:document,now:now))
        let fresh=request("save",project)
        XCTAssertNoThrow(try controller.authorizedFileDestination(for:fresh,lease:lease,
            project:project,document:document,now:now))
    }

    func testCompletedTurnCanPublishOnlyItsPreviouslyAcceptedFileJob() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        let document=binding(project,"/tmp/song.circlr")
        let grant=try AgentRunFileGrant.saveCurrentProject(document:document)
        var controller=AgentRunLeaseController()
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
            methods:["save"],targets:[],fileGrants:[grant],ttl:60,now:now)
        let save=request("save",project)
        try controller.complete(lease)
        XCTAssertThrowsError(try controller.authorizedFileDestination(for:save,lease:lease,
            project:project,document:document,now:now))
        XCTAssertEqual(try controller.authorizedOwnedFileJobDestination(for:save,lease:lease,
            jobID:"save-job",ownedLease:lease,ownedJobID:"save-job",project:project,
            document:document,now:now).path,"/tmp/song.circlr")
        XCTAssertThrowsError(try controller.authorizedOwnedFileJobDestination(for:save,lease:lease,
            jobID:"save-job",ownedLease:lease,ownedJobID:"other-job",project:project,
            document:document,now:now))
        XCTAssertThrowsError(try controller.authorizedOwnedFileJobDestination(for:save,lease:lease,
            jobID:"save-job",ownedLease:lease,ownedJobID:"save-job",project:project,
            document:document,now:now.addingTimeInterval(60)))
        var changed=project;changed.musicRevision += 1
        XCTAssertThrowsError(try controller.authorizedOwnedFileJobDestination(for:save,lease:lease,
            jobID:"save-job",ownedLease:lease,ownedJobID:"save-job",project:changed,
            document:document,now:now))
        controller.revoke()
        XCTAssertThrowsError(try controller.authorizedOwnedFileJobDestination(for:save,lease:lease,
            jobID:"save-job",ownedLease:lease,ownedJobID:"save-job",project:project,
            document:document,now:now))
    }

    func testExportRequiresSeparateAppDestinationAndStopsBeforeStagedPublish() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        let document=binding(project,"/tmp/song.circlr")
        XCTAssertThrowsError(try AgentRunFileGrant.exportWAV(to:URL(string:"https://example.com/song.wav")!,document:document))
        XCTAssertThrowsError(try AgentRunFileGrant.exportWAV(to:URL(fileURLWithPath:"/tmp/song.mp3"),document:document))
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let output=folder.appendingPathComponent("mix.wav")
        let grant=try AgentRunFileGrant.exportWAV(to:output,document:document)
        var controller=AgentRunLeaseController()
        XCTAssertThrowsError(try controller.issue(sessionID:"session",turnID:"turn",document:document,
            methods:["export"],targets:[],ttl:60,now:now))
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
            methods:["export"],targets:[],fileGrants:[grant],ttl:60,now:now)
        var export=request("export",project)
        var args=AgentArguments();args.tailSeconds=2
        export.arguments=args
        XCTAssertEqual(try controller.authorizedFileDestination(for:export,lease:lease,
            project:project,document:document,now:now),output)
        export.arguments?.path="/tmp/other.wav"
        XCTAssertThrowsError(try controller.authorizedFileDestination(for:export,lease:lease,
            project:project,document:document,now:now))
        export.arguments?.path=nil
        let nullPath=try JSONDecoder().decode(AgentRequest.self,
            from:Data("""
                {"id":"export-null","method":"export","projectID":"\(project.id)","expectedRevision":\(project.musicRevision),"arguments":{"path":null}}
                """.utf8))
        XCTAssertThrowsError(try controller.authorizedFileDestination(for:nullPath,lease:lease,
            project:project,document:document,now:now))
        let stage=folder.appendingPathComponent(".staged.wav")
        try Data([0x52,0x49,0x46,0x46]).write(to:stage)
        controller.revoke()
        if (try? controller.authorizedFileDestination(for:export,lease:lease,
            project:project,document:document,now:now)) != nil {
            try FileManager.default.moveItem(at:stage,to:output)
        } else {
            try FileManager.default.removeItem(at:stage)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath:output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:stage.path))
    }

    func testExportGrantCannotPlaceUnownedWAVInsideCurrentProjectPackage() throws {
        let project=Project()
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let package=folder.appendingPathComponent("song.circlr",isDirectory:true)
        try FileManager.default.createDirectory(at:package,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let document=AgentRunDocumentBinding(projectID:project.id,
            projectURL:package,mediaRoot:package)
        XCTAssertThrowsError(try AgentRunFileGrant.exportWAV(
            to:package.appendingPathComponent("mix.wav"),document:document))
        XCTAssertThrowsError(try AgentRunFileGrant.exportWAV(
            to:package.appendingPathComponent("nested/mix.wav"),document:document))
        let alias=folder.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:package)
        XCTAssertThrowsError(try AgentRunFileGrant.exportWAV(
            to:alias.appendingPathComponent("mix.wav"),document:document))
        XCTAssertNoThrow(try AgentRunFileGrant.exportWAV(
            to:folder.appendingPathComponent("mix.wav"),document:document))
    }

    func testExportGrantRechecksMovedDirectoryAliasBeforePublication() throws {
        let project=Project(),now=Date(timeIntervalSince1970:100)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let package=folder.appendingPathComponent("song.circlr",isDirectory:true)
        let outside=folder.appendingPathComponent("outside",isDirectory:true)
        try FileManager.default.createDirectory(at:package,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let alias=folder.appendingPathComponent("chosen-folder")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:outside)
        let document=AgentRunDocumentBinding(projectID:project.id,
            projectURL:package,mediaRoot:package)
        let grant=try AgentRunFileGrant.exportWAV(to:alias.appendingPathComponent("mix.wav"),
                                                   document:document)
        var controller=AgentRunLeaseController()
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
            methods:["export"],targets:[],fileGrants:[grant],ttl:60,now:now)
        let export=request("export",project)
        XCTAssertNoThrow(try controller.authorizedFileDestination(for:export,lease:lease,
            project:project,document:document,now:now))
        try FileManager.default.removeItem(at:alias)
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:package)
        XCTAssertThrowsError(try controller.authorizedOwnedFileJobDestination(for:export,
            lease:lease,jobID:"job",ownedLease:lease,ownedJobID:"job",project:project,
            document:document,now:now))
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
        let saved=try AgentRunReplyProjection.afterWrite(method:"save",native:unsafe,
                                                          project:project)
        let exported=try AgentRunReplyProjection.afterWrite(method:"export",native:unsafe,
                                                             project:project)
        for reply in [applied,bounced,saved,exported] {
            let data=try JSONSerialization.data(withJSONObject:reply)
            let text=String(decoding:data,as:UTF8.self)
            XCTAssertFalse(text.contains(secret))
            XCTAssertFalse(text.contains("path"))
        }
        XCTAssertEqual(applied["state"] as? String,"applied")
        XCTAssertEqual(bounced["jobID"] as? String,"job-1")
        XCTAssertEqual(saved["state"] as? String,"running")
        XCTAssertEqual(exported["jobID"] as? String,"job-1")
        XCTAssertThrowsError(try AgentRunReplyProjection.afterWrite(method:"save",native:[:],project:project))
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

    func testInspectRequiresExactSectionAndLaneScopeAndCurrentRevision() throws {
        let project=inspectFixture(),now=Date(timeIntervalSince1970:100)
        let section=AgentRunTarget.section(arrangementID:project.activeArrangementID,useID:project.active.uses[0].id)
        let selected=project.sections[0].lanes[0].id
        let lane=AgentRunTarget.lane(arrangementID:project.activeArrangementID,useID:project.active.uses[0].id,laneID:selected)
        var controller=AgentRunLeaseController()
        let document=binding(project)
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                       methods:["inspect"],targets:[section,lane],ttl:60,now:now)
        XCTAssertNoThrow(try controller.authorize(inspectRequest(project),lease:lease,
                                                   project:project,document:document,now:now))
        XCTAssertNoThrow(try controller.authorize(inspectRequest(project,laneID:selected),lease:lease,
                                                   project:project,document:document,now:now))
        XCTAssertThrowsError(try controller.authorize(inspectRequest(project,laneID:project.sections[0].lanes[1].id),
                                                       lease:lease,project:project,document:document,now:now))
        var stale=inspectRequest(project,laneID:selected)
        stale.expectedRevision=project.musicRevision+1
        XCTAssertThrowsError(try controller.authorize(stale,lease:lease,project:project,document:document,now:now))
        stale=inspectRequest(project,laneID:selected)
        stale.projectID="wrong-project"
        XCTAssertThrowsError(try controller.authorize(stale,lease:lease,project:project,document:document,now:now))
        stale=inspectRequest(project,laneID:selected)
        stale.arguments?.useID="wrong-use"
        XCTAssertThrowsError(try controller.authorize(stale,lease:lease,project:project,document:document,now:now))
        XCTAssertThrowsError(try AgentRunInspect(project,arrangementID:project.activeArrangementID,
                                                  useID:project.active.uses[0].id,laneID:"wrong-lane"))
    }

    func testInspectPagesEffectiveMIDINotesAndExcludesSensitiveModels() throws {
        let project=inspectFixture(),use=project.active.uses[0],laneID=project.sections[0].lanes[0].id
        let summary=try AgentRunInspect(project,arrangementID:project.activeArrangementID,
                                         useID:use.id,laneID:nil,offset:0,limit:1)
        let summaryJSON=try JSONSerialization.jsonObject(with:JSONEncoder().encode(summary)) as! [String:Any]
        XCTAssertEqual(summary.total,2)
        XCTAssertEqual(summary.lanes?.count,1)
        XCTAssertEqual(summary.nextOffset,1)
        XCTAssertNil(summary.notes)
        let lastLane=try AgentRunInspect(project,arrangementID:project.activeArrangementID,
                                          useID:use.id,laneID:nil,offset:summary.nextOffset!,limit:1)
        XCTAssertEqual(lastLane.lanes?.count,1)
        XCTAssertNil(lastLane.nextOffset)
        XCTAssertEqual((summaryJSON["context"] as? [String:Any])?["tempo"] as? Double,101)
        XCTAssertEqual((summaryJSON["section"] as? [String:Any])?["bars"] as? Int,3)
        let inspected=try AgentRunInspect(project,arrangementID:project.activeArrangementID,
                                           useID:use.id,laneID:laneID,offset:1,limit:1)
        XCTAssertEqual(inspected.total,3)
        XCTAssertEqual(inspected.notes?.count,1)
        XCTAssertEqual(inspected.notes?.first?.beat,1)
        XCTAssertEqual(inspected.notes?.first?.pitch,64)
        XCTAssertEqual(inspected.lane?.noteCount,3)
        XCTAssertEqual(inspected.nextOffset,2)
        XCTAssertNil(inspected.lanes)
        let lastNote=try AgentRunInspect(project,arrangementID:project.activeArrangementID,
                                          useID:use.id,laneID:laneID,offset:inspected.nextOffset!,limit:1)
        XCTAssertEqual(lastNote.notes?.first?.pitch,67)
        XCTAssertNil(lastNote.nextOffset)
        let beyond=try AgentRunInspect(project,arrangementID:project.activeArrangementID,
                                        useID:use.id,laneID:laneID,offset:99,limit:256)
        XCTAssertEqual(beyond.notes?.count,0)
        XCTAssertNil(beyond.nextOffset)
        for projection in [summary,inspected] {
            let text=String(decoding:try JSONEncoder().encode(projection),as:UTF8.self)
            for forbidden in ["/Users/private-session","source.wav","plugin","state","assets","graph","path","sourceStart"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden),"unexpected sensitive field: \(forbidden)")
            }
        }
    }

    func testInspectRejectsMalformedArgumentsIncludingUnknownAndNullFields() throws {
        let project=inspectFixture(),now=Date(timeIntervalSince1970:100)
        let section=AgentRunTarget.section(arrangementID:project.activeArrangementID,useID:project.active.uses[0].id)
        var controller=AgentRunLeaseController()
        let document=binding(project)
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                       methods:["inspect"],targets:[section],ttl:60,now:now)
        var invalid=inspectRequest(project)
        invalid.arguments?.path="/tmp/secret"
        XCTAssertThrowsError(try controller.authorize(invalid,lease:lease,project:project,document:document,now:now))
        for (offset,limit) in [(-1,1),(0,0),(0,257),(1_000_001,1)] {
            invalid=inspectRequest(project,offset:offset,limit:limit)
            XCTAssertThrowsError(try controller.authorize(invalid,lease:lease,project:project,document:document,now:now))
        }
        invalid=inspectRequest(project)
        invalid.arguments?.arrangementID=nil
        XCTAssertThrowsError(try controller.authorize(invalid,lease:lease,project:project,document:document,now:now))
        var payload:[String:Any]=["id":"req","method":"inspect","projectID":project.id,
                                  "expectedRevision":project.musicRevision,
                                  "arguments":["arrangementID":project.activeArrangementID,
                                               "useID":project.active.uses[0].id,"unexpected":NSNull()]]
        let raw=try JSONSerialization.data(withJSONObject:payload)
        let decoded=try JSONDecoder().decode(AgentRequest.self,from:raw)
        XCTAssertThrowsError(try controller.authorize(decoded,lease:lease,project:project,document:document,now:now))
        payload["arguments"]=["arrangementID":project.activeArrangementID,
                              "useID":project.active.uses[0].id,"path":NSNull()]
        let nullField=try JSONDecoder().decode(AgentRequest.self,from:JSONSerialization.data(withJSONObject:payload))
        XCTAssertThrowsError(try controller.authorize(nullField,lease:lease,project:project,document:document,now:now))
        for key in ["laneID","offset","limit"] {
            payload["arguments"]=["arrangementID":project.activeArrangementID,
                                  "useID":project.active.uses[0].id,key:NSNull()]
            let nullOptional=try JSONDecoder().decode(AgentRequest.self,
                from:JSONSerialization.data(withJSONObject:payload))
            XCTAssertThrowsError(try controller.authorize(nullOptional,lease:lease,
                                                          project:project,document:document,now:now))
        }
    }

    func testAgentRequestRunIDRoundTrip() throws {
        var request=AgentRequest(method:"snapshot",id:"run-bound")
        request.expectedRunID="12345678-1234-1234-1234-123456789ABC"
        let decoded=try JSONDecoder().decode(AgentRequest.self,from:JSONEncoder().encode(request))
        XCTAssertEqual(decoded.expectedRunID,request.expectedRunID)
        let malformed=Data(#"{"id":"run-bound","method":"snapshot","expectedRunID":123}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AgentRequest.self,from:malformed))
    }

    func testAgentRequestEncodingStillUsesOriginalWireFields() throws {
        let project=inspectFixture()
        let original=inspectRequest(project,laneID:project.sections[0].lanes[0].id,
                                    offset:1,limit:2)
        let encoded=try JSONEncoder().encode(original)
        let decoded=try JSONDecoder().decode(AgentRequest.self,from:encoded)
        let roundTrip=try JSONEncoder().encode(decoded)
        let before=try JSONSerialization.jsonObject(with:encoded) as! NSDictionary
        let after=try JSONSerialization.jsonObject(with:roundTrip) as! NSDictionary
        XCTAssertEqual(before,after)
        XCTAssertNil(before["decodedArgumentKeys"])
        XCTAssertNil(before["decodedCanonicalWire"])
        XCTAssertEqual((after["arguments"] as? [String:Any])?["laneID"] as? String,
                       project.sections[0].lanes[0].id)
    }

    func testTrustedReplayRejectsAddedUnknownOrNullFieldsForApplyAndInspect() throws {
        let project=inspectFixture(),now=Date(timeIntervalSince1970:100)
        let arrangementID=project.activeArrangementID,useID=project.active.uses[0].id
        let laneID=project.sections[0].lanes[0].id
        let section=AgentRunTarget.section(arrangementID:arrangementID,useID:useID)
        let lane=AgentRunTarget.lane(arrangementID:arrangementID,useID:useID,laneID:laneID)
        let document=binding(project)
        var controller=AgentRunLeaseController()
        let lease=try controller.issue(sessionID:"session",turnID:"turn",document:document,
                                       methods:["apply","inspect"],targets:[section,lane],ttl:60,now:now)
        var operation=AgentOperation("set_notes")
        operation.arrangementID=arrangementID;operation.useID=useID;operation.laneID=laneID
        operation.notes=[Note(beat:0,pitch:60)]
        var apply=request("apply",project),applyArgs=AgentArguments()
        applyArgs.operations=[operation];apply.arguments=applyArgs
        let requests=[apply,inspectRequest(project,laneID:laneID)]
        for source in requests {
            let valid=try JSONDecoder().decode(AgentRequest.self,from:JSONEncoder().encode(source))
            let fingerprint=try valid.trustedReplayFingerprintMaterial().base64EncodedString()
            var ledger=AgentRunReplayLedger<String>()
            XCTAssertNil(try ledger.replay(id:valid.id,fingerprint:fingerprint))
            try controller.authorize(valid,lease:lease,project:project,document:document,now:now)
            try ledger.remember(id:valid.id,fingerprint:fingerprint,value:"accepted")

            var wire=try JSONSerialization.jsonObject(with:JSONEncoder().encode(valid)) as! [String:Any]
            var arguments=wire["arguments"] as! [String:Any]
            for (key,value) in [("unexpected",NSNull() as Any),("path",NSNull() as Any)] {
                arguments[key]=value;wire["arguments"]=arguments
                let changed=try JSONDecoder().decode(AgentRequest.self,
                    from:JSONSerialization.data(withJSONObject:wire))
                let changedFingerprint=try changed.trustedReplayFingerprintMaterial().base64EncodedString()
                XCTAssertNotEqual(changedFingerprint,fingerprint)
                XCTAssertThrowsError(try ledger.replay(id:changed.id,fingerprint:changedFingerprint))
                arguments.removeValue(forKey:key)
            }
            if source.method=="apply" {
                var operations=arguments["operations"] as! [[String:Any]]
                for (key,value) in [("path","/tmp/secret" as Any),("original",NSNull() as Any)] {
                    operations[0][key]=value;arguments["operations"]=operations;wire["arguments"]=arguments
                    let changed=try JSONDecoder().decode(AgentRequest.self,
                        from:JSONSerialization.data(withJSONObject:wire))
                    let changedFingerprint=try changed.trustedReplayFingerprintMaterial().base64EncodedString()
                    XCTAssertNotEqual(changedFingerprint,fingerprint)
                    XCTAssertThrowsError(try ledger.replay(id:changed.id,fingerprint:changedFingerprint))
                    XCTAssertThrowsError(try controller.authorize(changed,lease:lease,
                                                                  project:project,document:document,now:now))
                    operations[0].removeValue(forKey:key)
                }
            }
            // The write gateway deliberately replays an exact accepted apply
            // before checking the new revision. Inspect itself is not replayable.
            if source.method=="apply" {
                var advanced=project;advanced.musicRevision += 1
                XCTAssertEqual(try ledger.replay(id:valid.id,fingerprint:fingerprint),"accepted")
                XCTAssertThrowsError(try controller.authorize(valid,lease:lease,
                                                              project:advanced,document:document,now:now))
            }
        }
    }
}
