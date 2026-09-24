import Foundation
import CirclrCore

/// The signed resource is only ever read. Each opening owns a new writable session.
enum BundledDemo {
    struct Entry:Decodable,Identifiable {
        var id:String
        var title:String
        var detail:String
        var project:String
    }
    static func catalog(bundle:Bundle = .main)throws->[Entry] {
        guard let root=bundle.resourceURL?.appendingPathComponent("Demos",isDirectory:true) else {throw CirclrError("데모 리소스를 찾을 수 없습니다")}
        let entries=try JSONDecoder().decode([Entry].self,from:Data(contentsOf:root.appendingPathComponent("catalog.json")))
        guard !entries.isEmpty,Set(entries.map(\.id)).count==entries.count else {throw CirclrError("데모 목록을 확인하세요")}
        for entry in entries {
            let components=entry.project.split(separator:"/",omittingEmptySubsequences:false)
            guard !entry.id.isEmpty,!entry.project.hasPrefix("/"),entry.project.hasSuffix(".circlr"),
                  !components.contains(".."),!components.contains("."),!components.contains("") else {throw CirclrError("데모 경로를 확인하세요")}
        }
        return entries
    }
    struct Copy { var project:Project; var root:URL; var lease:DemoCopyLease? }
    static func makeCopy(id:String="f0r-h3r",bundle: Bundle = .main) throws -> Copy {
        try Task.checkCancellation()
        guard let resources = bundle.resourceURL else {
            throw CirclrError("앱의 데모곡 리소스를 찾을 수 없습니다")
        }
        guard let entry=try catalog(bundle:bundle).first(where:{$0.id==id}) else {throw CirclrError("데모곡을 찾을 수 없습니다")}
        let source = resources.appendingPathComponent("Demos/"+entry.project, isDirectory: true)
        var project = try ProjectStore.load(source).project
        project.enableAlbum()
        project = try SectionGraphMigration.migrate(project)
        project.id = newID()
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let target = support.appendingPathComponent(bundle.bundleIdentifier ?? "com.circlr.app")
            .appendingPathComponent("Demo Projects")
            .appendingPathComponent(project.id + ".circlr", isDirectory: true)
        try Task.checkCancellation()
        let copied = try ProjectStore.save(project, to: target, mediaRoot: source)
        // Failure to enroll only disables cleanup; the playable copy remains available.
        let lease = try? DemoCopyLease(root: target, project: copied)
        if Task.isCancelled {
            _ = lease?.releaseIfPristine(project: copied, recoveryPresent: false)
            throw CancellationError()
        }
        return Copy(project: copied, root: target, lease: lease)
    }
}

extension AppStore {
    @discardableResult func applyLoadedBundledDemo(_ loaded:BundledDemo.Copy)->Bool {
        guard requireFinishedRecordingForDocumentAction() else {
            _ = loaded.lease?.releaseIfPristine(project:loaded.project,recoveryPresent:false)
            return false
        }
        retireDemoCopy();stop()
        project=loaded.project;projectURL=nil;mediaRoot=loaded.root
        selectedTrackID=project.tracks.first?.id
        resetSession();dirty=true;scheduleViewportRecovery()
        demoCopyLease=loaded.lease
        status="데모곡 불러오기 완료 · 편집한 곡은 새 위치에 저장하세요"
        return true
    }
    func cancelDemoLoading() {
        guard demoLoading || demoLoadTask != nil || demoLoadWorker != nil else {return}
        demoLoadGeneration += 1
        demoLoadTask?.cancel();demoLoadWorker?.cancel()
        demoLoadTask=nil;demoLoadWorker=nil;demoLoading=false
    }
    func openBundledDemo(id:String="f0r-h3r") {
        guard requireFinishedRecordingForDocumentAction() else{return}
        cancelDemoLoading()
        guard confirmDiscard(),requireFinishedRecordingForDocumentAction() else { return }
        demoLoadGeneration += 1
        let generation=demoLoadGeneration
        let ticket=DemoLoadTicket(generation:generation,project:project,
            projectPath:projectURL?.path,mediaPath:mediaRoot?.path)
        demoLoading=true;demoLoadError=nil;status="데모곡 읽는 중 · 취소할 수 있습니다"
        let worker=Task.detached(priority:.userInitiated){try BundledDemo.makeCopy(id:id)}
        demoLoadWorker=worker
        demoLoadTask=Task { [weak self] in
            do {
                let loaded=try await worker.value
                guard let self else {
                    _ = loaded.lease?.releaseIfPristine(project:loaded.project,recoveryPresent:false)
                    return
                }
                guard ticket.canApply(generation:self.demoLoadGeneration,project:self.project,
                    projectPath:self.projectURL?.path,mediaPath:self.mediaRoot?.path,cancelled:Task.isCancelled) else {
                    _ = loaded.lease?.releaseIfPristine(project:loaded.project,recoveryPresent:false)
                    if self.demoLoadGeneration == generation {
                        self.demoLoading=false;self.demoLoadTask=nil;self.demoLoadWorker=nil
                        self.status="현재 작업이 변경되어 데모 불러오기를 취소했습니다"
                    }
                    return
                }
                self.demoLoading=false;self.demoLoadTask=nil;self.demoLoadWorker=nil
                self.applyLoadedBundledDemo(loaded)
            } catch {
                guard let self,self.demoLoadGeneration == generation else{return}
                self.demoLoading=false;self.demoLoadTask=nil;self.demoLoadWorker=nil
                if error is CancellationError {self.status="데모 불러오기 취소"}
                else {self.demoLoadError="데모를 불러오지 못했습니다: "+error.localizedDescription;self.fail(error)}
            }
        }
    }
}
