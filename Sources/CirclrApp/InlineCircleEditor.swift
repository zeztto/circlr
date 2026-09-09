import SwiftUI
import CirclrCore
import CirclrAudio

/// Lives in the canvas view's hierarchy. It never creates an NSWindow or a docked pane.
struct InlineCircleEditor: View {
    @ObservedObject var store: AppStore
    @State private var topPitch = 72
    @State private var orbitViewport = MIDIOrbitViewport()
    @State private var stepState = StepEditorState()
    @State private var nameFocused=false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineEditorHeader(store:store,nameFocus:$nameFocused)
                .fixedSize(horizontal:false,vertical:true)
            if store.selectedMusic != nil {StudioRouteBar(store:store)}
            if store.audioRecordingStatusVisible {AudioRecordingStatusView(store:store)}
            // The flexible body cannot renegotiate the title/route/footer positions.
            GeometryReader { geometry in
                editorContent.frame(width:geometry.size.width,height:geometry.size.height,alignment:.topLeading)
            }.clipped()
            HStack { Text(store.currentAudioClip != nil && !store.automationVisible && !store.hierarchySettingsOpen && !store.connectionsOpen && store.midiImportDraft==nil ? "파형 위 휠로 확대·축소 · ⇧ 휠로 원본 시간 이동":"휠로 확대·축소 · ⇧ 휠로 편집 영역 이동"); Spacer(); Text("⌘S 저장") }
                .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .padding(14).background(store.project.usesOrbits && !store.hierarchySettingsOpen && store.midiImportDraft==nil ? Color.clear:StudioTheme.surface).foregroundStyle(StudioTheme.text)
        .font(.system(size: 13)).buttonStyle(CanvasButtonStyle()).controlSize(.regular)
        .tint(StudioTheme.accent).preferredColorScheme(.dark)
        .numberEditing(in:store)
        .onExitCommand { store.hierarchySettingsOpen = false; store.hierarchyParent() }
        .onAppear {
            topPitch = store.currentLane?.notes.map(\.pitch).max().map { min(128,max(12,$0+1)) } ?? (store.selectedTrack?.instrument.drums == true ? 48 : 72)
            orbitViewport.fitPitches(store.currentLane?.notes ?? [])
            stepState.drumMode=store.selectedTrack?.instrument.drums==true
            stepState.newPitch=store.selectedTrack?.instrument.sample?.rootPitch ?? 36
            // A false FocusState write can clear focus already assigned by the connection editor.
            if store.hierarchySettingsOpen && store.hierarchyTransitionID==nil { nameFocused = true }
        }
        .onChange(of:store.hierarchySettingsOpen){_,value in
            let shouldFocus=value && store.hierarchyTransitionID==nil
            if shouldFocus || nameFocused {nameFocused=shouldFocus}
        }
        .onChange(of:store.hierarchyTransitionID){_,id in if id != nil && nameFocused {nameFocused=false}}
        .onChange(of:store.editOriginal){_,_ in orbitViewport=MIDIOrbitViewport();orbitViewport.fitPitches(store.currentLane?.notes ?? [])}
    }
    @ViewBuilder private var editorContent:some View {
        VStack(alignment:.leading,spacing:12) {
            if store.connectionsOpen { PortConnectionsEditor(store: store).id(store.hierarchySelection) }
            else if let draft=store.midiImportDraft {MIDIImportView(store:store,draft:draft).id(draft.id)} else if let id=store.hierarchyTransitionID,let edge=store.project.active.edges.first(where:{$0.id==id}) {
                TransitionWorkspace(store:store,edgeID:edge.id)
            } else if let plugin = store.embeddedPlugin {
                HStack { Text("Audio Unit"); Spacer(); Button("서클로 돌아가기") { store.embeddedPlugin = nil } }
                EmbeddedPlugin(controller: plugin)
            } else if let signal=store.selectedSignal,case .signal = store.hierarchySelection {
                ScrollView { VStack(alignment:.leading,spacing:16) {
                    InspectorView(store:store).signal(signal)
                    if let track=store.selectedTrack { TrackLevelEditor(store:store,track:track) }
                    ForEach(store.project.signal.edges.filter{$0.from==signal.id}) { edge in
                        HStack { Text(store.project.signal.nodes.first{$0.id==edge.to}?.name ?? "출력"); Spacer(); Button("연결 해제"){store.disconnectHierarchy(.signal(signal.id),edgeID:edge.id)} }
                    }
                } }
            } else if store.hierarchySelection == .sound {
                VStack(alignment:.leading,spacing:16) { Text("모든 곡의 트랙 출력을 버스와 마스터로 연결합니다"); Button("버스 서클 추가"){store.addHierarchyBus()}; Menu("전역 이펙터 추가"){ForEach(EffectKind.allCases,id:\.self){kind in Button(AppStore.effectName(kind)){store.addHierarchySignalEffect(kind)}}}; Spacer() }
            } else if store.hierarchySettingsOpen || store.selectedMusic == nil {
                ScrollView { HierarchySettingsEditor(store: store).padding(.trailing, 8) }
            } else if store.automationVisible {
                AutomationEditor(store:store)
            } else if let node = store.selectedMusic {
                switch node.content {
                case .midi, .rhythmMIDI: midi
                case .audio: audio
                case .effect(let effect):
                    let projectID=store.project.id, address=store.hierarchySelection
                    ScrollView { VStack(alignment: .leading, spacing: 22) {
                        EffectControls(effect: Binding(get: {if case .effect(let value)=store.selectedMusic?.content {return value};return effect}, set: { value in store.updateMusic("이펙트 편집") { $0.content = .effect(value) } }), allowsAU: true,isCurrent:{store.project.id==projectID && store.hierarchySelection==address},chooseAudioUnit:{store.showSoundPicker(.musicEffect)})
                        SoundPickerButton(title:"Audio Unit 이펙트 찾기",current:effect.kind == .audioUnit ? effect.plugin?.name ?? "Audio Unit 선택 필요":"설치된 Audio Unit 이펙트") {store.showSoundPicker(.musicEffect)}
                        if effect.kind == .audioUnit {
                            Button("플러그인 편집") { store.showMusicPluginEditor() }.disabled(effect.plugin == nil)
                        }
                        HStack(spacing: 22) {
                            Toggle("음소거",isOn:Binding(get:{node.muted},set:{value in store.updateMusic("음소거"){$0.muted=value}}))
                            ValueField(title:"출력 볼륨",value:Binding(get:{store.selectedMusic?.gain ?? node.gain},set:{value in store.updateMusic("출력 볼륨"){$0.gain=value}}),range:0...4)
                            Spacer(minLength:8)
                            Button("트랙 바운스"){store.bounceTrack()}.disabled(store.preparing || store.selectedTrack == nil)
                        }.frame(maxWidth:660,alignment:.leading)
                    }.padding(.trailing, 8) }
                case .instrument:
                    if let track = store.selectedTrack { ScrollView { TrackInspector(store: store, track: track,showsTrackLevel:false) } }
                case .output:
                    if let track = store.selectedTrack { ScrollView { OutputEditor(store:store,track:track) } }
                case .mix: signalControls(node); Spacer()
                case .router(let router): AudioRouterEditor(store: store, router: router); signalControls(node); Spacer()
                case .rhythmAudio: Text("리듬 패턴의 오디오 클립"); AudioLane(store: store); Spacer()
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    @ViewBuilder private var midi:some View {
        if store.project.usesOrbits && !store.midiStepMode {MIDIOrbitWorkspace(store:store,viewport:$orbitViewport)}else{MIDIGridWorkspace(store:store,topPitch:$topPitch,steps:$stepState)}
    }
    @ViewBuilder private var audio: some View {
        if case .audio(_,let clipID) = store.selectedMusic?.content,
           let clip = store.currentLane?.audio.first(where: { $0.id == clipID }), let asset=store.project.assets.first(where: { $0.id == clip.assetID }) {
            AudioWorkspaceView(store:store,clip:clip,asset:asset)
        }
    }
    func editClip(_ clip: AudioClip, _ edit: (inout AudioClip) -> Void) {
        store.editAudioClip(clip,edit)
    }
    func clipBinding(_ clip: AudioClip, _ key: WritableKeyPath<AudioClip, Double>) -> Binding<Double> { Binding(get: { store.currentLane?.audio.first{$0.id==clip.id}?[keyPath:key] ?? clip[keyPath:key] }, set: { value in editClip(clip) { $0[keyPath:key]=value } }) }
    @ViewBuilder func signalControls(_ node: MusicCircle) -> some View {
        Toggle("음소거", isOn: Binding(get: { node.muted }, set: { value in store.updateMusic("음소거") { $0.muted=value } }))
        Button("트랙 바운스"){store.bounceTrack()}.disabled(store.preparing || store.selectedTrack == nil)
        ValueField(title: "출력 볼륨", value: Binding(get: { store.selectedMusic?.gain ?? node.gain }, set: { value in store.updateMusic("출력 볼륨") { $0.gain=value } }), range: 0...4)
    }
}

struct AudioTrimView: View {
    @ObservedObject var store: AppStore
    let clip: AudioClip
    let asset: Asset
    @State private var previewStart: Double?
    @State private var previewEnd: Double?
    var body: some View {
        GeometryReader { geometry in
            let width=geometry.size.width, height=geometry.size.height
            let start=previewStart ?? clip.sourceStart, end=previewEnd ?? (clip.sourceStart+clip.duration)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(StudioTheme.canvas))
                    if let waveform=store.waveforms[asset.id] {
                        var wave=Path()
                        for x in stride(from:0.0,through:size.width,by:1.5) {let amplitude=Double(waveform.peak(at:x/size.width*asset.duration))*size.height*0.44;wave.move(to:CGPoint(x:x,y:size.height/2-amplitude));wave.addLine(to:CGPoint(x:x,y:size.height/2+amplitude))}
                        context.stroke(wave,with:.color(StudioTheme.accent.opacity(0.85)),lineWidth:1)
                    }
                    context.fill(Path(CGRect(x:0,y:0,width:start/asset.duration*size.width,height:size.height)),with:.color(.black.opacity(0.6)))
                    context.fill(Path(CGRect(x:end/asset.duration*size.width,y:0,width:max(0,size.width-end/asset.duration*size.width),height:size.height)),with:.color(.black.opacity(0.6)))
                }
                trimHandle(x:start/asset.duration*width, height:height, label:"구간 시작")
                    .gesture(DragGesture(minimumDistance:0).onChanged { value in previewStart=max(0,min(end-0.01,clip.sourceStart+value.translation.width/width*asset.duration)) }.onEnded { _ in commit(start:previewStart ?? clip.sourceStart,end:end) })
                trimHandle(x:end/asset.duration*width, height:height, label:"구간 끝")
                    .gesture(DragGesture(minimumDistance:0).onChanged { value in previewEnd=min(asset.duration,max(start+0.01,clip.sourceStart+clip.duration+value.translation.width/width*asset.duration)) }.onEnded { _ in commit(start:start,end:previewEnd ?? end) })
            }.clipped()
        }
    }
    func trimHandle(x:Double,height:Double,label:String)->some View { Rectangle().fill(StudioTheme.accent).frame(width:3,height:height).frame(width:14).contentShape(Rectangle()).offset(x:x-7).accessibilityLabel(label) }
    func commit(start:Double,end:Double) {
        defer {previewStart=nil;previewEnd=nil}
        guard var lane=store.currentLane,let i=lane.audio.firstIndex(where:{$0.id==clip.id}) else{return}
        lane.audio[i].sourceStart=start;lane.audio[i].duration=max(0.01,end-start);store.setLane(lane)
    }
}

