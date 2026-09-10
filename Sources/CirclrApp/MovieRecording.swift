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
        moviePreparing=true;status="영상 녹화를 위한 오디오 준비"
        prepare(onlySelection:false,autoplay:false){[weak self] audio in
            guard let self,self.movieGeneration==generation,self.moviePreparing else{return}
            Task { @MainActor in
                do {
                    guard let image=self.captureMovieFrame?() else{throw CirclrError("녹화할 캔버스를 찾을 수 없습니다")}
                    let recorder=try CanvasMovieWriter(url:url,size:CGSize(width:image.width,height:image.height),pcm:audio.mix)
                    guard self.movieGeneration==generation,self.moviePreparing else{recorder.cancel();return}
                    self.movieWriter=recorder;self.movieRevision=self.project.musicRevision;self.movieSeconds=0
                    self.playbackFollow=self.playbackFollow.startingPlayback()
                    try await self.playback.play(audio,selection:outputSelection)
                    guard self.movieGeneration==generation,self.movieWriter === recorder else{recorder.cancel();return}
                    self.moviePreparing=false
                    try recorder.append(self.captureMovieFrame?() ?? image,seconds:0)
                    self.status="영상 녹화 중 · 캔버스 + 음악"
                }catch{guard self.movieGeneration==generation else{return};self.movieWriter?.cancel();self.movieWriter=nil;self.moviePreparing=false;self.handlePlaybackError(error)}
            }
        }
    }
    func captureMovieTick() {
        guard let recorder=movieWriter,!moviePreparing else{return}
        guard movieRevision==project.musicRevision else{finishMovieRecording();status="음악 변경으로 영상 녹화를 마쳤습니다";return}
        if !playback.playing {finishMovieRecording();return}
        let seconds=min(playback.seconds,playback.prepared?.mix.duration ?? playback.seconds)
        guard seconds>movieSeconds || recorder.frameCount==0 else{return}
        do {
            guard let frame=captureMovieFrame?() else{throw CirclrError("캔버스 화면을 읽을 수 없습니다")}
            try recorder.append(frame,seconds:seconds);movieSeconds=seconds
        }catch{recorder.cancel();movieWriter=nil;fail(error)}
    }
    func finishMovieRecording() {
        movieGeneration+=1;moviePreparing=false
        guard let recorder=movieWriter else{return}
        movieWriter=nil
        guard recorder.frameCount>0 else{recorder.cancel();status="영상 준비 취소";return}
        let duration=max(movieSeconds,playback.seconds)
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
