import Foundation

/// View state only; opening the editor never creates an expression sequence.
public struct SustainWorkspaceState:Codable,Equatable {
    public var selectedIndex:Int?
    public var displayedBeats:Double?
    public init(selectedIndex:Int?=nil,displayedBeats:Double?=nil){self.selectedIndex=selectedIndex;self.displayedBeats=displayedBeats}
    /// Positional events have no stable IDs. A changed source invalidates the old
    /// selection even if another identical event now occupies its index.
    public func reconciled(from previous:MIDISustainSequence?,to next:MIDISustainSequence?)->Self {
        var copy=validated(count:next?.events.count ?? 0)
        if previous != next {copy.selectedIndex=nil}
        return copy
    }
    public func validated(count:Int?=nil)->Self {
        var copy=self
        if let index=copy.selectedIndex,index<0 || index>=100000 || count.map({index >= $0})==true {copy.selectedIndex=nil}
        if let beats=copy.displayedBeats,!beats.isFinite || beats<=0 || beats>131072 {copy.displayedBeats=nil}
        return copy
    }
}
