import Foundation
import AppKit
import AVFAudio
import CryptoKit
import CirclrCore
import CirclrAudio

struct ActivityEvent:Codable,Identifiable {
    var id:Int
    var time:Date
    var source:String
    var message:String
    var revision:Int
}
struct AgentJob:Codable {
    var id:String
    var kind:String
    var state:String
    var progress:Double=0
    var message:String
    var path:String?
    var nodeID:ID?
    var tail:TailPlan?
    var renderedSeconds:Double?
    var endWindowSeconds:Double?
    var endWindowPeak:Double?
    var endWindowRMS:Double?
    var midiImport:AgentMIDIImportResult?
    var endWindowHasSignal:Bool?
}
extension AppStore {
    func pauseAgentBridgeForTermination() {agentBridgeShuttingDown=true}
    func resumeAgentBridgeAfterCancelledTermination() {
        agentBridgeShuttingDown=false
        if agentSocket == nil {startAgentBridge()}
    }
    func stopAgentBridgeForTermination() {
        agentBridgeShuttingDown=true
        agentSocket=nil // AgentSocket.deinit unlinks only its own inode.
        agentBridgeEndpointName=""
        agentBridgeDefaultSelected=false
    }
    func recordActivity(_ source:String,_ message:String) {
        activitySequence+=1
        activity.append(ActivityEvent(id:activitySequence,time:Date(),source:source,message:message,revision:project.musicRevision))
        if activity.count>500{activity.removeFirst(activity.count-500)}
    }
    func startAgentBridge() {
        guard agentStartupReady,agentSocket == nil else { return }
        let now=ProcessInfo.processInfo.systemUptime
        guard now >= agentBridgeRetryAt else{return}
        do {
            try openAgentBridge(name:"agent.sock")
            agentBridgeRetryAt=0
            agentBridgeLastFailure=nil
            agentBridgeNeedsManualRecovery=false
            recordActivity("연결","로컬 MCP 연결 준비 · 휠로 확대·축소 · Ctrl `로 콘솔 접기")
        }catch{
            agentBridgeRetryAt=now+10
            let message=error.localizedDescription
            if message != agentBridgeLastFailure {recordActivity("연결",message)}
            agentBridgeLastFailure=message
            let failure=error as NSError
            agentBridgeNeedsManualRecovery=(failure.domain=="CirclrAgent" && (failure.code==4 || failure.code==6)) ||
                (failure.domain==NSPOSIXErrorDomain && failure.code==EEXIST)
        }
    }
    private func openAgentBridge(name:String) throws {
        let directory=productionMediaRoot.deletingLastPathComponent().appendingPathComponent("Agent")
        let expectedPath=directory.appendingPathComponent(name).path
        let socket=try AgentSocket(directory:directory,name:name){[weak self] data,reply in
            guard let self else{return}
            let result:[String:Any]
            if self.agentSocket?.path==expectedPath {result=self.receiveAgent(data,source:"에이전트")}
            else {result=["ok":false,"error":"agent_target_changed: 연결이 교체됐습니다"]}
            reply((try? JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])) ?? Data(#"{"ok":false,"error":"encoding"}"#.utf8))
        }
        try AgentEndpointSelection.publish(.init(endpoint:name,runID:agentRunID,
            bundleID:Bundle.main.bundleIdentifier ?? "com.circlr.desktop"),in:directory)
        agentBridgeEndpointName=name
        agentSocket=socket
        agentBridgeDefaultSelected=true
    }
    func refreshAgentBridgeDefaultSelection() {
        guard let socket=agentSocket,socket.ownsPublishedPath else {
            agentBridgeDefaultSelected=false
            return
        }
        let directory=productionMediaRoot.deletingLastPathComponent().appendingPathComponent("Agent")
        let selected=AgentEndpointSelection.current(in:directory)
        agentBridgeDefaultSelected=selected?.runID==agentRunID && selected?.endpoint==agentBridgeEndpointName
    }
    func selectAgentBridgeAsDefault() {
        guard agentStartupReady,!agentBridgeShuttingDown,
              let socket=agentSocket,socket.ownsPublishedPath else {
            status="이 앱의 Agent 연결을 확인할 수 없습니다"
            agentBridgeDefaultSelected=false
            return
        }
        let directory=productionMediaRoot.deletingLastPathComponent().appendingPathComponent("Agent")
        do {
            try AgentEndpointSelection.publish(.init(endpoint:agentBridgeEndpointName,runID:agentRunID,
                bundleID:Bundle.main.bundleIdentifier ?? "com.circlr.desktop"),in:directory)
            agentBridgeDefaultSelected=true
            status="이 앱을 기본 MCP 연결로 선택했습니다 · 사용 중인 MCP 세션은 다시 시작하세요"
            recordActivity("연결","이 앱의 기본 MCP 연결 선택 · 기존 socket 보존")
        }catch {
            agentBridgeDefaultSelected=false
            status="기본 MCP 연결 선택 실패 · \(error.localizedDescription)"
        }
    }
    func recoverAgentBridgeWithNewEndpoint() {
        guard agentStartupReady,agentSocket == nil,agentBridgeNeedsManualRecovery else{return}
        for _ in 0..<4 {
            let name=".r"+String(UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased().prefix(8))
            do {
                try openAgentBridge(name:name)
                agentBridgeNeedsManualRecovery=false
                agentBridgeLastFailure=nil
                agentBridgeRetryAt=0
                recordActivity("연결","이 앱의 새 MCP 연결 준비 · 기존 경로는 보존했습니다")
                status="이 앱의 새 MCP 연결이 준비됐습니다 · 사용 중인 MCP 세션은 다시 시작하세요"
                return
            }catch {
                let failure=error as NSError
                if failure.domain==NSPOSIXErrorDomain && failure.code==EADDRINUSE {continue}
                agentBridgeLastFailure=error.localizedDescription
                status="새 MCP 연결 실패 · \(error.localizedDescription)"
                return
            }
        }
        status="새 MCP 연결 위치를 확보하지 못했습니다 · 다시 시도하세요"
    }
    // Multiple endpoints may coexist with older app instances. Stage cleanup
    // must wait for per-run ownership metadata; a socket path is not a lease
    // over the shared Bounces directory.
    func json<T:Encodable>(_ value:T)->Any {((try? JSONSerialization.jsonObject(with:JSONEncoder().encode(value),options:[.fragmentsAllowed])) ?? NSNull())}
    func agentState()->[String:Any] {
        refreshPlaybackLoopTransition()
        return ["projectID":project.id,"revision":project.musicRevision,"layoutRevision":project.portLayout?.revision ?? 0,"name":project.name,"dirty":dirty,"path":projectURL?.path ?? "","global":json(project.global),
         "tracks":json(project.tracks),"assets":json(project.assets),"album":json(project.album),"patterns":json(project.patterns),"activeArrangementID":project.activeArrangementID,
         "arrangements":project.arrangements.map{["id":$0.id,"name":$0.name,"uses":$0.uses.map{["id":$0.id,"sectionID":$0.sectionID,"name":$0.name]}]},
         "selection":json(hierarchySelection),"selectedNoteIDs":json(selectedMIDIIDs.sorted()),
         "automationEditor":["visible":automationVisible,"parameter":automationParameter.rawValue,"selectedPointID":json(selectedAutomationPointID),"displayBeats":automationDisplayedBeats,"supportedParameters":automationDescriptors],
         "recording":["midi":midiRecording,"audio":audioRecording,"permissionPending":audioRecordPending && audioCapturePhase != .starting,"format":json(audioInputFormat),"phase":audioRecordPending && !recorder.busy ? "authorizing":audioCapturePhase.rawValue,"busy":audioRecordingBusy,"seconds":audioInputSeconds,"peak":audioInputLevel,"message":audioCaptureMessage,"recoveryPath":audioRecoveryURL?.path ?? ""],"job":json(agentJob),"sequence":activitySequence,
         "playback":capturePlaybackVisualization?() ?? ["playing":playback.playing,"seconds":playback.seconds],"output":json(playback.outputStatus),"audition":json(auditionOutput.status),
         "view":["startupOpen":startupOpen,"loopMode":playbackLoopMode.rawValue,"loopTransition":playbackLoopState,"loopIteration":playback.loopIteration,"elapsedSeconds":playback.elapsedSeconds,"viewingMode":viewingMode,"follow":playbackFollow.rawValue,"followSettings":json(playbackFollowSettings),"zoom":hierarchyZoom,"layout":project.usesOrbits ? "orbit":"freeform","consoleOpen":consoleOpen,"consoleBounds":[consoleBounds.minX,consoleBounds.minY,consoleBounds.width,consoleBounds.height]],
         "library":["open":libraryOpen,"folders":library.folders.count,"files":library.entries.count,"selectedFiles":library.chosenIDs.count,"scanning":library.scanning,"searching":library.searching,"previewPreparing":library.previewPreparing,"previewPlaying":library.previewing,"previewPending":library.previewPending,"previewSeconds":library.previewSeconds],
         "runtime":["version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development","build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "development","runID":agentRunID,"agentEndpoint":agentBridgeEndpointName,"capabilities":["playbackLoop":1,"playbackLoopLive":1,"workspaceView":1,"soundCatalog":1,"synthCutoffAutomation":1,"synthResonanceAutomation":1,"midiTempoImport":1,"midiPitchBendImport":1,"midiSustainImport":1,"midiSustainEditing":1,"midiPitchBendEditing":1,"sectionLengthEditing":1,"jobCancellation":1],"bundleID":Bundle.main.bundleIdentifier ?? "","windows":NSApplication.shared.windows.filter{$0.identifier?.rawValue=="main"}.map{["visible":$0.isVisible,"minimized":$0.isMiniaturized]}]]
    }
    func receiveAgent(_ data:Data,source:String)->[String:Any] {
        guard agentStartupReady else {return ["ok":false,"error":"시작 복구 확인이 끝나지 않아 에이전트 요청을 받을 수 없습니다"]}
        do {
            // Dynamic endpoint calls use a non-JSON envelope. An older app
            // cannot ignore its run binding and accidentally accept a write.
            var requestData=data
            let prefix=Data("CIRCLR/2 ".utf8)
            if data.starts(with:prefix) {
                let remainder=data.dropFirst(prefix.count)
                guard let separator=remainder.firstIndex(of:32),
                      let runID=String(data:remainder[..<separator],encoding:.utf8),
                      runID==agentRunID else {
                    return ["ok":false,"error":"agent_target_changed: 실행 연결이 일치하지 않습니다"]
                }
                requestData=Data(remainder[remainder.index(after:separator)...])
            } else if agentBridgeEndpointName != "agent.sock" {
                return ["ok":false,"error":"agent_target_changed: 새 연결에는 실행 ID가 필요합니다"]
            }
            let request=try JSONDecoder().decode(AgentRequest.self,from:requestData)
            guard request.expectedRunID == nil || request.expectedRunID==agentRunID else {
                return ["ok":false,"requestID":request.id,"error":"agent_target_changed: 실행 연결이 일치하지 않습니다"]
            }
            guard !request.id.isEmpty,request.id.count<=128 else {throw CirclrError("request id가 필요합니다")}
            let fingerprint=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
            if let previous=agentReplies[request.id] {
                guard previous.0==fingerprint else {throw CirclrError("동일 request id에 다른 명령을 재사용할 수 없습니다")};return previous.1
            }
            let result: [String:Any]
            do {result=["ok":true,"requestID":request.id,"result":try executeAgent(request,source:source)]}
            catch {recordActivity(source,"실패 · \(request.method) · \(error.localizedDescription)");result=["ok":false,"requestID":request.id,"error":error.localizedDescription,"projectID":project.id,"revision":project.musicRevision,"layoutRevision":project.portLayout?.revision ?? 0]}
            if !["snapshot","inspect","ports","sounds","events","job"].contains(request.method) {
                agentReplies[request.id]=(fingerprint,result);agentReplyOrder.append(request.id)
                if agentReplyOrder.count>256 {agentReplies.removeValue(forKey:agentReplyOrder.removeFirst())}
            }
            return result
        }catch{return ["ok":false,"error":error.localizedDescription]}
    }
    func executeAgent(_ request:AgentRequest,source:String,
                      trustedLease:AgentRunLease?=nil) throws -> [String:Any] {
        guard agentStartupReady else {throw CirclrError("시작 복구 확인이 끝나지 않아 에이전트 요청을 받을 수 없습니다")}
        let args=request.arguments ?? AgentArguments()
        switch request.method {
        case "snapshot":return agentState()
        case "sounds":
            guard let catalog=agentSoundCatalog,let result=json(try catalog.page(args)) as? [String:Any] else{throw CirclrError("음색 목록을 준비하지 못했습니다. 앱을 다시 열어주세요")}
            return result
        case "ports":
            guard let node=args.node else {throw CirclrError("조회할 node 주소가 필요합니다")}
            guard let result=json(try AgentPortEditing.snapshot(at:node,in:project)) as? [String:Any] else {throw CirclrError("포트 응답을 인코딩할 수 없습니다")}
            return result
        case "inspect":
            guard let id=args.useID,let arrangement=project.arrangements.first(where:{$0.id==(args.arrangementID ?? project.activeArrangementID)}),let use=arrangement.uses.first(where:{$0.id==id}),let section=project.sections.first(where:{$0.id==use.sectionID}) else {throw CirclrError("arrangementID와 useID를 확인하세요")}
            let (_,context,clock)=try ArrangementCompiler.context(project:project,use:use,arrangementID:arrangement.id)
            let circles=hierarchyScene?.nodes.filter{node in
                switch node.id {case .section(let ai,let ui),.music(let ai,let ui,_):return ai==arrangement.id && ui==id;default:return false}
            }.map{node -> [String:Any] in ["address":json(node.id),"timeline":json(node.timeline),"orbit":json(node.orbit)]} ?? []
            return ["projectID":project.id,"revision":project.musicRevision,"use":json(use),"context":json(context),"clock":["beats":clock.beats,"seconds":clock.seconds,"barStarts":clock.barStarts],"lanes":json(try ArrangementCompiler.effectiveLanes(section:section,use:use)),"graph":json(try SectionGraphEditing.effective(section:section,use:use)),"circles":circles]
        case "events":return ["events":json(activity.filter{$0.id>(args.afterSequence ?? 0)}),"sequence":activitySequence,"job":json(agentJob)]
        case "job":guard let id=args.jobID,let job=agentJobs[id] else {throw CirclrError("jobID를 찾을 수 없습니다")};return ["job":json(job),"revision":project.musicRevision]
        case "cancel_job":
            guard request.projectID==project.id else {throw CirclrError("stale_project: 현재 문서를 다시 확인하세요")}
            guard let id=args.jobID else {throw CirclrError("jobID가 필요합니다")}
            return try cancelAgentJob(id,source:source)
        case "stop":stop();return ["state":"stopped"]
        case "play":guard !preparing else {throw CirclrError("현재 렌더 작업을 정지한 뒤 재생하세요")};if !playback.playing{play()};recordActivity(source,"재생 요청");return ["state":"preparing_or_playing"]
        case "playback_loop":
            try AgentProjectEditing.check(request,project:project)
            guard let mode=args.loopMode else {throw CirclrError("루프 범위를 지정하세요")}
            guard choosePlaybackLoop(mode) else {throw CirclrError(status)}
            var state=agentState();state["loopRequestState"]=playbackLoopChangeBusy ? "accepted_pending":"configured";return state
        case "workspace_view":
            try AgentProjectEditing.check(request,project:project)
            guard args.followSettings != nil || args.follow != nil || args.viewingMode != nil else {throw CirclrError("표시 설정을 지정하세요")}
            if let settings=args.followSettings,settings.target == .pinned {
                guard let pin=settings.pinned else {throw CirclrError("고정할 서클 주소가 필요합니다")}
                _ = try StudioNavigation.scene(revealing:pin,in:project)
            }
            // Validate the complete request before changing any presentation state.
            if let enabled=args.viewingMode,!setViewingMode(enabled) {throw CirclrError("편집 중인 입력을 먼저 확정하거나 취소하세요")}
            if let settings=args.followSettings {setPlaybackFollowSettings(settings)}
            if let enabled=args.follow {playbackFollow=enabled ? .following:.off}
            return agentState()
        case "focus":
            if args.node != nil, args.useID != nil || args.nodeID != nil || args.compositionID != nil || args.arrangementID != nil || args.follow != nil || args.minimized != nil {
                throw CirclrError("node 주소는 다른 focus 대상 없이 사용하세요")
            }
            if let follow=args.follow {
                guard args.minimized == nil,args.useID == nil,args.nodeID == nil,args.compositionID == nil else {throw CirclrError("follow는 다른 focus 대상 없이 사용하세요")}
                playbackFollow=follow ? .following:.off;return agentState()
            }
            if let minimized=args.minimized {
                guard let window=NSApplication.shared.windows.first(where:{$0.identifier?.rawValue=="main"}) else {throw CirclrError("앱 창을 찾을 수 없습니다")}
                if minimized {window.miniaturize(nil)}else{window.deminiaturize(nil);window.makeKeyAndOrderFront(nil)}
                return agentState()
            }
            let address:CircleAddress
            if let node=args.node {address=node}else if let use=args.useID {address=args.nodeID.map{.music(arrangementID:args.arrangementID ?? project.activeArrangementID,useID:use,nodeID:$0)} ?? .section(arrangementID:args.arrangementID ?? project.activeArrangementID,useID:use)}else if let id=args.compositionID {address = .composition(id)}else{address = .album}
            _ = try StudioNavigation.scene(revealing:address,in:project)
            _=setViewingMode(false)
            startupOpen=false
            hierarchySettingsOpen=false;focusHierarchy(address,detail:args.detail ?? false);return ["selection":json(address)]
        default:break
        }
        try AgentProjectEditing.check(request,project:project)
        guard !midiRecording,!audioRecordingBusy else {throw CirclrError("녹음 대기·진행·파일 마무리 중에는 에이전트 편집을 적용하지 않습니다")}
        recordActivity(source,"실행 · \(request.method)")
        switch request.method {
        case "connect_ports","reconnect_ports","disconnect_ports","move_ports","set_group_port","remove_group_port":
            let edit=try AgentPortEditing.apply(request,to:project),changed=edit.project != project
            let layoutOnly=["move_ports","set_group_port","remove_group_port"].contains(request.method)
            mutate(layoutOnly ? "에이전트 연결 위치 이동":"에이전트 포트 편집",musical:!layoutOnly,portLayoutOnly:layoutOnly){$0=edit.project}
            if changed && !layoutOnly {cancelAudition();normalizeHierarchySelection()}
            var result=agentState();result["changed"]=changed;result["connectionID"]=json(edit.connectionID);result["portID"]=json(edit.portID)
            return result

        case "record":
            guard audioRecordingAvailable,!audioRecordingBusy,!preparing else{throw CirclrError("녹음할 서클·트랙과 장치 정리 상태를 확인하세요")}
            startAudioRecording();return agentState()
        case "apply":
            let explicitArrangement=args.operations?.last(where:{$0.kind=="select_arrangement"})
            if explicitArrangement != nil {
                guard nameEditing.resolve() else{throw CirclrError("이름 편집을 적용한 뒤 편곡안을 선택하세요")}
                try AgentProjectEditing.check(request,project:project)
            }
            var leaving=explicitArrangement == nil ? nil:capturedArrangementWorkspace()
            let previousChoice=explicitArrangement.flatMap{$0.compositionID}.flatMap{project.album?.composition($0)?.selectedArrangementID}
            let previousActive=project.activeArrangementID
            let candidate=try AgentProjectEditing.apply(request,to:project)
            // This pre-mutation snapshot is cached after project reconciliation;
            // reconcile it too so restore cannot reintroduce a stale event index.
            if let memory=leaving {
                var workspace=memory.workspace
                let key=EditorWorkspaceKey(node:memory.address,original:workspace.original)
                workspace.pitchBend=workspace.pitchBend?.reconciled(from:pitchBendSource(at:key,in:project),to:pitchBendSource(at:key,in:candidate))
                workspace.sustain=workspace.sustain?.reconciled(from:sustainSource(at:key,in:project),to:sustainSource(at:key,in:candidate))
                leaving=ArrangementWorkspaceMemory(projectID:memory.projectID,arrangementID:memory.arrangementID,
                    compositionID:memory.compositionID,address:memory.address,workspace:workspace,
                    midiStepMode:memory.midiStepMode,capturedAt:memory.capturedAt)
            }
            mutate("에이전트 편집 · \(args.operations?.count ?? 0)개"){$0=candidate}
            cancelAudition()
            if let compositionID=explicitArrangement?.compositionID,let arrangementID=explicitArrangement?.arrangementID {
                if previousChoice != arrangementID || previousActive != arrangementID {
                    restoreArrangementWorkspace(arrangementID,compositionID:compositionID,leaving:leaving)
                }else{normalizeHierarchySelection()}
            }else{normalizeHierarchySelection()}
            return agentState()
        case "undo":
            if let expected=args.expectedLayoutRevision {try AgentPortEditing.checkLayout(expected,project:project)}
            guard undoCount>0 else {throw CirclrError("취소할 편집이 없습니다")};undo();return agentState()
        case "save":
            cancelDemoLoading()
            guard let path=args.path ?? projectURL?.path,path.hasSuffix(".circlr") else {throw CirclrError("저장할 .circlr 절대 경로가 필요합니다")}
            let url=try agentPath(path)
            if FileManager.default.fileExists(atPath:url.path),try ProjectStore.load(url).project.id != project.id {throw CirclrError("다른 프로젝트를 덮어쓸 수 없습니다")}
            captureViewport()
            var cleanupWarning: String?
            let saved=try ProjectStore.saveSessionReportingCleanup(project,to:url,mediaRoot:mediaRoot) { cleanupWarning = $0 }
            if let lease=demoCopyLease,url.standardizedFileURL == lease.root {
                try? DemoCopyLease.retainIfManaged(lease.root);demoCopyLease=nil
            } else {retireDemoCopy()}
            project=saved;projectURL=url;mediaRoot=url;dirty=false;clearSavedRecovery();status=cleanupWarning ?? "에이전트 저장 완료"
            var result=agentState()
            if let cleanupWarning { result["warning"] = cleanupWarning }
            return result
        case "open":
            return try beginAgentOpen(request,source:source)
        case "import_midi":return try beginAgentMIDIImport(request,source:source)
        case "bounce","export":return try beginAgentRender(request,source:source,
                                                              trustedLease:trustedLease)
        case "restore_bounce":
            guard let use=args.useID,let node=args.nodeID else {throw CirclrError("useID와 nodeID가 필요합니다")}
            var candidate=project;candidate.activeArrangementID=args.arrangementID ?? project.activeArrangementID
            try BounceEditing.restore(nodeID:node,useID:use,in:&candidate);candidate.activeArrangementID=project.activeArrangementID
            mutate("바운스 원본 복원"){$0=candidate};return agentState()
        default:throw CirclrError("지원하지 않는 method: \(request.method)")
        }
    }
    /// Cancel only the active native agent job. Transport, recording and movie state are untouched.
    func cancelAgentJob(_ id:ID,source:String)throws->[String:Any] {
        guard let known=agentJobs[id] else {throw CirclrError("jobID를 찾을 수 없습니다")}
        if known.state != "running" {return ["job":json(known),"revision":project.musicRevision]}
        guard var current=agentJob,current.id==id else {throw CirclrError("현재 실행 중인 작업이 아닙니다")}
        productionGeneration+=1
        productionTask?.cancel();productionWorker?.cancel();agentOpenWorker?.cancel()
        current.state="cancelled";current.message="에이전트 작업 취소"
        agentJob=current
        preparing=false;progress=0;status="에이전트 작업 취소 · \(current.kind)"
        recordActivity(source,"취소 · \(current.kind) · \(id)")
        return ["job":json(current),"revision":project.musicRevision]
    }
    /// Recheck at the MainActor commit boundary after each suspended worker step.
    /// A cancelled/replaced job cannot publish a WAV or mutate the document.
    func checkAgentJobCommit(_ lease:AgentJobCommitLease,
                             trustedLease:AgentRunLease?=nil)throws {
        guard lease.permits(projectID:project.id,revision:project.musicRevision,
                            generation:productionGeneration,jobID:agentJob?.id,
                            jobState:agentJob?.state) else {throw CancellationError()}
        if let trustedLease {try checkTrustedAgentJobCommit(trustedLease,jobID:lease.jobID)}
    }
    /// Encode on a worker so the MainActor can process cancel_job during long WAV writes.
    /// A cancelled encoder removes its private stage before returning.
    func writeAgentWAVStage(_ pcm:PCM,to stage:URL) async throws {
        let writer=Task.detached(priority:.userInitiated) {
            do {
                try Task.checkCancellation()
                guard pcm.left.count==pcm.right.count,
                      let format=AVAudioFormat(standardFormatWithSampleRate:PCM.rate,channels:2),
                      let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4096),
                      let channels=buffer.floatChannelData else {throw CirclrError("WAV 인코딩 buffer를 준비하지 못했습니다")}
                try FileManager.default.createDirectory(at:stage.deletingLastPathComponent(),withIntermediateDirectories:true)
                let file=try AVAudioFile(forWriting:stage,settings:[
                    AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:PCM.rate,
                    AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:24,
                    AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false
                ],commonFormat:.pcmFormatFloat32,interleaved:false)
                try AgentStageChunks.process(totalFrames:pcm.count,chunkFrames:4096,
                                             check:{try Task.checkCancellation()}) {range in
                    for i in range {
                        let local=i-range.lowerBound
                        channels[0][local]=pcm.left[i];channels[1][local]=pcm.right[i]
                    }
                    buffer.frameLength=AVAudioFrameCount(range.count)
                    try file.write(from:buffer)
                }
            }catch{
                try? FileManager.default.removeItem(at:stage)
                throw error
            }
        }
        try await withTaskCancellationHandler {
            try await writer.value
        } onCancel: {
            writer.cancel()
        }
    }
    nonisolated private static func checkedAgentPCM(_ pcm:PCM)throws->PCM {
        try AgentStageChunks.requireSafePCM(left:pcm.left,right:pcm.right,chunkFrames:4096,
                                            check:{try Task.checkCancellation()})
        return pcm
    }
    func agentPath(_ path:String)throws->URL {
        guard path.hasPrefix("/"),!path.contains("\0") else {throw CirclrError("절대 경로를 사용하세요")}
        return URL(fileURLWithPath:path).standardizedFileURL
    }
    /// An app-selected, already open document is the only trusted save target.
    /// Media is staged away from the MainActor. STOP, a changed document, or a
    /// later user edit prevents publication even if the copy worker finishes.
    func beginTrustedAgentSave(_ request:AgentRequest,destination:URL,
                               lease:AgentRunLease)throws->[String:Any] {
        guard !preparing,!midiRecording,!audioRecordingBusy,!audioRecordPending else {
            throw CirclrError("현재 작업 또는 녹음 마무리가 끝난 뒤 저장하세요")
        }
        guard let current=projectURL,
              current.standardizedFileURL==destination.standardizedFileURL,
              mediaRoot != nil else {
            throw CirclrError("trusted_run_scope: 사용자가 선택한 현재 곡 위치가 필요합니다")
        }
        guard try ProjectStore.load(destination).project.id==project.id else {
            throw CirclrError("trusted_run_scope: 선택한 곡의 ID가 현재 문서와 다릅니다")
        }
        captureViewport()
        let snapshot=project,root=mediaRoot
        let drain=takeProductionDrain()
        let generation=productionGeneration,jobID=newID()
        let jobLease=AgentJobCommitLease(projectID:snapshot.id,
            revision:snapshot.musicRevision,generation:generation,jobID:jobID)
        agentJob=AgentJob(id:jobID,kind:"save",state:"running",
                          message:"선택한 곡 저장 준비 중")
        preparing=true;progress=0;status="선택한 곡 저장 준비 중"
        recordActivity("내장 AI","실행 · save · \(jobID)")
        productionTask=Task { [weak self] in
            await drain.wait()
            guard let self,self.productionGeneration==generation,!Task.isCancelled else{return}
            do {
                let worker=Task.detached(priority:.userInitiated) {
                    try ProjectStore.prepareSessionSave(snapshot,to:destination,
                        mediaRoot:root,checkCancellation:{try Task.checkCancellation()})
                }
                let staged=try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                defer {ProjectStore.discard(staged)}
                try Task.checkCancellation()
                try self.checkAgentJobCommit(jobLease,trustedLease:lease)
                try AgentJobCommitLease.requireUnchanged(current:self.project,snapshot:snapshot)
                guard self.mediaRoot==root,
                      self.projectURL?.standardizedFileURL==destination.standardizedFileURL else {
                    throw CancellationError()
                }
                let authorized=try self.trustedRun.authorizedOwnedFileJobDestination(
                    for:request,lease:lease,jobID:jobID,
                    ownedLease:self.trustedAgentJob?.lease,
                    ownedJobID:self.trustedAgentJob?.id,
                    project:self.project,document:self.currentTrustedDocument)
                guard authorized==destination else {throw CancellationError()}
                guard try ProjectStore.load(destination).project.id==snapshot.id else {
                    throw CirclrError("저장 대상이 다른 곡으로 바뀌었습니다")
                }
                var cleanupWarning:String?
                let saved=try ProjectStore.publishSessionSaveReportingCleanup(staged) {
                    cleanupWarning=$0
                }
                // Publication and these session updates are synchronous on the
                // MainActor: no agent turn can interleave after the final check.
                self.project=saved
                self.projectURL=destination
                self.mediaRoot=destination
                self.dirty=false
                self.clearSavedRecovery()
                self.preparing=false;self.progress=1
                self.agentJob?.state="completed";self.agentJob?.progress=1
                self.agentJob?.message=cleanupWarning ?? "저장 완료"
                self.status=cleanupWarning ?? "내장 AI 저장 완료"
                self.recordActivity("내장 AI","완료 · save · \(jobID)")
            } catch {
                guard self.productionGeneration==generation else{return}
                self.preparing=false
                self.agentJob?.state=error is CancellationError ? "cancelled":"failed"
                self.agentJob?.message=error.localizedDescription
                self.status=error.localizedDescription
                self.recordActivity("내장 AI","실패 · save · \(jobID)")
            }
        }
        return ["jobID":jobID,"state":"running"]
    }
    func beginAgentOpen(_ request:AgentRequest,source:String)throws->[String:Any] {
        cancelDemoLoading()
        guard !dirty else {throw CirclrError("저장되지 않은 편집이 있습니다. 먼저 save하세요")}
        guard !preparing else {throw CirclrError("현재 작업을 정지한 뒤 프로젝트를 여세요")}
        guard let path=request.arguments?.path else {throw CirclrError("path가 필요합니다")}
        let url=try agentPath(path)
        stop();productionGeneration+=1
        let generation=productionGeneration,jobID=newID()
        let lease=AgentJobCommitLease(projectID:project.id,revision:project.musicRevision,
                                      generation:generation,jobID:jobID)
        agentJob=AgentJob(id:jobID,kind:"open",state:"running",message:"프로젝트 읽는 중")
        preparing=true;progress=0;status="프로젝트 읽는 중 · macOS 접근 요청이 있으면 확인하세요"
        productionTask=Task { [weak self] in
            guard let self else{return}
            let worker=Task.detached(priority:.userInitiated){try Task.checkCancellation();let root=try ProjectStore.rootURL(for:url);try DemoCopyLease.retainIfManaged(root);let loaded=try ProjectStore.load(root);try Task.checkCancellation();return loaded}
            self.agentOpenWorker=worker
            do {
                let loaded=try await worker.value
                guard !Task.isCancelled,self.productionGeneration==generation else{return}
                try self.checkAgentJobCommit(lease)
                try AgentProjectEditing.check(request,project:self.project)
                guard !self.dirty else {throw CirclrError("읽는 동안 문서가 변경되었습니다")}
                var p=loaded.project;p.enableAlbum();p=try SectionGraphMigration.migrate(p)
                self.retireDemoCopy()
                self.project=p;self.projectURL=p==loaded.project ? loaded.root:nil;self.mediaRoot=loaded.root
                self.selectedTrackID=p.tracks.first?.id;self.resetSession();self.dirty=p != loaded.project
                self.preparing=false;self.progress=1;self.agentJob?.state="completed";self.agentJob?.progress=1;self.agentJob?.path=loaded.root.path;self.agentJob?.message="완료"
                self.status="\(self.project.name) 열기 완료";self.recordActivity(source,"완료 · open · \(jobID)")
            }catch{
                guard self.productionGeneration==generation else{return}
                self.preparing=false;self.agentJob?.state=error is CancellationError ? "cancelled":"failed";self.agentJob?.message=error.localizedDescription
                self.status=error.localizedDescription;self.recordActivity(source,"실패 · open · \(error.localizedDescription)")
            }
        }
        return ["jobID":jobID,"state":"running"]
    }
    func beginAgentRender(_ request:AgentRequest,source:String,
                          trustedLease:AgentRunLease?=nil,
                          trustedDestination:URL?=nil)throws->[String:Any] {
        guard !preparing else {throw CirclrError("이미 실행 중인 렌더 작업이 있습니다")}
        guard !playbackLoopChangeBusy,playbackLoopDrainTask == nil else {
            throw CirclrError("루프 전환 렌더가 끝난 뒤 에이전트 렌더를 시작하세요")
        }
        let args=request.arguments ?? AgentArguments(),snapshot=project,root=mediaRoot
        let isBounce=request.method=="bounce",arrangementID=args.arrangementID ?? project.activeArrangementID
        let file:URL?
        let approvedExport:TrustedExportPublisher.Destination?
        if isBounce {
            file=nil;approvedExport=nil
        } else if let trustedLease {
            guard let trustedDestination,args.path == nil,
                  trustedRun.active==trustedLease,
                  let selected=trustedExportDestination,
                  selected.url==trustedDestination else {
                throw CirclrError("trusted_run_scope: 앱이 선택한 WAV 위치가 필요합니다")
            }
            var isDirectory:ObjCBool=false
            guard FileManager.default.fileExists(
                atPath:trustedDestination.deletingLastPathComponent().path,
                isDirectory:&isDirectory),isDirectory.boolValue else {
                throw CirclrError("trusted_run_scope: 선택한 WAV 폴더를 찾을 수 없습니다")
            }
            file=trustedDestination;approvedExport=selected
        } else {
            guard let path=args.path,path.hasSuffix(".wav") else {throw CirclrError(".wav 절대 경로가 필요합니다")}
            file=try agentPath(path);approvedExport=nil
        }
        if let file,FileManager.default.fileExists(atPath:file.path) {
            throw CirclrError("기존 파일을 보존하려면 새 WAV 이름을 사용하세요")
        }
        let use=project.arrangements.first{$0.id==arrangementID}?.uses.first{$0.id==args.useID}
        // Resolve once before allocating a job, then render and persist that exact policy.
        // In particular, an omitted MCP value never reads the UI session preference.
        let tail:TailPlan
        let sectionRender:(plan:SectionSignalPlan,clock:MusicClock)?
        let albumRender:ExecutionPlan?
        if let seconds=args.tailSeconds {
            guard seconds.isFinite,(0...RenderTailPlanner.maximumTailSeconds).contains(seconds) else {
                throw CirclrError("tailSeconds는 0–120초의 유한한 숫자여야 합니다")
            }
        }
        if isBounce {
            guard let use,let trackID=args.trackID else {throw CirclrError("바운스에는 useID와 trackID가 필요합니다")}
            let target=try BounceEditing.target(trackID:trackID,useID:use.id,arrangementID:arrangementID,in:snapshot)
            let (section,context,clock)=try ArrangementCompiler.context(project:snapshot,use:use,arrangementID:arrangementID)
            guard let plan=try SectionGraphCompiler.compile(project:snapshot,section:section,use:use,context:context,clock:clock) else {throw CirclrError("음악 그래프가 없습니다")}
            let selectedPlan=try plan.selectingOutput(target.outputNodeID)
            tail=try RenderTailPlanner.section(selectedPlan,project:snapshot,clock:clock,trackID:trackID,requestedSeconds:args.tailSeconds)
            sectionRender=(selectedPlan,clock);albumRender=nil
        }else{
            let plan=try AlbumCompiler.executionPlan(snapshot)
            tail=try RenderTailPlanner.arrangement(project:snapshot,plan:plan,requestedSeconds:args.tailSeconds,includeStems:false)
            sectionRender=nil;albumRender=plan
        }
        let renderDrain=takeRenderDrainForAgent()
        let productionDrain=takeProductionDrain()
        let generation=productionGeneration,jobID=newID()
        let lease=AgentJobCommitLease(projectID:snapshot.id,revision:snapshot.musicRevision,
                                      generation:generation,jobID:jobID)
        let renderTitle=(isBounce ? "이펙트 포함 바운스":"앨범 WAV 렌더")+String(format:" · 여운 %.2f초",tail.effectiveSeconds)
        agentJob=AgentJob(id:jobID,kind:request.method,state:"running",message:([renderTitle]+tail.notices).joined(separator:" · "),tail:tail)
        preparing=true;progress=0;status=agentJob!.message
        productionTask=Task { [weak self] in
            await renderDrain.wait()
            await productionDrain.wait()
            guard let self,self.productionGeneration==generation,!Task.isCancelled else{return}
            do {
                let body=sectionRender?.clock.seconds ?? 0
                let worker:Task<PCM,Error>
                if let sectionRender,let trackID=args.trackID {
                    worker=Task.detached(priority:.userInitiated){let buffers=try await SectionGraphRenderer.render(sectionRender.plan,project:snapshot,root:root,clock:sectionRender.clock,tail:tail.effectiveSeconds,applyOutputGain:false);guard let pcm=buffers[trackID] else {throw CirclrError("트랙 출력을 찾을 수 없습니다")};return try Self.checkedAgentPCM(pcm)}
                }else if let plan=albumRender {
                    worker=Task.detached(priority:.userInitiated){let pcm=try await ArrangementRenderer.render(project:snapshot,root:root,plan:plan,tailSeconds:tail.effectiveSeconds,includeStems:false){message,value in DispatchQueue.main.async{[weak self] in guard let self,self.productionGeneration==generation else{return};self.progress=value;self.agentJob?.progress=value;self.agentJob?.message=message;self.status=message}}.mix;return try Self.checkedAgentPCM(pcm)}
                }else{throw CirclrError("렌더 계획이 없습니다")}
                self.productionWorker=worker
                let pcm=try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled,self.productionGeneration==generation else{return}
                try self.checkAgentJobCommit(lease,trustedLease:trustedLease)
                try AgentProjectEditing.check(request,project:self.project)
                try self.checkTrustedAgentDocument(snapshot,mediaRoot:root,
                                                   trustedLease:trustedLease,jobID:jobID)
                let endFrames=min(pcm.count,Int(PCM.rate*0.1))
                var endPeak=0.0,endSquares=0.0
                if endFrames>0 {
                    for i in (pcm.count-endFrames)..<pcm.count {
                        let left=Double(pcm.left[i]),right=Double(pcm.right[i])
                        guard left.isFinite,right.isFinite else {throw CirclrError("렌더 끝부분에 유효하지 않은 오디오 값이 있습니다")}
                        endPeak=max(endPeak,abs(left),abs(right));endSquares+=left*left+right*right
                    }
                    self.agentJob?.endWindowSeconds=Double(endFrames)/PCM.rate
                    self.agentJob?.endWindowPeak=endPeak
                    self.agentJob?.endWindowRMS=sqrt(endSquares/Double(endFrames*2))
                    self.agentJob?.endWindowHasSignal=endPeak>0.0001
                }
                self.agentJob?.renderedSeconds=pcm.duration
                if isBounce,let use,let trackID=args.trackID {
                    let url=self.productionMediaRoot.appendingPathComponent(newID()+".wav")
                    let stage=url.deletingLastPathComponent().appendingPathComponent(".circlr-agent-\(jobID).wav")
                    var published=false
                    do {
                        try await self.writeAgentWAVStage(pcm,to:stage)
                        try Task.checkCancellation();try self.checkAgentJobCommit(lease,trustedLease:trustedLease)
                        try AgentProjectEditing.check(request,project:self.project)
                        try self.checkTrustedAgentDocument(snapshot,mediaRoot:root,
                                                           trustedLease:trustedLease,jobID:jobID)
                        try FileManager.default.moveItem(at:stage,to:url);published=true
                        let name=(snapshot.tracks.first{$0.id==trackID}?.name ?? "트랙")+" 바운스"
                        var candidate=self.project;candidate.activeArrangementID=arrangementID
                        let id=try BounceEditing.apply(asset:Asset(name:name,path:url.path,duration:pcm.duration,sampleRate:PCM.rate),trackID:trackID,useID:use.id,bodySeconds:body,tailSeconds:tail.effectiveSeconds,in:&candidate)
                        candidate.activeArrangementID=self.project.activeArrangementID
                        let expectedRevision=self.project.musicRevision+1
                        self.mutate("\(source) 오디오 바운스"){$0=candidate}
                        guard self.project.musicRevision==expectedRevision,
                              self.project.assets.contains(where:{$0.path==url.path}) else {
                            throw CirclrError("바운스 결과를 문서에 적용하지 못했습니다")
                        }
                        self.agentJob?.nodeID=id
                        if source=="콘솔" || source=="사용자" {self.focusHierarchy(.music(arrangementID:arrangementID,useID:use.id,nodeID:id),detail:true)}
                    }catch{
                        try? FileManager.default.removeItem(at:stage)
                        if published {try? FileManager.default.removeItem(at:url)}
                        throw error
                    }
                }else if let file{
                    if let approvedExport,let trustedLease {
                        // The encoder writes outside the selected folder. Its
                        // pinned parent is opened by descriptor for staging and
                        // the final exclusive publication.
                        let stage=FileManager.default.temporaryDirectory
                            .appendingPathComponent(".circlr-agent-\(jobID)-\(newID()).wav")
                        defer {try? FileManager.default.removeItem(at:stage)}
                        try await self.writeAgentWAVStage(pcm,to:stage)
                        let publisher=Task.detached(priority:.userInitiated) {
                            try TrustedExportPublisher.prepare(source:stage,
                                destination:approvedExport,
                                checkCancellation:{try Task.checkCancellation()})
                        }
                        let prepared=try await withTaskCancellationHandler {
                            try await publisher.value
                        } onCancel: {
                            publisher.cancel()
                        }
                        defer {prepared.discard()}
                        try Task.checkCancellation()
                        try prepared.publish {
                            try Task.checkCancellation()
                            try self.checkAgentJobCommit(lease,trustedLease:trustedLease)
                            try AgentProjectEditing.check(request,project:self.project)
                            let authorized=try self.trustedRun.authorizedOwnedFileJobDestination(
                                for:request,lease:trustedLease,jobID:jobID,
                                ownedLease:self.trustedAgentJob?.lease,
                                ownedJobID:self.trustedAgentJob?.id,
                                project:self.project,document:self.currentTrustedDocument)
                            guard authorized==file else {throw CancellationError()}
                        }
                    } else {
                        let parent=file.deletingLastPathComponent()
                        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
                        let stage=parent.appendingPathComponent(".circlr-agent-\(jobID).wav")
                        do {
                            try await self.writeAgentWAVStage(pcm,to:stage)
                            try Task.checkCancellation();try self.checkAgentJobCommit(lease)
                            try AgentProjectEditing.check(request,project:self.project)
                            guard !FileManager.default.fileExists(atPath:file.path) else {throw CirclrError("렌더 중 같은 이름의 파일이 생성되었습니다")}
                            try FileManager.default.moveItem(at:stage,to:file)
                        }catch{try? FileManager.default.removeItem(at:stage);throw error}
                        self.agentJob?.path=file.path
                    }
                }
                self.preparing=false;self.progress=1;self.agentJob?.state="completed";self.agentJob?.progress=1;self.agentJob?.message=self.agentJob?.endWindowHasSignal == true ? "완료 · 마지막 0.1초에 신호가 남아 있습니다. 여운 길이를 확인하세요":"완료"
                self.status="\(request.method) 완료";self.recordActivity(source,"완료 · \(request.method) · \(jobID)")
            }catch{guard self.productionGeneration==generation else{return};self.preparing=false;self.agentJob?.state=error is CancellationError ? "cancelled":"failed";self.agentJob?.message=error.localizedDescription;self.status=error.localizedDescription;self.recordActivity(source,"실패 · \(request.method) · \(error.localizedDescription)")}
        }
        return ["jobID":jobID,"state":"running","tail":json(tail)]
    }
}
