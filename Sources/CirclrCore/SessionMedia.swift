import Foundation

public extension ProjectStore {
    /// A portable package owns its copies. The open session keeps local source references
    /// so saving an Undo state cannot delete media needed by a later Redo.
    static func saveSession(_ project:Project,to target:URL,mediaRoot:URL?)throws->Project {
        try saveSessionReportingCleanup(project,to:target,mediaRoot:mediaRoot) {
            FileHandle.standardError.write(Data(("circlr: \($0)\n").utf8))
        }
    }

    static func saveSessionReportingCleanup(_ project:Project,to target:URL,mediaRoot:URL?,onCleanupWarning:(String)->Void)throws->Project {
        let staged = try prepareSessionSave(project,to:target,mediaRoot:mediaRoot)
        defer { discard(staged) }
        return try publishSessionSaveReportingCleanup(staged,onCleanupWarning:onCleanupWarning)
    }

    /// The returned value keeps absolute local media paths in `savedProject`
    /// for Undo/Redo, while its staged package contains portable relative paths.
    static func prepareSessionSave(_ project:Project,to target:URL,mediaRoot:URL?)throws->StagedProjectSave {
        try prepareSave(project,to:target,mediaRoot:mediaRoot,preserveLocalAssetPaths:true)
    }
}
