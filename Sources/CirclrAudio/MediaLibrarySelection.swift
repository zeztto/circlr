import Foundation
import CirclrCore

public enum MediaLibrarySelection {
    public static let limit=64
    public static func toggling(_ id:String,in selected:Set<String>)throws->Set<String> {
        var next=selected;if !next.insert(id).inserted{next.remove(id)}
        guard next.count<=limit else{throw CirclrError("한 번에 최대 64개 파일을 선택하세요")};return next
    }
    public static func range(_ orderedIDs:[String],anchor:String?,target:String)throws->Set<String> {
        guard let end=orderedIDs.firstIndex(of:target) else{throw CirclrError("선택할 파일을 다시 확인하세요")}
        let start=anchor.flatMap{orderedIDs.firstIndex(of:$0)} ?? end
        guard abs(end-start)+1<=limit else{throw CirclrError("한 번에 최대 64개 파일을 선택하세요")}
        return Set(orderedIDs[min(start,end)...max(start,end)])
    }
    /// Returns the visible selection in display order; never silently drops a stale file ID.
    public static func entries(_ results:[LibraryEntry],ids:Set<String>)throws->[LibraryEntry] {
        guard !ids.isEmpty,ids.count<=limit else{throw CirclrError("한 번에 1–64개 파일을 선택하세요")}
        let entries=results.filter{ids.contains($0.id)}
        guard entries.count==ids.count,Set(entries.map(\.id))==ids else{throw CirclrError("검색 결과가 변경됐습니다. 파일을 다시 선택하세요")}
        return entries
    }
    public static func validate(_ entries:[LibraryEntry])throws {
        guard !entries.isEmpty,entries.count<=limit,Set(entries.map(\.id)).count==entries.count else{throw CirclrError("한 번에 1–64개 파일을 선택하세요")}
        if entries.contains(where:{$0.kind == .midi}) {
            guard entries.count==1 else{throw CirclrError("MIDI는 한 파일씩 가져옵니다. 오디오와 따로 선택하세요")}
            guard entries[0].bytes>0,entries[0].bytes<=16_777_216 else{throw CirclrError("16 MiB 이하의 MIDI 파일을 선택하세요")}
        } else {
            var total:Int64=0
            for entry in entries {
                guard entry.bytes>0,entry.bytes<=AudioFileImport.maximumFileBytes,total<=AudioFileImport.maximumBatchBytes-entry.bytes else{throw CirclrError("파일당 2 GiB·한 번에 4 GiB 이하의 오디오를 선택하세요")}
                total+=entry.bytes
            }
        }
    }
}
