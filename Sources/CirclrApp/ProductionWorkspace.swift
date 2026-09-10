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
        guard nameEditing.resolve(),let lane=currentLane,let clock=currentClock else{return}
        let identity=numberEditIdentity,context=currentContext,title=selectedCircle?.title ?? "연주"
        let panel=NSSavePanel();panel.title="MIDI 저장";panel.nameFieldStringValue=title+".mid";panel.allowedContentTypes=[UTType(filenameExtension:"mid")!]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        guard identity==numberEditIdentity,currentLane==lane,currentContext==context,currentClock==clock else{status="연주나 편집 대상이 바뀌었습니다. MIDI 저장을 다시 실행하세요";return}
        do {
            let data=try MIDIFile.encode(sources:[(title,lane)],tempo:clock.tempos.first?.bpm ?? context.tempo,meter:context.meter,tempoChanges:Array(clock.tempos.dropFirst()))
            try data.write(to:url,options:.atomic);status="MIDI 저장 완료"
        }catch{fail(error)}
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
    func restoreBounce(identity expected:NumberEditIdentity) {
        guard expected==numberEditIdentity,!trackBounceRecoveryLocked,let node=selectedMusic,let source=node.bounce,
              case .music(let arrangementID,let useID,let nodeID)=hierarchySelection,
              nodeID==node.id,arrangementID==project.activeArrangementID,selectedUse?.id==useID else{return}
        var identity=expected
        guard nameEditing.resolve() else{return}
        identity.revision=project.musicRevision
        guard identity==numberEditIdentity,!trackBounceRecoveryLocked,selectedMusic?.bounce==source else{return}
        do {
            let baseline=project
            var candidate=baseline
            try BounceEditing.restore(nodeID:nodeID,useID:useID,in:&candidate)
            let destination=CircleAddress.music(arrangementID:arrangementID,useID:useID,nodeID:source.outputNodeID)
            let scene=try StudioNavigation.scene(revealing:destination,in:candidate)
            guard let output=scene.node(destination)?.music,case .output(let trackID)=output.content else {
                throw CirclrError("바운스 원본의 출력 서클을 찾을 수 없습니다")
            }
            guard candidate != baseline,identity==numberEditIdentity,!trackBounceRecoveryLocked else{return}
            mutate("바운스 원본 복원") {project in
                guard project==baseline else{return}
                project=candidate
            }
            // mutate can decline an edit; only the exact committed candidate permits navigation.
            candidate.musicRevision=baseline.musicRevision+1
            identity.revision=candidate.musicRevision
            guard project==candidate,numberEditIdentity==identity else{return}
            navigateStudio(destination,track:trackID)
        }catch{fail(error)}
    }
}
