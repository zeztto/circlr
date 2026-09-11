import Foundation

/// A gesture always derives from one immutable lane, preserving the selection's relative timing.
public struct MIDINoteDrag {
    public let original:Lane
    public let ids:Set<ID>
    private let selected:[Note]
    private let beats:Double
    private let grid:Double
    public init(lane:Lane,ids:Set<ID>,beats:Double,subdivisions:Int)throws {
        guard beats.isFinite,beats>0,beats<=131072,(1...64).contains(subdivisions),
              !ids.isEmpty,lane.notes.count<=100000,Set(lane.notes.map(\.id)).count==lane.notes.count,
              ids.isSubset(of:Set(lane.notes.map(\.id))) else {throw CirclrError("드래그할 MIDI 선택·시간·격자를 확인하세요")}
        for note in lane.notes where ids.contains(note.id) {try ArrangementCompiler.validateNote(note)}
        original=lane;self.ids=ids;selected=lane.notes.filter{ids.contains($0.id)};self.beats=beats;grid=Double(subdivisions)
    }
    private func snap(_ value:Double)->Double {(min(131072,max(-131072,value))*grid).rounded()/grid}
    public func moving(beatDelta:Double,pitchDelta:Int)->Lane {
        guard beatDelta.isFinite else{return original}
        let lower = -selected.map(\.beat).min()!
        // Existing tails beyond this circle remain intact; they cannot be moved farther out.
        let upper=max(0,beats-selected.map{$0.beat+$0.length}.max()!)
        let time=min(upper,max(lower,snap(beatDelta)))
        let pitch=min(127-selected.map(\.pitch).max()!,max(-selected.map(\.pitch).min()!,pitchDelta))
        var result=original
        for i in result.notes.indices where ids.contains(result.notes[i].id) {
            result.notes[i].beat+=time;result.notes[i].pitch+=pitch
        }
        return result
    }
    public func resizing(lengthDelta:Double)->Lane {
        guard lengthDelta.isFinite else{return original}
        let lower=selected.map{min($0.length,1/grid)-$0.length}.max()!
        let upper=selected.map{max(0,beats-$0.beat-$0.length)}.min()!
        let delta=min(upper,max(lower,snap(lengthDelta)))
        var result=original
        for i in result.notes.indices where ids.contains(result.notes[i].id) {result.notes[i].length+=delta}
        return result
    }
}
