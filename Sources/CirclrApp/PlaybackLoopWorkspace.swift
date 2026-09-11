import Foundation
import CirclrCore
import CirclrAudio

struct WorkspaceLoopTransition {
    let id=UUID()
    let projectID:ID
    let revision:Int
    let mode:PlaybackLoopMode
    let arrangementID:ID
    let useID:ID?
    var phase="rendering"
    var progress=0.0
    var boundary:PlaybackLoopChangeStatus?
}

@MainActor extension AppStore {
    var playbackLoopChangeBusy:Bool {playbackLoopTransition != nil}
    var canChoosePlaybackLoop:Bool {
        !preparing && !moviePreparing && !playbackLoopChangeBusy && !audioRecordingBusy && !midiRecording &&
        (!playback.playing || playback.loopPCM == nil || playbackLoopMode != .off)
    }
    @discardableResult func choosePlaybackLoop(_ mode:PlaybackLoopMode)->Bool {
        guard canChoosePlaybackLoop else {status=audioRecordingBusy || midiRecording ? "오디오·MIDI 녹음을 마친 뒤 루프 범위를 바꾸세요":"진행 중인 루프 전환을 기다리거나 정지하세요";return false}
        // One-shot output is never restarted to enable a loop. This setting applies on the next Play.
        guard playback.playing,playback.loopPCM != nil else {
            playbackLoopMode=mode
            status=(playback.playing ? "다음 재생에 적용 · ":"")+loopModeTitle(mode)+(mode == .section ? " · 재생 시작 시 선택 섹션 고정":"")
            return true
        }
        let snapshot=project,root=mediaRoot
        let useID=mode == .section ? selectedUse?.id:nil
        guard mode != .section || useID != nil else {status="루프할 섹션을 먼저 선택하세요";return false}
        let request=WorkspaceLoopTransition(projectID:snapshot.id,revision:snapshot.musicRevision,mode:mode,arrangementID:snapshot.activeArrangementID,useID:useID)
        playbackLoopTransition=request
        status=mode == .off ? "현재 반복을 마친 뒤 잔향 재생":"현재 루프 재생 유지 · 새 범위 준비"
        playbackLoopTask=Task { [weak self] in
            guard let self else{return}
            do {
                let audio:PreparedAudio?
                if mode == .off {audio=nil}
                else {
                    let plan=try useID.map{try ArrangementCompiler.compile(snapshot,onlyUseID:$0)} ?? ArrangementCompiler.compile(snapshot)
                    let worker=Task.detached(priority:.userInitiated) {
                        try await ArrangementRenderer.render(project:snapshot,root:root,plan:plan,includeStems:false,includeVisualization:true) {_,progress in
                            Task{@MainActor [weak self] in
                                guard self?.playbackLoopTransition?.id==request.id else{return}
                                self?.playbackLoopTransition?.progress=progress
                            }
                        }
                    }
                    self.playbackLoopWorker=worker
                    audio=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
                }
                try Task.checkCancellation()
                guard self.playbackLoopTransition?.id==request.id else{return}
                guard self.project.id==request.projectID,self.project.musicRevision==request.revision,self.playback.playing,!self.audioRecordingBusy,!self.midiRecording else {
                    throw CirclrError("곡이 변경되어 루프 전환을 취소했습니다")
                }
                self.playbackLoopTransition?.phase="scheduling"
                let scheduled:PlaybackLoopChangeStatus
                if let audio {
                    scheduled=try await self.playback.requestLoopChange(to:audio){[weak self] change,loop in
                        guard let self else{throw CancellationError()}
                        try self.scheduleMovieLoopChange(change,loop:loop)
                    }
                } else {
                    scheduled=try await self.playback.finishLoopAtBoundary{[weak self] change,loop in
                        guard let self else{throw CancellationError()}
                        try self.scheduleMovieLoopChange(change,loop:loop)
                    }
                }
                try Task.checkCancellation()
                guard self.playbackLoopTransition?.id==request.id else{return}
                guard self.project.id==request.projectID,self.project.musicRevision==request.revision else {
                    self.stop();throw CirclrError("곡 변경과 루프 예약이 겹쳐 안전하게 정지했습니다")
                }
                self.playbackLoopTransition?.boundary=scheduled
                self.playbackLoopTransition?.phase="scheduled"
                self.playbackLoopWorker=nil;self.playbackLoopTask=nil
                self.status="루프 경계에서 "+self.loopModeTitle(mode)+" 적용 예정"
                self.refreshPlaybackLoopTransition()
            } catch {
                guard self.playbackLoopTransition?.id==request.id else{return}
                self.playbackLoopTransition=nil;self.playbackLoopWorker=nil;self.playbackLoopTask=nil
                if !(error is CancellationError) {self.fail(error)}
            }
        }
        return true
    }
    func cancelPlaybackLoopTransition() {
        playbackLoopTransition=nil
        playbackLoopTask?.cancel();playbackLoopTask=nil
        playbackLoopWorker?.cancel();playbackLoopWorker=nil
    }
    func refreshPlaybackLoopTransition() {
        guard let pending=playbackLoopTransition else{return}
        if !playback.playing {
            // A short exit tail may finish between UI ticks. Explicit Stop clears this request first.
            let transport=playback.outputStatus.transport
            if let boundary=pending.boundary,boundary.exiting,transport.phase == .idle,transport.loopChange?.id==boundary.id {
                playbackLoopMode = .off
            }
            cancelPlaybackLoopTransition();return
        }
        guard project.id==pending.projectID,project.musicRevision==pending.revision,!audioRecordingBusy,!midiRecording else {
            if pending.phase=="rendering" {cancelPlaybackLoopTransition();status="곡이 변경되어 새 루프 준비를 취소했습니다"}
            else {stop();status="곡 변경과 루프 예약이 겹쳐 안전하게 정지했습니다"}
            return
        }
        guard let boundary=pending.boundary,playback.elapsedSeconds>=boundary.elapsedSeconds,
              playback.pendingLoopChange == nil else{return}
        playbackLoopMode=pending.mode
        playbackLoopArrangementID=pending.arrangementID;playbackLoopUseID=pending.useID
        prepared=playback.prepared;preparedKey=""
        playbackLoopTransition=nil
        status=pending.mode == .off ? "루프 해제 · 잔향이 끝나면 정지":loopModeTitle(pending.mode)+" 재생 중"
    }
    func loopModeTitle(_ mode:PlaybackLoopMode)->String {
        switch mode {case .off:return "루프 꺼짐";case .song:return "곡 루프";case .section:return "섹션 루프"}
    }
    var playbackLoopState:[String:Any] {
        var value:[String:Any]=["mode":playbackLoopMode.rawValue,"busy":playbackLoopChangeBusy,
            "outputPlaying":playback.playing,"arrangementID":playbackLoopArrangementID ?? "","useID":playbackLoopUseID ?? "",
            "phase":playbackLoopTransition?.phase ?? (playback.playing && playback.loopPCM != nil && playbackLoopMode == .off ? "tail":"idle")]
        if let pending=playbackLoopTransition {
            value["pendingMode"]=pending.mode.rawValue;value["progress"]=pending.progress
            value["pendingArrangementID"]=pending.arrangementID;value["pendingUseID"]=pending.useID ?? ""
            if let boundary=pending.boundary {value["boundaryElapsedSeconds"]=boundary.elapsedSeconds;value["boundaryElapsedFrame"]=boundary.elapsedFrame}
        }
        return value
    }
    var playbackLoopCaption:String? {
        if let pending=playbackLoopTransition {return pending.phase=="rendering" ? "재생 유지 · 새 루프 준비 \(Int(pending.progress*100))%":"재생 유지 · 다음 경계에서 "+loopModeTitle(pending.mode)}
        guard playback.playing,playback.loopPCM != nil else{return nil}
        if playbackLoopMode == .off {return "루프 해제 · 잔향 재생 중"}
        return loopModeTitle(playbackLoopMode)+" · \(playback.loopIteration+1)회"
    }
}
