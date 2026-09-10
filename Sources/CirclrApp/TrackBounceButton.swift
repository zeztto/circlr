import SwiftUI
import CirclrCore

struct TrackBounceRecoveryContext {
    let identity:NumberEditIdentity
    let useID:ID
    let trackID:ID
}

extension AppStore {
    var trackBounceAssessment:BounceAssessment? {
        guard let use=selectedUse,let track=selectedTrack else{return nil}
        return BounceAssessment.make(trackID:track.id,useID:use.id,arrangementID:project.activeArrangementID,
                                     selectedNodeID:selectedMusic?.id,in:project)
    }
    var trackBounceIssue:String? {
        guard let assessment=trackBounceAssessment else{return "바운스할 출력 트랙을 선택하세요"}
        return assessment.issue?.message
    }
    var trackBounceRecoveryContext:TrackBounceRecoveryContext? {
        guard let use=selectedUse,let track=selectedTrack else{return nil}
        return TrackBounceRecoveryContext(identity:numberEditIdentity,useID:use.id,trackID:track.id)
    }
    var trackBounceRecoveryLocked:Bool {preparing || midiRecording || audioRecordingBusy || audioRecordPending || mediaImportTask != nil}
    func trackBounceStatus(_ assessment:BounceAssessment)->String? {
        if let issue=assessment.issue{return issue.message}
        switch assessment.membership {
        case .outsidePath:return "현재 서클은 출력 경로 밖입니다"
        case .sidechainOnly:return "현재 서클은 사이드체인으로만 연결됩니다"
        case .missingNode:return "현재 서클을 찾을 수 없습니다"
        default:return nil
        }
    }
    func trackBounceRecoveryTitle(_ assessment:BounceAssessment)->String {
        switch assessment.issue {
        case .multipleOutputs:return "출력 찾기"
        case .noOutput:return selectedCircle?.ports.contains(where:{$0.id==CirclePort.audioOutput}) == true ? "현재 서클 연결 보기":"섹션 보기"
        case .missingSection,.invalidGraph:return "섹션 보기"
        default:return assessment.destinations.isEmpty ? "섹션 보기":"출력 연결 보기"
        }
    }
    func recoverTrackBounce(_ context:TrackBounceRecoveryContext) {
        guard !trackBounceRecoveryLocked else{status="재생 준비·녹음·가져오기가 끝난 뒤 출력 연결을 확인하세요";return}
        guard nameEditing.resolve() else{return}
        guard numberEditIdentity==context.identity,selectedUse?.id==context.useID,selectedTrack?.id==context.trackID,
              let assessment=trackBounceAssessment else{status="대상이나 음악이 바뀌었습니다. 현재 서클에서 다시 실행하세요";return}
        let section=CircleAddress.section(arrangementID:context.identity.arrangementID,useID:context.useID)
        commandPalette=nil
        if case .multipleOutputs=assessment.issue {
            showNavigation(section:section,track:context.trackID,role:.output);return
        }
        let destination:CircleAddress
        let port:String?
        switch assessment.issue {
        case .noOutput:
            if let source=selectedCircle,source.ports.contains(where:{$0.id==CirclePort.audioOutput}) {
                destination=source.id;port=CirclePort.audioOutput
            }else{destination=section;port=nil}
        case .missingSection,.invalidGraph:
            destination=section;port=nil
        default:
            if let output=assessment.destinations.first(where:{$0.kind == .output}) {
                destination=output.id;port=CirclePort.audioInput
            }else{destination=section;port=nil}
        }
        do {
            _ = try StudioNavigation.scene(revealing:destination,in:project)
            navigateStudio(destination,track:context.trackID)
            if let port {showConnections(portID:port)}
        }catch{fail(error)}
    }
}

struct TrackBounceStatus:View {
    @ObservedObject var store:AppStore
    private var displayedPathMessage:String? {
        guard store.trackBounceRecoveryContext != nil,let assessment=store.trackBounceAssessment else{return nil}
        return store.trackBounceStatus(assessment)
    }
    private var displayedTailMessage:String? {
        guard let notice=store.bounceTailNotice,notice != displayedPathMessage else{return nil}
        return notice
    }
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
        if let assessment=store.trackBounceAssessment,let message=displayedPathMessage,
           let context=store.trackBounceRecoveryContext {
            HStack(alignment:.center,spacing:8) {
                Text(message).font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                    .lineLimit(2).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).help(message+" · 바운스는 연결된 트랙의 주 출력을 오디오로 만듭니다")
                Button(store.trackBounceRecoveryTitle(assessment)){store.recoverTrackBounce(context)}
                    .fixedSize().disabled(store.trackBounceRecoveryLocked)
                    .help("명령 검색 ⇧⌘P · 바운스 출력 연결 보기")
            }.accessibilityElement(children:.contain)
        }
        if let notice=displayedTailMessage {
            let identity=store.numberEditIdentity
            HStack(alignment:.center,spacing:8) {
                Text(notice).font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                    .lineLimit(2).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                    .help((store.bounceTailAssessment?.notices ?? [notice]).joined(separator:" · "))
                Button("여운 설정"){store.beginBounceTailEditing(identity:identity)}
                    .fixedSize().disabled(!store.bounceTailUIAvailable)
                    .help("명령 검색 ⇧⌘P · 바운스 여운 설정")
            }.accessibilityElement(children:.contain)
        }
        }
    }
}

struct TrackBounceButton:View {
    @ObservedObject var store:AppStore
    var body:some View {
        let issue=store.trackBounceIssue
        let title=store.selectedTrack.map{"바운스 · \($0.name)"} ?? "바운스 · 트랙 선택"
        let identity=store.numberEditIdentity
        HStack(spacing:4) {
            Button {store.runCurrentTrackBounce(identity:identity)}label:{Text("바운스").lineLimit(1)}
                .disabled(store.trackBounceRecoveryLocked || issue != nil || store.bounceTailEditing || store.bounceTailAssessment==nil)
                .accessibilityLabel(title)
                .help(issue ?? "\(store.selectedTrack?.name ?? "트랙") · 이번 섹션 사용의 출력 앞 경로와 이펙트를 오디오로 만듭니다. 출력 볼륨·오토메이션과 전역 처리는 유지하며 원본 복원으로 되돌릴 수 있습니다.")
            BounceTailControl(store:store)
        }.frame(width:170)
    }
}
