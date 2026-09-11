import SwiftUI
import AppKit
import CirclrAudio

extension AppStore {
    var audioRecordingBusy:Bool {recorder.busy || audioRecordPending}
    var audioRecordingAvailable:Bool {selectedUse != nil && selectedTrackID != nil && editPatternID==nil && !midiRecording}
    var audioRecordTitle:String {
        switch audioCapturePhase {
        case .cancelling:return "장치 정리 중"
        case .finishing:return "파일 마무리 중"
        case .recording:return "녹음 정지"
        case .starting:return "시작 취소"
        default:return audioRecordPending ? "시작 취소":"오디오 녹음"
        }
    }
    var audioRecordingLocked:Bool {audioCapturePhase == .cancelling || audioCapturePhase == .finishing}
    var audioRecordingStatusVisible:Bool {audioRecordingBusy || audioRecoveryURL != nil || !audioCaptureMessage.isEmpty}
    func revealAudioRecovery(){if let url=audioRecoveryURL{NSWorkspace.shared.activateFileViewerSelecting([url])}}
}
struct AudioRecordButton:View {
    @ObservedObject var store:AppStore
    var body:some View {
        Button {store.startAudioRecording()} label:{Label(store.audioRecordTitle,systemImage:store.audioRecording ? "stop.circle":"record.circle")}
            .disabled(store.audioRecordingLocked || (!store.audioRecordingAvailable && !store.audioRecordingBusy))
            .help("오디오 녹음 / 정지 · ⌥⌘R · 기본 입력 장치의 첫 두 채널, 모노 장치는 1채널")
    }
}
struct AudioRecordingStatusView:View {
    @ObservedObject var store:AppStore
    var level:Double {max(0,min(1,(20*log10(max(0.000001,Double(store.audioInputLevel)))+60)/60))}
    var body:some View {
        HStack(spacing:12) {
            Text(store.audioRecordPending && store.audioCapturePhase != .starting && store.audioCapturePhase != .cancelling ? "마이크 접근 확인 중":store.audioCaptureMessage)
                .lineLimit(2).font(.system(size:12))
            if store.audioRecording {
                Text(String(format:"%.1f초",store.audioInputSeconds)).monospacedDigit().fixedSize()
                if let f=store.audioInputFormat {Text(String(format:"%.1f kHz · 입력 %@",f.sampleRate/1000,f.channels==1 ? "1":"1–2")).font(.system(size:11)).foregroundStyle(StudioTheme.secondary).fixedSize()}
                ZStack(alignment:.leading) {Capsule().fill(StudioTheme.line);Capsule().fill(store.audioInputLevel>=1 ? Color.red:StudioTheme.accent).frame(width:80*level)}.frame(width:80,height:6)
                    .accessibilityLabel("입력 레벨").accessibilityValue(store.audioInputLevel>0 ? String(format:"%.1f dBFS",20*log10(Double(store.audioInputLevel))):"입력 없음")
            }
            Spacer(minLength:0)
            if store.audioRecoveryURL != nil {Button("녹음 파일 보기"){store.revealAudioRecovery()}.fixedSize()}
        }.foregroundStyle(StudioTheme.secondary).padding(.vertical,2)
    }
}
