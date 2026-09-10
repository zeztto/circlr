import Foundation
import CirclrCore
import CirclrAudio

extension AppStore {
    func cancelAudition() {auditionOutput.cancel();refreshAuditionStatus()}
    @discardableResult func audition(pitch:Int,velocity:Int,on:Bool)->AuditionNoteToken? {
        guard let track=selectedTrack else{return nil}
        let key=project.id+":"+track.id
        let target=AuditionTarget(key:key,instrument:track.instrument,project:project,root:mediaRoot)
        let token=auditionOutput.note(target:target,pitch:pitch,velocity:velocity,on:on)
        refreshAuditionStatus();return token
    }
    func refreshAuditionStatus() {
        let next=auditionOutput.status
        guard next != auditionStatus else{return}
        let previous=auditionStatus;auditionStatus=next
        if auditionPresentation(for:previous).logIdentity != auditionPresentation.logIdentity,next.phase != .idle {
            recordActivity("미리 듣기",next.phase == .ready ? "악기 준비 완료":auditionDetail)
        }
    }
    var auditionPresentation:AuditionPresentation {auditionPresentation(for:auditionStatus)}
    private func auditionPresentation(for value:AuditionStatus)->AuditionPresentation {
        let event=value.trace?.inFlight.flatMap{$0.stage == .note ? nil:$0} ?? value.trace?.events.last(where:{$0.stage != .note})
        return AuditionPresentation(phase:value.phase.rawValue,stage:event?.stage.rawValue,stagePhase:event?.phase.rawValue,
            elapsedSeconds:value.elapsedSeconds,message:value.message,interruption:value.trace?.interruption?.reason.rawValue,
            interruptedStage:value.trace?.interruption?.inFlight?.stage.rawValue)
    }
    var auditionLabel:String? {auditionPresentation.label}
    var auditionDetail:String {auditionPresentation.detail}
}
