import Foundation
import CirclrCore
import CirclrAudio

struct LiveLoopUpdate {
    let id=UUID()
    let commitGate=PlaybackLoopCommitGate()
    let projectID:ID
    let revision:Int
    let arrangementID:ID
    let useID:ID?
    var phase="preparing"
    var boundary:PlaybackLoopChangeStatus?
}

@MainActor extension AppStore {
    /// Polls musical identity, covering GUI edits, Undo/Redo and agent batches alike.
    func refreshLiveLoopUpdate() {
        guard playback.playing,playback.loopPCM != nil,playbackLoopMode != .off,
              let arrangementID=playbackLoopArrangementID,project.activeArrangementID==arrangementID,
              playbackLoopTransition == nil,!moviePreparing,movieWriter == nil,movieFinalizing == nil else {
            if liveLoopUpdate != nil {cancelLiveLoopUpdate()}
            return
        }
        if let pending=liveLoopUpdate {
            guard pending.projectID==project.id,pending.arrangementID==arrangementID else {cancelLiveLoopUpdate();playback.stop();return}
            if pending.phase == "preparing",pending.revision != project.musicRevision {cancelLiveLoopUpdate()}
            else if let boundary=pending.boundary,playback.elapsedSeconds>=boundary.elapsedSeconds,playback.pendingLoopChange == nil {
                prepared=playback.prepared;preparedKey="";liveLoopUpdate=nil
                status="루프 편집 반영 · revision \(pending.revision)"
            } else{return}
        }
        guard prepared?.plan.revision != project.musicRevision,liveLoopFailedRevision != project.musicRevision else{return}
        let snapshot=project,root=mediaRoot
        let request=LiveLoopUpdate(projectID:project.id,revision:project.musicRevision,arrangementID:arrangementID,useID:playbackLoopUseID)
        let previousTask=liveLoopTask,previousWorker=liveLoopWorker,drain=liveLoopDrainTask
        liveLoopUpdate=request
        liveLoopTask=Task { [weak self] in
            if let drain {await drain.value}
            if let previousTask {await previousTask.value}
            if let previousWorker {_ = try? await previousWorker.value}
            do {
                try await Task.sleep(for:.milliseconds(120))
                guard let self,self.isLiveLoopRequestCurrent(request,matchingRevision:true) else{return}
                let plan=try request.useID.map{try ArrangementCompiler.compile(snapshot,onlyUseID:$0)} ?? ArrangementCompiler.compile(snapshot)
                let worker=Task.detached(priority:.userInitiated) {
                    try await ArrangementRenderer.render(project:snapshot,root:root,plan:plan,includeStems:false,includeVisualization:true)
                }
                self.liveLoopWorker=worker
                let audio=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
                try Task.checkCancellation()
                guard self.isLiveLoopRequestCurrent(request,matchingRevision:true) else{return}
                self.liveLoopUpdate?.phase="scheduling"
                let boundary=try await self.playback.requestLoopChange(to:audio,commitGate:request.commitGate,shouldSchedule:{[weak self] in
                    self?.isLiveLoopRequestCurrent(request,matchingRevision:true) == true
                })
                guard self.isLiveLoopRequestCurrent(request,matchingRevision:false) else{return}
                self.liveLoopUpdate?.phase="queued";self.liveLoopUpdate?.boundary=boundary
                self.liveLoopWorker=nil;self.liveLoopTask=nil
                self.status="다음 루프 경계에 편집 반영 예약 · revision \(request.revision)"
            } catch {
                guard let self,self.liveLoopUpdate?.id==request.id else{return}
                self.liveLoopUpdate=nil;self.liveLoopWorker=nil;self.liveLoopTask=nil
                if self.project.musicRevision==request.revision {self.liveLoopFailedRevision=request.revision}
                if !(error is CancellationError) {self.status="현재 루프 유지 · 새 편집 준비 실패: "+error.localizedDescription}
            }
        }
        status="현재 루프 유지 · 편집 내용 준비 중"
    }
    func isLiveLoopRequestCurrent(_ request:LiveLoopUpdate,matchingRevision:Bool)->Bool {
        liveLoopUpdate?.id==request.id && project.id==request.projectID && project.activeArrangementID==request.arrangementID &&
        (!matchingRevision || project.musicRevision==request.revision) && playback.playing && playbackLoopTransition == nil && playbackLoopMode != .off
    }
    func cancelLiveLoopUpdate() {
        liveLoopUpdate?.commitGate.invalidate()
        liveLoopUpdate=nil
        let task=liveLoopTask,worker=liveLoopWorker
        task?.cancel();worker?.cancel();liveLoopTask=nil;liveLoopWorker=nil
        guard task != nil || worker != nil else{return}
        let previous=liveLoopDrainTask,id=UUID();liveLoopDrainID=id
        liveLoopDrainTask=Task { [weak self] in
            if let previous {await previous.value}
            if let task {await task.value}
            if let worker {_ = try? await worker.value}
            if self?.liveLoopDrainID==id {self?.liveLoopDrainTask=nil;self?.liveLoopDrainID=nil}
        }
    }
    var liveLoopUpdateState:[String:Any] {
        var result:[String:Any]=["phase":liveLoopUpdate?.phase ?? "idle","appliedRevision":prepared?.plan.revision ?? -1,"currentRevision":project.musicRevision]
        if let pending=liveLoopUpdate {result["pendingRevision"]=pending.revision;if let boundary=pending.boundary {result["boundaryElapsedSeconds"]=boundary.elapsedSeconds}}
        return result
    }
}
