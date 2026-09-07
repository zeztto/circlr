import Foundation

/// Musical edits shared by keyboard entry points; bounds are in quarter-note beats.
public enum KeyboardEditing {
    public enum NoteChange {case time(Double),pitch(Int),length(Double),velocity(Int)}
    public static func changed(_ note:Note,by change:NoteChange,beats:Double)->Note {
        guard beats.isFinite,beats>0 else{return note}
        var next=note
        switch change {
        case .time(let delta):
            guard delta.isFinite else{return note}
            next.beat=max(0,min(max(0,beats-note.length),note.beat+delta))
        case .pitch(let delta): next.pitch=max(0,min(127,note.pitch+max(-127,min(127,delta))))
        case .length(let delta):
            guard delta.isFinite else{return note}
            next.length=max(1.0/960,min(max(1.0/960,beats-note.beat),note.length+delta))
        case .velocity(let delta): next.velocity=max(1,min(127,note.velocity+max(-127,min(127,delta))))
        }
        return next
    }
}
