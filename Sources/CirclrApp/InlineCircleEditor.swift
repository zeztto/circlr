import SwiftUI
import CirclrCore
import CirclrAudio

/// Lives in the canvas view's hierarchy. It never creates an NSWindow or a docked pane.
struct InlineCircleEditor: View {
    @ObservedObject var store: AppStore
    @State private var viewState=EditorViewportState()
    @State private var viewKey:EditorWorkspaceKey?
    @State private var viewProjectID:ID?
    @State private var viewGeneration:Int?
    @State private var nameFocused=false
    @StateObject private var connectionKeyboard=PortKeyboardFocus()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineEditorHeader(store:store,nameFocus:$nameFocused,connectionKeyboard:connectionKeyboard)
                .fixedSize(horizontal:false,vertical:true)
            if store.selectedMusic != nil {StudioRouteBar(store:store)}
            if store.audioRecordingStatusVisible {AudioRecordingStatusView(store:store)}
            // The flexible body cannot renegotiate the title/route/footer positions.
            GeometryReader { geometry in
                editorContent.frame(width:geometry.size.width,height:geometry.size.height,alignment:.topLeading)
            }.clipped()
            HStack {
                if store.selectedMusic != nil {
                    let identity=store.numberEditIdentity
                    Picker("서클 편집 범위",selection:Binding(get:{store.editOriginal},set:{_ = store.setMusicEditScope(original:$0,identity:identity)})) {
                        Text("서클 · 이번 사용").tag(false);Text("서클 · 공유 원본").tag(true)
                    }.labelsHidden().controlSize(.mini).frame(width:130)
                        .help("서클 이름·속성의 편집 범위 · 공유 원본 변경은 같은 원본의 다른 사용에도 반영됩니다. 트랙 음색·레벨은 이 선택과 관계없이 트랙 전체에 적용됩니다.")
                        .disabled(store.preparing || store.midiRecording || store.audioRecordingBusy || store.audioRecordPending || store.midiImportDraft != nil)
                }
                Text(store.currentAudioClip != nil && !store.automationVisible && !store.hierarchySettingsOpen && !store.connectionsOpen && store.midiImportDraft==nil ? "파형 위 휠로 확대·축소 · ⇧ 휠로 원본 시간 이동":"휠로 확대·축소 · ⇧ 휠로 편집 영역 이동"); Spacer(); Text("⌘S 저장") }
                .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .padding(14).background(store.project.usesOrbits && !store.hierarchySettingsOpen && store.midiImportDraft==nil ? Color.clear:StudioTheme.surface).foregroundStyle(StudioTheme.text)
        .font(.system(size: 13)).buttonStyle(CanvasButtonStyle()).controlSize(.regular)
        .tint(StudioTheme.accent).preferredColorScheme(.dark)
        .numberEditing(in:store)
        .onExitCommand { store.hierarchySettingsOpen = false; store.hierarchyParent() }
        .onAppear {
            loadViewState()
            // A false FocusState write can clear focus already assigned by the connection editor.
            if store.hierarchySettingsOpen && store.hierarchyTransitionID==nil { nameFocused = true }
        }
        .onChange(of:store.hierarchySettingsOpen){_,value in
            let shouldFocus=value && store.hierarchyTransitionID==nil
            if shouldFocus || nameFocused {nameFocused=shouldFocus}
        }
        .onChange(of:store.hierarchyTransitionID){_,id in if id != nil && nameFocused {nameFocused=false}}
        .onChange(of:viewState){_,_ in rememberViewState()}
        .onDisappear{rememberViewState()}
        .onChange(of:store.editOriginal){_,_ in rememberViewState();loadViewState()}
        .onChange(of:store.hierarchySelection){_,_ in rememberViewState();loadViewState()}
        .onChange(of:store.mediaImportGeneration){_,_ in loadViewState()}
        .onChange(of:store.editorBeats){_,_ in if isCurrentView {viewState=store.validatedEditorViewport(viewState)}}
        .onChange(of:store.currentAudioClip?.assetID){_,_ in if isCurrentView {viewState=store.validatedEditorViewport(viewState)}}
    }
    @ViewBuilder private var editorContent:some View {
        VStack(alignment:.leading,spacing:12) {
            if let issue=store.musicEditingIssue,!store.audioIsOutsideSharedOriginal {
                let identity=store.numberEditIdentity
                VStack(alignment:.leading,spacing:12) {
                    Text("공유 원본에서 편집할 수 없습니다").font(.system(size:13,weight:.medium))
                    Text(issue).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
                    if store.editOriginal {Button("이번 사용 편집") {_ = store.setMusicEditScope(original:false,identity:identity)}}
                }
            } else if store.connectionsOpen { PortConnectionsEditor(store: store,keyboard:connectionKeyboard).id(store.hierarchySelection).id(store.mediaImportGeneration) }
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
                ScrollView { HierarchySettingsEditor(store: store).padding(.trailing, 8).rememberEditorScroll(scroll("settings")) }
            } else if store.automationVisible {
                AutomationEditor(store:store)
            } else if let node = store.musicEditingNode ?? (store.audioIsOutsideSharedOriginal ? store.selectedMusic:nil) {
                switch node.content {
                case .midi, .rhythmMIDI: midi
                case .audio: audio
                case .effect(let effect):
                    let projectID=store.project.id, address=store.hierarchySelection
                    let original=store.editOriginal,generation=store.mediaImportGeneration
                    ScrollView { VStack(alignment: .leading, spacing: 22) {
                        EffectControls(effect: Binding(get: {if case .effect(let value)=store.musicEditingNode?.content {return value};return effect}, set: { value in store.updateMusic("이펙트 편집") { $0.content = .effect(value) } }), allowsAU: true,isCurrent:{store.project.id==projectID && store.hierarchySelection==address && store.editOriginal==original && store.mediaImportGeneration==generation},chooseAudioUnit:{store.showSoundPicker(.musicEffect)})
                        SoundPickerButton(title:"Audio Unit 이펙트 찾기",current:effect.kind == .audioUnit ? effect.plugin?.name ?? "Audio Unit 선택 필요":"설치된 Audio Unit 이펙트") {store.showSoundPicker(.musicEffect)}
                        if effect.kind == .audioUnit {
                            Button("플러그인 편집") { store.showMusicPluginEditor() }.disabled(effect.plugin == nil)
                        }
                        HStack(spacing: 22) {
                            Toggle("음소거",isOn:Binding(get:{node.muted},set:{value in store.updateMusic("음소거"){$0.muted=value}}))
                            ValueField(title:"출력 볼륨 dB",value:Binding(get:{store.musicEditingNode?.gain ?? node.gain},set:{value in store.updateMusic("출력 볼륨"){$0.gain=value}}),range:0...4,presentation:.gainDecibels)
                                .help("0 dB 원래 레벨 · −∞ 무음")
                            Spacer(minLength:8)
                            TrackBounceButton(store:store)
                        }.frame(maxWidth:660,alignment:.leading)
                    }.padding(.trailing, 8).rememberEditorScroll(scroll("effect")) }
                case .instrument:
                    if let track = store.selectedTrack { ScrollView { TrackInspector(store: store, track: track,showsTrackLevel:false).rememberEditorScroll(scroll("instrument")) } }
                case .output:
                    if let track = store.selectedTrack { ScrollView { OutputEditor(store:store,track:track).rememberEditorScroll(scroll("output")) } }
                case .mix: signalControls(node); Spacer()
                case .router(let router):
                    ScrollView {
                        VStack(alignment:.leading,spacing:14) {
                            AudioRouterEditor(store:store,router:router)
                            signalControls(node)
                        }.padding(.trailing,8).rememberEditorScroll(scroll("router"))
                    }
                case .rhythmAudio: Text("리듬 패턴의 오디오 클립"); AudioLane(store: store); Spacer()
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    @ViewBuilder private var midi:some View {
        if store.project.usesOrbits && !store.midiStepMode {MIDIOrbitWorkspace(store:store,viewport:$viewState.orbit,scroll:scroll("orbitControls"))}else{MIDIGridWorkspace(store:store,topPitch:$viewState.topPitch,steps:$viewState.steps,pianoScroll:scroll("piano"),stepScroll:scroll("steps"))}
    }
    @ViewBuilder private var audio: some View {
        if case .audio(_,let clipID) = store.selectedMusic?.content,
           let clip = store.currentLane?.audio.first(where: { $0.id == clipID }), let asset=store.project.assets.first(where: { $0.id == clip.assetID }) {
            AudioWorkspaceView(store:store,clip:clip,asset:asset,viewport:$viewState.audio)
        }else if store.audioIsOutsideSharedOriginal {
            let identity=store.numberEditIdentity
            VStack(alignment:.leading,spacing:12) {
                Text("공유 원본 편집 중").font(.system(size:13,weight:.medium))
                Text("이 오디오는 이번 사용에 추가되어 공유 원본에는 없습니다. 이번 사용 편집으로 전환하면 파형과 구간을 조절할 수 있습니다.")
                    .foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
                Button("이번 사용 편집") {
                    if store.recoverAudioEditScope(identity:identity) {store.focusCanvas?()}
                }.keyboardShortcut(.defaultAction).disabled(!store.audioScopeRecoveryAvailable)
                    .help("선택한 오디오를 유지하고 이번 사용 편집으로 전환 · Return")
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }else{
            Text("선택한 오디오의 구간 또는 원본 파일 정보를 찾을 수 없습니다.")
                .foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
                .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }
    }
    private var isCurrentView:Bool {viewKey==store.editorWorkspaceKey && viewProjectID==store.project.id && viewGeneration==store.mediaImportGeneration}
    private func loadViewState() {
        viewKey=store.editorWorkspaceKey;viewProjectID=store.project.id;viewGeneration=store.mediaImportGeneration
        viewState=store.initialEditorViewport()
    }
    private func rememberViewState() {
        guard let viewKey,viewProjectID==store.project.id,viewGeneration==store.mediaImportGeneration else{return}
        store.editorViewStates[viewKey]=viewState
    }
    private func scroll(_ name:String)->Binding<EditorScrollPosition> {
        Binding(get:{viewState.scrolls[name] ?? .init()},set:{viewState.scrolls[name]=$0})
    }
    func editClip(_ clip: AudioClip, _ edit: (inout AudioClip) -> Void) {
        store.editAudioClip(clip,edit)
    }
    func clipBinding(_ clip: AudioClip, _ key: WritableKeyPath<AudioClip, Double>) -> Binding<Double> { Binding(get: { store.currentLane?.audio.first{$0.id==clip.id}?[keyPath:key] ?? clip[keyPath:key] }, set: { value in editClip(clip) { $0[keyPath:key]=value } }) }
    @ViewBuilder func signalControls(_ node: MusicCircle) -> some View {
        Toggle("음소거", isOn: Binding(get: { node.muted }, set: { value in store.updateMusic("음소거") { $0.muted=value } }))
        TrackBounceButton(store:store)
        ValueField(title: "출력 볼륨 dB", value: Binding(get: { store.musicEditingNode?.gain ?? node.gain }, set: { value in store.updateMusic("출력 볼륨") { $0.gain=value } }), range: 0...4, presentation: .gainDecibels)
            .help("0 dB 원래 레벨 · −∞ 무음")
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
        VStack(alignment:.leading,spacing:10) {
            if case .section=store.hierarchySelection,let use=store.selectedUse {
                Button{store.showConnections(portID:CirclePort.flowOutput)}label:{
                    HStack(spacing:12) {
                        Text("섹션 순서·전환").font(.system(size:13,weight:.medium))
                        Text("다음 연결 \(store.project.active.edges.filter{$0.from==use.id}.count)개").font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                        Spacer(minLength:8)
                        Image(systemName:"arrow.triangle.branch").foregroundStyle(StudioTheme.accent)
                    }.padding(.horizontal,12).frame(height:32).background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:6))
                }.buttonStyle(.plain).frame(maxWidth:660).accessibilityLabel("섹션 순서·전환 · "+use.name).help("다음 섹션 검색 · 재생 분기 · 전환 효과 · 연결 L")
            }
            if case .composition(let id)=store.hierarchySelection,
               let composition=store.project.album?.composition(id),!composition.arrangementIDs.isEmpty {
                ArrangementPickerButton(store:store,owner:composition)
            }
            if store.selectedMusic != nil {
                HStack(spacing:12) {
                    Toggle("공유 원본 편집",isOn:Binding(get:{store.editOriginal},set:{_ = store.setMusicEditScope(original:$0,identity:store.numberEditIdentity)}))
                    Text(store.editOriginal ? "같은 원본을 사용하는 서클에 반영":"이번 사용에만 반영").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                }
            }
            if let use=store.selectedUse,store.selectedMusic==nil,store.selectedHierarchyGroup==nil {
                HStack(spacing:24) {
                CountControl(title:"마디",value:Binding(get:{store.selectedUse?.barsOverride ?? store.project.sections.first{$0.id==use.sectionID}?.bars ?? 8},set:{v in store.updateUse("섹션 길이"){$0.barsOverride=v}}),range:1...1024)
                CountControl(title:"반복",value:Binding(get:{store.selectedUse?.repeatCount ?? use.repeatCount},set:{v in store.updateUse("섹션 반복"){$0.repeatCount=v}}),range:1...256)
                }
            }
            if let music=store.musicEditingNode {
                if music.content.input == nil {
                    HStack(spacing:18) {
                    ValueField(title:"부모 안 시작 박",value:Binding(get:{store.musicEditingNode?.startBeat ?? music.startBeat},set:{v in store.updateMusic("시작 박"){$0.startBeat=v}}),range:0...131072,presentation:.beatPosition)
                    ValueField(title:"길이 박",value:Binding(get:{store.musicEditingNode?.lengthBeats ?? store.currentClock?.beats ?? 32},set:{v in store.updateMusic("길이"){$0.lengthBeats=v}}),range:0.03125...131072)
                    CountControl(title:"반복",value:Binding(get:{store.musicEditingNode?.repeatCount ?? music.repeatCount},set:{v in store.updateMusic("반복"){$0.repeatCount=v}}),range:1...256)
                    }
                }
            }
            if case .composition(let id)=store.hierarchySelection,let composition=store.project.album?.composition(id) {
                CountControl(title:"곡·악장 반복",value:Binding(get:{store.project.album?.compositions.first{$0.id==id}?.repeatCount ?? composition.repeatCount},set:{value in store.mutate("곡·악장 반복"){p in if let i=p.album?.compositions.firstIndex(where:{$0.id==id}){p.album?.compositions[i].repeatCount=value}}}),range:1...256)
            }
            if let group=store.selectedHierarchyGroup {
                Text("\(group.members.count)개 서클 · 음악과 연결을 유지하는 배치 그룹")
                Button(group.collapsed ? "그룹 펼치기" : "그룹 접기") {store.updateHierarchyGroup{$0.collapsed.toggle()};store.hierarchySettingsOpen=false;store.hierarchyCommand=HierarchyCommand(action:.focus(store.hierarchySelection ?? .album,false))}
                Button("그룹 해제"){store.ungroupHierarchy()}
            } else if let address=store.hierarchySelection {
                MusicContextEditor(store:store,address:address,projectID:store.project.id,generation:store.mediaImportGeneration,original:store.selectedMusic != nil && store.editOriginal)
            }
            if store.selectedUse != nil,store.selectedMusic == nil,store.selectedHierarchyGroup == nil {
                HStack{Button("시작 섹션으로 지정"){store.setStart()};Button("재사용"){store.reuse()};Button("독립 원본으로 분리"){store.detach()}}
            }
            if let music=store.musicEditingNode {
                Toggle("음소거",isOn:Binding(get:{music.muted},set:{v in store.updateMusic("음소거"){$0.muted=v}}))
            }
            if case .composition(let id)=store.hierarchySelection,store.project.album?.composition(id) != nil {
                Button("악장 추가"){store.addComposition(.movement)}
            }
            if store.selectedUse != nil,store.selectedHierarchyGroup == nil { Button("리듬 패턴 만들기") { store.makeHierarchyPattern() } }
        }.id(store.hierarchySelection)
    }
}
