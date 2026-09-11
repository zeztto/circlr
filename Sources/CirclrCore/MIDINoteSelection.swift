import Foundation

/// Selection spans the entire current lane; it never changes musical data.
public enum MIDINoteSelection {
    public enum Action {case all,clear,invert,samePitch,sameStart}
    public static func applying(_ action:Action,to notes:[Note],selected:Set<ID>)->Set<ID> {
        let all=Set(notes.map(\.id)),ids=selected.intersection(all)
        switch action {
        case .all:return all
        case .clear:return []
        case .invert:return all.subtracting(ids)
        case .samePitch:
            let pitches=Set(notes.filter{ids.contains($0.id)}.map(\.pitch))
            return Set(notes.filter{pitches.contains($0.pitch)}.map(\.id))
        case .sameStart:
            let starts=notes.filter{ids.contains($0.id) && $0.beat.isFinite}.map(\.beat).sorted()
            guard !starts.isEmpty else{return []}
            // A binary lower bound avoids quadratic work on dense imported performances.
            return Set(notes.filter{note in
                guard note.beat.isFinite else{return false}
                var lower=0,upper=starts.count
                while lower<upper {let mid=(lower+upper)/2;if starts[mid]<note.beat-1e-7{lower=mid+1}else{upper=mid}}
                return lower<starts.count && abs(starts[lower]-note.beat)<=1e-7
            }.map(\.id))
        }
    }
}
