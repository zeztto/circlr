import SwiftUI
import CirclrCore
import CirclrAudio

extension AppStore {
    func showMediaLibrary() {
        soundPickerRequest=nil;commandPalette=nil;navigationOpen=false;keyboardHelp=false
        library.foldersVisible=false;refreshLibraryDestination();libraryOpen=true;library.refresh()
        library.watchKeyboard{[weak self] in self?.libraryOpen == true && self?.canStartMediaImport == true}
    }
    func closeMediaLibrary() {libraryOpen=false;focusCanvas?()}
    func refreshLibraryDestination() {
        library.notice=""
        libraryDestination=audioImportDestination(at:nil).map(mediaImportRequest)
    }
    var libraryDestinationCurrent:Bool {
        guard let target=libraryDestination else{return false}
        return target.projectID==project.id && target.revision==project.musicRevision && target.generation==mediaImportGeneration && target.selection==hierarchySelection
    }
    var libraryDestinationText:String {
        guard let target=libraryDestination else{return "가져올 섹션을 선택하세요"}
        switch target.destination {
        case .pattern(let id,let beat):return "\(project.patterns.first{$0.id==id}?.name ?? "리듬") · \(BeatPosition.text(beat))박"
        case .section(let a,let u,let track,let beat,_,let original):
            let name=studioRoutes.first{$0.id == .section(arrangementID:a,useID:u)}.map{$0.path+" › "+$0.name} ?? project.arrangements.first{$0.id==a}?.uses.first{$0.id==u}?.name ?? "섹션"
            let lane=library.chosen.count==1 && library.chosen.first?.kind == .midi ? "새 MIDI 트랙":library.chosenIDs.count>1 ? "새 트랙 \(library.chosenIDs.count)개":AudioImportPlacement.trackLabel(track,in:project)
            return "\(name) › \(lane) · \(BeatPosition.text(beat))박"+(original ? " · 공유 원본":"")
        }
    }
    func importLibrarySelection() {
        library.notice=""
        guard libraryOpen,!library.searching,canStartMediaImport,libraryDestinationCurrent,let request=libraryDestination else{library.notice="가져오기 대상을 갱신하고 재생·녹음을 정지하세요";return}
        do {
            if let issue=libraryPlacementIssue {throw CirclrError(issue)}
            let (entries,access,urls)=try library.accessSelection()
            library.stopPreview()
            if entries[0].kind == .midi {
                guard case .section(let a,let u,_,let beat,let position,_)=request.destination else{throw CirclrError("MIDI를 넣을 섹션을 선택하세요")}
                guard previewMIDIImport(urls[0],projectID:request.projectID,revision:request.revision,generation:request.generation,arrangementID:a,useID:u,beat:beat,position:position) else{library.notice=status;return}
                withExtendedLifetime(access){}
                closeMediaLibrary()
            } else {
                beginAudioImport(urls,request:request,retaining:access);closeMediaLibrary()
            }
        } catch {if library.selectionIssue==nil{library.notice="가져오기 실패: \(mediaLibraryError(error))"}}
    }
}

