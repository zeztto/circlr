import Foundation

public struct LibraryFolderLocation:Sendable {
    public let id:String
    public let name:String
    public let path:String?
    public init(id:String,name:String,path:String?) {self.id=id;self.name=name;self.path=path}
}

/// Presentation only: folder IDs and relative file paths remain unchanged.
public enum MediaLibraryFolderDisplay {
    public static func labels(_ folders:[LibraryFolderLocation])->[String:String] {
        let key:(String)->String = {$0.precomposedStringWithCanonicalMapping.lowercased()}
        let groups=Dictionary(grouping:folders,by:{key($0.name)})
        var result:[String:String]=[:]
        for (index,folder) in folders.enumerated() {
            let peers=groups[key(folder.name)] ?? []
            guard peers.count>1 else{result[folder.id]=folder.name;continue}
            let parts=folder.path.map{($0 as NSString).pathComponents.filter{$0 != "/"}} ?? []
            var label:String?
            if parts.count>=2 {
                for depth in 2...parts.count {
                    let candidate=parts.suffix(depth).joined(separator:"/")
                    let unique=peers.filter{$0.id != folder.id}.allSatisfy {other in
                        guard let path=other.path else{return true}
                        return key((path as NSString).pathComponents.suffix(depth).joined(separator:"/")) != key(candidate)
                    }
                    if unique {label=candidate;break}
                }
            }
            result[folder.id]=label ?? "\(folder.name) · 등록 \(index+1)"
        }
        return result
    }
}