struct HierarchySettingsEditor: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            if case .composition(let id)=store.hierarchySelection,
               let composition=store.project.album?.composition(id),!composition.arrangementIDs.isEmpty {
                ArrangementPickerButton(store:store,owner:composition)
            }
            if let group=store.selectedHierarchyGroup {
                Text("\(group.members.count)개 서클 · 음악과 연결을 유지하는 배치 그룹")
                Button(group.collapsed ? "그룹 펼치기" : "그룹 접기") {store.updateHierarchyGroup{$0.collapsed.toggle()};store.hierarchySettingsOpen=false;store.hierarchyCommand=HierarchyCommand(action:.focus(store.hierarchySelection ?? .album,false))}
                Button("그룹 해제"){store.ungroupHierarchy()}
            } else if let address=store.hierarchySelection {
                if store.selectedMusic != nil {
                    HStack(spacing:12) {
                        Toggle("공유 원본 편집",isOn:$store.editOriginal)
                        Text(store.editOriginal ? "같은 원본을 사용하는 서클에 반영":"이번 사용에만 반영").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                    }
                }
                MusicContextEditor(store:store,address:address,projectID:store.project.id,generation:store.mediaImportGeneration,original:store.selectedMusic != nil && store.editOriginal)
            }
            if let use=store.selectedUse,store.selectedMusic == nil,store.selectedHierarchyGroup == nil {
                CountControl(title:"마디",value:Binding(get:{store.selectedUse?.barsOverride ?? store.project.sections.first{$0.id==use.sectionID}?.bars ?? 8},set:{v in store.updateUse("섹션 길이"){$0.barsOverride=v}}),range:1...1024)
                CountControl(title:"반복",value:Binding(get:{store.selectedUse?.repeatCount ?? use.repeatCount},set:{v in store.updateUse("섹션 반복"){$0.repeatCount=v}}),range:1...256)
                HStack{Button("시작 섹션으로 지정"){store.setStart()};Button("재사용"){store.reuse()};Button("독립 원본으로 분리"){store.detach()}}
                let address=CircleAddress.section(arrangementID:store.project.activeArrangementID,useID:use.id)
                Menu("다음 섹션 연결"){ForEach(store.project.active.uses.filter{$0.id != use.id}){target in Button(target.name){store.connectHierarchy(address,.section(arrangementID:store.project.activeArrangementID,useID:target.id))}}}
                ForEach(store.project.active.edges.filter{$0.from==use.id}){edge in
                    HStack{Text(store.project.active.uses.first{$0.id==edge.to}?.name ?? "다음 섹션");Spacer();Button(store.project.active.chosenEdges[use.id]==edge.id ? "재생 경로":"이 경로 재생"){store.chooseHierarchyEdge(address,edgeID:edge.id)};Button("전환 편집"){store.openHierarchyTransition(address,edgeID:edge.id)};Button("연결 해제"){store.disconnectHierarchy(address,edgeID:edge.id)}}
                }
            }
            if let music=store.selectedMusic {
                Toggle("음소거",isOn:Binding(get:{music.muted},set:{v in store.updateMusic("음소거"){$0.muted=v}}))
                if music.content.input == nil {
                    ValueField(title:"부모 안 시작 박",value:Binding(get:{store.selectedMusic?.startBeat ?? music.startBeat},set:{v in store.updateMusic("시작 박"){$0.startBeat=v}}),range:0...131072,presentation:.beatPosition)
                    ValueField(title:"길이 박",value:Binding(get:{store.selectedMusic?.lengthBeats ?? store.currentClock?.beats ?? 32},set:{v in store.updateMusic("길이"){$0.lengthBeats=v}}),range:0.03125...131072)
                    CountControl(title:"반복",value:Binding(get:{store.selectedMusic?.repeatCount ?? music.repeatCount},set:{v in store.updateMusic("반복"){$0.repeatCount=v}}),range:1...256)
                }
            }
            if case .composition(let id)=store.hierarchySelection,let composition=store.project.album?.composition(id) {
                CountControl(title:"곡·악장 반복",value:Binding(get:{store.project.album?.compositions.first{$0.id==id}?.repeatCount ?? composition.repeatCount},set:{value in store.mutate("곡·악장 반복"){p in if let i=p.album?.compositions.firstIndex(where:{$0.id==id}){p.album?.compositions[i].repeatCount=value}}}),range:1...256)
                if !composition.arrangementIDs.isEmpty {
                    Button("편곡안 복제"){store.duplicateHierarchyArrangement()}
                }
                Button("악장 추가"){store.addComposition(.movement)}
            }
            if store.selectedUse != nil,store.selectedHierarchyGroup == nil { Button("리듬 패턴 만들기") { store.makeHierarchyPattern() } }
        }.id(store.hierarchySelection)
    }
}
