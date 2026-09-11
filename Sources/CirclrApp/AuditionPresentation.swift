import Foundation

/// Value-only mapping: component QA needs neither AppStore nor an audio backend.
struct AuditionPresentation:Equatable {
    let pending:Bool
    let canCancel:Bool
    let label:String?
    let detail:String
    let footer:String?
    let logIdentity:String

    init(phase:String,stage:String?,stagePhase:String?,elapsedSeconds:Int,message:String?,interruption:String?,interruptedStage:String?) {
        pending=phase=="preparing" || phase=="stopping"
        canCancel=phase=="preparing"
        let elapsed=max(0,elapsedSeconds)
        let short:String
        switch stage {
        case "sourceLoad":short="음원"
        case "auInstantiation":short="AU"
        case "engineCreation","mixerAcquisition","routing":short="연결"
        case "engineStart":short="시작"
        case "cleanup":short="정리"
        default:short="준비"
        }
        switch phase {
        case "preparing":label="미리 듣기 · "+short;footer="전체 \(elapsed)초 · 취소"
        case "stopping":label="미리 듣기 · 정리";footer="전체 \(elapsed)초 · 정리 중"
        case "failed":label="미리 듣기 실패";footer=nil
        default:label=nil;footer=nil
        }
        var parts:[String]=[]
        if pending {
            parts.append("미리 듣기 · 전체 \(elapsed)초")
            if let stage {parts.append("현재 단계: \(Self.stageName(stage)) [\(stage)] · \(stagePhase == "completed" ? "완료":"진행 중")")}
            parts.append(canCancel ? "Space 또는 정지 버튼으로 취소할 수 있습니다. 준비 전에 놓은 건반은 재생하지 않습니다.":"취소 요청 후 정리 중입니다. 편집은 계속할 수 있습니다.")
        } else if phase=="failed" {parts.append("미리 듣기를 준비하지 못했습니다. 악기 설정을 확인하고 다시 연주하세요.")}
        if let interruption {
            let reason=interruption=="timedOut" ? "준비 시간 초과":interruption=="superseded" ? "연주 대상 변경":interruption=="failed" ? "준비 실패":"취소 요청"
            parts.append(reason)
            if let interruptedStage {parts.append("중단 요청 당시 단계: \(Self.stageName(interruptedStage)) [\(interruptedStage)]")}
        }
        if let message,!message.isEmpty {parts.append(message)}
        detail=parts.joined(separator:" · ")
        // Note traffic, event sequence and elapsed time never create activity-log spam.
        logIdentity=[phase,pending ? (stage=="note" ? "":stage ?? ""):"",interruption ?? "",interruptedStage ?? ""].joined(separator:"|")
    }
    func preferredLabel(over output:String?)->String? {pending ? label:output}
    func preferredDetail(over output:String)->String {pending ? detail:output}
    private static func stageName(_ stage:String)->String {
        switch stage {
        case "backendPreparation":return "악기 준비"
        case "sourceLoad":return "음원 읽기"
        case "auInstantiation":return "Audio Unit 준비"
        case "engineCreation":return "오디오 엔진 생성"
        case "mixerAcquisition":return "믹서 연결"
        case "routing":return "오디오 경로 연결"
        case "engineStart":return "오디오 엔진 시작"
        case "cleanup":return "오디오 정리"
        case "note":return "노트 전달"
        default:return stage
        }
    }
}
