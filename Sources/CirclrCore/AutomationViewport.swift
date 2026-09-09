import Foundation

/// A fitted range belongs to the editing session, not the document or audio clock.
public struct AutomationViewport:Equatable {
    public private(set) var fittedBeats:Double?
    public init(){}
    public func displayedBeats(base:Double)->Double {max(base,fittedBeats ?? base)}
    public mutating func fit(base:Double,points:[AutomationPoint]) {
        fittedBeats=max(base,points.map(\.beat).max() ?? 0)
    }
    public mutating func reveal(base:Double,beat:Double) {
        guard beat.isFinite,(0...1_048_576).contains(beat),beat>displayedBeats(base:base) else{return}
        fittedBeats=beat
    }
    public mutating func reset(){fittedBeats=nil}
}
