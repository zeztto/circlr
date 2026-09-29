import AppKit
import Combine
import CirclrCore

@MainActor extension AppStore {
    @discardableResult func resolveDocumentDrafts() -> Bool {
        if let editor=NSApp.keyWindow?.firstResponder as? NSTextView,editor.hasMarkedText() {
            status="한글 입력을 확정한 뒤 저장하거나 곡을 전환하세요"
            return false
        }
        return resolveActiveNumericDraft() && nameEditing.resolve()
    }
    func showProjectMedia() {
        guard resolveDocumentDrafts(),requireFinishedRecordingForDocumentAction() else{return}
        libraryOpen=false;navigationOpen=false;commandPalette=nil;keyboardHelp=false
        soundPickerRequest=nil;arrangementPickerRequest=nil
        projectMediaOpen=true;projectMedia.refresh()
    }
}

/// The current project remains authoritative until a checked result is committed.
/// Portable copies never switch the open document or clear its dirty state.
@MainActor final class ProjectMediaWorkspace:ObservableObject {
    @Published private(set) var busy=false
    @Published private(set) var draining=false
    @Published private(set) var message=""
    @Published private(set) var issues:[ProjectMediaRelink.Issue]=[]
    @Published private(set) var exportedURL:URL?
    private weak var store:AppStore?
    private var generation=0
    private var cancelInspection:(()->Void)?
    private var task:Task<Void,Never>?
    private var worker:Task<StagedProjectSave,Error>?
    private var readerDrainTask:Task<Void,Never>?
    private var drainID:UUID?
    typealias PreparePortable = @Sendable (Project,URL,URL?) throws -> StagedProjectSave
    private let preparePortable:PreparePortable
    init(store:AppStore,preparePortable:@escaping PreparePortable = {project,target,root in
        try Task.checkCancellation()
        _=try ProjectStore.portableCopyPreflight(project:project,mediaRoot:root,destination:target,checkCancellation:{try Task.checkCancellation()})
        return try ProjectStore.prepareSessionSave(project,to:target,mediaRoot:root,checkCancellation:{try Task.checkCancellation()})
    }) {self.store=store;self.preparePortable=preparePortable}
    /// Includes cancelled work until its detached reader and stage cleanup finish.
    /// Document retirement captures these handles before releasing a demo lease.
    var readerTasks:[Task<Void,Never>]{[task,readerDrainTask].compactMap{$0}}
    private var canStart:Bool {
        guard !busy,!draining else{return false}
        return true
    }
    func cancel() {
        generation+=1
        task?.cancel();worker?.cancel();cancelInspection?();cancelInspection=nil
        if let reader=task {
            // No new reader starts during a drain, so at most one retained drain exists.
            let id=UUID();drainID=id;draining=true
            readerDrainTask=Task { [weak self] in
                await reader.value
                guard let self,self.drainID==id else{return}
                self.readerDrainTask=nil;self.drainID=nil;self.draining=false
                self.message="취소했습니다 · 현재 곡과 원본 파일은 유지됩니다"
            }
        }
        task=nil;worker=nil
        if draining {message="취소 중 · 파일 작업이 마무리될 때까지 원본을 보존합니다"}
        busy=false
    }
    func close(){cancel();store?.projectMediaOpen=false;store?.focusCanvas?()}
    func refresh() {
        guard let store,canStart else{return}
        let snapshot=store.project,root=store.mediaRoot
        generation+=1;let epoch=generation;busy=true;message="미디어 확인 중"
        let inspection=Task.detached(priority:.utility){try ProjectMediaRelink.diagnostics(project:snapshot,root:root,checkCancellation:{try Task.checkCancellation()})}
        cancelInspection={inspection.cancel()}
        task=Task { [weak self] in
            do {
            let result=try await inspection.value
            guard let self,self.generation==epoch,!Task.isCancelled else{return}
            self.busy=false;self.cancelInspection=nil
            guard store.project==snapshot,store.mediaRoot==root else{self.message="검사 중 곡이 변경되었습니다. 다시 검사하세요";return}
            self.issues=result
            self.message=result.isEmpty ? "모든 미디어를 사용할 수 있습니다":"\(result.count)개 미디어를 확인하세요"
            } catch {
                guard let self,self.generation==epoch else{return};self.busy=false;self.message=error.localizedDescription
            }
        }
    }
    func chooseReplacement(_ issue:ProjectMediaRelink.Issue) {
        guard let store,canStart,store.resolveDocumentDrafts(),store.requireFinishedRecordingForDocumentAction() else{return}
        let panel=NSOpenPanel();panel.title="미디어 재연결";panel.message="\(issue.displayName) 원본을 선택하세요. 이름이 같아도 내용이 다르면 연결하지 않습니다. 이 asset을 참조하는 모든 서클에 적용되며 실행 취소할 수 있습니다."
        panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        var allowUnverified=false
        if store.project.assets.first(where:{$0.id==issue.assetID})?.checksum.isEmpty==true {
            let alert=NSAlert();alert.messageText="원본 확인 정보가 없는 미디어입니다"
            alert.informativeText="기존 곡에는 이 파일의 checksum이 없습니다. 이름만으로 원본을 확인할 수 없습니다. 선택한 파일의 형식을 검사한 뒤 직접 지정한 대체 파일로 연결할까요? 이 asset의 모든 참조가 바뀝니다."
            alert.addButton(withTitle:"대체 파일로 연결");alert.addButton(withTitle:"취소")
            guard alert.runModal() == .alertFirstButtonReturn else{return};allowUnverified=true
        }
        relink(assetID:issue.assetID,candidate:url,allowUnverified:allowUnverified)
    }
    func relink(assetID:ID,candidate:URL,allowUnverified:Bool=false) {
        guard let store,canStart,store.requireFinishedRecordingForDocumentAction() else{return}
        let snapshot=store.project,root=store.mediaRoot
        generation+=1;let epoch=generation;busy=true;message="선택한 파일 검사 중"
        let inspection=Task.detached(priority:.utility){
            let scoped=candidate.startAccessingSecurityScopedResource();defer{if scoped{candidate.stopAccessingSecurityScopedResource()}}
            return try ProjectMediaRelink.prepareRelink(project:snapshot,root:root,assetID:assetID,candidate:candidate,allowUnverified:allowUnverified,checkCancellation:{try Task.checkCancellation()})
        }
        cancelInspection={inspection.cancel()}
        task=Task { [weak self] in
            do {
                let result=try await inspection.value
                guard let self,self.generation==epoch,!Task.isCancelled else{return}
                guard store.project==snapshot,store.mediaRoot==root,!store.recordingBlocksDocumentAction else{throw CirclrError("검사 중 곡이 변경되었습니다. 다시 시도하세요")}
                try result.validateCandidate()
                store.mutate("미디어 재연결"){$0=result.project};self.busy=false
                self.message="재연결 완료 · 실행 취소할 수 있습니다";self.refresh()
            } catch {
                guard let self,self.generation==epoch else{return};self.busy=false;self.message=error.localizedDescription
            }
        }
    }
    func choosePortableCopy() {
        guard let store,canStart,store.resolveDocumentDrafts(),store.requireFinishedRecordingForDocumentAction() else{return}
        let panel=NSSavePanel();panel.title="미디어를 포함한 곡 사본 저장";panel.nameFieldStringValue=store.project.name+" 사본.circlr"
        panel.message="모든 오디오 미디어를 수집합니다. 현재 곡은 그대로 열려 있으며 사본 저장은 현재 편집의 저장 상태를 바꾸지 않습니다."
        guard panel.runModal() == .OK,let url=panel.url else{return}
        portableCopy(to:url)
    }
    func portableCopy(to target:URL) {
        guard let store,canStart,store.requireFinishedRecordingForDocumentAction() else{return}
        let snapshot=store.project,root=store.mediaRoot
        if let projectURL=store.projectURL,target.standardizedFileURL.resolvingSymlinksInPath()==projectURL.standardizedFileURL.resolvingSymlinksInPath(){message="사본은 현재 곡과 다른 위치에 저장하세요";return}
        guard !FileManager.default.fileExists(atPath:target.path) else{message="이미 있는 목적지입니다. 새로운 이름을 선택하세요";return}
        generation+=1;let epoch=generation;busy=true;exportedURL=nil;message="미디어 검사·사본 준비 중 · 취소할 수 있습니다"
        let preparePortable=preparePortable
        let worker=Task.detached(priority:.utility){try preparePortable(snapshot,target,root)}
        self.worker=worker
        task=Task { [weak self] in
            do {
                let staged=try await worker.value
                defer{ProjectStore.discard(staged)}
                guard let self,self.generation==epoch,!Task.isCancelled else{return}
                guard store.project==snapshot,store.mediaRoot==root,!store.recordingBlocksDocumentAction else{throw CirclrError("복사 중 곡이 변경되었습니다. 원본을 유지했습니다. 다시 시도하세요")}
                guard !FileManager.default.fileExists(atPath:target.path) else{throw CirclrError("복사 중 목적지가 생성되었습니다. 새 이름을 선택하세요")}
                var warning:String?
                _=try ProjectStore.publishSessionSaveReportingCleanup(staged){warning=$0}
                self.exportedURL=target;self.busy=false;self.worker=nil
                self.message=warning ?? "사본 저장 완료 · 현재 곡은 그대로 유지됩니다"
            } catch {
                guard let self,self.generation==epoch else{return};self.busy=false;self.worker=nil
                self.message=error is CancellationError ? "복사를 취소했습니다":error.localizedDescription
            }
        }
    }
    func exportDiagnostics(to target:URL,appVersion:String,appBuild:String,runtime:ProjectDiagnostics.Runtime) {
        guard let store,canStart else{return}
        let snapshot=store.project,root=store.mediaRoot
        generation+=1;let epoch=generation;busy=true;message="진단 정보 준비 중"
        let inspection=Task.detached(priority:.utility){
            try ProjectDiagnostics(project:snapshot,mediaRoot:root,appVersion:appVersion,appBuild:appBuild,runtime:runtime,checkCancellation:{try Task.checkCancellation()}).encoded()
        }
        cancelInspection={inspection.cancel()}
        task=Task { [weak self] in
            do {
                let data=try await inspection.value
                guard let self,self.generation==epoch,!Task.isCancelled else{return}
                guard store.project==snapshot,store.mediaRoot==root else{throw CirclrError("진단 중 곡이 바뀌었습니다. 다시 시도하세요")}
                try data.write(to:target,options:.atomic)
                self.busy=false;self.cancelInspection=nil;self.message="진단 정보 저장 완료 · 음악 원본과 개인 정보는 포함하지 않았습니다"
            } catch {
                guard let self,self.generation==epoch else{return};self.busy=false;self.cancelInspection=nil;self.message=error.localizedDescription
            }
        }
    }

}
