import Foundation
import AppKit
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
}
extension AppStore {
    func recordActivity(_ source:String,_ message:String) {
        activitySequence+=1
        activity.append(ActivityEvent(id:activitySequence,time:Date(),source:source,message:message,revision:project.musicRevision))
        if activity.count>500{activity.removeFirst(activity.count-500)}
    }
    func startAgentBridge() {
        do {
            agentSocket=try AgentSocket(directory:productionMediaRoot.deletingLastPathComponent().appendingPathComponent("Agent")){[weak self] data,reply in
                guard let self else{return}
                let result=self.receiveAgent(data,source:"에이전트")
                reply((try? JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])) ?? Data(#"{"ok":false,"error":"encoding"}"#.utf8))
            }
            recordActivity("연결","로컬 MCP 연결 준비 · 휠로 확대·축소 · Ctrl `로 콘솔 접기")
        }catch{recordActivity("연결",error.localizedDescription)}
    }
    func json<T:Encodable>(_ value:T)->Any {((try? JSONSerialization.jsonObject(with:JSONEncoder().encode(value),options:[.fragmentsAllowed])) ?? NSNull())}
    func agentState()->[String:Any] {
        ["projectID":project.id,"revision":project.musicRevision,"layoutRevision":project.portLayout?.revision ?? 0,"name":project.name,"dirty":dirty,"path":projectURL?.path ?? "","global":json(project.global),
         "tracks":json(project.tracks),"assets":json(project.assets),"album":json(project.album),"patterns":json(project.patterns),"activeArrangementID":project.activeArrangementID,
         "arrangements":project.arrangements.map{["id":$0.id,"name":$0.name,"uses":$0.uses.map{["id":$0.id,"sectionID":$0.sectionID,"name":$0.name]}]},
         "selection":json(hierarchySelection),"selectedNoteIDs":json(selectedMIDIIDs.sorted()),
         "automationEditor":["visible":automationVisible,"parameter":automationParameter.rawValue,"selectedPointID":json(selectedAutomationPointID),"displayBeats":automationDisplayedBeats],
         "recording":["midi":midiRecording,"audio":audioRecording,"permissionPending":audioRecordPending && audioCapturePhase != .starting,"format":json(audioInputFormat),"phase":audioRecordPending && !recorder.busy ? "authorizing":audioCapturePhase.rawValue,"busy":audioRecordingBusy,"seconds":audioInputSeconds,"peak":audioInputLevel,"message":audioCaptureMessage,"recoveryPath":audioRecoveryURL?.path ?? ""],"job":json(agentJob),"sequence":activitySequence,
         "playback":capturePlaybackVisualization?() ?? ["playing":playback.playing,"seconds":playback.seconds],"output":json(playback.outputStatus),"audition":json(auditionOutput.status),
         "view":["zoom":hierarchyZoom,"layout":project.usesOrbits ? "orbit":"freeform","consoleOpen":consoleOpen,"consoleBounds":[consoleBounds.minX,consoleBounds.minY,consoleBounds.width,consoleBounds.height]],
         "library":["open":libraryOpen,"folders":library.folders.count,"files":library.entries.count,"selectedFiles":library.chosenIDs.count,"scanning":library.scanning,"searching":library.searching,"previewPreparing":library.previewPreparing,"previewPlaying":library.previewing,"previewPending":library.previewPending,"previewSeconds":library.previewSeconds],
         "runtime":["version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development","build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "development","capabilities":["soundCatalog":1],"bundleID":Bundle.main.bundleIdentifier ?? "","windows":NSApplication.shared.windows.filter{$0.identifier?.rawValue=="main"}.map{["visible":$0.isVisible,"minimized":$0.isMiniaturized]}]]
    }
    func receiveAgent(_ data:Data,source:String)->[String:Any] {
        do {
            let request=try JSONDecoder().decode(AgentRequest.self,from:data)
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
    func executeAgent(_ request:AgentRequest,source:String) throws -> [String:Any] {
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
        case "stop":stop();return ["state":"stopped"]
        case "play":guard !preparing else {throw CirclrError("현재 렌더 작업을 정지한 뒤 재생하세요")};if !playback.playing{play()};recordActivity(source,"재생 요청");return ["state":"preparing_or_playing"]
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
            let candidate=try AgentProjectEditing.apply(request,to:project)
            mutate("에이전트 편집 · \(args.operations?.count ?? 0)개"){$0=candidate}
            cancelAudition()
            if let compositionID=args.operations?.last(where:{$0.kind=="select_arrangement"})?.compositionID {
                // Explicit selection navigates to its owner; background copies and names keep the editor scope.
                hierarchySettingsOpen=false;focusHierarchy(.composition(compositionID))
            }else{normalizeHierarchySelection()}
            return agentState()
        case "undo":
            if let expected=args.expectedLayoutRevision {try AgentPortEditing.checkLayout(expected,project:project)}
            guard undoCount>0 else {throw CirclrError("취소할 편집이 없습니다")};undo();return agentState()
        case "save":
            guard let path=args.path ?? projectURL?.path,path.hasSuffix(".circlr") else {throw CirclrError("저장할 .circlr 절대 경로가 필요합니다")}
            let url=try agentPath(path)
            if FileManager.default.fileExists(atPath:url.path),try ProjectStore.load(url).project.id != project.id {throw CirclrError("다른 프로젝트를 덮어쓸 수 없습니다")}
            captureViewport();project=try ProjectStore.saveSession(project,to:url,mediaRoot:mediaRoot);projectURL=url;mediaRoot=url;dirty=false;clearSavedRecovery();status="에이전트 저장 완료";return agentState()
        case "open":
            return try beginAgentOpen(request,source:source)
        case "bounce","export":return try beginAgentRender(request,source:source)
        case "restore_bounce":
            guard let use=args.useID,let node=args.nodeID else {throw CirclrError("useID와 nodeID가 필요합니다")}
            var candidate=project;candidate.activeArrangementID=args.arrangementID ?? project.activeArrangementID
            try BounceEditing.restore(nodeID:node,useID:use,in:&candidate);candidate.activeArrangementID=project.activeArrangementID
            mutate("바운스 원본 복원"){$0=candidate};return agentState()
        default:throw CirclrError("지원하지 않는 method: \(request.method)")
        }
    }
    func agentPath(_ path:String)throws->URL {
        guard path.hasPrefix("/"),!path.contains("\0") else {throw CirclrError("절대 경로를 사용하세요")}
        return URL(fileURLWithPath:path).standardizedFileURL
    }
    func beginAgentOpen(_ request:AgentRequest,source:String)throws->[String:Any] {
        guard !dirty else {throw CirclrError("저장되지 않은 편집이 있습니다. 먼저 save하세요")}
        guard !preparing else {throw CirclrError("현재 작업을 정지한 뒤 프로젝트를 여세요")}
        guard let path=request.arguments?.path else {throw CirclrError("path가 필요합니다")}
        let url=try agentPath(path)
        stop();productionGeneration+=1
        let generation=productionGeneration,jobID=newID()
        agentJob=AgentJob(id:jobID,kind:"open",state:"running",message:"프로젝트 읽는 중")
        preparing=true;progress=0;status="프로젝트 읽는 중 · macOS 접근 요청이 있으면 확인하세요"
        productionTask=Task { [weak self] in
            guard let self else{return}
            let worker=Task.detached(priority:.userInitiated){try Task.checkCancellation();let loaded=try ProjectStore.load(url);try Task.checkCancellation();return loaded}
            self.agentOpenWorker=worker
            do {
                let loaded=try await worker.value
                guard !Task.isCancelled,self.productionGeneration==generation else{return}
                try AgentProjectEditing.check(request,project:self.project)
                guard !self.dirty else {throw CirclrError("읽는 동안 문서가 변경되었습니다")}
                var p=loaded.project;p.enableAlbum();p=try SectionGraphMigration.migrate(p)
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
    func beginAgentRender(_ request:AgentRequest,source:String)throws->[String:Any] {
        guard !preparing else {throw CirclrError("이미 실행 중인 렌더 작업이 있습니다")}
        let args=request.arguments ?? AgentArguments(),snapshot=project,root=mediaRoot
        let isBounce=request.method=="bounce",arrangementID=args.arrangementID ?? project.activeArrangementID
        let file:URL?
        if isBounce{file=nil}else{guard let path=args.path,path.hasSuffix(".wav") else {throw CirclrError(".wav 절대 경로가 필요합니다")};file=try agentPath(path);guard !FileManager.default.fileExists(atPath:file!.path) else {throw CirclrError("기존 파일을 보존하려면 새 WAV 이름을 사용하세요")}}
        let use=project.arrangements.first{$0.id==arrangementID}?.uses.first{$0.id==args.useID}
        if isBounce {
            guard let use,let trackID=args.trackID else {throw CirclrError("바운스에는 useID와 trackID가 필요합니다")}
            _=try BounceEditing.target(trackID:trackID,useID:use.id,arrangementID:arrangementID,in:project)
        }
        productionGeneration+=1;let generation=productionGeneration,jobID=newID()
        agentJob=AgentJob(id:jobID,kind:request.method,state:"running",message:isBounce ? "이펙트 포함 바운스":"앨범 WAV 렌더")
        preparing=true;progress=0;status=agentJob!.message
        productionTask=Task { [weak self] in
            guard let self else{return}
            do {
                var body=0.0
                let worker:Task<PCM,Error>
                if isBounce,let use,let trackID=args.trackID {
                    let (section,context,clock)=try ArrangementCompiler.context(project:snapshot,use:use,arrangementID:arrangementID);body=clock.seconds
                    guard let plan=try SectionGraphCompiler.compile(project:snapshot,section:section,use:use,context:context,clock:clock) else {throw CirclrError("음악 그래프가 없습니다")}
                    worker=Task.detached(priority:.userInitiated){let buffers=try await SectionGraphRenderer.render(plan,project:snapshot,root:root,clock:clock,tail:2,applyOutputGain:false);guard let pcm=buffers[trackID] else {throw CirclrError("트랙 출력을 찾을 수 없습니다")};return pcm}
                }else{
                    let plan=try AlbumCompiler.executionPlan(snapshot)
                    worker=Task.detached(priority:.userInitiated){try await ArrangementRenderer.render(project:snapshot,root:root,plan:plan,includeStems:false){message,value in DispatchQueue.main.async{[weak self] in guard let self,self.productionGeneration==generation else{return};self.progress=value;self.agentJob?.progress=value;self.agentJob?.message=message;self.status=message}}.mix}
                }
                self.productionWorker=worker;let pcm=try await worker.value
                guard !Task.isCancelled,self.productionGeneration==generation else{return}
                try AgentProjectEditing.check(request,project:self.project)
                guard pcm.peak<=1 else {throw CirclrError("출력이 0 dBFS를 넘습니다. Gain을 낮추세요")}
                if isBounce,let use,let trackID=args.trackID {
                    let url=self.productionMediaRoot.appendingPathComponent(newID()+".wav");try pcm.writeWAV(url)
                    do {
                        let name=(snapshot.tracks.first{$0.id==trackID}?.name ?? "트랙")+" 바운스"
                        var candidate=self.project;candidate.activeArrangementID=arrangementID
                        let id=try BounceEditing.apply(asset:Asset(name:name,path:url.path,duration:pcm.duration,sampleRate:PCM.rate),trackID:trackID,useID:use.id,bodySeconds:body,tailSeconds:2,in:&candidate)
                        candidate.activeArrangementID=self.project.activeArrangementID
                        self.mutate("\(source) 오디오 바운스"){$0=candidate};self.agentJob?.nodeID=id
                        if source=="콘솔" || source=="사용자" {self.focusHierarchy(.music(arrangementID:arrangementID,useID:use.id,nodeID:id),detail:true)}
                    }catch{try? FileManager.default.removeItem(at:url);throw error}
                }else if let file{
                    guard !FileManager.default.fileExists(atPath:file.path) else {throw CirclrError("렌더 중 같은 이름의 파일이 생성되었습니다")}
                    let parent=file.deletingLastPathComponent();try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
                    let stage=parent.appendingPathComponent(".circlr-agent-\(jobID).wav")
                    do {try pcm.writeWAV(stage);try FileManager.default.moveItem(at:stage,to:file)}catch{try? FileManager.default.removeItem(at:stage);throw error}
                    self.agentJob?.path=file.path
                }
                self.preparing=false;self.progress=1;self.agentJob?.state="completed";self.agentJob?.progress=1;self.agentJob?.message="완료"
                self.status="\(request.method) 완료";self.recordActivity(source,"완료 · \(request.method) · \(jobID)")
            }catch{guard self.productionGeneration==generation else{return};self.preparing=false;self.agentJob?.state=error is CancellationError ? "cancelled":"failed";self.agentJob?.message=error.localizedDescription;self.status=error.localizedDescription;self.recordActivity(source,"실패 · \(request.method) · \(error.localizedDescription)")}
        }
        return ["jobID":jobID,"state":"running"]
    }
}
