import Foundation

/// Source-data edits preserve events beyond the current circle's playback window.
public enum MIDIPitchBendEditing {
    public enum Change:Codable,Equatable {
        case insert(MIDIPitchBendEvent)
        case update(index:Int,event:MIDIPitchBendEvent)
        case remove(index:Int)
        case setInitial(channel:Int,value:Int,range:MIDIPitchBendRange)
        case clear
    }
    public struct Result:Equatable {
        public let sequence:MIDIPitchBendSequence?
        public let selectedIndex:Int?
    }
    /// Indices address the supplied snapshot. Callers must reject stale project revisions.
    /// Insertions and beat moves follow existing events at the same beat; value-only
    /// edits retain their existing position in that beat's ordered event stream.
    public static func apply(_ change:Change,to sequence:MIDIPitchBendSequence?)throws->Result {
        try sequence?.validate()
        if case .clear=change {return Result(sequence:nil,selectedIndex:nil)}
        var candidate=sequence ?? MIDIPitchBendSequence()
        var selected:Int?
        func checkedIndex(_ index:Int)throws {
            guard sequence != nil,candidate.events.indices.contains(index) else{throw CirclrError("편집할 피치 벤드 이벤트가 변경되었습니다")}
        }
        func insertionIndex(for event:MIDIPitchBendEvent)->Int {
            candidate.events.firstIndex{$0.beat>event.beat} ?? candidate.events.count
        }
        switch change {
        case .insert(let event):
            try event.validate()
            guard candidate.events.count<100000 else{throw CirclrError("피치 벤드 이벤트는 최대 100,000개입니다")}
            let index=insertionIndex(for:event);candidate.events.insert(event,at:index);selected=index
        case .update(let index,let event):
            try checkedIndex(index);try event.validate()
            if candidate.events[index].beat==event.beat {candidate.events[index]=event;selected=index}
            else {
                candidate.events.remove(at:index)
                let destination=insertionIndex(for:event);candidate.events.insert(event,at:destination);selected=destination
            }
        case .remove(let index):
            try checkedIndex(index);candidate.events.remove(at:index)
        case .setInitial(let channel,let value,let range):
            candidate.channel=channel;candidate.initialValue=value;candidate.initialRange=range
        case .clear:break
        }
        try candidate.validate()
        return Result(sequence:candidate,selectedIndex:selected)
    }
}
