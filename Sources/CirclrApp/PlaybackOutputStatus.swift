import Foundation
import CirclrAudio

extension AppStore {
    func refreshOutputStatus() {
        var next=playback.outputStatus
        // The canvas clock already updates meters; do not invalidate this status row per frame.
        next.transport.seconds=0
        if outputStatus != next {
            let previous=outputStatus;outputStatus=next
            if previous.phase != next.phase || previous.step != next.step || previous.request != next.request || previous.transport.phase != next.transport.phase {
                if !outputDetail.isEmpty {recordActivity("출력",outputDetail)}
            }
        }
    }
    var outputLabel:String? {
        switch outputStatus.transport.phase {
        case .starting:return "출력 시작 중"
        case .stopping:return "출력 정리 중"
        case .failed:return "출력 시작 실패"
        default:break
        }
        if outputStatus.phase == .connecting {return "출력 \(outputStatus.request == .waiting ? "연결":"대기") \(outputStatus.elapsedSeconds)초"}
        if outputStatus.phase == .ready,[.timedOut,.cancelled].contains(outputStatus.request) {return "출력 준비됨"}
        return nil
    }
    var outputDetail:String {
        switch outputStatus.transport.phase {
        case .starting:return "장치에서 재생을 시작하고 있습니다. Space로 취소할 수 있습니다."
        case .stopping:return "재생 요청은 멈췄으며 출력 장치를 정리하고 있습니다. 편집은 계속할 수 있습니다. 정리가 끝나면 다시 재생하세요."
        case .failed:return outputStatus.transport.message ?? "출력을 시작할 수 없습니다. 다시 재생하세요."
        default:break
        }
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
        else if error is PlaybackTransportError {status=error.localizedDescription}
        else if !(error is CancellationError) {fail(error)}
    }
}
