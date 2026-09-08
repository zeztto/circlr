import Foundation
import CirclrAudio

extension AppStore {
    func refreshOutputStatus() {
        let next=playback.outputStatus
        if outputStatus != next {
            let previous=outputStatus;outputStatus=next
            if previous.phase != next.phase || previous.step != next.step || previous.request != next.request {
                if !outputDetail.isEmpty {recordActivity("출력",outputDetail)}
            }
        }
    }
    var outputLabel:String? {
        if outputStatus.phase == .connecting {return "출력 \(outputStatus.request == .waiting ? "연결":"대기") \(outputStatus.elapsedSeconds)초"}
        if outputStatus.phase == .ready,[.timedOut,.cancelled].contains(outputStatus.request) {return "출력 준비됨"}
        return nil
    }
    var outputDetail:String {
        if outputStatus.phase == .connecting {
            let step:String
            switch outputStatus.step {
            case .player:step="플레이어 연결 중"
            case .device:step="시스템 출력 장치 응답 대기"
            case .routing:step="출력 믹서 연결 중"
            default:step="출력 연결 중"
            }
            return step+" · \(outputStatus.elapsedSeconds)초. "+(outputStatus.request == .waiting ? "Space로 재생 준비를 취소할 수 있습니다.":"재생 요청은 멈췄으며 장치 응답을 기다립니다. 준비되면 다시 재생하세요.")
        }
        if outputStatus.phase == .ready,[.timedOut,.cancelled].contains(outputStatus.request) {return "출력 준비 완료. Space로 다시 재생하세요."}
        return ""
    }
    func handlePlaybackError(_ error:Error) {
        refreshOutputStatus()
        if case PlaybackOutputWaitError.timedOut = error {status=error.localizedDescription}
        else if !(error is CancellationError) {fail(error)}
    }
}
