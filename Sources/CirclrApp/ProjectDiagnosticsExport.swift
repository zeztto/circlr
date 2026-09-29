import AppKit
import UniformTypeIdentifiers
import CirclrCore

extension AppStore {
    /// Explicit local export only. No telemetry, account access or network work.
    func exportProjectDiagnostics() {
        guard !projectMedia.busy else { return }
        let panel = NSSavePanel()
        panel.title = "진단 정보 저장"
        panel.message = "앱 버전·프로젝트 개수·미디어 읽기 상태·작업 상태를 JSON으로 저장합니다. 이름·경로·오디오·계정 정보는 포함하지 않습니다."
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "circlr-diagnostics.json"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let jobKind = ProjectDiagnostics.JobKind(rawValue: agentJob?.kind ?? "none") ?? .other
        let jobState = ProjectDiagnostics.JobState(rawValue: agentJob?.state ?? "idle") ?? .unknown
        let runtime = ProjectDiagnostics.Runtime(playbackPlaying: playback.playing, playbackPreparing: preparing,
            midiRecording: midiRecording, audioRecording: audioRecording,
            audioRecordingBusy: audioRecordingBusy, audioRecordingPending: audioRecordPending,
            jobKind: jobKind, jobState: jobState)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        projectMediaOpen = true
        projectMedia.exportDiagnostics(to: destination, appVersion: version, appBuild: build, runtime: runtime)
    }
}
