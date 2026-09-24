import SwiftUI
import AppKit
import CirclrCore

private struct CanvasNavigationBoundsKey:PreferenceKey {
    static var defaultValue=CGRect.zero
    static func reduce(value:inout CGRect,nextValue:()->CGRect){let next=nextValue();if next.width>0{value=next}}
}

/// The visible song-form controls use the same preview and guarded command as
/// the orbit handle, context menu, and keyboard shortcut.
struct SectionReorderToolbarState {
    let address:CircleAddress
    let projectID:ID
    let revision:Int
    let canMoveEarlier:Bool
    let canMoveLater:Bool
    let blockedReason:String?
    let orbitShortcuts:Bool
    let isFirst:Bool
    let isLast:Bool

    @MainActor init?(store:AppStore) {
        guard let address=store.hierarchySelection,case .section(let arrangementID,let useID)=address,
              store.hierarchySelections.count==1,store.hierarchySelections.contains(address) else{return nil}
        self.address=address
        projectID=store.project.id
        revision=store.project.musicRevision
        orbitShortcuts=store.project.usesOrbits
        var seen=Set<ID>()
        let order=(try? ArrangementCompiler.compile(store.project,arrangementID:arrangementID))?.occurrences
            .compactMap{seen.insert($0.use.id).inserted ? $0.use.id:nil} ?? []
        isFirst=order.first==useID
        isLast=order.last==useID
        if store.viewingMode || store.startupOpen {
            blockedReason="편집 화면에서 순서를 이동하세요"
        } else if store.midiRecording || store.audioRecordingBusy || store.audioRecordPending {
            blockedReason="테이크 녹음을 마친 뒤 순서를 이동하세요"
        } else if store.moviePreparing || store.movieWriter != nil || store.movieFinalizing != nil {
            blockedReason="영상 녹화를 마친 뒤 순서를 이동하세요"
        } else {
            blockedReason=nil
        }
        canMoveEarlier=blockedReason == nil && CanvasSectionReorder.placement(for:address,direction:.earlier,in:store.project) != nil
        canMoveLater=blockedReason == nil && CanvasSectionReorder.placement(for:address,direction:.later,in:store.project) != nil
    }

    @MainActor @discardableResult func move(_ direction:CanvasSectionReorder.Direction,on store:AppStore)->Bool {
        let enabled:Bool
        switch direction {case .earlier:enabled=canMoveEarlier;case .later:enabled=canMoveLater}
        guard store.hierarchySelection==address,
              store.hierarchySelections.count==1,store.hierarchySelections.contains(address),
              !(store.viewingMode || store.startupOpen || store.recordingBlocksDocumentAction ||
                store.audioRecordPending || store.moviePreparing || store.movieWriter != nil || store.movieFinalizing != nil),
              enabled else{return false}
        return store.moveSectionOccurrence(address,direction:direction,
                                           expectedProjectID:projectID,expectedRevision:revision)
    }

    func help(for direction:CanvasSectionReorder.Direction)->String {
        let title:String,enabled:Bool
        switch direction {
        case .earlier:title="선택 섹션 재생 순서 앞으로 한 칸";enabled=canMoveEarlier
        case .later:title="선택 섹션 재생 순서 뒤로 한 칸";enabled=canMoveLater
        }
        let shortcut:String
        if orbitShortcuts {
            switch direction {case .earlier:shortcut=" · ⇧⌥←";case .later:shortcut=" · ⇧⌥→"}
        } else {shortcut=""}
        guard !enabled else{return title+shortcut}
        let reason:String
        if let blockedReason {reason=blockedReason}
        else {
            switch direction {
            case .earlier:reason=isFirst ? "첫 섹션이라 앞에 놓을 수 없습니다":"분기·전환 때문에 이 방향으로 순서를 옮길 수 없습니다"
            case .later:reason=isLast ? "마지막 섹션이라 뒤에 놓을 수 없습니다":"분기·전환 때문에 이 방향으로 순서를 옮길 수 없습니다"
            }
        }
        return title+shortcut+" · "+reason
    }
}

private struct SectionReorderToolbar:View {
    @ObservedObject var store:AppStore
    let state:SectionReorderToolbarState

