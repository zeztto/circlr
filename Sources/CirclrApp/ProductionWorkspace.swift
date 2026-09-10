import AppKit
import AVFAudio
import UniformTypeIdentifiers
import CirclrCore
import CirclrAudio

extension AppStore {
    func generateMIDI(_ pattern:MIDIPattern) {
        guard nameEditing.resolve(),let request=midiGenerationRequest else{return}
        generateMIDI(pattern,request:request)
    }
    func generateMIDI(_ pattern:MIDIPattern,request:MIDIGenerationRequest) {
        guard !trackBounceRecoveryLocked,midiImportDraft==nil else{status="녹음·가져오기·렌더가 끝난 뒤 MIDI를 추가하세요";return}
        guard midiGenerationRequest==request,nameEditing.resolve(),midiGenerationRequest==request,
              var lane=currentLane else{status="편집 대상이나 커서·길이가 바뀌었습니다. MIDI 메뉴를 다시 여세요";return}
        do {
            var notes=try MIDIGenerator.notes(pattern:pattern,context:request.context,beats:request.duration)
            for i in notes.indices {notes[i].beat+=request.start}
            lane.notes+=notes;setLane(lane)
        }catch{fail(error)}
    }
    func exportMIDI() {
        guard let lane=currentLane else{return}
        let panel=NSSavePanel();panel.title="MIDI 저장";panel.nameFieldStringValue=(selectedCircle?.title ?? "연주")+".mid";panel.allowedContentTypes=[UTType(filenameExtension:"mid")!]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try MIDIFile.encode(lanes:[(selectedCircle?.title ?? "연주",lane.notes)],tempo:currentContext.tempo,meter:currentContext.meter).write(to:url,options:.atomic);status="MIDI 저장 완료"}catch{fail(error)}
    }
    func chooseSampleInstrument() {
        guard let trackID=selectedTrackID else{return}
        let panel=NSOpenPanel();panel.title="샘플 악기 원본 선택";panel.allowedContentTypes=[.audio];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            let file=try AVAudioFile(forReading:url),duration=Double(file.length)/file.processingFormat.sampleRate
            guard duration>0,duration<=60 else{throw CirclrError("샘플 악기에는 60초 이내의 오디오를 사용하세요")}
            let asset=Asset(name:url.lastPathComponent,path:url.path,duration:duration,sampleRate:file.processingFormat.sampleRate)
            mutate("샘플 악기 선택") {p in guard let i=p.tracks.firstIndex(where:{$0.id==trackID}) else{return};p.assets.append(asset);p.tracks[i].instrument = .sampler(assetID:asset.id);try ProjectStore.validateStructure(p)}
            cancelAudition()
        }catch{fail(error)}
    }
    func bounceTrack() {
        guard let use=selectedUse,let track=selectedTrack else{return}
        var request=AgentRequest(method:"bounce");request.projectID=project.id;request.expectedRevision=project.musicRevision
        var args=AgentArguments();args.arrangementID=project.activeArrangementID;args.useID=use.id;args.trackID=track.id;args.tailSeconds=bounceTailSeconds;request.arguments=args
        do {_ = try executeAgent(request,source:"사용자")}catch{fail(error)}
    }
    func restoreBounce() {
        guard let node=selectedMusic,let use=selectedUse else{return}
        mutate("바운스 원본 복원"){try BounceEditing.restore(nodeID:node.id,useID:use.id,in:&$0)}
    }
}