struct MediaLibraryView:View {
    @ObservedObject var store:AppStore
    @ObservedObject var library:MediaLibraryController
    init(store:AppStore) {self.store=store;self.library=store.library}
    private var canImport:Bool {store.canStartMediaImport && store.libraryDestinationCurrent && !library.chosenIDs.isEmpty && library.selectionIssue==nil && store.libraryPlacementIssue==nil && !library.searching}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text("샘플 라이브러리").font(.system(size:18,weight:.semibold))
                Spacer()
                Button(library.workspace != .files ? "파일 검색":"폴더 관리 · \(library.folders.count)"){library.workspace = library.workspace == .files ? .folders:.files}
                Button("폴더 추가…"){library.chooseFolder()}
                Button{library.refresh()}label:{Image(systemName:"arrow.clockwise")}.help("등록 폴더 새로고침").accessibilityLabel("라이브러리 새로고침")
                Button(library.choosingDestination || library.choosingTrack ? "파일 목록 · Esc":"닫기 · Esc"){if library.choosingDestination || library.choosingTrack{library.workspace = .files}else{store.closeMediaLibrary()}}.keyboardShortcut(.escape,modifiers:[]).foregroundStyle(StudioTheme.secondary)
            }.padding(18)
            if library.foldersVisible {folderWorkspace} else if library.choosingDestination {
                LibrarySectionChooser(store:store,library:library,projectID:store.project.id,revision:store.project.musicRevision,generation:store.mediaImportGeneration,selection:store.hierarchySelection)
            } else if case .track(let request,let entryID)=library.workspace {
                LibraryTrackChooser(store:store,library:library,request:request,entryID:entryID)
            } else {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:$library.query,onMove:library.move,onSubmit:store.importLibrarySelection,onCancel:store.closeMediaLibrary,placeholder:"파일명 · 하위 폴더 · 형식 검색",onExtend:library.extend).id(library.searchFocus)
            }.padding(.horizontal,18).padding(.bottom,14)
            HStack(spacing:16) {
                Menu {
                    Button("모든 폴더"){library.folderFilter=nil}
                    ForEach(library.folders){folder in Button(library.folderLabel(folder.id)){library.folderFilter=folder.id}}
                }label:{Label(library.folderFilter.map{library.folderLabel($0)} ?? "모든 폴더",systemImage:"folder").lineLimit(1).truncationMode(.middle)}
                    .frame(maxWidth:250,alignment:.leading).accessibilityLabel("검색 폴더 선택").accessibilityValue(library.folderFilter.map{library.folderLabel($0)} ?? "모든 폴더")
                Menu {
                    Button("모든 형식"){library.kindFilter=nil};Button("오디오"){library.kindFilter = .audio};Button("MIDI"){library.kindFilter = .midi}
                }label:{Text(library.kindFilter.map{$0 == .audio ? "오디오":"MIDI"} ?? "모든 형식")}.accessibilityLabel("샘플 형식 선택")
                Spacer()
                Button("모두 선택"){library.selectAll()}.disabled(library.searching || library.results.isEmpty || library.results.count>64).help("검색 결과 전체 선택 · 한 번에 최대 64개")
                Button("해제"){library.clearSelection()}.disabled(library.searching || library.chosenIDs.isEmpty).accessibilityLabel("샘플 선택 해제")
                Text(library.scanning ? "폴더 읽는 중":library.searching ? "검색 중":"\(library.results.count)개 파일").foregroundStyle(StudioTheme.secondary).monospacedDigit()
            }.menuStyle(.borderlessButton).padding(.horizontal,18).padding(.vertical,10).background(StudioTheme.raised)
            notices
            ScrollViewReader { proxy in
                ScrollView {
                    if library.results.isEmpty {
                        VStack(spacing:12) {
                            Text(library.folders.isEmpty ? "다운로드한 샘플 폴더를 연결하세요":library.scanning ? "오디오·MIDI 파일을 찾고 있습니다":"일치하는 파일이 없습니다").font(.system(size:15))
                            if library.folders.isEmpty {Text("Splice 다운로드 폴더와 개인 샘플 폴더를 함께 검색할 수 있습니다.").foregroundStyle(StudioTheme.secondary);Button("샘플 폴더 추가…"){library.chooseFolder()}}
                        }.frame(maxWidth:.infinity).padding(.vertical,50)
                    }
                    LazyVStack(spacing:1) {
                        ForEach(library.results){entry in
                            LibraryResultRow(entry:entry,folderLabel:library.folderLabel(entry.folderID),selected:library.chosenIDs.contains(entry.id),focused:library.selectedID==entry.id,select:{library.select(entry.id)},toggle:{library.toggleSelection(entry.id)}).disabled(library.searching)
                        }
                    }
                }.onChange(of:library.selectedID){_,id in if let id{proxy.scrollTo(id,anchor:.center)}}
            }
            Divider().overlay(StudioTheme.line)
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:12) {
                    Text("\(library.chosenIDs.count)개 선택").monospacedDigit()
                    Text(library.selectionIssue ?? library.selected.map{"현재 파일 · "+$0.name} ?? "파일을 선택하세요")
                        .foregroundStyle(library.selectionIssue==nil ? StudioTheme.secondary:StudioTheme.accent).lineLimit(1).truncationMode(.middle).help(library.selectionIssue ?? library.selected?.name ?? "")
                }.font(.system(size:12))
                HStack(spacing:12) {
                    Button{library.togglePreview()}label:{Label(library.previewPreparing ? "준비 취소":library.previewing ? "미리 듣기 정지":"미리 듣기",systemImage:library.previewPreparing || library.previewing ? "stop.fill":"play.fill")}
                        .disabled(library.selected?.kind != .audio || !store.canStartMediaImport || (library.previewPending && !library.previewPreparing && !library.previewing))
                        .help("원속도 미리 듣기 · ⌥Space").keyboardShortcut(.space,modifiers:[.option])
                    Text(library.previewPreparing ? "출력 준비 중 · 취소할 수 있습니다":library.previewPending && !library.previewing ? "이전 출력 준비를 정리하고 있습니다":library.previewing ? String(format:"%.1f초 · ",library.previewSeconds)+library.detail:library.detail).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                }
                HStack(spacing:12) {
                    Button("대상 섹션…"){library.notice="";library.choosingDestination=true}.help("곡·섹션 검색으로 가져오기 위치 선택")
                    Text(store.libraryDestinationText).font(.system(size:12)).lineLimit(1).truncationMode(.middle).help(store.libraryDestinationText)
                    if !store.libraryDestinationCurrent {Button("대상 갱신"){store.refreshLibraryDestination()}.help("현재 선택과 최신 음악 상태를 가져오기 대상으로 사용")}
                    Spacer(minLength:4)
                    Button(library.chosen.count==1 && library.chosen.first?.kind == .midi ? "MIDI 트랙 선택 →":"\(library.chosenIDs.count)개 가져오기 · Return"){store.importLibrarySelection()}.disabled(!canImport)
                }
                if let request=store.libraryDestination {LibraryPlacementControls(store:store,library:library,request:request)}
                if let issue=store.libraryPlacementIssue,store.libraryDestination != nil {Text(issue).font(.system(size:12)).foregroundStyle(StudioTheme.accent)}
                Text(store.libraryDestination != nil && !store.libraryDestinationCurrent ? "곡이나 선택이 변경되었습니다. 가져오기 대상을 확인하고 갱신하세요":"체크박스 여러 파일 · ↑↓ 한 파일 · ⇧↑↓ 범위 · Return 가져오기 · ⌥Space 현재 파일 듣기").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
            }.padding(18)
            }
        }.frame(width:850,height:560).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))
            .overlay{RoundedRectangle(cornerRadius:10).stroke(StudioTheme.line,lineWidth:1)}
            .onChange(of:store.canStartMediaImport){_,ready in if !ready{library.stopPreview()}}
    }
    @ViewBuilder private var notices:some View {
        if !library.notice.isEmpty {
            HStack(alignment:.top,spacing:12) {
                Text(library.notice).fixedSize(horizontal:false,vertical:true).lineLimit(3).help(library.notice)
                Spacer(minLength:0)
                Button{library.notice=""}label:{Image(systemName:"xmark")}.accessibilityLabel("라이브러리 안내 닫기")
            }.font(.system(size:12)).foregroundStyle(StudioTheme.accent).padding(.horizontal,18).padding(.vertical,8)
        }
        if !library.foldersVisible && !library.scanNotice.isEmpty {
            Text(library.scanNotice).font(.system(size:12)).foregroundStyle(StudioTheme.accent).fixedSize(horizontal:false,vertical:true).lineLimit(3).help(library.scanNotice).padding(.horizontal,18).padding(.vertical,8)
        }
    }
    private var folderWorkspace:some View {
        VStack(alignment:.leading,spacing:0) {
            Text("등록을 해제해도 원본 파일과 곡에 가져온 오디오는 유지됩니다.")
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(.horizontal,18).padding(.bottom,14)
            notices
            ScrollView {
                if library.folders.isEmpty {
                    Text("검색할 샘플 폴더를 추가하세요").frame(maxWidth:.infinity).padding(.vertical,50)
                }
                LazyVStack(spacing:0) {
                    ForEach(library.folders){folder in
                        VStack(alignment:.leading,spacing:8) {
                            HStack(spacing:12) {
                                Text(library.folderLabel(folder.id)).font(.system(size:14,weight:.medium)).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength:8)
                                Button("파일 보기"){library.showFiles(folder.id);library.foldersVisible=false}.accessibilityLabel("\(library.folderLabel(folder.id)) 파일 보기")
                                Button("등록 해제"){library.removeFolder(folder.id)}.accessibilityLabel("\(library.folderLabel(folder.id)) 등록 해제")
                            }
                            Text(library.folderLocations[folder.id] ?? "폴더 위치를 확인할 수 없습니다")
                                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                                .help(library.folderLocations[folder.id] ?? folder.name)
                            Text(library.folderStatus(folder.id))
                                .font(.system(size:12)).foregroundStyle(library.folderIssues[folder.id]==nil ? StudioTheme.secondary:StudioTheme.accent)
                                .fixedSize(horizontal:false,vertical:true)
                        }.padding(18)
                        Divider().overlay(StudioTheme.line)
                    }
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}


private struct LibraryResultRow:View {
    let entry:LibraryEntry
    let folderLabel:String
    let selected:Bool
    let focused:Bool
    let select:()->Void
    let toggle:()->Void
    private var path:String {folderLabel+" / "+entry.relativePath}
    private var typeName:String {entry.kind == .midi ? "MIDI":(entry.name as NSString).pathExtension.uppercased()}
    var body:some View {
        HStack(spacing:0) {
            Toggle("가져오기 선택",isOn:Binding(get:{selected},set:{_ in toggle()})).toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel("\(path) 가져오기 선택").padding(.leading,18)
        Button(action:select) {
            HStack(spacing:12) {
                Image(systemName:entry.kind == .audio ? "waveform":"pianokeys").foregroundStyle(StudioTheme.secondary).frame(width:20)
                VStack(alignment:.leading,spacing:4) {
                    Text(entry.name).font(.system(size:14,weight:.medium)).lineLimit(1)
                    Text(path).font(.system(size:11)).foregroundStyle(StudioTheme.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength:12)
                Text(typeName).font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                Text(ByteCountFormatter.string(fromByteCount:entry.bytes,countStyle:.file)).font(.system(size:12)).monospacedDigit().frame(width:72,alignment:.trailing)
            }.padding(.horizontal,12).padding(.vertical,10).frame(maxWidth:.infinity,alignment:.leading)
        }.buttonStyle(.plain).help(path).accessibilityLabel(path).accessibilityAddTraits(focused ? .isSelected:[])
        }.background(selected ? StudioTheme.raised:Color.clear)
            .overlay(alignment:.leading){if focused{Rectangle().fill(StudioTheme.accent).frame(width:3)}}.id(entry.id)
    }
}
