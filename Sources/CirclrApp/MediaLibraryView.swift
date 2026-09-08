import SwiftUI
import CirclrCore
import CirclrAudio

extension AppStore {
    func showMediaLibrary() {
        commandPalette=nil;navigationOpen=false;keyboardHelp=false
        refreshLibraryDestination();libraryOpen=true;library.refresh()
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
        case .pattern(let id,let beat):return "\(project.patterns.first{$0.id==id}?.name ?? "리듬") · \(beat.formatted())박"
        case .section(let a,let u,let track,let beat,_,let original):
            let name=project.arrangements.first{$0.id==a}?.uses.first{$0.id==u}?.name ?? "섹션"
            let lane=project.tracks.first{$0.id==track}?.name ?? "새 트랙"
            return "\(name) › \(lane) · \(beat.formatted())박"+(original ? " · 공유 원본":"")
        }
    }
    func importLibrarySelection() {
        guard libraryOpen,!library.searching,canStartMediaImport,libraryDestinationCurrent,let request=libraryDestination else{library.notice="가져오기 대상을 갱신하고 재생·녹음을 정지하세요";return}
        do {
            let (entry,access,url)=try library.accessSelected()
            library.stopPreview()
            if entry.kind == .midi {
                guard case .section(let a,let u,_,_,_,_)=request.destination else{throw CirclrError("MIDI를 넣을 섹션을 선택하세요")}
                guard previewMIDIImport(url,projectID:request.projectID,revision:request.revision,generation:request.generation,arrangementID:a,useID:u) else{library.notice=status;return}
                withExtendedLifetime(access){}
                closeMediaLibrary()
            } else {
                beginAudioImport([url],request:request,retaining:access);closeMediaLibrary()
            }
        } catch {library.notice="가져오기 실패: \(mediaLibraryError(error))"}
    }
}

