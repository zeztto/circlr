import SwiftUI
import CirclrCore
import CirclrAudio

extension AppStore {
    func showMediaLibrary() {
        arrangementPickerRequest=nil;soundPickerRequest=nil;commandPalette=nil;navigationOpen=false;keyboardHelp=false
        library.foldersVisible=false;refreshLibraryDestination();libraryOpen=true;library.refresh()
        library.watchKeyboard{[weak self] in self?.libraryOpen == true && self?.canStartMediaImport == true}
    }
    func closeMediaLibrary() {libraryOpen=false;focusCanvas?()}
    func refreshLibraryDestination() {
        library.notice=""
        libraryDestination=audioImportDestination(at:nil).map{mediaImportRequest($0)}
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
                guard previewMIDIImport(urls[0],projectID:request.projectID,revision:request.revision,generation:request.generation,arrangementID:a,useID:u,beat:beat,position:position,retaining:access) else{library.notice=status;return}
                closeMediaLibrary()
            } else {
                beginAudioImport(urls,request:request,retaining:access);closeMediaLibrary()
            }
        } catch {if library.selectionIssue==nil{library.notice="가져오기 실패: \(mediaLibraryError(error))"}}
    }
}

enum MediaLibraryFilterMenu:Equatable {
    case folder,kind
    static func acceptsActivation(_ modifiers:EventModifiers)->Bool {
        modifiers.intersection([.command,.control,.option,.shift]).isEmpty
    }
    var triggerFocus:String {self == .folder ? "folder-filter":"kind-filter"}
    func optionFocusKeys(folderCount:Int)->[String] {
        switch self {
        case .folder:return (0...folderCount).map{"folder-option-\($0)"}
        case .kind:return (0...2).map{"kind-option-\($0)"}
        }
    }
    func optionHeight(in overlayHeight:CGFloat,folderCount:Int)->CGFloat {
        min(CGFloat(optionFocusKeys(folderCount:folderCount).count)*32+12,min(180,max(88,overlayHeight*0.2)))
    }
}

/// Only the focused key is materialized. Large search results never become a
/// 100,000-element array of focus identifiers on each Tab press.
struct MediaLibraryKeyboardOrder {
    enum Rows {
        case none
        case files(Int)
        case folders(Int)
        case filter(MediaLibraryFilterMenu,Int)

        var count:Int {
            switch self {
            case .none:return 0
            case .files(let count),.folders(let count):return max(0,count)*2
            case .filter(let menu,let folders):return menu == .folder ? max(0,folders)+1:3
            }
        }
        func key(at index:Int)->String? {
            guard index>=0,index<count else{return nil}
            switch self {
            case .none:return nil
            case .files:return index.isMultiple(of:2) ? "file-toggle-\(index/2)":"file-\(index/2)"
            case .folders:return index.isMultiple(of:2) ? "folder-open-\(index/2)":"folder-remove-\(index/2)"
            case .filter(let menu,_):return "\(menu == .folder ? "folder":"kind")-option-\(index)"
            }
        }
        func index(of key:String)->Int? {
            func suffix(_ prefix:String,limit:Int)->Int? {
                guard key.hasPrefix(prefix),let index=Int(key.dropFirst(prefix.count)),index>=0,index<limit else{return nil}
                return index
            }
            switch self {
            case .none:return nil
            case .files(let count):
                if let index=suffix("file-toggle-",limit:count){return index*2}
                return suffix("file-",limit:count).map{$0*2+1}
            case .folders(let count):
                if let index=suffix("folder-open-",limit:count){return index*2}
                return suffix("folder-remove-",limit:count).map{$0*2+1}
            case .filter(let menu,_):return suffix("\(menu == .folder ? "folder":"kind")-option-",limit:count)
            }
        }
    }
    let before:[String]
    let rows:Rows
    let after:[String]
    private var count:Int {before.count+rows.count+after.count}
    private func index(of key:String)->Int? {
        if let index=before.firstIndex(of:key){return index}
        if let index=rows.index(of:key){return before.count+index}
        return after.firstIndex(of:key).map{before.count+rows.count+$0}
    }
    private func key(at index:Int)->String? {
        guard index>=0,index<count else{return nil}
        if index<before.count{return before[index]}
        let rowIndex=index-before.count
        if rowIndex<rows.count{return rows.key(at:rowIndex)}
        return after[rowIndex-rows.count]
    }
    func next(current:String?,backward:Bool)->String? {
        guard count>0 else{return nil}
        let index=current.flatMap{self.index(of:$0)} ?? 0
        return key(at:backward ? (index==0 ? count-1:index-1):(index+1)%count)
    }
}

