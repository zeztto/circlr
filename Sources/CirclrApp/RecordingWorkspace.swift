import SwiftUI
import AppKit
import CirclrAudio

extension AppStore {
    var audioRecordingBusy:Bool {recorder.busy || audioRecordPending}
    var audioRecordingAvailable:Bool {takeRecordingTargetIssue == nil && hierarchySelection != nil && !midiRecording}
    var takeRecordingTargetIssue:String? {
        if moviePreparing || movieWriter != nil || movieFinalizing != nil {return "영상 녹화를 마친 뒤 테이크를 녹음하세요"}
        if selectedUse == nil {return "녹음할 섹션 서클을 선택하세요"}
        if selectedTrackID == nil {return "녹음할 트랙을 선택하세요"}
        if recordingClock == nil {return "섹션의 박자와 템포를 확인하세요"}
        if editPatternID != nil {return "공유 리듬 편집을 마친 뒤 섹션에서 녹음하세요"}
        return nil
    }
    var canStartMIDITake:Bool {takeRecordingTargetIssue == nil && !takeCaptureInProgress}
    var canStartAudioTake:Bool {takeRecordingTargetIssue == nil && hierarchySelection != nil && !takeCaptureInProgress}
    var takeRecordingStatusTitle:String {
        if midiRecording {return "MIDI 녹음 중"}
        switch audioCapturePhase {
        case .recording:return "오디오 녹음 중"
        case .finishing:return "파일 저장 중"
        case .cancelling:return "장치 정리 중"
        case .starting:return "오디오 준비 중"
        default:return audioRecordPending ? "마이크 확인 중":"테이크 녹음"
        }
    }
    var takeRecordingCompactTitle:String {
        if midiRecording {return "MIDI 중"}
        if audioCapturePhase == .cancelling {return "장치 정리"}
        if audioCapturePhase == .finishing {return "저장 중"}
        if audioRecording {return "오디오 중"}
        if audioRecordPending {return "준비 중"}
        return "녹음"
    }
    var takeCaptureInProgress:Bool {
        midiRecording || audioRecordingBusy || [.starting,.recording,.cancelling,.finishing].contains(audioCapturePhase)
    }
    /// Capture destinations are fixed at start. The private capture snapshot is not exposed here,
    /// so an active menu omits the target rather than naming a newly selected section or track.
    var takeRecordingTargetTitle:String? {
        if takeCaptureInProgress {return nil}
        guard let use=selectedUse,let track=selectedTrack else{return nil}
        return use.name+" · "+track.name
    }
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

/// Top-level capture entry: MIDI/audio takes remain distinct from MP4 canvas recording.
struct TakeRecordingMenu:View {
    @ObservedObject var store:AppStore
    var compact=false
    private var captureActive:Bool {store.midiRecording || store.audioRecording}
    private var targetTitle:String? {store.takeRecordingTargetTitle}
    private var label:String {compact ? store.takeRecordingCompactTitle:store.takeRecordingStatusTitle}
    private var helpText:String {
        if store.takeCaptureInProgress {return store.takeRecordingStatusTitle}
        if let issue=store.takeRecordingTargetIssue {return issue}
        if let targetTitle {return targetTitle+" · MIDI 또는 오디오 테이크"}
        return "선택한 섹션과 트랙에 MIDI 또는 오디오 테이크를 녹음"
    }
    private var statusAccessibilityValue:String {
        var value=store.takeRecordingStatusTitle
        if let targetTitle {value+=" · "+targetTitle}
        if !store.takeCaptureInProgress,let issue=store.takeRecordingTargetIssue {value+=" · "+issue}
        return value
    }
    var body:some View {
        Menu {
            if let targetTitle {Text(targetTitle)}
            if store.midiRecording {
                Button("MIDI 녹음 정지"){store.stopRecording()}
            } else if store.takeCaptureInProgress {
                if store.audioRecordingLocked {
                    Text(store.audioRecordTitle)
                } else if store.audioRecording || store.audioRecordPending {
                    Button(store.audioRecording ? "오디오 녹음 정지":"오디오 녹음 시작 취소"){
                        store.startAudioRecording()
                    }
                } else {
                    Text(store.takeRecordingStatusTitle)
                }
                if !store.audioCaptureMessage.isEmpty {Text(store.audioCaptureMessage)}
            } else {
                if let issue=store.takeRecordingTargetIssue {Text(issue)}
                else if store.hierarchySelection == nil {Text("녹음할 서클을 선택하세요")}
                Button("MIDI 테이크 녹음"){store.startMIDIRecording()}
                    .disabled(!store.canStartMIDITake)
                Button("오디오 테이크 녹음"){store.startAudioRecording()}
                    .disabled(!store.canStartAudioTake)
                if !store.audioCaptureMessage.isEmpty {Text(store.audioCaptureMessage)}
            }
        } label: {
            HStack(spacing:6) {
                if store.audioRecordingBusy && !store.audioRecording {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName:captureActive ? "stop.circle.fill":"record.circle")
                        .font(.system(size:15,weight:.medium))
                }
                Text(label).font(.system(size:11,weight:.semibold)).fixedSize(horizontal:true,vertical:false)
            }
            .foregroundStyle(captureActive ? Color.red:StudioTheme.text)
            .frame(minHeight:26)
            .padding(.horizontal,7)
            .background(captureActive ? Color.red.opacity(0.12):StudioTheme.raised,in:RoundedRectangle(cornerRadius:6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(helpText)
        .accessibilityLabel("MIDI 또는 오디오 테이크 녹음")
        .accessibilityValue(statusAccessibilityValue)
    }
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