    var body:some View {
        HStack(spacing:2) {
            Text("순서").font(.system(size:11,weight:.medium)).foregroundStyle(StudioTheme.secondary)
                .accessibilityHidden(true)
            Button{state.move(.earlier,on:store)}label:{Image(systemName:"arrow.left").frame(width:22,height:26)}
                .disabled(!state.canMoveEarlier)
                .help(state.help(for:.earlier))
                .accessibilityLabel("선택 섹션 재생 순서 앞으로 한 칸")
                .accessibilityHint(state.help(for:.earlier))
            Button{state.move(.later,on:store)}label:{Image(systemName:"arrow.right").frame(width:22,height:26)}
                .disabled(!state.canMoveLater)
                .help(state.help(for:.later))
                .accessibilityLabel("선택 섹션 재생 순서 뒤로 한 칸")
                .accessibilityHint(state.help(for:.later))
        }.fixedSize(horizontal:true,vertical:false)
            .padding(.horizontal,4)
            .background(StudioTheme.canvas.opacity(0.94),in:RoundedRectangle(cornerRadius:6))
    }
}

struct RootView: View {
    private static let appVersion=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
    private static let appBuild=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "development"
    @ObservedObject var store: AppStore
    var body: some View {
        GeometryReader {geometry in workspace(size:geometry.size)}
            .frame(minWidth:700,minHeight:600)
    }
    private func workspace(size:CGSize)->some View {
        let chrome=WorkspaceChromeLayout(width:size.width)
        let overlays=WorkspaceOverlayLayout(viewport:size,headerHeight:chrome.headerHeight)
        return VStack(spacing:0) {
            if !store.viewingMode {
                header(chrome)
                Rectangle().fill(StudioTheme.line.opacity(0.65)).frame(height:1)
            }
            AlbumCanvas(store:store)
                .overlay(alignment:.top) {
                    if !store.viewingMode {
                        HStack(alignment:.top,spacing:12) {
                            breadcrumbs(compact:chrome.compactOverlays).frame(maxWidth:.infinity,alignment:.leading)
                            if chrome.compactOverlays {compactActions} else {actions.fixedSize(horizontal:true,vertical:false)}
                        }.padding(chrome.inset)
                    }
                }
                .overlay(alignment:.bottom) {
                    if store.viewingMode {
                        HStack {Spacer();ViewingModeControls(store:store)}.padding(chrome.inset)
                    } else {
                        footer(chrome).padding(.horizontal,chrome.inset).padding(.bottom,16)
                    }
                }
                .coordinateSpace(name:"albumCanvas")
                .onPreferenceChange(AgentConsoleBoundsKey.self){if store.consoleBounds != $0 {store.consoleBounds=$0}}
                .onPreferenceChange(CanvasNavigationBoundsKey.self){if store.navigationBounds != $0 {store.navigationBounds=$0}}
        }
        .disabled(store.outputPreferencesOpen)
        .accessibilityHidden(store.outputPreferencesOpen || store.libraryOpen || store.navigationOpen || store.soundPickerRequest != nil || store.arrangementPickerRequest != nil)
        .overlay(alignment:.top) {
            if !store.viewingMode,let palette=store.commandPalette {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.25).contentShape(Rectangle()).onTapGesture{store.commandPalette=nil;store.focusCanvas?()}
                    StudioCommandPalette(store:store,palette:palette).id(palette.id).padding(.top,overlays.topInset)
                }
            }
        }
        .overlay(alignment:.top) {
            if !store.viewingMode,store.navigationOpen {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.3).contentShape(Rectangle()).onTapGesture{store.navigationOpen=false;store.focusCanvas?()}
                    StudioNavigationView(store:store,size:overlays.pickerSize).id(store.navigationIntent.id).padding(.top,overlays.topInset)
                }
            }
        }
        .overlay(alignment:.top) {
            if !store.viewingMode,store.keyboardHelp {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.25).contentShape(Rectangle()).onTapGesture{store.keyboardHelp=false}
                    KeyboardHelpView(store:store).padding(.top,overlays.topInset)
                }
            }
        }
        .overlay(alignment:.top) {
            if !store.viewingMode,store.libraryOpen {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.3).contentShape(Rectangle()).onTapGesture{store.closeMediaLibrary()}
                    MediaLibraryView(store:store,size:overlays.pickerSize).padding(.top,overlays.topInset)
                }
            }
        }
        .overlay(alignment:.top) {
            if !store.viewingMode,let request=store.soundPickerRequest {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.3).contentShape(Rectangle()).onTapGesture{store.closeSoundPicker()}
                    SoundPickerView(store:store,request:request,size:overlays.pickerSize).id(request.id).padding(.top,overlays.topInset)
                }
            }
        }
        .overlay(alignment:.top) {
            if !store.viewingMode,let request=store.arrangementPickerRequest {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.3).contentShape(Rectangle())
                    ArrangementPickerView(store:store,request:request,size:overlays.pickerSize).id(request.id).padding(.top,overlays.topInset)
                }
            }
        }
        .overlay(alignment:.top) {
            if !store.viewingMode,store.outputPreferencesOpen {
                ZStack(alignment:.top) {
                    Color.black.opacity(0.3).contentShape(Rectangle()).onTapGesture{store.closeOutputPreferences()}
                    OutputPreferencesView(store:store,preferences:store.outputPreferences).padding(.top,overlays.topInset)
                }
            }
        }
        .disabled(store.startupOpen)
        .accessibilityHidden(store.startupOpen)
        .overlay {if store.startupOpen {StartupWorkspace(store:store)}}
        .onChange(of:store.navigationOpen){_,open in if open,store.outputPreferencesOpen{store.closeOutputPreferences(returnFocus:false)}}
        .onChange(of:store.libraryOpen){_,open in if open,store.outputPreferencesOpen{store.closeOutputPreferences(returnFocus:false)}}
        .onChange(of:store.keyboardHelp){_,open in if open,store.outputPreferencesOpen{store.closeOutputPreferences(returnFocus:false)}}
        .onChange(of:store.arrangementPickerRequest?.id){_,id in if id != nil,store.outputPreferencesOpen{store.closeOutputPreferences(returnFocus:false)}}
        .onChange(of:store.soundPickerRequest?.id){_,id in if id != nil,store.outputPreferencesOpen{store.closeOutputPreferences(returnFocus:false)}}
        .background(StudioTheme.canvas)
        .font(.system(size:12)).foregroundStyle(StudioTheme.text).buttonStyle(CanvasButtonStyle())
        .numberEditing(in:store)
        .onExitCommand{if store.startupOpen {store.closeStartup()} else if store.viewingMode {_ = store.setViewingMode(false)} else if !store.viewingMode,store.outputPreferencesOpen {store.closeOutputPreferences()} else if store.arrangementPickerRequest != nil {store.closeArrangementPicker()} else if store.soundPickerRequest != nil {store.closeSoundPicker()} else if !store.viewingMode,store.libraryOpen {store.closeMediaLibrary()} else if store.connectionsOpen {store.connectionsOpen=false;store.focusCanvas?()} else if !store.viewingMode,store.navigationOpen {store.navigationOpen=false;store.focusCanvas?()} else if store.commandPalette != nil {store.commandPalette=nil;store.focusCanvas?()} else if !store.viewingMode,store.keyboardHelp {store.keyboardHelp=false} else if let draft=store.midiImportDraft {store.cancelMIDIImport(draft.id)} else {store.hierarchySettingsOpen=false;store.hierarchyParent()}}
        .alert("작업을 완료하지 못했습니다",isPresented:Binding(get:{store.errorMessage != nil},set:{if !$0{store.errorMessage=nil}})){Button("확인"){store.errorMessage=nil}}message:{Text(store.errorMessage ?? "")}
    }
    private func header(_ chrome:WorkspaceChromeLayout)->some View {
        VStack(spacing:0) {
            if chrome.twoHeaderRows {
                HStack(spacing:12) {
                    brand
                    projectMenu.frame(maxWidth:.infinity,alignment:.leading)
                    globalSettings(compact:true)
                    addCircleMenu
                }.frame(height:58)
                HStack(spacing:10) {
                    TransportControls(store:store,meter:store.meter,compact:true).layoutPriority(1)
                    recordingAndViewingControls(compact:chrome.width<900)
                    Spacer(minLength:8)
                    utilityMenu
                }.frame(height:58)
            } else {
                HStack(spacing:12) {
                    brand
                    projectMenu.frame(width:160)
                    Rectangle().fill(StudioTheme.line).frame(width:1,height:24)
                    TransportControls(store:store,meter:store.meter,compact:chrome.compactTransport)
                    recordingAndViewingControls(compact:false)
                    Spacer(minLength:8)
                    utilityMenu
                    globalSettings(compact:chrome.compactTransport)
                    addCircleMenu
                }.frame(height:66)
            }
        }.menuStyle(.borderlessButton).padding(.horizontal,chrome.inset).background(StudioTheme.surface)
    }
    private var brand:some View {
            VStack(alignment:.leading,spacing:1) {
                Text("circlr").font(.system(size:25,weight:.semibold)).tracking(-1)
                Text("\(Self.appVersion) · \(Self.appBuild)")
                    .font(.system(size:11,weight:.medium,design:.monospaced))
                    .foregroundStyle(StudioTheme.secondary)
                    .accessibilityLabel("써클러 버전 \(Self.appVersion), 빌드 \(Self.appBuild)")
                    .help("버전 \(Self.appVersion) · 빌드 \(Self.appBuild)")
            }.fixedSize()
    }
    private var projectMenu:some View {
            Menu {
                Button("새 앨범"){store.newProject()};Button("열기…"){store.open()};Button("저장"){store.save()};Button("다른 이름으로 저장…"){store.save(as:true)}
                Divider();Button("앨범 WAV 내보내기…"){store.export()};Button("트랙별 stems 내보내기…"){store.export(stems:true)}
            }label:{HStack(spacing:7){Text(store.project.name).lineLimit(1);if store.dirty{Circle().fill(StudioTheme.accent).frame(width:4,height:4)}}.frame(maxWidth:.infinity,alignment:.leading)}
    }
    private func movieButton(compact:Bool)->some View {
        let recording=store.movieWriter != nil && !store.moviePreparing
        let finalizing=store.movieFinalizing != nil
        return Button{store.toggleMovieRecording()}label:{
            HStack(spacing:6) {
                if store.moviePreparing || finalizing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName:recording ? "stop.circle.fill":"record.circle")
                        .font(.system(size:15,weight:.medium))
                }
                Text(finalizing ? (compact ? "영상 저장":"영상 저장 중")
                    :store.moviePreparing ? (compact ? "영상 준비":"영상 준비 중")
                    :recording ? (compact ? "영상 중":"영상 녹화 중")
                    :compact ? "영상":"영상 녹화")
                    .font(.system(size:11,weight:.semibold))
                    .fixedSize(horizontal:true,vertical:false)
            }
            .foregroundStyle(recording ? Color.red:StudioTheme.text)
            .frame(minHeight:26)
            .padding(.horizontal,7)
            .background(recording ? Color.red.opacity(0.12):StudioTheme.raised,in:RoundedRectangle(cornerRadius:6))
        }
        .help(finalizing ? "영상 파일을 저장하고 있습니다":store.moviePreparing ? "녹화 준비 중 · 누르면 취소":recording ? "영상 녹화 마치기":store.midiRecording || store.audioRecordingBusy ? "테이크 녹음을 마친 뒤 영상 녹화를 시작하세요":"캔버스와 음악을 MP4로 녹화")
        .accessibilityLabel(finalizing ? "영상 저장 중":store.moviePreparing ? "영상 녹화 준비 취소":recording ? "영상 녹화 마치기":"영상 녹화 시작")
        .disabled(!recording && !store.moviePreparing && (finalizing || store.midiRecording || store.audioRecordingBusy))
    }
    private func recordingAndViewingControls(compact:Bool)->some View {
        HStack(spacing:2) {
            TakeRecordingMenu(store:store,compact:compact)
            movieButton(compact:compact)
            viewingModeButton
        }.fixedSize(horizontal:true,vertical:false)
    }
    private var viewingModeButton:some View {
            Button{_ = store.setViewingMode(true)}label:{
                Image(systemName:"eye")
                    .font(.system(size:15,weight:.medium))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width:26,height:26)
            }
            .help("텍스트 없는 감상 모드 (⇧⌘V)")
            .accessibilityLabel("감상 모드 시작")
    }
    private func globalSettings(compact:Bool)->some View {
            Button{store.focusHierarchy(.album,detail:true);store.hierarchySettingsOpen=true}label:{
                HStack(spacing:compact ? 7:12){Text("앨범").font(.system(size:11)).foregroundStyle(StudioTheme.secondary);Text("\(store.project.global.tempo.formatted())").font(.system(size:18,weight:.medium,design:.rounded)).monospacedDigit();Text("BPM").font(.system(size:11)).foregroundStyle(StudioTheme.secondary);Text(store.project.global.meter.label);if !compact{Text(store.project.global.scale.label).foregroundStyle(StudioTheme.secondary)}}
            }.fixedSize(horizontal:true,vertical:false).help("앨범의 글로벌 음악 설정").accessibilityLabel("앨범 글로벌 음악 설정").accessibilityValue("\(store.project.global.tempo.formatted()) BPM · \(store.project.global.meter.label) · \(store.project.global.scale.label)")
    }
    private var utilityMenu:some View {
        Menu {
            Button("샘플 라이브러리…"){store.showMediaLibrary()}
            Button("작업 이동…"){store.showNavigation()}
            Button("명령 검색…"){store.showCommands()}
            Button("텍스트 없는 감상 모드"){_ = store.setViewingMode(true)}
        }label:{Image(systemName:"ellipsis").frame(width:24,height:24)}
            .accessibilityLabel("작업 도구").help("샘플·작업 이동·명령 검색·감상 모드")
    }
    private var addCircleMenu:some View {
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
            } label: {
                HStack(spacing:6) {
                    Image(systemName:"plus")
                    Text("서클 추가")
                    Image(systemName:"chevron.down").font(.system(size:9,weight:.bold))
                }
                .font(.system(size:12,weight:.semibold))
                .foregroundStyle(StudioTheme.canvas)
                .padding(.horizontal,10).frame(minHeight:30)
                .background(StudioTheme.accent,in:RoundedRectangle(cornerRadius:6))
                .contentShape(RoundedRectangle(cornerRadius:6))
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("서클 추가")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .fixedSize(horizontal:true,vertical:false)
            .help("현재 위치에 서클 추가")
            .accessibilityLabel("서클 추가")
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
    private func breadcrumbs(compact:Bool)->some View {
        let path=store.hierarchyScene?.path(to:store.hierarchySelection ?? .album) ?? []
        return HStack(spacing:3) {
            if let root=path.first {breadcrumb(root)}
            if path.count>(compact ? 2:4) {
                Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(StudioTheme.secondary)
                Menu("…") {ForEach(Array(path.dropFirst().dropLast(compact ? 1:2))){node in Button(node.title){store.hierarchySettingsOpen=false;store.focusHierarchy(node.id)}}}
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("상위 서클 경로")
            }
            ForEach(Array(path.count>(compact ? 2:4) ? path.suffix(compact ? 1:2):path.dropFirst())){node in
                Image(systemName:"chevron.right").font(.system(size:10)).foregroundStyle(StudioTheme.secondary)
                breadcrumb(node)
            }
        }.padding(3).background(StudioTheme.canvas.opacity(0.94),in:RoundedRectangle(cornerRadius:6))
    }
    private func breadcrumb(_ node:CircleSceneNode)->some View {
        Button{store.hierarchySettingsOpen=false;store.focusHierarchy(node.id)}label:{Text(node.role == .album ? "앨범":node.title).font(.system(size:13,weight:node.id==store.hierarchySelection ? .semibold:.regular)).lineLimit(1).frame(maxWidth:130).foregroundStyle(node.id==store.hierarchySelection ? StudioTheme.text:StudioTheme.secondary)}.help(node.title+" · "+node.subtitle)
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
                if let reorder=SectionReorderToolbarState(store:store) {
                    SectionReorderToolbar(store:store,state:reorder)
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
                autoLayoutMenu
                Button("가로 정렬"){store.alignHierarchy(0)}.disabled(store.project.usesOrbits || store.hierarchySelections.count<2)
                Button("세로 정렬"){store.alignHierarchy(1)}.disabled(store.project.usesOrbits || store.hierarchySelections.count<2)
                Button("동일 간격"){store.alignHierarchy(2)}.disabled(store.project.usesOrbits || store.hierarchySelections.count<3)
                Button("원형 그룹 만들기"){store.makeHierarchyGroup()}.disabled(store.hierarchySelections.count<2)
                if let group=store.selectedHierarchyGroup {Button(group.collapsed ? "그룹 펼치기":"그룹 접기"){store.updateHierarchyGroup{$0.collapsed.toggle()}};Button("그룹 해제"){store.ungroupHierarchy()}}
                Divider();Button("전체 앨범 맞추기"){store.hierarchyCommand=HierarchyCommand(action:.fit)}
            }label:{Image(systemName:"square.grid.3x3")}.menuStyle(.borderlessButton).help("그리드·정렬 기준")
        }.padding(3).background(StudioTheme.canvas.opacity(0.94),in:RoundedRectangle(cornerRadius:6))
    }
    private var autoLayoutMenu:some View {
        Menu("자동 정렬") {
            Text(store.hierarchyAutoLayoutScope()?.label ?? "같은 위치의 서클을 2개 이상 선택하세요")
            ForEach(store.hierarchyAutoLayoutModes,id:\.1){mode,title in
                Button(title){store.autoLayoutHierarchy(mode)}
            }
        }.disabled(store.hierarchyAutoLayoutLocked || store.hierarchyAutoLayoutScope()==nil)
    }
    private var compactActions:some View {
        HStack(spacing:5) {
            if let reorder=SectionReorderToolbarState(store:store) {
                SectionReorderToolbar(store:store,state:reorder)
            }
            Menu {
            if let owner=store.arrangementPickerOwner {
                Button("현재 곡의 편곡안…"){store.showArrangementPicker(compositionID:owner.id)}
            }
            if store.canEditCirclePorts {Button("서클 연결…"){store.showConnections()}}
            if let address=store.hierarchySelection {
                Button("선택 서클 설정…"){store.connectionsOpen=false;store.hierarchyTransitionID=nil;store.focusHierarchy(address,detail:true);store.hierarchySettingsOpen=true}
            }
            if store.selectedUse != nil {
                Button("선택 섹션 듣기"){store.play(onlySelection:true)}
                Button("섹션 재사용"){store.reuse()}
            }
            if let reorder=SectionReorderToolbarState(store:store) {
                Divider()
                Button("재생 순서 앞으로 한 칸"){reorder.move(.earlier,on:store)}
                    .disabled(!reorder.canMoveEarlier).help(reorder.help(for:.earlier))
                Button("재생 순서 뒤로 한 칸"){reorder.move(.later,on:store)}
                    .disabled(!reorder.canMoveLater).help(reorder.help(for:.later))
            }
            Divider()
            Toggle("궤도 타임라인",isOn:Binding(get:{store.project.usesOrbits},set:{store.setCanvasViewPreferences(layout:$0 ? .orbit:.freeform)}))
            Toggle("그리드",isOn:Binding(get:{store.project.album?.layout.grid ?? true},set:{store.setCanvasViewPreferences(grid:$0)}))
            Toggle("놓을 때 스냅",isOn:Binding(get:{store.project.album?.layout.snap ?? true},set:{store.setCanvasViewPreferences(snap:$0)}))
            autoLayoutMenu
            Button("가로 정렬"){store.alignHierarchy(0)}.disabled(store.project.usesOrbits || store.hierarchySelections.count<2)
            Button("세로 정렬"){store.alignHierarchy(1)}.disabled(store.project.usesOrbits || store.hierarchySelections.count<2)
            Button("동일 간격"){store.alignHierarchy(2)}.disabled(store.project.usesOrbits || store.hierarchySelections.count<3)
            Button("원형 그룹 만들기"){store.makeHierarchyGroup()}.disabled(store.hierarchySelections.count<2)
            if let group=store.selectedHierarchyGroup {
                Button(group.collapsed ? "그룹 펼치기":"그룹 접기"){store.updateHierarchyGroup{$0.collapsed.toggle()}}
                Button("그룹 해제"){store.ungroupHierarchy()}
            }
            Button("전체 앨범 맞추기"){store.hierarchyCommand=HierarchyCommand(action:.fit)}
            }label:{Label("서클 도구",systemImage:"slider.horizontal.3")}
                .menuStyle(.borderlessButton).fixedSize().padding(3)
                .background(StudioTheme.canvas.opacity(0.94),in:RoundedRectangle(cornerRadius:6))
                .accessibilityLabel("선택 서클 도구")
        }
    }
    @ViewBuilder private func footer(_ chrome:WorkspaceChromeLayout)->some View {
        if chrome.compactOverlays {
            VStack(alignment:.trailing,spacing:8) {
                navigation
                measuredConsole.frame(maxWidth:.infinity,alignment:.leading)
            }
        } else {
            HStack(alignment:.bottom,spacing:16) {
                measuredConsole.frame(maxWidth:.infinity,alignment:.leading)
                navigation.fixedSize(horizontal:true,vertical:false)
            }
        }
    }
    private var measuredConsole:some View {
        AgentConsole(store:store)
            .background(GeometryReader{geometry in Color.clear.preference(key:AgentConsoleBoundsKey.self,value:geometry.frame(in:.named("albumCanvas")))})
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
            .background(GeometryReader{geometry in Color.clear.preference(key:CanvasNavigationBoundsKey.self,value:geometry.frame(in:.named("albumCanvas")))})
    }
}
struct TransportControls:View {
    @ObservedObject var store:AppStore
    @ObservedObject var meter:TransportMeter
    var compact=false
    private var followTargetTitle:String {
        switch store.playbackFollowSettings.target {
        case .song: return "곡"
        case .section: return "섹션"
        case .pinned: return "고정"
        }
    }
    private var followButtonTitle:String {
        switch store.playbackFollow {
        case .suspended: return "\(followTargetTitle) 팔로우 재개"
        case .off: return "\(followTargetTitle) 팔로우 끔"
        case .following: return "\(followTargetTitle) 팔로우"
        }
    }
    private var followAccessibilityLabel:String {
        switch store.playbackFollow {
        case .suspended: return "\(followTargetTitle) 팔로우 재개"
        case .off: return "\(followTargetTitle) 팔로우 켜기"
        case .following: return "\(followTargetTitle) 팔로우 끄기"
        }
    }
    private var compactFollowTitle:String {
        switch store.playbackFollow {
        case .suspended: return "\(followTargetTitle) 팔로우 재개"
        case .off: return "\(followTargetTitle) 팔로우 끔"
        case .following: return "\(followTargetTitle) 팔로우"
        }
    }
    private var followSymbol:String {
        switch store.playbackFollow {
        case .suspended: return "pause.circle"
        case .off: return "location.slash"
        case .following: return "scope"
        }
    }
    var body:some View {
        HStack(spacing:12) {
            Button {store.play()} label:{Image(systemName:meter.playing || store.preparing || store.auditionStatus.pending || store.moviePreparing || store.midiRecording || store.audioRecording || store.audioRecordingBusy ? "stop.fill":"play.fill").font(.system(size:13)).foregroundStyle(StudioTheme.accent).frame(width:24,height:26)}
                .background(StudioTheme.raised,in:Circle()).help(store.mediaImportTask != nil ? "파일 가져오기 취소 · Space":store.auditionStatus.pending ? store.auditionDetail:store.agentJob?.kind=="bounce" && store.agentJob?.state=="running" ? "바운스 취소 · Space":"재생 / 정지 · Space")
                .accessibilityLabel(store.mediaImportTask != nil ? "파일 가져오기 취소":store.agentJob?.kind=="bounce" && store.agentJob?.state=="running" ? "바운스 취소":store.auditionStatus.pending ? (store.auditionPresentation.canCancel ? "미리 듣기 취소":"미리 듣기 정리 중"):store.preparing || store.moviePreparing ? "재생 준비 취소":store.midiRecording || store.audioRecordingBusy ? "녹음 정지":meter.playing ? "재생 정지":"재생")
            TransportStatusReadout(time:time,label:store.mediaImportTask != nil ? "파일 가져오는 중":store.outputLabel,detail:store.mediaImportTask != nil ? store.status:store.outputDetail,
                footer:store.mediaImportTask != nil ? "Space로 취소":store.auditionStatus.pending ? store.auditionPresentation.footer:store.outputCanCancel ? "Space로 취소":store.playbackLoopCaption,
                textColor:StudioTheme.text,secondaryColor:StudioTheme.secondary)
            Button { store.playbackFollow = store.playbackFollow.toggled() } label: {
                HStack(spacing:compact ? 4:6) {
                    Image(systemName:followSymbol)
                    Text(compact ? compactFollowTitle:followButtonTitle)
                }.font(.system(size:compact ? 11:12,weight:.medium)).lineLimit(1).fixedSize(horizontal:true,vertical:false)
                    .foregroundStyle(store.playbackFollow == .following ? StudioTheme.accent : store.playbackFollow == .suspended ? StudioTheme.text : StudioTheme.secondary)
            }
            .accessibilityLabel(followAccessibilityLabel)
            .accessibilityValue(store.playbackFollow == .following ? "켜짐" : store.playbackFollow == .off ? "꺼짐" : "일시 중지")
            .help(store.playbackFollow == .suspended ? "\(followTargetTitle) 팔로우 재개":"선택한 대상을 따라갑니다. 화면을 직접 조작하면 일시 중지합니다")
            Menu {
                Button((store.playbackFollowSettings.target == .song ? "✓ ":"")+"현재 곡 서클"){store.choosePlaybackFollowTarget(.song)}
                Button((store.playbackFollowSettings.target == .section ? "✓ ":"")+"현재 섹션 서클"){store.choosePlaybackFollowTarget(.section)}
                Button("선택한 서클 고정"){store.choosePlaybackFollowTarget(.pinned)}.disabled(store.hierarchySelection == nil)
                Button("팔로우 끄기"){store.playbackFollow = .off}
                Divider()
                Button((store.playbackFollowSettings.framing == .fit ? "✓ ":"")+"대상 전체 맞춤"){store.choosePlaybackFollowFraming(.fit)}
                Button((store.playbackFollowSettings.framing == .keepZoom ? "✓ ":"")+"현재 배율 유지"){store.choosePlaybackFollowFraming(.keepZoom)}
                Menu("섹션 전환 연출") {
                    Button((store.playbackFollowSettings.transition == .off ? "✓ ":"")+"끄기"){store.choosePlaybackFollowTransition(.off)}
                    Button((store.playbackFollowSettings.transition == .subtle ? "✓ ":"")+"은은하게"){store.choosePlaybackFollowTransition(.subtle)}
                    Button((store.playbackFollowSettings.transition == .emphasized ? "✓ ":"")+"강조"){store.choosePlaybackFollowTransition(.emphasized)}
                }
            } label:{Image(systemName:"chevron.down")}
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .accessibilityLabel("재생 팔로우 대상과 구도").help("곡·섹션·고정 서클과 전환 연출")
            Menu {
                Button("루프 끄기"){_ = store.choosePlaybackLoop(.off)}
                Button("현재 곡 전체"){_ = store.choosePlaybackLoop(.song)}
                Button("선택 섹션"){_ = store.choosePlaybackLoop(.section)}
            } label:{
                HStack(spacing:5){Image(systemName:"repeat");if !compact {Text(store.playbackLoopMode == .off ? "루프 꺼짐":store.playbackLoopMode == .song ? "곡 루프":"섹션 루프")}}
                    .foregroundStyle(store.playbackLoopMode == .off ? StudioTheme.secondary:StudioTheme.accent)
            }.menuStyle(.borderlessButton)
                .disabled(!store.canChoosePlaybackLoop)
                .accessibilityLabel("루프 재생 범위")
                .accessibilityValue(store.playbackLoopCaption ?? store.playbackLoopMode.rawValue)
                .help("재생 중 루프 범위는 다음 경계에서 전환 · 루프 해제 후 잔향 재생")
            if store.audioRecordingBusy {Button(store.audioRecordTitle){store.stop()}.disabled(store.audioRecordingLocked).foregroundStyle(.red).lineLimit(1).frame(maxWidth:110)}
            else if store.midiRecording {Button("녹음 정지"){store.stop()}.foregroundStyle(.red)}
        }
    }
    var time:String {
        let seconds=store.audioRecording ? store.audioInputSeconds
            :store.midiRecording ? store.midiRecordingElapsedSeconds:meter.seconds
        let t=max(0,seconds)
        return String(format:"%02d:%04.1f",Int(t)/60,t.truncatingRemainder(dividingBy:60))
    }
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
