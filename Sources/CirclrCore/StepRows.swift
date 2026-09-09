import Foundation

public struct StepRow:Equatable {
    public let pitch:Int
    public let label:String
    public init(pitch:Int,label:String){self.pitch=pitch;self.label=label}
}

/// Row navigation is independent of note timing, instruments, and musical edits.
public enum StepRows {
    public static func pitches(observed:[Int],mapped:[Int],extra:Set<Int>,fallback:Int)->[Int] {
        let result=Set(observed).union(mapped).union(extra).filter{(0...127).contains($0)}.sorted()
        return result.isEmpty ? [max(0,min(127,fallback))]:result
    }
    public static func filter(_ rows:[StepRow],query:String)->[StepRow] {
        let terms=normalized(query).split(whereSeparator:{$0.isWhitespace}).map(String.init)
        guard !terms.isEmpty else{return rows}
        return rows.filter { row in
            let text=normalized("\(row.pitch) "+row.label)
            return terms.allSatisfy{text.contains($0)}
        }
    }
    private static func normalized(_ value:String)->String {
        value.replacingOccurrences(of:"♯",with:"#").replacingOccurrences(of:"♭",with:"b")
            .folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX"))
    }
}
