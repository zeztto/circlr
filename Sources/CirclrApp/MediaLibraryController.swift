import AppKit
import AVFAudio
import Combine
import CirclrCore
import CirclrAudio

struct LibraryFolder:Identifiable,Codable,Equatable,Sendable {
    var id=UUID().uuidString
    var name:String
    var bookmark:Data
}
/// Access is balanced for each asynchronous operation, including discarded late results.
final class LibraryAccess:@unchecked Sendable {
    let url:URL
    private let scoped:Bool
    let bookmarkWasStale:Bool
    init(_ folder:LibraryFolder)throws {
        var stale=false
        url=try URL(resolvingBookmarkData:folder.bookmark,options:[.withSecurityScope,.withoutUI,.withoutMounting],relativeTo:nil,bookmarkDataIsStale:&stale)
        scoped=url.startAccessingSecurityScopedResource();bookmarkWasStale=stale
    }
    deinit {if scoped {url.stopAccessingSecurityScopedResource()}}
}
func mediaLibraryError(_ error:Error)->String {
    if error is CirclrError {return error.localizedDescription}
    let ns=error as NSError
    if ns.domain==NSCocoaErrorDomain && [4,260].contains(ns.code){return "파일이 이동되었거나 삭제됐습니다. 새로고침하세요"}
    if ns.domain==NSCocoaErrorDomain && [257,513].contains(ns.code){return "폴더 접근 권한을 확인하고 다시 추가하세요"}
    return "파일을 읽을 수 없습니다. 형식과 손상 여부를 확인하세요"
}