struct MediaLibraryView:View {
    @ObservedObject var store:AppStore
    @ObservedObject var library:MediaLibraryController
    let size:CGSize
    @FocusState private var keyboardFocus:String?
    @State private var openFilter:MediaLibraryFilterMenu?
    init(store:AppStore,size:CGSize) {self.store=store;self.library=store.library;self.size=size}
    private var canImport:Bool {store.canStartMediaImport && store.libraryDestinationCurrent && !library.chosenIDs.isEmpty && library.selectionIssue==nil && store.libraryPlacementIssue==nil && !library.searching}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text("샘플 라이브러리").font(.system(size:18,weight:.semibold))
                Spacer()
                Button(library.workspace != .files ? "파일 검색":"폴더 관리 · \(library.folders.count)"){library.workspace = library.workspace == .files ? .folders:.files}
                    .focusable().focused($keyboardFocus,equals:"workspace")
                Button("폴더 추가…"){library.chooseFolder()}.focusable().focused($keyboardFocus,equals:"add-folder")
                Button{library.refresh()}label:{Image(systemName:"arrow.clockwise")}.help("등록 폴더 새로고침").accessibilityLabel("라이브러리 새로고침")
                    .focusable().focused($keyboardFocus,equals:"refresh")
                Button(library.choosingDestination || library.choosingTrack ? "파일 목록 · Esc":"닫기 · Esc"){if library.choosingDestination || library.choosingTrack{library.workspace = .files}else{store.closeMediaLibrary()}}.frame(minHeight:32).keyboardShortcut(.escape,modifiers:[]).foregroundStyle(StudioTheme.secondary)
                    .focusable().focused($keyboardFocus,equals:"close")
            }.padding(18).simultaneousGesture(TapGesture().onEnded {dismissFilterForPointer()})
            if library.foldersVisible {folderWorkspace} else if library.choosingDestination {
                LibrarySectionChooser(store:store,library:library,projectID:store.project.id,revision:store.project.musicRevision,generation:store.mediaImportGeneration,selection:store.hierarchySelection,keyboardFocus:$keyboardFocus)
            } else if case .track(let request,let entryID)=library.workspace {
                LibraryTrackChooser(store:store,library:library,request:request,entryID:entryID,keyboardFocus:$keyboardFocus)
            } else {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:$library.query,onMove:library.move,onSubmit:store.importLibrarySelection,onCancel:store.closeMediaLibrary,placeholder:"파일명 · 하위 폴더 · 형식 검색",onExtend:library.extend).id(library.searchFocus).frame(minHeight:32)
                    .focused($keyboardFocus,equals:"search")
            }.padding(.horizontal,18).padding(.bottom,14)
                .simultaneousGesture(TapGesture().onEnded {dismissFilterForPointer()})
            HStack(spacing:8) {
                Button {toggleFilter(.folder)} label: {
                    HStack(spacing:8) {
                        Label(library.folderFilter.map{library.folderLabel($0)} ?? "모든 폴더",systemImage:"folder").lineLimit(1).truncationMode(.middle)
                        Image(systemName:"chevron.down").font(.system(size:10,weight:.semibold))
                    }
                }.buttonStyle(.borderless)
                    .frame(maxWidth:size.width<760 ? 170:250,alignment:.leading).accessibilityLabel("검색 폴더 선택").accessibilityValue(library.folderFilter.map{library.folderLabel($0)} ?? "모든 폴더")
                    .focusable().focused($keyboardFocus,equals:"folder-filter")
                    .onKeyPress(keys:[.return,.space],phases:.down) {press in
                        guard MediaLibraryFilterMenu.acceptsActivation(press.modifiers) else{return .ignored}
                        toggleFilter(.folder);return .handled
                    }
                Button {toggleFilter(.kind)} label: {
                    HStack(spacing:8) {
                        Text(library.kindFilter.map{$0 == .audio ? "오디오":"MIDI"} ?? "모든 형식")
                        Image(systemName:"chevron.down").font(.system(size:10,weight:.semibold))
                    }
                }.buttonStyle(.borderless).accessibilityLabel("샘플 형식 선택")
                    .accessibilityValue(library.kindFilter.map{$0 == .audio ? "오디오":"MIDI"} ?? "모든 형식")
                    .focusable().focused($keyboardFocus,equals:"kind-filter")
                    .onKeyPress(keys:[.return,.space],phases:.down) {press in
                        guard MediaLibraryFilterMenu.acceptsActivation(press.modifiers) else{return .ignored}
                        toggleFilter(.kind);return .handled
                    }
                Spacer()
                Button("모두 선택"){dismissFilterForPointer();library.selectAll()}.disabled(library.searching || library.results.isEmpty || library.results.count>64).help("검색 결과 전체 선택 · 한 번에 최대 64개")
                    .focusable().focused($keyboardFocus,equals:"select-all")
                Button("해제"){dismissFilterForPointer();library.clearSelection()}.disabled(library.searching || library.chosenIDs.isEmpty).accessibilityLabel("샘플 선택 해제")
                    .focusable().focused($keyboardFocus,equals:"clear")
                Text(library.scanning ? "폴더 읽는 중":library.searching ? "검색 중":"\(library.results.count)개 파일").foregroundStyle(StudioTheme.secondary).monospacedDigit()
            }.padding(.horizontal,18).padding(.vertical,10).background(StudioTheme.raised)
            if let openFilter {filterChoices(openFilter)}
            notices
            ScrollViewReader { proxy in
                ScrollView {
                    if library.results.isEmpty {
                        VStack(spacing:12) {
                            Text(library.folders.isEmpty ? "다운로드한 샘플 폴더를 연결하세요":library.scanning ? "오디오·MIDI 파일을 찾고 있습니다":"일치하는 파일이 없습니다").font(.system(size:15))
                            if library.folders.isEmpty {Text("Splice 다운로드 폴더와 개인 샘플 폴더를 함께 검색할 수 있습니다.").foregroundStyle(StudioTheme.secondary);Button("샘플 폴더 추가…"){dismissFilterForPointer();library.chooseFolder()}.focusable().focused($keyboardFocus,equals:"empty-add-folder")}
                        }.frame(maxWidth:.infinity).padding(.vertical,50)
                    }
                    LazyVStack(spacing:1) {
                        ForEach(library.results.indices,id:\.self){index in
                            let entry=library.results[index]
                            LibraryResultRow(entry:entry,folderLabel:library.folderLabel(entry.folderID),selected:library.chosenIDs.contains(entry.id),focused:library.selectedID==entry.id,keyboardFocus:$keyboardFocus,focusKey:"file-\(index)",select:{dismissFilterForPointer();library.select(entry.id)},toggle:{dismissFilterForPointer();library.toggleSelection(entry.id)}).disabled(library.searching)
                        }
                    }
                }.simultaneousGesture(TapGesture().onEnded {dismissFilterForPointer()})
                    .onChange(of:library.selectedID){_,id in if let id{proxy.scrollTo(id,anchor:.center)}}
                    .onChange(of:keyboardFocus){_,focus in
                        guard let focus,(focus.hasPrefix("file-") || focus.hasPrefix("file-toggle-")),
                              let index=Int(focus.split(separator:"-").last ?? ""),library.results.indices.contains(index) else{return}
                        proxy.scrollTo(library.results[index].id,anchor:.center)
                    }
            }
            Divider().overlay(StudioTheme.line)
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:12) {
                    Text("\(library.chosenIDs.count)개 선택").monospacedDigit()
                    Text(library.selectionIssue ?? library.selected.map{"현재 파일 · "+$0.name} ?? "파일을 선택하세요")
                        .foregroundStyle(library.selectionIssue==nil ? StudioTheme.secondary:StudioTheme.accent).lineLimit(1).truncationMode(.middle).help(library.selectionIssue ?? library.selected?.name ?? "")
                }.font(.system(size:12))
                HStack(spacing:12) {
                    Button{dismissFilterForPointer();library.togglePreview()}label:{Label(library.previewPreparing ? "준비 취소":library.previewing ? "미리 듣기 정지":"미리 듣기",systemImage:library.previewPreparing || library.previewing ? "stop.fill":"play.fill")}
                        .disabled(library.selected?.kind != .audio || !store.canStartMediaImport || (library.previewPending && !library.previewPreparing && !library.previewing))
                        .help("원속도 미리 듣기 · ⌥Space").keyboardShortcut(.space,modifiers:[.option])
                        .focusable().focused($keyboardFocus,equals:"preview")
                    Text(library.previewPreparing ? "출력 준비 중 · 취소할 수 있습니다":library.previewPending && !library.previewing ? "이전 출력 준비를 정리하고 있습니다":library.previewing ? String(format:"%.1f초 · ",library.previewSeconds)+library.detail:library.detail).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                }
                HStack(spacing:12) {
                    Button("대상 섹션…"){dismissFilterForPointer();library.notice="";library.choosingDestination=true}.help("곡·섹션 검색으로 가져오기 위치 선택")
                        .focusable().focused($keyboardFocus,equals:"destination")
                    Text(store.libraryDestinationText).font(.system(size:12)).lineLimit(1).truncationMode(.middle).help(store.libraryDestinationText)
                    if !store.libraryDestinationCurrent {Button("대상 갱신"){dismissFilterForPointer();store.refreshLibraryDestination()}.help("현재 선택과 최신 음악 상태를 가져오기 대상으로 사용").focusable().focused($keyboardFocus,equals:"refresh-destination")}
                    Spacer(minLength:4)
                    Button(library.singleChosen?.kind == .midi ? "MIDI 트랙 선택 →":"\(library.chosenIDs.count)개 가져오기 · Return"){dismissFilterForPointer();store.importLibrarySelection()}.frame(minHeight:32).layoutPriority(1).disabled(!canImport)
                        .focusable().focused($keyboardFocus,equals:"import")
                }
                if let request=store.libraryDestination {LibraryPlacementControls(store:store,library:library,request:request,keyboardFocus:$keyboardFocus)}
                if let issue=store.libraryPlacementIssue,store.libraryDestination != nil {Text(issue).font(.system(size:12)).foregroundStyle(StudioTheme.accent)}
                Text(store.libraryDestination != nil && !store.libraryDestinationCurrent ? "곡이나 선택이 변경되었습니다. 가져오기 대상을 확인하고 갱신하세요":"체크박스 여러 파일 · ↑↓ 한 파일 · ⇧↑↓ 범위 · Return 가져오기 · ⌥Space 현재 파일 듣기").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
            }.padding(18).simultaneousGesture(TapGesture().onEnded {dismissFilterForPointer()})
            }
        }.frame(width:size.width,height:size.height).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))
            .overlay{RoundedRectangle(cornerRadius:10).stroke(StudioTheme.line,lineWidth:1)}
            .background(OverlayKeyboardKeys(active:{store.libraryOpen && !library.choosingDestination && !library.choosingTrack},move:moveKeyboardFocus,cancel:cancelKeyboard).frame(width:0,height:0))
            .onChange(of:store.canStartMediaImport){_,ready in if !ready{library.stopPreview()}}
            .onChange(of:library.workspace){_,workspace in
                openFilter=nil
                if workspace == .files {keyboardFocus="search"}
                else if workspace == .folders {keyboardFocus="workspace"}
            }
            .onChange(of:keyboardFocus){_,focus in
                guard let menu=openFilter,let focus else{return}
                if focus != menu.triggerFocus && !menu.optionFocusKeys(folderCount:library.folders.count).contains(focus) {openFilter=nil}
            }
    }
    private func filterChoices(_ menu:MediaLibraryFilterMenu)->some View {
        let keys=menu.optionFocusKeys(folderCount:library.folders.count)
        return ScrollViewReader {proxy in
            ScrollView {
                VStack(alignment:.leading,spacing:2) {
                    switch menu {
                    case .folder:
                        filterChoice("모든 폴더",selected:library.folderFilter==nil,focusKey:keys[0]) {library.folderFilter=nil}
                        ForEach(Array(library.folders.enumerated()),id:\.element.id){index,folder in
                            filterChoice(library.folderLabel(folder.id),selected:library.folderFilter==folder.id,focusKey:keys[index+1]) {library.folderFilter=folder.id}
                        }
                    case .kind:
                        filterChoice("모든 형식",selected:library.kindFilter==nil,focusKey:keys[0]) {library.kindFilter=nil}
                        filterChoice("오디오",selected:library.kindFilter == .audio,focusKey:keys[1]) {library.kindFilter = .audio}
                        filterChoice("MIDI",selected:library.kindFilter == .midi,focusKey:keys[2]) {library.kindFilter = .midi}
                    }
                }.padding(6)
            }.frame(height:menu.optionHeight(in:size.height,folderCount:library.folders.count))
                .onChange(of:keyboardFocus){_,focus in if let focus,keys.contains(focus){proxy.scrollTo(focus,anchor:.center)}}
        }.padding(.horizontal,18).padding(.vertical,7).background(StudioTheme.surface)
            .onMoveCommand {direction in
                if direction == .down || direction == .up {
                    keyboardFocus=OverlayKeyboardTraversal.next(in:keys,current:keyboardFocus,backward:direction == .up)
                }
            }
    }
    private func filterChoice(_ title:String,selected:Bool,focusKey:String,choose:@escaping()->Void)->some View {
        Button {
            choose()
            closeFilter()
        } label: {
            HStack(spacing:8) {
                Image(systemName:"checkmark").opacity(selected ? 1:0).frame(width:14)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength:0)
            }.padding(.horizontal,8).frame(minHeight:30)
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected:[])
            .focusable().focused($keyboardFocus,equals:focusKey).id(focusKey)
            .onKeyPress(keys:[.return,.space],phases:.down) {press in
                guard MediaLibraryFilterMenu.acceptsActivation(press.modifiers) else{return .ignored}
                choose();closeFilter();return .handled
            }
    }
    private func toggleFilter(_ menu:MediaLibraryFilterMenu) {
        if openFilter == menu {closeFilter();return}
        openFilter=menu
        let first=menu.optionFocusKeys(folderCount:library.folders.count)[0]
        DispatchQueue.main.async {if openFilter == menu {keyboardFocus=first}}
    }
    private func closeFilter() {
        guard let menu=openFilter else{return}
        openFilter=nil
        keyboardFocus=menu.triggerFocus
    }
    private func dismissFilterForPointer() {openFilter=nil}
    @ViewBuilder private var notices:some View {
        if !library.notice.isEmpty {
            HStack(alignment:.top,spacing:12) {
                Text(library.notice).fixedSize(horizontal:false,vertical:true).lineLimit(3).help(library.notice)
                Spacer(minLength:0)
                Button{library.notice=""}label:{Image(systemName:"xmark")}.accessibilityLabel("라이브러리 안내 닫기")
                    .focusable().focused($keyboardFocus,equals:"clear-notice")
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
                    ForEach(Array(library.folders.enumerated()),id:\.element.id){index,folder in
                        VStack(alignment:.leading,spacing:8) {
                            HStack(spacing:12) {
                                Text(library.folderLabel(folder.id)).font(.system(size:14,weight:.medium)).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength:8)
                                Button("파일 보기"){library.showFiles(folder.id);library.foldersVisible=false}.accessibilityLabel("\(library.folderLabel(folder.id)) 파일 보기")
                                    .focusable().focused($keyboardFocus,equals:"folder-open-\(index)")
                                Button("등록 해제"){library.removeFolder(folder.id)}.accessibilityLabel("\(library.folderLabel(folder.id)) 등록 해제")
                                    .focusable().focused($keyboardFocus,equals:"folder-remove-\(index)")
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
    private var keyboardOrder:MediaLibraryKeyboardOrder {
        if let openFilter {return MediaLibraryKeyboardOrder(before:[],rows:.filter(openFilter,library.folders.count),after:[])}
        var before=(library.foldersVisible ? []:["search"])+["workspace","add-folder","refresh","close"]
        if library.foldersVisible {
            return MediaLibraryKeyboardOrder(before:before,rows:.folders(library.folders.count),after:library.notice.isEmpty ? []:["clear-notice"])
        } else {
            before += ["folder-filter","kind-filter"]
            if !library.searching && !library.results.isEmpty && library.results.count<=64 {before.append("select-all")}
            if !library.searching && !library.chosenIDs.isEmpty {before.append("clear")}
            if library.folders.isEmpty {before.append("empty-add-folder")}
            var after:[String]=[]
            if library.selected?.kind == .audio && store.canStartMediaImport {after.append("preview")}
            after.append("destination")
            if !store.libraryDestinationCurrent {after.append("refresh-destination")}
            if canImport {after.append("import")}
            if store.libraryDestination != nil && store.libraryDestinationCurrent && store.canStartMediaImport {
                after += ["start","start-zero"]
                if library.singleChosen?.kind == .audio {after.append("track")}
            }
            if !library.notice.isEmpty {after.append("clear-notice")}
            return MediaLibraryKeyboardOrder(before:before,rows:library.searching ? .none:.files(library.results.count),after:after)
        }
    }
    private func moveKeyboardFocus(_ backward:Bool) {
        keyboardFocus=keyboardOrder.next(current:keyboardFocus,backward:backward)
    }
    private func cancelKeyboard() {
        if openFilter != nil {closeFilter()}
        else if library.choosingDestination || library.choosingTrack {library.workspace = .files;library.searchFocus=UUID();keyboardFocus="search"}
        else {store.closeMediaLibrary()}
    }
}


private struct LibraryResultRow:View {
    let entry:LibraryEntry
    let folderLabel:String
    let selected:Bool
    let focused:Bool
    let keyboardFocus:FocusState<String?>.Binding
    let focusKey:String
    let select:()->Void
    let toggle:()->Void
    private var path:String {folderLabel+" / "+entry.relativePath}
    private var typeName:String {entry.kind == .midi ? "MIDI":(entry.name as NSString).pathExtension.uppercased()}
    var body:some View {
        HStack(spacing:0) {
            Toggle("가져오기 선택",isOn:Binding(get:{selected},set:{_ in toggle()})).toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel("\(path) 가져오기 선택").padding(.leading,18)
                .focusable().focused(keyboardFocus,equals:focusKey.replacingOccurrences(of:"file-",with:"file-toggle-"))
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
            .focusable().focused(keyboardFocus,equals:focusKey)
        }.background(selected ? StudioTheme.raised:Color.clear)
            .overlay(alignment:.leading){if focused{Rectangle().fill(StudioTheme.accent).frame(width:3)}}.id(entry.id)
    }
}
