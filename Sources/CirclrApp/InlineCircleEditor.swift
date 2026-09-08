import SwiftUI
import CirclrCore
import CirclrAudio

/// Lives in the canvas view's hierarchy. It never creates an NSWindow or a docked pane.
struct InlineCircleEditor: View {
    @ObservedObject var store: AppStore
    @State private var topPitch = 72
    @FocusState private var nameFocused:Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("서클 이름", text: Binding(get: { store.selectedCircle?.title ?? "" }, set: { store.renameHierarchy($0) }))
                    .textFieldStyle(.plain).font(.system(size: 17, weight: .semibold)).focused($nameFocused).disabled(store.midiImportDraft != nil)
                Spacer()
                if store.canEditCirclePorts {
                    Button(store.connectionsOpen ? "편집으로" : "연결") { if store.connectionsOpen { store.connectionsOpen = false } else { store.showConnections() } }.help("IN/OUT·대상·8방향 위치 편집 · L")
                }
                if store.selectedUse != nil {AudioRecordButton(store:store)}
                if store.selectedMusic != nil {
                    Button(store.automationVisible ? "편집으로":"오토메이션") {store.connectionsOpen=false;if store.automationVisible {store.automationOpen=false}else{store.showAutomation()}}.help("이 서클의 볼륨·팬 곡선 · ⌘5")
                    Button { store.connectionsOpen=false;store.hierarchySettingsOpen.toggle() } label: { Image(systemName: "slider.horizontal.3") }.help("템포·박자·스케일·반복 설정")
                }
                Button { store.hierarchySettingsOpen = false; store.hierarchyParent() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("상위 서클로 축소 · Esc")
            }
            if store.selectedMusic != nil {StudioRouteBar(store:store)}
            if store.audioRecordingStatusVisible {AudioRecordingStatusView(store:store)}
            if store.connectionsOpen { PortConnectionsEditor(store: store).id(store.hierarchySelection) }
            else if let draft=store.midiImportDraft {MIDIImportView(store:store,draft:draft)} else if let id=store.hierarchyTransitionID,let edge=store.project.active.edges.first(where:{$0.id==id}) {
                HStack{Text("섹션 사이 전환");Spacer();Button("서클 설정"){store.hierarchyTransitionID=nil}}
                ScrollView{VStack(alignment:.leading,spacing:18){InspectorView(store:store).transition(edge)}}
            } else if let plugin = store.embeddedPlugin {
                HStack { Text("Audio Unit"); Spacer(); Button("서클로 돌아가기") { store.embeddedPlugin = nil } }
                EmbeddedPlugin(controller: plugin)
            } else if let signal=store.selectedSignal,case .signal = store.hierarchySelection {
                ScrollView { VStack(alignment:.leading,spacing:16) {
                    InspectorView(store:store).signal(signal)
                    if let track=store.selectedTrack { TrackInspector(store:store,track:track) }
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
                    ScrollView { VStack(spacing: 18) {
                        EffectControls(effect: Binding(get: { effect }, set: { value in store.updateMusic("이펙트 편집") { $0.content = .effect(value) } }), allowsAU: true)
                        if effect.kind == .audioUnit {
                            StudioChoice("Audio Unit", selection: Binding(get: { effect.plugin?.id ?? "" }, set: { id in store.updateMusic("Audio Unit 선택") { var value = effect; value.plugin = store.effects.first { $0.id == id }; $0.content = .effect(value) } }), options: [("", "선택")]+store.effects.map { ($0.id, $0.name) })
                            Button("플러그인 편집") { store.showMusicPluginEditor() }.disabled(effect.plugin == nil)
                        }
                        signalControls(node)
                    }.padding(.trailing, 8) }
                case .instrument, .output:
                    if let track = store.selectedTrack { ScrollView { TrackInspector(store: store, track: track) } }
                case .mix: signalControls(node); Spacer()
                case .router(let router): AudioRouterEditor(store: store, router: router); signalControls(node); Spacer()
                case .rhythmAudio: Text("리듬 패턴의 오디오 클립"); AudioLane(store: store); Spacer()
                }
            }
            if let use=store.selectedUse,let track=store.selectedTrackID,store.selectedMusic != nil {
                let takes=(store.project.takes ?? []).filter{$0.useID==use.id && $0.lane.trackID==track && ($0.targetLaneID == nil || $0.targetLaneID==store.selectedLaneID)}
                if !takes.isEmpty {Menu("녹음 테이크 선택"){ForEach(takes){take in Button(take.name){store.activateTake(take)}}}}
            }
            HStack { Text("휠로 확대·축소 · ⇧ 휠로 편집 영역 이동"); Spacer(); Text("⌘S 저장") }
                .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .padding(14).background(store.project.usesOrbits && !store.hierarchySettingsOpen && store.midiImportDraft==nil ? Color.clear:StudioTheme.surface).foregroundStyle(StudioTheme.text)
        .font(.system(size: 13)).buttonStyle(CanvasButtonStyle()).controlSize(.regular)
        .tint(StudioTheme.accent).preferredColorScheme(.dark)
        .onExitCommand { store.hierarchySettingsOpen = false; store.hierarchyParent() }
        .onAppear {
            topPitch = store.currentLane?.notes.map(\.pitch).max().map { min(128,max(12,$0+1)) } ?? (store.selectedTrack?.instrument.drums == true ? 48 : 72)
            // A false FocusState write can clear focus already assigned by the connection editor.
            if store.hierarchySettingsOpen { nameFocused = true }
        }
        .onChange(of:store.hierarchySettingsOpen){_,value in if value || nameFocused { nameFocused=value } }
    }
    private var midi: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("MIDI 편집 방식",selection:$store.midiStepMode){Text(store.project.usesOrbits ? "궤도":"피아노 롤").tag(false);Text("스텝").tag(true)}.pickerStyle(.segmented).labelsHidden().frame(width:110)
                Text("\(store.currentLane?.notes.count ?? 0)개 노트").foregroundStyle(StudioTheme.secondary)
                Menu("MIDI"){Button("MIDI 파일 가져오기"){store.chooseMIDIImport()};Divider();Button("노트 전체 선택 · ⌘A"){store.selectMIDINotes(Set((store.currentLane?.notes ?? []).map(\.id)))};Button("선택 해제"){store.selectedNoteID=nil};Divider();Menu("패턴 추가"){ForEach(MIDIPattern.allCases,id:\.self){pattern in Button(pattern.label){store.generateMIDI(pattern)}}};Button("MIDI 저장"){store.exportMIDI()}}
                Button("바운스"){store.bounceTrack()}.disabled(store.preparing).help("이 트랙의 섹션 출력을 이펙트와 함께 오디오로 변환")
                Spacer()
                Button { topPitch = max(12, topPitch-12) } label: { Image(systemName: "minus") }.help("한 옥타브 아래")
                Text("\(Scale.roots[(topPitch-1)%12])\((topPitch-1)/12-1)").monospacedDigit().help("표시 범위의 가장 높은 음")
                Button { topPitch = min(128, topPitch+12) } label: { Image(systemName: "plus") }.help("한 옥타브 위")
                Button { store.startMIDIRecording() } label: { Label(store.midiRecording ? "녹음 정지" : "MIDI 녹음", systemImage: "record.circle") }.disabled(store.editPatternID != nil)
            }
            if store.midiStepMode {StepEditor(store:store,topPitch:topPitch)} else if store.project.usesOrbits {
                OrbitMIDIEditor(store:store,topPitch:topPitch-1).frame(minHeight:120,maxHeight:.infinity)
            } else { GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    PianoRoll(store: store, topPitch: topPitch-1).frame(width: max(geometry.size.width, store.editorBeats*48+64), height: 452)
                }.background(StudioTheme.canvas)
            } }
            if !store.selectedMIDIIDs.isEmpty {MIDISelectionControls(store:store)}
            if store.selectedMIDIIDs.count==1,let id = store.selectedNoteID, let note = store.currentLane?.notes.first(where: { $0.id == id }) {
                HStack(spacing: 10) {
                    Text("\(Scale.roots[note.pitch%12])\(note.pitch/12-1)").monospacedDigit().accessibilityLabel("음높이 \(note.pitch)")
                    ValueField(title: "시작 박", value: noteBinding(id, \.beat, note.beat), range: 0...max(0,store.editorBeats-note.length))
                    ValueField(title: "길이", value: noteBinding(id, \.length, note.length), range: 0.03125...max(0.03125,store.editorBeats-note.beat))
                    ValueField(title: "세기", value: Binding(get: { Double(note.velocity) }, set: { value in guard var lane=store.currentLane,let i=lane.notes.firstIndex(where:{$0.id==id}) else{return};lane.notes[i].velocity=Int(value);store.setLane(lane) }), range: 1...127)
                    Button { store.removeNote() } label: { Image(systemName: "trash") }.help("선택 노트 삭제")
                }
            } else if store.selectedMIDIIDs.isEmpty { Text(store.midiStepMode ? "셀 클릭으로 입력 · ⌥ 클릭으로 선택 · Tab으로 입력 필드 이동" : store.project.usesOrbits ? "원호에 노트 입력 · 각도로 시간 이동 · 반경으로 음높이 · 끝 점으로 길이 조절":"빈 칸에 노트 입력 · 드래그로 이동 · 오른쪽 끝으로 길이 조절").font(.system(size: 11)).foregroundStyle(StudioTheme.secondary) }
        }
    }
    func noteBinding(_ id: ID, _ key: WritableKeyPath<Note, Double>, _ fallback: Double) -> Binding<Double> {
        Binding(get: { store.currentLane?.notes.first { $0.id == id }?[keyPath: key] ?? fallback }, set: { value in
            guard var lane = store.currentLane, let i = lane.notes.firstIndex(where: { $0.id == id }) else { return }
            lane.notes[i][keyPath: key] = value; store.setLane(lane)
        })
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
    func clipBinding(_ clip: AudioClip, _ key: WritableKeyPath<AudioClip, Double>) -> Binding<Double> { Binding(get: { clip[keyPath:key] }, set: { value in editClip(clip) { $0[keyPath:key]=value } }) }
    @ViewBuilder func signalControls(_ node: MusicCircle) -> some View {
        Toggle("음소거", isOn: Binding(get: { node.muted }, set: { value in store.updateMusic("음소거") { $0.muted=value } }))
        Button("트랙 바운스"){store.bounceTrack()}.disabled(store.preparing || store.selectedTrack == nil)
        ValueField(title: "출력 볼륨", value: Binding(get: { node.gain }, set: { value in store.updateMusic("출력 볼륨") { $0.gain=value } }), range: 0...4)
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
    @State private var settings=ContextSettings()
    @State private var global=MusicContext()
    private var context: MusicContext { store.selectedCircle?.context ?? store.project.global }
    func value<T>(_ key:WritableKeyPath<ContextSettings,Setting<T>>,_ fallback:T)->Binding<T> {Binding(get:{settings[keyPath:key].value ?? fallback},set:{settings[keyPath:key] = .local($0)})}
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            if let group=store.selectedHierarchyGroup {
                Text("\(group.members.count)개 서클 · 음악과 연결을 유지하는 배치 그룹")
                Button(group.collapsed ? "그룹 펼치기" : "그룹 접기") {store.updateHierarchyGroup{$0.collapsed.toggle()};store.hierarchySettingsOpen=false;store.hierarchyCommand=HierarchyCommand(action:.focus(store.hierarchySelection ?? .album,false))}
                Button("그룹 해제"){store.ungroupHierarchy()}
            } else if store.hierarchySelection == .album {
                CompactNumber("템포 · BPM",value:$global.tempo);MeterEditor(meter:$global.meter);ScaleEditor(scale:$global.scale)
                BeatEditor(grid:$global.beatGrid);PatternPicker(project:store.project,assignment:$global.rhythm)
                Button("앨범에 적용") {do{try ContextResolver.validate(global);store.mutate("앨범 음악 설정"){$0.global=global}}catch{store.fail(error)}}
            } else {
                SourcePicker(title:"템포",setting:$settings.tempo,fallback:context.tempo)
                if settings.tempo.source == .local {CompactNumber("BPM",value:value(\.tempo,context.tempo))}
                SourcePicker(title:"박자",setting:$settings.meter,fallback:context.meter)
                if settings.meter.source == .local {MeterEditor(meter:value(\.meter,context.meter))}
                SourcePicker(title:"스케일",setting:$settings.scale,fallback:context.scale)
                if settings.scale.source == .local {ScaleEditor(scale:value(\.scale,context.scale))}
                SourcePicker(title:"박 분할·강세",setting:$settings.beatGrid,fallback:context.beatGrid)
                if settings.beatGrid.source == .local {BeatEditor(grid:value(\.beatGrid,context.beatGrid))}
                SourcePicker(title:"리듬 패턴",setting:$settings.rhythm,fallback:context.rhythm)
                if settings.rhythm.source == .local {PatternPicker(project:store.project,assignment:value(\.rhythm,context.rhythm))}
                Button("서클에 적용") {store.updateHierarchySettings(settings)}
            }
            if let use=store.selectedUse,store.selectedMusic == nil,store.selectedHierarchyGroup == nil {
                CountControl(title:"마디",value:Binding(get:{use.barsOverride ?? store.project.sections.first{$0.id==use.sectionID}?.bars ?? 8},set:{v in store.updateUse("섹션 길이"){$0.barsOverride=v}}),range:1...1024)
                CountControl(title:"반복",value:Binding(get:{use.repeatCount},set:{v in store.updateUse("섹션 반복"){$0.repeatCount=v}}),range:1...256)
                HStack{Button("시작 섹션으로 지정"){store.setStart()};Button("재사용"){store.reuse()};Button("독립 원본으로 분리"){store.detach()}}
                let address=CircleAddress.section(arrangementID:store.project.activeArrangementID,useID:use.id)
                Menu("다음 섹션 연결"){ForEach(store.project.active.uses.filter{$0.id != use.id}){target in Button(target.name){store.connectHierarchy(address,.section(arrangementID:store.project.activeArrangementID,useID:target.id))}}}
                ForEach(store.project.active.edges.filter{$0.from==use.id}){edge in
                    HStack{Text(store.project.active.uses.first{$0.id==edge.to}?.name ?? "다음 섹션");Spacer();Button(store.project.active.chosenEdges[use.id]==edge.id ? "재생 경로":"이 경로 재생"){store.chooseHierarchyEdge(address,edgeID:edge.id)};Button("전환 편집"){store.openHierarchyTransition(address,edgeID:edge.id)};Button("연결 해제"){store.disconnectHierarchy(address,edgeID:edge.id)}}
                }
            }
            if let music=store.selectedMusic {
                Toggle("공유 원본 편집",isOn:$store.editOriginal)
                Toggle("음소거",isOn:Binding(get:{music.muted},set:{v in store.updateMusic("음소거"){$0.muted=v}}))
                if music.content.input == nil {
                    ValueField(title:"부모 안 시작 박",value:Binding(get:{music.startBeat},set:{v in store.updateMusic("시작 박"){$0.startBeat=v}}),range:0...131072)
                    ValueField(title:"길이 박",value:Binding(get:{music.lengthBeats ?? store.currentClock?.beats ?? 32},set:{v in store.updateMusic("길이"){$0.lengthBeats=v}}),range:0.03125...131072)
                    CountControl(title:"반복",value:Binding(get:{music.repeatCount},set:{v in store.updateMusic("반복"){$0.repeatCount=v}}),range:1...256)
                }
            }
            if case .composition(let id)=store.hierarchySelection,let composition=store.project.album?.composition(id) {
                CountControl(title:"곡·악장 반복",value:Binding(get:{composition.repeatCount},set:{value in store.mutate("곡·악장 반복"){p in if let i=p.album?.compositions.firstIndex(where:{$0.id==id}){p.album?.compositions[i].repeatCount=value}}}),range:1...256)
                if !composition.arrangementIDs.isEmpty {
                    StudioChoice("편곡안",selection:Binding(get:{composition.selectedArrangementID ?? ""},set:{store.chooseHierarchyArrangement($0)}),options:store.project.arrangements.filter{composition.arrangementIDs.contains($0.id)}.map{($0.id,$0.name)})
                    Button("편곡안 복제"){store.duplicateHierarchyArrangement()}
                }
                Button("악장 추가"){store.addComposition(.movement)}
            }
            if store.selectedUse != nil,store.selectedHierarchyGroup == nil { Button("리듬 패턴 만들기") { store.makeHierarchyPattern() } }
        }.onAppear{settings=store.hierarchySettings;global=store.project.global}
        .id(store.hierarchySelection)
    }
}