@MainActor final class MediaLibraryController:ObservableObject {
    @Published private(set) var folders:[LibraryFolder]=[]
    @Published private(set) var entries:[LibraryEntry]=[]
    @Published private(set) var results:[LibraryEntry]=[]
    @Published var query="" {didSet{filter()}}
    @Published var folderFilter:String? {didSet{filter()}}
    @Published var kindFilter:LibraryMediaKind? {didSet{filter()}}
    @Published private(set) var selectedID:String?
    @Published private(set) var chosenIDs:Set<String>=[]
    private var rangeAnchor:String?
    @Published private(set) var scanning=false
    @Published private(set) var searching=false
    @Published var notice=""
    @Published private(set) var detail="파일을 선택하세요"
    @Published private(set) var previewPreparing=false
    @Published private(set) var previewing=false
    @Published private(set) var previewSeconds=0.0
    @Published private(set) var previewPending=false
    private var previewCancellation:MediaPreviewCancellation?
    private var keyMonitor:Any?
    private var scanGeneration=0,searchGeneration=0,selectionGeneration=0,previewGeneration=0
    private var scanTask:Task<Void,Never>?,searchTask:Task<Void,Never>?,detailTask:Task<Void,Never>?,previewTask:Task<Void,Never>?
    private var scanWorker:Task<([LibraryEntry],[String],[String:Data]),Error>?
    private var searchWorker:Task<[LibraryEntry],Never>?
    private var detailWorker:Task<LibraryMediaInfo,Error>?
    private var previewWorker:Task<Void,Error>?
    private let defaults:UserDefaults
    private let key="circlr.mediaLibrary.folders.v1"
    var selected:LibraryEntry? {entries.first{$0.id==selectedID}}
    var chosen:[LibraryEntry] {results.filter{chosenIDs.contains($0.id)}}
    var selectionIssue:String? {
        guard !chosenIDs.isEmpty else{return nil}
        do {try MediaLibrarySelection.validate(MediaLibrarySelection.entries(results,ids:chosenIDs));return nil}
        catch{return mediaLibraryError(error)}
    }
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        if let data=defaults.data(forKey:key) {
            do {folders=try JSONDecoder().decode([LibraryFolder].self,from:data)}
            catch {notice="등록 폴더 설정을 읽지 못했습니다. 폴더를 다시 추가하세요"}
        }
    }
    private func persist() {do{defaults.set(try JSONEncoder().encode(folders),forKey:key)}catch{notice=mediaLibraryError(error)}}
    func chooseFolder() {
        let panel=NSOpenPanel();panel.title="샘플 폴더 추가";panel.message="다운로드한 오디오·MIDI 폴더를 선택하세요. 원본은 변경하지 않습니다."
        panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            guard folders.count<16 else{throw CirclrError("폴더는 최대 16개까지 등록할 수 있습니다")}
            let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
            let path=url.resolvingSymlinksInPath().standardizedFileURL.path
            guard !folders.contains(where:{(try? LibraryAccess($0).url.resolvingSymlinksInPath().standardizedFileURL.path)==path}) else {notice="이미 등록된 폴더입니다";return}
            let bookmark=try url.bookmarkData(options:[.withSecurityScope,.securityScopeAllowOnlyReadAccess],includingResourceValuesForKeys:nil,relativeTo:nil)
            folders.append(LibraryFolder(name:url.lastPathComponent,bookmark:bookmark));persist();refresh()
        } catch {notice="폴더 추가 실패: \(mediaLibraryError(error))"}
    }
    func removeFolder(_ id:String) {
        stopPreview();folders.removeAll{$0.id==id};persist()
        if folderFilter==id {folderFilter=nil}
        entries.removeAll{$0.folderID==id};filter();refresh()
    }
    func refresh() {
        scanGeneration+=1;let generation=scanGeneration,sources=folders
        scanTask?.cancel();scanWorker?.cancel();scanning = !sources.isEmpty;notice=""
        if sources.isEmpty {entries=[];filter();return}
        let worker=Task.detached(priority:.utility) { () throws -> ([LibraryEntry],[String],[String:Data]) in
            var all:[LibraryEntry]=[],warnings:[String]=[],bookmarks:[String:Data]=[:]
            for folder in sources {
                try Task.checkCancellation()
                if all.count>=50_000 {warnings.append("전체 50,000개 검색 한도에 도달했습니다. 더 작은 폴더를 등록하세요");break}
                do {
                    let access=try LibraryAccess(folder)
                    if access.bookmarkWasStale {
                        do {bookmarks[folder.id]=try access.url.bookmarkData(options:[.withSecurityScope,.securityScopeAllowOnlyReadAccess],includingResourceValuesForKeys:nil,relativeTo:nil)}
                        catch {warnings.append(folder.name+": 폴더 위치를 보관하지 못했습니다. 다시 추가하세요")}
                    }
                    let result=try MediaLibrary.scan(access.url,folderID:folder.id,folderName:folder.name,limit:50_000-all.count)
                    all += result.entries
                    if result.limited {warnings.append(folder.name+": 검색 한도에 도달했습니다. 더 작은 폴더를 등록하세요")}
                    if result.skipped>0 {warnings.append(folder.name+": \(result.skipped)개 항목을 읽지 못했습니다")}
                } catch is CancellationError {throw CancellationError()}
                catch {warnings.append(folder.name+": 폴더를 읽지 못했습니다. 연결 또는 접근 권한을 확인하세요")}
            }
            return (all,warnings,bookmarks)
        }
        scanWorker=worker
        scanTask=Task { [weak self] in
            do {
                let (entries,warnings,bookmarks)=try await worker.value
                guard let self,self.scanGeneration==generation,!Task.isCancelled else{return}
                for index in self.folders.indices {if let data=bookmarks[self.folders[index].id]{self.folders[index].bookmark=data}}
                if !bookmarks.isEmpty{self.persist()}
                self.scanning=false;self.entries=entries;self.notice=warnings.joined(separator:"\n");self.filter()
            } catch {guard let self,self.scanGeneration==generation else{return};self.scanning=false}
        }
    }
    private func filter() {
        searchGeneration+=1;let generation=searchGeneration,entries=entries,query=query,folder=folderFilter,kind=kindFilter
        searchTask?.cancel();searchWorker?.cancel();searching=true
        searchTask=Task { [weak self] in
            do {try await Task.sleep(for:.milliseconds(100))} catch{return}
            guard let self,!Task.isCancelled else{return}
            let worker=Task.detached(priority:.userInitiated){MediaLibrary.search(entries,query:query,folderID:folder,kind:kind)}
            self.searchWorker=worker
            let result=await worker.value
            guard self.searchGeneration==generation,!Task.isCancelled else{return}
            self.results=result;self.searching=false
            self.chosenIDs.formIntersection(Set(result.map(\.id)))
            let focus=result.contains(where:{$0.id==self.selectedID}) ? self.selectedID:result.first?.id
            if self.chosenIDs.isEmpty {self.chosenIDs=focus.map{[$0]} ?? []}
            self.rangeAnchor=focus;self.select(focus,force:true,preserving:true)
        }
    }
    func select(_ id:String?,force:Bool=false,preserving:Bool=false) {
        guard !searching else{return}
        if !preserving {let next:Set<String>=id.map{[$0]} ?? [];if chosenIDs != next{stopPreview()};chosenIDs=next;rangeAnchor=id}
        guard force || id != selectedID else{return}
        stopPreview();selectedID=id;selectionGeneration+=1;let generation=selectionGeneration
        detailTask?.cancel();detailWorker?.cancel()
        guard let entry=selected,let folder=folders.first(where:{$0.id==entry.folderID}) else{detail="파일을 선택하세요";return}
        detail="파일 정보 확인 중"
        let worker=Task.detached(priority:.utility) {let access=try LibraryAccess(folder);return try MediaLibrary.inspect(entry,under:access.url)}
        detailWorker=worker
        detailTask=Task { [weak self] in
            do {
                let info=try await worker.value
                guard let self,self.selectionGeneration==generation,!Task.isCancelled else{return}
                if let notes=info.notes {self.detail="MIDI · \(notes)개 노트 · 가져오기에서 트랙 선택"}
                else {self.detail=String(format:"%.2f초 · %.0f Hz · %@",info.duration ?? 0,info.sampleRate ?? 0,info.channels==1 ? "모노":"스테레오")}
            } catch {guard let self,self.selectionGeneration==generation,!Task.isCancelled else{return};self.detail="파일 확인 실패: \(mediaLibraryError(error))"}
        }
    }
    func move(_ delta:Int) {
        guard !results.isEmpty else{return}
        let index=results.firstIndex{$0.id==selectedID} ?? 0
        select(results[max(0,min(results.count-1,index+delta))].id)
    }
    func toggleSelection(_ id:String) {
        guard !searching,results.contains(where:{$0.id==id}) else{return}
        do {let next=try MediaLibrarySelection.toggling(id,in:chosenIDs);stopPreview();chosenIDs=next;rangeAnchor=id;select(id,preserving:true)}
        catch{notice=mediaLibraryError(error)}
    }
    func extend(_ delta:Int) {
        guard !searching,!results.isEmpty else{return}
        let index=results.firstIndex{$0.id==selectedID} ?? 0,target=results[max(0,min(results.count-1,index+delta))].id
        let anchor=rangeAnchor ?? selectedID ?? target
        do {let next=try MediaLibrarySelection.range(results.map(\.id),anchor:anchor,target:target);stopPreview();chosenIDs=next;rangeAnchor=anchor;select(target,preserving:true)}
        catch{notice=mediaLibraryError(error)}
    }
    func selectAll() {
        guard !searching else{return}
        guard results.count<=MediaLibrarySelection.limit else{notice="한 번에 최대 64개 파일을 선택하세요. 검색 범위를 줄이세요";return}
        stopPreview();chosenIDs=Set(results.map(\.id))
    }
    func clearSelection(){guard !searching else{return};stopPreview();chosenIDs=[]}
    func accessSelection()throws->([LibraryEntry],[LibraryAccess],[URL]) {
        let entries=try MediaLibrarySelection.entries(results,ids:chosenIDs)
        try MediaLibrarySelection.validate(entries)
        var access:[String:LibraryAccess]=[:],urls:[URL]=[]
        for entry in entries {
            guard let folder=folders.first(where:{$0.id==entry.folderID}) else{throw CirclrError("등록 폴더가 변경됐습니다. 파일을 다시 선택하세요")}
            if access[folder.id]==nil {access[folder.id]=try LibraryAccess(folder)}
            urls.append(try MediaLibrary.file(entry,under:access[folder.id]!.url))
        }
        return (entries,Array(access.values),urls)
    }
    func watchKeyboard(canPreview:@escaping()->Bool) {
        if let keyMonitor{NSEvent.removeMonitor(keyMonitor)}
        keyMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
            guard NSApp.keyWindow?.identifier?.rawValue=="main" else{return event}
            let flags=event.modifierFlags.intersection([.command,.option,.control,.shift])
            guard event.keyCode==49,flags == .option else{return event}
            if let text=NSApp.keyWindow?.firstResponder as? NSTextView,text.hasMarkedText(){return event}
            if canPreview(){self?.togglePreview()}
            return nil
        }
    }
    func togglePreview() {
        if previewPreparing || previewing {stopPreview();return}
        guard !previewPending else{notice="이전 출력 준비를 정리하고 있습니다. 잠시 뒤 다시 시도하세요";return}
        guard let entry=selected,entry.kind == .audio,let folder=folders.first(where:{$0.id==entry.folderID}) else{return}
        stopPreview();let generation=previewGeneration,token=MediaPreviewCancellation()
        previewCancellation=token;previewPending=true;previewPreparing=true
        let report:@Sendable(Double)->Void = { [weak self] seconds in
            guard let controller=self else{return}
            Task { @MainActor in
                guard controller.previewGeneration==generation,!token.isCancelled else{return}
                controller.previewPreparing=false;controller.previewing=true;controller.previewSeconds=seconds
            }
        }
        let worker=Task.detached(priority:.userInitiated){
            guard entry.bytes<=134_217_728 else{throw CirclrError("미리 듣기는 128 MiB 이하의 파일을 지원합니다. 가져오기는 2 GiB까지 가능합니다")}
            let access=try LibraryAccess(folder)
            _=try MediaLibrary.inspect(entry,under:access.url)
            let player=try LocalMediaPreviewPlayer(url:MediaLibrary.file(entry,under:access.url))
            try await MediaPreview.run(player,cancellation:token,update:report)
            withExtendedLifetime(access){}
        }
        previewWorker=worker
        previewTask=Task { [weak self] in
            defer{self?.previewPending=false}
            do {
                try await worker.value
                guard let self,self.previewGeneration==generation,!Task.isCancelled else{return}
                self.stopPreview()
            } catch {
                guard let self,self.previewGeneration==generation,!Task.isCancelled else{return}
                self.stopPreview();self.notice="미리 듣기 실패: \(mediaLibraryError(error))"
            }
        }
    }
    func stopPreview() {
        previewGeneration+=1;previewCancellation?.cancel();previewTask?.cancel();previewWorker?.cancel()
        previewPreparing=false;previewing=false;previewSeconds=0
    }
    func suspend() {
        if let keyMonitor{NSEvent.removeMonitor(keyMonitor);self.keyMonitor=nil}
        stopPreview();scanGeneration+=1;searchGeneration+=1;selectionGeneration+=1
        scanTask?.cancel();scanWorker?.cancel();searchTask?.cancel();searchWorker?.cancel();detailTask?.cancel();detailWorker?.cancel()
        scanning=false;searching=false
    }
}
