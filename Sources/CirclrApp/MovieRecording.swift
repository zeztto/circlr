import AppKit
import UniformTypeIdentifiers
import CirclrAudio
import CirclrCore

extension AppStore {
    func toggleMovieRecording() {
        if moviePreparing {stop();return}
        if movieWriter != nil {finishMovieRecording();return}
        guard movieFinalizing==nil,!preparing,!midiRecording,!audioRecording else{status="현재 작업을 마친 뒤 영상 녹화를 시작하세요";return}
        let panel=NSSavePanel();panel.allowedContentTypes=[.mpeg4Movie];panel.nameFieldStringValue=project.name+".mp4"
        guard panel.runModal() == .OK,let url=panel.url else{return}
        guard !FileManager.default.fileExists(atPath:url.path) else{fail(CirclrError("기존 영상을 보존하려면 새 파일 이름을 지정하세요"));return}
        if playback.playing {stop()}
        movieGeneration+=1;let generation=movieGeneration
        let outputSelection=outputPreferences.selection
        let loopMode=playbackLoopMode
        moviePreparing=true;status="영상 녹화를 위한 오디오 준비"
        prepare(onlySelection:false,autoplay:false,loopMode:loopMode){[weak self] audio in
            guard let self,self.movieGeneration==generation,self.moviePreparing else{return}
            Task { @MainActor in
                var preparedRecorder:CanvasMovieWriter?
                do {
                    self.playbackFollow=self.playbackFollow.startingPlayback()
                    try await self.playback.play(audio,selection:outputSelection,loop:loopMode != .off,onPrepared:{ loopPCM in
                        guard self.movieGeneration==generation,self.moviePreparing else{throw CancellationError()}
                        guard let image=self.captureMovieFrame?() else{throw CirclrError("녹화할 캔버스를 찾을 수 없습니다")}
                        let recorder=try CanvasMovieWriter(url:url,size:CGSize(width:image.width,height:image.height),pcm:audio.mix,loop:loopPCM)
                        preparedRecorder=recorder
                        // Capture the opening frame before the output clock starts.
                        try recorder.append(image,seconds:0)
                        self.movieWriter=recorder;self.movieRevision=self.project.musicRevision;self.movieSeconds=0
                    })
                    guard let recorder=preparedRecorder,self.movieGeneration==generation,self.moviePreparing,self.movieWriter === recorder else{
                        preparedRecorder?.cancel()
                        if let preparedRecorder,self.movieWriter === preparedRecorder {self.movieWriter=nil}
                        return
                    }
                    self.moviePreparing=false
                    self.status="영상 녹화 중 · 캔버스 + 음악"
                }catch{
                    preparedRecorder?.cancel()
                    if let preparedRecorder,self.movieWriter === preparedRecorder {self.movieWriter=nil}
                    guard self.movieGeneration==generation else{return}
                    self.movieWriter=nil;self.moviePreparing=false;self.playback.stop();self.handlePlaybackError(error)
                }
            }
        }
    }
    /// Call from Playback's acknowledged boundary callback, before its old cycle retires.
    func scheduleMovieLoopChange(_ change:PlaybackLoopChangeStatus,loop:PlaybackLoopPCM?) throws {
        guard let recorder=movieWriter else{return}
        do {
            try recorder.scheduleAudio(loop:loop,exitTail:change.exiting ? playback.loopPCM?.exitTail:nil,atFrame:change.elapsedFrame)
        } catch {
            recorder.cancel();movieWriter=nil
            throw error
        }
    }
    func captureMovieTick() {
        guard let recorder=movieWriter,!moviePreparing else{return}
        let started=ProcessInfo.processInfo.systemUptime
        defer { movieTickTiming.record(start:started,end:ProcessInfo.processInfo.systemUptime) }
        guard movieRevision==project.musicRevision else{finishMovieRecording();status="음악 변경으로 영상 녹화를 마쳤습니다";return}
        if !playback.playing {finishMovieRecording();return}
        let seconds=playback.elapsedSeconds
        guard seconds>movieSeconds || recorder.submittedFrameCount==0 else{return}
        do {
            try recorder.checkForFailure()
            guard recorder.canAcceptFrame else{recorder.reportSkippedCapture();return}
            guard let frame=captureMovieFrame?() else{throw CirclrError("캔버스 화면을 읽을 수 없습니다")}
            try recorder.append(frame,seconds:seconds);movieSeconds=seconds
        }catch{recorder.cancel();movieWriter=nil;fail(error)}
    }
    func finishMovieRecording() {
        let wasPreparing=moviePreparing
        movieGeneration+=1;moviePreparing=false
        guard let recorder=movieWriter else{return}
        movieWriter=nil
        // The opening frame is submitted before Playback acknowledges its output.
        // Stopping in that interval is a cancellation, not a one-frame recording.
        if wasPreparing {recorder.cancel();status="영상 준비 취소";return}
        guard recorder.submittedFrameCount>0 else{recorder.cancel();status="영상 준비 취소";return}
        let duration=max(movieSeconds,playback.elapsedSeconds,playback.completedElapsedSeconds ?? 0)
        status="영상 저장 중"
        movieFinalizing=Task { @MainActor [weak self] in
            do {
                try await recorder.finish(seconds:duration)
                guard let self else{return}
                self.lastMovieURL=recorder.url
                self.status="영상 저장 완료 · \(recorder.frameCount)프레임 · \(recorder.url.lastPathComponent)"
                self.recordActivity("영상", "\(recorder.width)×\(recorder.height) · H.264/AAC · 누락 \(recorder.droppedFrames)프레임")
            }catch{self?.fail(error)}
            self?.movieFinalizing=nil
        }
    }
}
