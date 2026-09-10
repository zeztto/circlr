import AppKit
import CirclrCore
import CirclrAudio

struct MediaImportRequest:Equatable {
    let projectID:ID
    let revision:Int
    let generation:Int
    let selection:CircleAddress?
    let destination:AudioImportDestination
}

extension AppStore {
    var canStartMediaImport:Bool {!preparing && !playback.playing && !midiRecording && !audioRecordPending && !audioRecordingBusy && !moviePreparing && movieWriter==nil}
    func audioImportDestination(at point:Point?)->AudioImportDestination? {
        if let id=editPatternID {return .pattern(id:id,beat:selectedBeat)}
        guard let use=selectedUse else{return nil}
        return .section(arrangementID:project.activeArrangementID,useID:use.id,trackID:AudioImportPlacement.suggestedTrack(for:hierarchySelection,selectedTrack:selectedTrackID),beat:selectedBeat,position:point,original:editOriginal)
    }
    func mediaImportRequest(_ destination:AudioImportDestination)->MediaImportRequest {
        MediaImportRequest(projectID:project.id,revision:project.musicRevision,generation:mediaImportGeneration,selection:hierarchySelection,destination:destination)
    }
    func cancelMediaImport() {
        mediaImportGeneration+=1
        if mediaImportTask != nil {preparing=false}
        mediaImportTask?.cancel();mediaImportWorker?.cancel();mediaImportTask=nil;mediaImportWorker=nil
    }
    func beginAudioImport(_ urls:[URL],request:MediaImportRequest,retaining access:[LibraryAccess]=[]) {
        guard canStartMediaImport,request.projectID==project.id,request.revision==project.musicRevision,request.generation==mediaImportGeneration else {status="대상이 변경됐거나 다른 작업 중입니다. 파일을 다시 가져오세요";return}
        library.stopPreview()
        mediaImportGeneration+=1;let generation=mediaImportGeneration
        let scoped=urls.filter{$0.startAccessingSecurityScopedResource()}
        let root=productionMediaRoot.deletingLastPathComponent().appendingPathComponent("Imports")
        preparing=true;progress=0;status="오디오 \(urls.count)개 복사·검증 중 · 정지로 취소"
        let worker=Task.detached(priority:.userInitiated) {
            try AudioFileImport.stage(urls,under:root){[weak self] value in
                Task { @MainActor in
                    guard let self,self.mediaImportGeneration==generation,self.mediaImportTask != nil else{return}
                    self.progress=value
                }
            }
        }
        mediaImportWorker=worker
        mediaImportTask=Task { [weak self] in
            defer{scoped.forEach{$0.stopAccessingSecurityScopedResource()};withExtendedLifetime(access){}}
            do {
                let staged=try await worker.value
                var retained=false;defer{if !retained{staged.discard()}}
                guard let self,generation==self.mediaImportGeneration,!Task.isCancelled else{return}
                defer{self.mediaImportTask=nil;self.mediaImportWorker=nil;self.preparing=false}
                guard self.project.id==request.projectID,self.project.musicRevision==request.revision,!self.midiRecording,!self.audioRecordPending,!self.audioRecordingBusy else {self.status="가져오는 동안 음악이 변경되어 파일을 적용하지 않았습니다";return}
                var candidate=self.project
                let clips=try AudioImportEditing.apply(staged.assets,to:request.destination,projectID:request.projectID,revision:request.revision,in:&candidate)
                self.mutate("오디오 \(staged.assets.count)개 가져오기"){$0=candidate}
                guard staged.assets.allSatisfy({asset in self.project.assets.contains{$0.id==asset.id}}) else{return}
                retained=true
                if self.hierarchySelection==request.selection,let clip=clips.first {
                    self.selectedClipID=clip
                    if case .section(let a,let u,_,_,_,_)=request.destination {
                        self.hierarchySettingsOpen=false
                        // Explicit import focus opens the new audio, even when the
                        // previous source was being edited in automation mode.
                        self.automationOpen=false
                        self.focusHierarchy(clips.count==1 ? .music(arrangementID:a,useID:u,nodeID:"audio:\(clip)"):.section(arrangementID:a,useID:u),detail:clips.count==1)
                        if clips.count==1,!(NSApp.keyWindow?.firstResponder is NSTextView) {self.requestEditorNavigationFocus()}
                    }
                }
            } catch {
                guard let self,self.mediaImportGeneration==generation,!Task.isCancelled else{return}
                self.mediaImportTask=nil;self.mediaImportWorker=nil;self.preparing=false
                self.status="오디오 가져오기 실패: \(error.localizedDescription)"
            }
        }
    }
}
