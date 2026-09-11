import Foundation
import CirclrCore

/// The signed resource is only ever read. Each opening owns a new writable session.
enum BundledDemo {
    static func makeCopy(bundle: Bundle = .main) throws -> (project: Project, root: URL) {
        guard let resources = bundle.resourceURL else {
            throw CirclrError("앱의 데모곡 리소스를 찾을 수 없습니다")
        }
        let source = resources.appendingPathComponent("Demos/f0r-h3r.circlr", isDirectory: true)
        var project = try ProjectStore.load(source).project
        project.enableAlbum()
        project = try SectionGraphMigration.migrate(project)
        project.id = newID()
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let target = support.appendingPathComponent(bundle.bundleIdentifier ?? "com.circlr.app")
            .appendingPathComponent("Demo Projects")
            .appendingPathComponent(project.id + ".circlr", isDirectory: true)
        let copied = try ProjectStore.save(project, to: target, mediaRoot: source)
        return (project: copied, root: target)
    }
}

extension AppStore {
    func openBundledDemo() {
        guard confirmDiscard() else { return }
        do {
            let loaded = try BundledDemo.makeCopy()
            stop()
            project = loaded.project
            projectURL = nil
            mediaRoot = loaded.root
            selectedTrackID = project.tracks.first?.id
            resetSession()
            dirty = true
            scheduleViewportRecovery()
            status = "데모곡 불러오기 완료 · 편집한 곡은 새 위치에 저장하세요"
        } catch { fail(error) }
    }
}
