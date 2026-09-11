import Foundation
import AVFAudio
import CirclrCore

public enum LibraryMediaKind:String,CaseIterable,Codable,Sendable {case audio,midi}
public struct LibraryEntry:Identifiable,Equatable,Sendable {
    public let folderID:String
    public let folderName:String
    public let relativePath:String
    public let kind:LibraryMediaKind
    public let bytes:Int64
    public let modified:Date
    public var id:String {folderID+":"+relativePath}
    public var name:String {(relativePath as NSString).lastPathComponent}
}
public struct LibraryScan:Sendable {
    public var entries:[LibraryEntry]=[]
    public var skipped=0
    public var limited=false
}
public struct LibraryMediaInfo:Sendable {
    public let duration:Double?
    public let sampleRate:Double?
    public let channels:Int?
    public let notes:Int?
}

/// A filename catalog only. Decoders validate a selected file before it is used.
public enum MediaLibrary {
    public static func kind(_ url:URL)->LibraryMediaKind? {
        let ext=url.pathExtension.lowercased()
        if ["mid","midi"].contains(ext) {return .midi}
        return AudioFileImport.extensions.contains(ext) ? .audio:nil
    }
    public static func scan(_ root:URL,folderID:String,folderName:String,limit:Int=50_000,visitLimit:Int=200_000)throws->LibraryScan {
        try Task.checkCancellation()
        let root=try directory(root),fm=FileManager.default
        var result=LibraryScan(),visited=0
        let keys:Set<URLResourceKey>=[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey,.isPackageKey,.fileSizeKey,.contentModificationDateKey]
        guard let walk=fm.enumerator(at:root,includingPropertiesForKeys:Array(keys),options:[.skipsHiddenFiles,.skipsPackageDescendants],errorHandler:{_,_ in result.skipped+=1;return true}) else {throw CirclrError("폴더를 읽을 수 없습니다")}
        while let next=walk.nextObject() as? URL {
            let url=next.standardizedFileURL
            try Task.checkCancellation();visited+=1
            if visited>max(0,visitLimit) {result.limited=true;break}
            do {
                let values=try url.resourceValues(forKeys:keys)
                if values.isSymbolicLink==true || values.isPackage==true || url.pathExtension=="circlr" {walk.skipDescendants();continue}
                guard values.isRegularFile==true,let kind=kind(url) else {continue}
                if result.entries.count>=max(0,limit) {result.limited=true;break}
                guard contained(url,in:root),let size=values.fileSize,size>0,let modified=values.contentModificationDate else {result.skipped+=1;continue}
                result.entries.append(LibraryEntry(folderID:folderID,folderName:folderName,relativePath:url.pathComponents.dropFirst(root.pathComponents.count).joined(separator:"/"),kind:kind,bytes:Int64(size),modified:modified))
            } catch {result.skipped+=1}
        }
        result.entries=search(result.entries,query:"")
        return result
    }
    public static func search(_ entries:[LibraryEntry],query:String,folderID:String?=nil,kind:LibraryMediaKind?=nil)->[LibraryEntry] {
        let terms=fold(query).split(whereSeparator:{$0.isWhitespace})
        return entries.filter {entry in
            guard folderID==nil || entry.folderID==folderID,kind==nil || entry.kind==kind else{return false}
            let text=fold(entry.folderName+" "+entry.relativePath+" "+entry.kind.rawValue)
            return terms.allSatisfy{text.contains($0)}
        }.sorted {a,b in
            let left=fold(a.name),right=fold(b.name)
            return left==right ? a.id<b.id:left<right
        }
    }
    public static func file(_ entry:LibraryEntry,under root:URL)throws->URL {
        let root=try directory(root)
        let parts=entry.relativePath.split(separator:"/",omittingEmptySubsequences:false)
        guard !entry.relativePath.hasPrefix("/"),!parts.isEmpty,parts.allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}) else {throw CirclrError("라이브러리 파일 경로를 확인하세요")}
        let url=root.appendingPathComponent(entry.relativePath).standardizedFileURL
        guard contained(url,in:root),url.resolvingSymlinksInPath().standardizedFileURL.path==url.path,kind(url)==entry.kind else {throw CirclrError("등록 폴더 밖의 파일 또는 심볼릭 링크는 가져올 수 없습니다")}
        let attrs=try FileManager.default.attributesOfItem(atPath:url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? NSNumber)?.int64Value==entry.bytes,attrs[.modificationDate] as? Date==entry.modified else {throw CirclrError("파일이 변경됐습니다. 라이브러리를 새로고침하세요")}
        let maximum=entry.kind == .midi ? 16_777_216:AudioFileImport.maximumFileBytes
        guard entry.bytes>0,entry.bytes<=maximum else {throw CirclrError(entry.kind == .midi ? "16 MiB 이하의 MIDI 파일을 선택하세요":"2 GiB 이하의 오디오 파일을 선택하세요")}
        return url
    }
    public static func inspect(_ entry:LibraryEntry,under root:URL)throws->LibraryMediaInfo {
        try Task.checkCancellation()
        let url=try file(entry,under:root)
        if entry.kind == .midi {
            let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
            let midi=try MIDIImport.read(handle.read(upToCount:16_777_217) ?? Data())
            return LibraryMediaInfo(duration:nil,sampleRate:nil,channels:nil,notes:midi.tracks.reduce(0){$0+$1.notes.count})
        }
        let audio=try AVAudioFile(forReading:url),rate=audio.processingFormat.sampleRate,channels=audio.processingFormat.channelCount
        guard rate.isFinite,rate>0,audio.length>0,channels>0,channels<=2 else {throw CirclrError("Mono 또는 stereo 오디오를 선택하세요")}
        let duration=Double(audio.length)/rate
        guard duration.isFinite,duration<=3600 else {throw CirclrError("1시간 이하의 오디오를 선택하세요")}
        return LibraryMediaInfo(duration:duration,sampleRate:rate,channels:Int(channels),notes:nil)
    }
    private static func directory(_ url:URL)throws->URL {
        guard url.isFileURL else {throw CirclrError("로컬 폴더를 선택하세요")}
        let root=url.resolvingSymlinksInPath().standardizedFileURL
        guard try root.resourceValues(forKeys:[.isDirectoryKey]).isDirectory==true else {throw CirclrError("등록 폴더가 없거나 읽을 수 없습니다")}
        return root
    }
    private static func contained(_ url:URL,in root:URL)->Bool {
        let base=root.pathComponents,child=url.standardizedFileURL.pathComponents
        return child.count>base.count && Array(child.prefix(base.count))==base
    }
    private static func fold(_ text:String)->String {text.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX"))}
}
