import Foundation

public extension ProjectStore {
    /// A portable package owns its copies. The open session keeps local source references
    /// so saving an Undo state cannot delete media needed by a later Redo.
    static func saveSession(_ project:Project,to target:URL,mediaRoot:URL?)throws->Project {
        var saved=try save(project,to:target,mediaRoot:mediaRoot)
        let localPaths=Dictionary(uniqueKeysWithValues:project.assets.filter{$0.path.hasPrefix("/")}.map{($0.id,$0.path)})
        for i in saved.assets.indices {
            if let source=localPaths[saved.assets[i].id] {saved.assets[i].path=source}
        }
        return saved
    }
}