struct MediaLibraryView:View {
    @ObservedObject var store:AppStore
    @ObservedObject var library:MediaLibraryController
    init(store:AppStore) {self.store=store;self.library=store.library}
    private var canImport:Bool {store.canStartMediaImport && store.libraryDestinationCurrent && library.selected != nil && !library.searching}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text("샘플 라이브러리").font(.system(size:18,weight:.semibold))
                Spacer();Button("폴더 추가…"){library.chooseFolder()}
                Button{library.refresh()}label:{Image(systemName:"arrow.clockwise")}.help("등록 폴더 새로고침").accessibilityLabel("라이브러리 새로고침")
                Button("닫기 · Esc"){store.closeMediaLibrary()}.foregroundStyle(StudioTheme.secondary)
            }.padding(18)
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:$library.query,onMove:library.move,onSubmit:store.importLibrarySelection,onCancel:store.closeMediaLibrary,placeholder:"파일명 · 하위 폴더 · 형식 검색")
            }.padding(.horizontal,18).padding(.bottom,14)
            HStack(spacing:16) {
                Menu {
                    Button("모든 폴더"){library.folderFilter=nil}
                    ForEach(library.folders){folder in Button(folder.name){library.folderFilter=folder.id}}
                    if !library.folders.isEmpty {
                        Divider();Menu("목록에서 폴더 제거") {ForEach(library.folders){folder in Button(folder.name){library.removeFolder(folder.id)}}}
                    }
                }label:{Label(library.folders.first{$0.id==library.folderFilter}?.name ?? "모든 폴더",systemImage:"folder")}
                    .accessibilityLabel("검색 폴더 선택")
                Menu {
                    Button("모든 형식"){library.kindFilter=nil};Button("오디오"){library.kindFilter = .audio};Button("MIDI"){library.kindFilter = .midi}
                }label:{Text(library.kindFilter.map{$0 == .audio ? "오디오":"MIDI"} ?? "모든 형식")}.accessibilityLabel("샘플 형식 선택")
                Spacer()
                Text(library.scanning ? "폴더 읽는 중":library.searching ? "검색 중":"\(library.results.count)개 파일").foregroundStyle(StudioTheme.secondary).monospacedDigit()
            }.menuStyle(.borderlessButton).padding(.horizontal,18).padding(.vertical,10).background(StudioTheme.raised)
            if !library.notice.isEmpty {Text(library.notice).font(.system(size:12)).foregroundStyle(StudioTheme.accent).fixedSize(horizontal:false,vertical:true).lineLimit(3).help(library.notice).padding(.horizontal,18).padding(.vertical,8)}
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
                            LibraryResultRow(entry:entry,selected:library.selectedID==entry.id){library.select(entry.id)}
                        }
                    }
                }.onChange(of:library.selectedID){_,id in if let id{proxy.scrollTo(id,anchor:.center)}}
            }
            Divider().overlay(StudioTheme.line)
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:12) {
                    Button{library.togglePreview()}label:{Label(library.previewPreparing ? "준비 취소":library.previewing ? "미리 듣기 정지":"미리 듣기",systemImage:library.previewPreparing || library.previewing ? "stop.fill":"play.fill")}
                        .disabled(library.selected?.kind != .audio || !store.canStartMediaImport || (library.previewPending && !library.previewPreparing && !library.previewing))
                        .help("원속도 미리 듣기 · ⌥Space").keyboardShortcut(.space,modifiers:[.option])
                    Text(library.previewPreparing ? "출력 준비 중 · 취소할 수 있습니다":library.previewPending && !library.previewing ? "이전 출력 준비를 정리하고 있습니다":library.previewing ? String(format:"%.1f초 · ",library.previewSeconds)+library.detail:library.detail).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                }
                HStack(spacing:12) {
                    Menu("대상 섹션") {
                        ForEach(store.studioRoutes){section in Button(section.path+" › "+section.name){store.navigateStudio(section.id);store.refreshLibraryDestination()}}
                    }.menuStyle(.borderlessButton).fixedSize()
                    Text(store.libraryDestinationText).font(.system(size:12)).lineLimit(1).truncationMode(.middle)
                    if !store.libraryDestinationCurrent {Button("대상 갱신"){store.refreshLibraryDestination()}.help("현재 선택과 최신 음악 상태를 가져오기 대상으로 사용")}
                    Spacer(minLength:4)
                    Button(library.selected?.kind == .midi ? "MIDI 트랙 선택 →":"가져오기 · Return"){store.importLibrarySelection()}.disabled(!canImport)
                }
                Text(store.libraryDestination != nil && !store.libraryDestinationCurrent ? "곡이나 선택이 변경되었습니다. 가져오기 대상을 확인하고 갱신하세요":"↑↓ 선택 · Return 가져오기 · ⌥Space 미리 듣기 · Esc 닫기").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
            }.padding(18)
        }.frame(width:850,height:560).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))
            .overlay{RoundedRectangle(cornerRadius:10).stroke(StudioTheme.line,lineWidth:1)}
            .onChange(of:store.canStartMediaImport){_,ready in if !ready{library.stopPreview()}}
    }
}


private struct LibraryResultRow:View {
    let entry:LibraryEntry
    let selected:Bool
    let select:()->Void
    private var path:String {entry.folderName+" / "+entry.relativePath}
    private var typeName:String {entry.kind == .midi ? "MIDI":(entry.name as NSString).pathExtension.uppercased()}
    var body:some View {
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
            }.padding(.horizontal,18).padding(.vertical,10).frame(maxWidth:.infinity,alignment:.leading)
                .background(selected ? StudioTheme.raised:Color.clear)
                .overlay(alignment:.leading){if selected{Rectangle().fill(StudioTheme.accent).frame(width:3)}}
        }.buttonStyle(.plain).id(entry.id).help(path).accessibilityLabel(path).accessibilityAddTraits(selected ? .isSelected:[])
    }
}
