import Foundation
import CirclrAudio

extension AppStore {
    func refreshOutputStatus() {
        var next=playback.outputStatus
        // The canvas clock already updates meters; do not invalidate this status row per frame.
        next.transport.seconds=0
        if outputStatus != next {
            let previous=outputStatus;outputStatus=next
            if previous.phase != next.phase || previous.step != next.step || previous.request != next.request || previous.transport.phase != next.transport.phase || previous.trace?.sessionID != next.trace?.sessionID || previous.trace?.events.last?.stage != next.trace?.events.last?.stage {
                if !outputDetail.isEmpty {recordActivity("출력",outputDetail)}
            }
        }
    }
    var outputCanCancel:Bool {
        outputStatus.request == .waiting && (outputStatus.transport.phase == .starting || outputStatus.phase == .connecting)
    }
    private var outputPreparationStage:String? {
        guard let stage=outputStatus.trace?.events.last?.stage else{return nil}
        switch stage {
        case .cafWrite:return "파일 준비"
        case .helperHello:return "출력 연결"
        case .fileValidation:return "파일 확인"
        case .engineCreation:return "장치 준비"
        case .mixerAcquisition:return "믹서 준비"
        case .routing:return "경로 연결"
        case .scheduling:return "재생 배치"
        case .engineStart:return "장치 시작"
        case .playerPlay:return "재생 시작"
        }
    }
    private var outputLastStageDetail:String {
        guard let title=outputPreparationStage,let event=outputStatus.trace?.events.last else{return ""}
        let state=event.phase == .completed ? "완료":"진입"
        return " 마지막 확인: \(title) \(state)(시작 후 \(String(format:"%.1f",event.elapsedSeconds))초)."
    }
    var outputLabel:String? {
        switch outputStatus.transport.phase {
        case .starting:return "\(outputPreparationStage ?? "재생 준비") \(outputStatus.elapsedSeconds)초"
        case .stopping:return "출력 정리 중"
        case .failed:return "출력 시작 실패"
        default:break
        }
        if outputStatus.phase == .connecting {return "\(outputPreparationStage ?? "출력 연결") \(outputStatus.elapsedSeconds)초"}
        if outputStatus.phase == .ready,[.timedOut,.cancelled].contains(outputStatus.request) {return "출력 준비됨"}
        if outputStatus.phase == .idle,outputStatus.attempts>0,[.timedOut,.cancelled].contains(outputStatus.request) {return "다시 재생 가능"}
        return auditionLabel
    }
    var outputDetail:String {
        switch outputStatus.transport.phase {
        case .starting:return "\(outputPreparationStage ?? "재생 준비") 중 · \(outputStatus.elapsedSeconds)초. Space로 취소할 수 있습니다."
        case .stopping:return (outputStatus.request == .timedOut ? "재생 준비 제한 시간을 초과했습니다. ":"")+"재생 요청은 멈췄으며 출력을 정리하고 있습니다. 편집은 계속할 수 있습니다. 정리가 끝나면 다시 재생하세요."+outputLastStageDetail
        case .failed:return (outputStatus.transport.message ?? "출력을 시작할 수 없습니다. 다시 재생하세요.")+outputLastStageDetail
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
            return (outputPreparationStage ?? step)+" · \(outputStatus.elapsedSeconds)초. "+(outputStatus.request == .waiting ? "Space로 재생 준비를 취소할 수 있습니다.":"재생 요청은 멈췄으며 장치 응답을 기다립니다. 준비되면 다시 재생하세요.")+outputLastStageDetail
        }
        if outputStatus.phase == .ready,[.timedOut,.cancelled].contains(outputStatus.request) {return "출력 준비 완료. Space로 다시 재생하세요."}
        if outputStatus.phase == .idle,outputStatus.attempts>0,[.timedOut,.cancelled].contains(outputStatus.request) {return (outputStatus.request == .timedOut ? "재생 준비 제한 시간을 초과했습니다. ":"")+"이전 출력 정리가 끝났습니다. Space로 새 출력을 연결해 재생하세요."+outputLastStageDetail}
        return auditionDetail
    }
    func handlePlaybackError(_ error:Error) {
        refreshOutputStatus()
        if case PlaybackOutputWaitError.timedOut = error {status=error.localizedDescription}
        else if error is PlaybackTransportError {status=error.localizedDescription}
        else if !(error is CancellationError) {fail(error)}
    }
}
