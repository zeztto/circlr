import Foundation

public struct StepRow:Equatable {
    public let pitch:Int
    public let label:String
    public init(pitch:Int,label:String){self.pitch=pitch;self.label=label}
}

/// Row navigation is independent of note timing, instruments, and musical edits.
public enum StepRows {
    public static let generalMIDIDrumNames: [Int:String] = [36:"킥",38:"스네어",39:"클랩",42:"닫힌 하이햇",46:"열린 하이햇",45:"톰",49:"크래시",51:"라이드"]
    public static func pitches(observed:[Int],mapped:[Int],extra:Set<Int>,fallback:Int,defaults:[Int]=[])->[Int] {
        let result=Set(observed).union(mapped).union(extra).union(defaults).filter{(0...127).contains($0)}.sorted()
        return result.isEmpty ? [max(0,min(127,fallback))]:result
    }
    public static func pitches(instrument:Instrument?,observed:[Int],extra:Set<Int>)->[Int] {
        let sample=instrument?.kind == .sampler ? instrument?.sample:nil
        let defaults=instrument?.kind == .soundBank && instrument?.drums == true ? Array(generalMIDIDrumNames.keys):[]
        return pitches(observed:observed,mapped:sample?.zones?.map(\.pitch) ?? [],extra:extra,fallback:sample?.rootPitch ?? 36,defaults:defaults)
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
