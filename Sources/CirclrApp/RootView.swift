import SwiftUI
import AppKit
import CirclrCore

struct RootView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(spacing:0) {
            header
            Rectangle().fill(StudioTheme.line.opacity(0.65)).frame(height:1)
            AlbumCanvas(store:store)
                .overlay(alignment:.topLeading){breadcrumbs.padding(20)}
                .overlay(alignment:.topTrailing){actions.padding(20)}
                .overlay(alignment:.bottomLeading){AgentConsole(store:store).background(GeometryReader{geometry in Color.clear.preference(key:AgentConsoleBoundsKey.self,value:geometry.frame(in:.named("albumCanvas")))}).padding(.leading,20).padding(.trailing,210).padding(.bottom,18)}
                .overlay(alignment:.bottomTrailing){navigation.padding(20)}
                .coordinateSpace(name:"albumCanvas")
                .onPreferenceChange(AgentConsoleBoundsKey.self){if store.consoleBounds != $0 {store.consoleBounds=$0}}
        }
        .disabled(store.outputPreferencesOpen)
        .accessibilityHidden(store.outputPreferencesOpen || store.libraryOpen || store.navigationOpen || store.soundPickerRequest != nil || store.arrangementPickerRequest != nil)
        .overlay(alignment:.top) {
            if let palette=store.commandPalette {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.25).contentShape(Rectangle()).onTapGesture{store.commandPalette=nil;store.focusCanvas?()}
                    StudioCommandPalette(store:store,palette:palette).id(palette.id).padding(.top,85)
                }
            }
        }
        .overlay(alignment:.top) {
            if store.navigationOpen {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.3).contentShape(Rectangle()).onTapGesture{store.navigationOpen=false;store.focusCanvas?()}
                    StudioNavigationView(store:store).id(store.navigationIntent.id).padding(.top,85)
                }
            }
        }
        .overlay(alignment:.top) {
            if store.keyboardHelp {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.25).contentShape(Rectangle()).onTapGesture{store.keyboardHelp=false}
                    KeyboardHelpView(store:store).padding(.top,85)
                }
            }
        }
        .overlay(alignment:.top) {
            if store.libraryOpen {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.3).contentShape(Rectangle()).onTapGesture{store.closeMediaLibrary()}
                    MediaLibraryView(store:store).padding(.top,85)
                }
            }
        }
        .overlay(alignment:.top) {
            if let request=store.soundPickerRequest {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.3).contentShape(Rectangle()).onTapGesture{store.closeSoundPicker()}
                    SoundPickerView(store:store,request:request).id(request.id).padding(.top,85)
                }
            }
        }
        .overlay(alignment:.top) {
            if let request=store.arrangementPickerRequest {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.3).contentShape(Rectangle())
                    ArrangementPickerView(store:store,request:request).id(request.id).padding(.top,85)
                }
            }
        }
        .overlay(alignment:.top) {
            if store.outputPreferencesOpen {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.3).contentShape(Rectangle()).onTapGesture{store.closeOutputPreferences()}
                    OutputPreferencesView(store:store,preferences:store.outputPreferences).padding(.top,85)
                }
            }
        }
        .onChange(of:store.navigationOpen){_,open in if open,store.outputPreferencesOpen{store.closeOutputPreferences(returnFocus:false)}}
        .onChange(of:store.libraryOpen){_,open in if open,store.outputPreferencesOpen{store.closeOutputPreferences(returnFocus:false)}}
        .onChange(of:store.keyboardHelp){_,open in if open,store.outputPreferencesOpen{store.closeOutputPreferences(returnFocus:false)}}
        .onChange(of:store.arrangementPickerRequest?.id){_,id in if id != nil,store.outputPreferencesOpen{store.closeOutputPreferences(returnFocus:false)}}
        .onChange(of:store.soundPickerRequest?.id){_,id in if id != nil,store.outputPreferencesOpen{store.closeOutputPreferences(returnFocus:false)}}
        .frame(minWidth:1024,minHeight:740).background(StudioTheme.canvas)
        .font(.system(size:12)).foregroundStyle(StudioTheme.text).buttonStyle(CanvasButtonStyle())
        .numberEditing(in:store)
        .onExitCommand{if store.outputPreferencesOpen {store.closeOutputPreferences()} else if store.arrangementPickerRequest != nil {store.closeArrangementPicker()} else if store.soundPickerRequest != nil {store.closeSoundPicker()} else if store.libraryOpen {store.closeMediaLibrary()} else if store.connectionsOpen {store.connectionsOpen=false;store.focusCanvas?()} else if store.navigationOpen {store.navigationOpen=false;store.focusCanvas?()} else if store.commandPalette != nil {store.commandPalette=nil;store.focusCanvas?()} else if store.keyboardHelp {store.keyboardHelp=false} else if let draft=store.midiImportDraft {store.cancelMIDIImport(draft.id)} else {store.hierarchySettingsOpen=false;store.hierarchyParent()}}
        .alert("작업을 완료하지 못했습니다",isPresented:Binding(get:{store.errorMessage != nil},set:{if !$0{store.errorMessage=nil}})){Button("확인"){store.errorMessage=nil}}message:{Text(store.errorMessage ?? "")}
    }
    private var header:some View {
        GeometryReader { geometry in headerRow(compact:geometry.size.width<1180) }.frame(height:66)
    }
    private func headerRow(compact:Bool)->some View {
        HStack(spacing:compact ? 10:14) {
            Text("circlr").font(.system(size:25,weight:.semibold)).tracking(-1)
            Menu {
                Button("새 앨범"){store.newProject()};Button("열기…"){store.open()};Button("저장"){store.save()};Button("다른 이름으로 저장…"){store.save(as:true)}
                Divider();Button("앨범 WAV 내보내기…"){store.export()};Button("트랙별 stems 내보내기…"){store.export(stems:true)}
            }label:{HStack(spacing:7){Text(store.project.name).lineLimit(1);if store.dirty{Circle().fill(StudioTheme.accent).frame(width:4,height:4)}}.frame(maxWidth:compact ? 110:170,alignment:.leading)}
            Rectangle().fill(StudioTheme.line).frame(width:1,height:24)
            TransportControls(store:store,meter:store.meter)
            Button{store.toggleMovieRecording()}label:{
                Image(systemName:store.movieWriter != nil ? "stop.circle.fill":"record.circle")
                    .foregroundStyle(store.movieWriter != nil ? Color.red:StudioTheme.secondary)
            }.help(store.movieWriter != nil ? "영상 녹화 마치기":"캔버스와 음악을 MP4로 녹화")
                .accessibilityLabel(store.movieWriter != nil ? "영상 녹화 마치기":"영상 녹화 시작")
                .disabled(store.movieFinalizing != nil)
            Spacer(minLength:8)
            Button{store.showMediaLibrary()}label:{Label("샘플",systemImage:"waveform")}.help("로컬 샘플 검색·미리 듣기 · ⌥⌘L")
            Button{store.showNavigation()}label:{HStack(spacing:6){Image(systemName:"arrow.left.arrow.right");if !compact{Text("작업 이동")}}}.help("섹션·트랙·음색·이펙트로 바로 이동 · ⌘J").accessibilityLabel("작업 이동")
            Button{store.showCommands()}label:{Image(systemName:"command")}.help("명령 검색 · ⇧⌘P")
            Button{store.focusHierarchy(.album,detail:true);store.hierarchySettingsOpen=true}label:{
                HStack(spacing:compact ? 7:12){Text("앨범").font(.system(size:11)).foregroundStyle(StudioTheme.secondary);Text("\(store.project.global.tempo.formatted())").font(.system(size:18,weight:.medium,design:.rounded)).monospacedDigit();Text("BPM").font(.system(size:9)).foregroundStyle(StudioTheme.secondary);Text(store.project.global.meter.label);Text(store.project.global.scale.label).foregroundStyle(StudioTheme.secondary)}
            }.fixedSize(horizontal:true,vertical:false).help("앨범의 글로벌 음악 설정").accessibilityLabel("앨범 글로벌 음악 설정").accessibilityValue("\(store.project.global.tempo.formatted()) BPM · \(store.project.global.meter.label) · \(store.project.global.scale.label)")
            Menu {
                Text(creationTitle)
                switch creationContainer {
                case .composition(let id):
                    if store.project.album?.composition(id)?.children.isEmpty != false {Button("섹션 서클"){store.addSection()}}
                    Button("악장 서클"){store.addComposition(.movement)}
                case .section:
                    Button("MIDI 서클"){store.addMIDICircle()}
                    Button("오디오 가져오기…"){store.importAudio()}
                    Button("오디오 녹음"){store.startAudioRecording()}
                    Button("오디오 라우터 서클"){store.addMusicRouter()}
                    Menu("이펙터 서클"){ForEach(EffectKind.allCases,id:\.self){kind in Button(AppStore.effectName(kind)){store.addMusicEffect(kind)}}}
                case .sound:
                    Button("버스 서클"){store.addHierarchyBus()}
                    Menu("전역 이펙터 서클"){ForEach(EffectKind.allCases,id:\.self){kind in Button(AppStore.effectName(kind)){store.addHierarchySignalEffect(kind)}}}
                default:
                    Button("곡 서클"){store.addComposition(.song)}
                }
                Divider()
                Menu("다른 위치") {
                    if creationContainer != .album {Button("앨범에 곡 서클"){store.addComposition(.song)}}
                    if case .composition = creationContainer {} else if store.selectedCompositionID != nil {
                        Button("현재 곡에 섹션 서클"){store.addSection()}
                        Button("현재 곡에 악장 서클"){store.addComposition(.movement)}
                    }
                    if creationContainer != .sound {
                        Button("앨범 사운드로 이동"){store.hierarchySettingsOpen=false;store.focusHierarchy(.sound)}
                        Button("앨범 사운드에 버스 서클"){store.addHierarchyBus()}
                        Menu("앨범 사운드에 이펙터"){ForEach(EffectKind.allCases,id:\.self){kind in Button(AppStore.effectName(kind)){store.addHierarchySignalEffect(kind)}}}
                    }
                }
            }label:{Label("서클 추가",systemImage:"plus").font(.system(size:12,weight:.semibold)).foregroundStyle(StudioTheme.canvas).padding(.horizontal,8).padding(.vertical,5)}
                .background(StudioTheme.accent,in:RoundedRectangle(cornerRadius:6))
        }.menuStyle(.borderlessButton).padding(.horizontal,22).frame(height:66).background(StudioTheme.surface)
    }
    private var creationContainer:CircleAddress {(store.hierarchySelection ?? .album).creationContainer}
    private var creationTitle:String {
        switch creationContainer {
        case .composition:return "현재 곡·악장에 추가"
        case .section:return "현재 섹션에 추가"
        case .sound:return "앨범 사운드에 추가"
        default:return "앨범에 추가"
        }
    }
    private var breadcrumbs:some View {
        let path=store.hierarchyScene?.path(to:store.hierarchySelection ?? .album) ?? []
        return HStack(spacing:3) {
            if let root=path.first {breadcrumb(root)}
            if path.count>4 {
                Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(StudioTheme.secondary)
                Menu("…") {ForEach(Array(path.dropFirst().dropLast(2))){node in Button(node.title){store.hierarchySettingsOpen=false;store.focusHierarchy(node.id)}}}
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("상위 서클 경로")
            }
            ForEach(Array(path.count>4 ? path.suffix(2):path.dropFirst())){node in
                Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(StudioTheme.secondary)
                breadcrumb(node)
            }
        }.padding(3).background(StudioTheme.canvas.opacity(0.94),in:RoundedRectangle(cornerRadius:6))
    }
    private func breadcrumb(_ node:CircleSceneNode)->some View {
        Button{store.hierarchySettingsOpen=false;store.focusHierarchy(node.id)}label:{Text(node.role == .album ? "앨범":node.title).lineLimit(1).frame(maxWidth:130).foregroundStyle(node.id==store.hierarchySelection ? StudioTheme.text:StudioTheme.secondary)}.help(node.title+" · "+node.subtitle)
    }
    private var actions:some View {
        HStack(spacing:5) {
            if let address=store.hierarchySelection {
                if let owner=store.arrangementPickerOwner {
                    let choice=(try? ArrangementSelection.catalog(store.project,compositionID:owner.id))?.first{$0.id==owner.selectedArrangementID}
                    Button{store.showArrangementPicker(compositionID:owner.id)}label:{
                        Label(choice?.title ?? "편곡안",systemImage:"magnifyingglass").lineLimit(1).frame(maxWidth:180)
                    }.help((choice?.title ?? owner.name)+" · 이 곡·악장의 편곡안 찾기 · ⌥⌘J")
                        .accessibilityLabel("현재 편곡안 · "+(choice?.title ?? owner.name))
                }
                if store.canEditCirclePorts { Button("연결") { store.showConnections() }.help("IN/OUT·대상·8방향 위치 편집 · L") }
                Button{store.connectionsOpen=false;store.hierarchyTransitionID=nil;store.focusHierarchy(address,detail:true);store.hierarchySettingsOpen=true}label:{Image(systemName:"slider.horizontal.3")}.help("선택 서클의 이름·음악 설정")
                if store.selectedUse != nil {
                    Button{store.play(onlySelection:true)}label:{Image(systemName:"play.circle")}.help("선택 섹션 듣기")
                    Button{store.reuse()}label:{Image(systemName:"plus.square.on.square")}.help("섹션 재사용")
                }
            }
            Menu {
                Toggle("궤도 타임라인",isOn:Binding(get:{store.project.usesOrbits},set:{value in
                    store.setCanvasViewPreferences(layout:value ? .orbit:.freeform)
                }))
                Divider()
                Toggle("그리드",isOn:Binding(get:{store.project.album?.layout.grid ?? true},set:{value in store.setCanvasViewPreferences(grid:value)}))
                Toggle("놓을 때 스냅",isOn:Binding(get:{store.project.album?.layout.snap ?? true},set:{value in store.setCanvasViewPreferences(snap:value)}))
                Divider()
                Button("가로 정렬"){store.alignHierarchy(0)}.disabled(store.project.usesOrbits || store.hierarchySelections.count<2)
                Button("세로 정렬"){store.alignHierarchy(1)}.disabled(store.project.usesOrbits || store.hierarchySelections.count<2)
                Button("동일 간격"){store.alignHierarchy(2)}.disabled(store.project.usesOrbits || store.hierarchySelections.count<3)
                Button("원형 그룹 만들기"){store.makeHierarchyGroup()}.disabled(store.hierarchySelections.count<2)
                if let group=store.selectedHierarchyGroup {Button(group.collapsed ? "그룹 펼치기":"그룹 접기"){store.updateHierarchyGroup{$0.collapsed.toggle()}};Button("그룹 해제"){store.ungroupHierarchy()}}
                Divider();Button("전체 앨범 맞추기"){store.hierarchyCommand=HierarchyCommand(action:.fit)}
            }label:{Image(systemName:"square.grid.3x3")}.menuStyle(.borderlessButton).help("그리드·정렬 기준")
        }.padding(3).background(StudioTheme.canvas.opacity(0.94),in:RoundedRectangle(cornerRadius:6))
    }
    private var status:some View {
        VStack(alignment:.leading,spacing:7) {
            HStack{if store.preparing{if store.agentJob?.kind=="bounce" {ProgressView().controlSize(.small)}else{ProgressView(value:store.progress).frame(width:65)}};Text(store.status).lineLimit(1)}
            if store.hierarchySelections.count>1 { Text("\(store.hierarchySelections.count)개 서클 선택 · ⌘G 그룹") }
            Text("휠 ↑ 확대 · ↓ 축소     두 번 클릭해 들어가기     Esc 상위 서클")
        }.font(.system(size:10)).foregroundStyle(StudioTheme.secondary).frame(maxWidth:560,alignment:.leading).allowsHitTesting(false)
    }
    private var navigation:some View {
        HStack(spacing:1) {
            Button{store.panMode.toggle()}label:{Image(systemName:store.panMode ? "hand.draw.fill":"cursorarrow").foregroundStyle(StudioTheme.accent)}.help("선택 V · 화면 이동 H")
            Button{store.hierarchyCommand=HierarchyCommand(action:.zoom(0.75))}label:{Image(systemName:"minus")}.help("축소")
            Button{store.hierarchyCommand=HierarchyCommand(action:.zoom(1.33))}label:{Image(systemName:"plus")}.help("확대")
            Button{store.hierarchyParent()}label:{Image(systemName:"arrow.up.backward")}.help("상위 서클")
            Button{store.hierarchySettingsOpen=false;store.hierarchyCommand=HierarchyCommand(action:.fit)}label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}.help("전체 앨범 · F")
        }.padding(4).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(StudioTheme.line))
    }
}
struct TransportControls:View {
    @ObservedObject var store:AppStore
    @ObservedObject var meter:TransportMeter
    var body:some View {
        HStack(spacing:12) {
            Button {store.play()} label:{Image(systemName:meter.playing || store.preparing || store.auditionStatus.pending || store.moviePreparing || store.midiRecording || store.audioRecording || store.audioRecordingBusy ? "stop.fill":"play.fill").font(.system(size:13)).foregroundStyle(StudioTheme.accent).frame(width:24,height:26)}
                .background(StudioTheme.raised,in:Circle()).help(store.mediaImportTask != nil ? "파일 가져오기 취소 · Space":store.auditionStatus.pending ? store.auditionDetail:store.agentJob?.kind=="bounce" && store.agentJob?.state=="running" ? "바운스 취소 · Space":"재생 / 정지 · Space")
                .accessibilityLabel(store.mediaImportTask != nil ? "파일 가져오기 취소":store.agentJob?.kind=="bounce" && store.agentJob?.state=="running" ? "바운스 취소":store.auditionStatus.pending ? (store.auditionPresentation.canCancel ? "미리 듣기 취소":"미리 듣기 정리 중"):store.preparing || store.moviePreparing ? "재생 준비 취소":store.midiRecording || store.audioRecordingBusy ? "녹음 정지":meter.playing ? "재생 정지":"재생")
            TransportStatusReadout(time:time,label:store.mediaImportTask != nil ? "파일 가져오는 중":store.outputLabel,detail:store.mediaImportTask != nil ? store.status:store.outputDetail,
                footer:store.mediaImportTask != nil ? "Space로 취소":store.auditionStatus.pending ? store.auditionPresentation.footer:store.outputCanCancel ? "Space로 취소":nil,
                textColor:StudioTheme.text,secondaryColor:StudioTheme.secondary)
            Button { store.playbackFollow = store.playbackFollow.toggled() } label: {
                Label(store.playbackFollow == .suspended ? "팔로우 재개" : "재생 팔로우", systemImage: store.playbackFollow == .following ? "scope" : "location.slash")
                    .font(.system(size:11)).lineLimit(1).fixedSize(horizontal:true,vertical:false)
                    .foregroundStyle(store.playbackFollow == .following ? StudioTheme.accent : StudioTheme.secondary)
            }
            .accessibilityLabel(store.playbackFollow == .suspended ? "재생 팔로우 재개" : "재생 팔로우")
            .accessibilityValue(store.playbackFollow == .following ? "켜짐" : store.playbackFollow == .off ? "꺼짐" : "일시 중지")
            .help("현재 섹션을 따라갑니다. 화면을 직접 조작하면 멈춥니다")
            if store.audioRecordingBusy {Button(store.audioRecordTitle){store.stop()}.disabled(store.audioRecordingLocked).foregroundStyle(.red)}
            else if store.midiRecording {Button("녹음 정지"){store.stop()}.foregroundStyle(.red)}
        }
    }
    var time:String {let t=max(0,store.audioRecording ? store.audioInputSeconds:meter.seconds);return String(format:"%02d:%04.1f",Int(t)/60,t.truncatingRemainder(dividingBy:60))}
}
struct CanvasButtonStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {StudioButtonBody(configuration:configuration)}
    private struct StudioButtonBody:View {
        let configuration:ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hovering=false
        var body:some View {
            configuration.label.padding(.horizontal,9).padding(.vertical,7)
                .background(Color.white.opacity(configuration.isPressed ? 0.12:(hovering && enabled ? 0.065:0)),in:RoundedRectangle(cornerRadius:6))
                .opacity(enabled ? 1:0.35).contentShape(Rectangle()).onHover{hovering=$0}
        }
    }
}
