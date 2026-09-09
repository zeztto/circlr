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
        if previous.phase != next.phase,next.phase != .idle {
            recordActivity("미리 듣기",next.phase == .ready ? "악기 준비 완료":auditionDetail)
        }
    }
    var auditionLabel:String? {
        switch auditionStatus.phase {
        case .preparing:return "미리 듣기 준비 \(auditionStatus.elapsedSeconds)초"
        case .stopping:return "미리 듣기 정리 중"
        case .failed:return "미리 듣기 실패"
        case .idle,.ready:return nil
        }
    }
    var auditionDetail:String {
        if let message=auditionStatus.message{return message}
        switch auditionStatus.phase {
        case .preparing:return "악기 미리 듣기 준비 중 · \(auditionStatus.elapsedSeconds)초. Space로 취소할 수 있습니다. 준비 전에 놓은 건반은 재생하지 않습니다."
        case .stopping:return "연주 요청을 취소했습니다. 장치 응답 후 정리하며, 편집은 계속할 수 있습니다."
        case .failed:return "미리 듣기를 준비하지 못했습니다. 악기 설정을 확인하고 다시 연주하세요."
        case .idle,.ready:return ""
        }
    }
}
