import Foundation
import CirclrCore

@MainActor extension AppStore {
    var editorCursorPlaybackSeconds:Double? {
        guard editPatternID == nil,selectedUse != nil,let sectionClock,let clock=currentClock,
              selectedBeat.isFinite,selectedBeat>=0,selectedBeat<editorBeats else{return nil}
        let seconds:Double
        if let music=selectedMusic {
            switch music.content {case .midi,.rhythmMIDI:break;default:return nil}
            seconds=sectionClock.seconds(at:music.startBeat)+clock.seconds(at:selectedBeat)
        } else {seconds=sectionClock.seconds(at:selectedBeat)}
        return seconds.isFinite && seconds>=0 && seconds<sectionClock.seconds ? seconds:nil
    }
    var canPlayFromEditorCursor:Bool {
        editorCursorPlaybackSeconds != nil && !preparing && !moviePreparing && movieWriter == nil && movieFinalizing == nil && !midiRecording && !audioRecordingBusy
    }
    var editorCursorPlaybackHelp:String {
        guard let seconds=editorCursorPlaybackSeconds else{return "선택 섹션 안의 MIDI 편집 커서를 지정하세요"}
        return String(format:"선택 섹션의 커서부터 재생 · %.2f초 · 루프 사용 시 섹션 반복",seconds)
    }
    func playFromEditorCursor() {
        guard canPlayFromEditorCursor,let seconds=editorCursorPlaybackSeconds else{return}
        let mode:PlaybackLoopMode=playbackLoopMode == .off ? .off:.section
        stop()
        playbackLoopMode=mode
        playbackFollow=playbackFollow.startingPlayback(visiblePrecisionEditor:true)
        prepare(onlySelection:true,autoplay:true,loopMode:mode,fromSeconds:seconds)
    }
}
