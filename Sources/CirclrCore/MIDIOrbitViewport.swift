import Foundation

/// Local editing view only; the complete lane and its note times remain unchanged.
public struct MIDIOrbitViewport:Codable,Equatable {
    public var topPitch=71
    public var pitchRows=12
    public var barsPerPage=4 // Zero means the complete circle.
    public var page=0
    public init(){}
    public var rows:Int {pitchRows==24 ? 24:12}
    public var highest:Int {max(rows-1,min(127,topPitch))}
    public var lowest:Int {highest-rows+1}
    public mutating func setLowestPitch(_ pitch:Int) {topPitch=max(0,min(128-rows,pitch))+rows-1}
    public mutating func movePitches(_ semitones:Int) {setLowestPitch(lowest+max(-128,min(128,semitones)))}
    public mutating func centerPitch(_ pitch:Int) {setLowestPitch(max(0,min(127,pitch))-rows/2)}
    public static func pitch(at fraction:Double)->Int? {
        guard fraction.isFinite else{return nil}
        return min(127,Int(max(0,min(1,fraction))*128))
    }
    public func bars(_ clock:MusicClock)->Range<Int> {
        let count=max(1,clock.meters.count),size=barsPerPage>0 ? min(count,barsPerPage):count
        let first=max(0,min((count-1)/size,page))*size
        return first..<min(count,first+size)
    }
    public func pageCount(_ clock:MusicClock)->Int {
        barsPerPage>0 ? max(1,(clock.meters.count+barsPerPage-1)/barsPerPage):1
    }
    public func beats(_ clock:MusicClock)->Range<Double> {
        let range=bars(clock)
        return clock.barStarts[range.lowerBound]..<clock.barStarts[range.upperBound]
    }
    public func phase(_ beat:Double,clock:MusicClock)->Double {
        let r=beats(clock),start=clock.seconds(at:r.lowerBound)
        return (clock.seconds(at:beat)-start)/max(1e-9,clock.seconds(at:r.upperBound)-start)
    }
    public func beat(_ phase:Double,clock:MusicClock)->Double {
        let r=beats(clock),start=clock.seconds(at:r.lowerBound)
        return clock.beat(atSeconds:start+phase*(clock.seconds(at:r.upperBound)-start))
    }
    public func visible(_ note:Note,clock:MusicClock)->Bool {
        let r=beats(clock)
        return (lowest...highest).contains(note.pitch) && note.beat<r.upperBound && note.beat+note.length>r.lowerBound
    }
    public func showsEnd(_ note:Note,clock:MusicClock)->Bool {
        let r=beats(clock),end=note.beat+note.length
        return end>r.lowerBound && end<=r.upperBound
    }
    public mutating func fitPitches(_ notes:[Note]) {
        guard let high=notes.map(\.pitch).max(),let low=notes.map(\.pitch).min() else{return}
        pitchRows=high-low<12 ? 12:24
        topPitch=min(127,max(rows-1,high-low<rows ? min(high+1,low+rows-1):high))
    }
    public mutating func reveal(_ note:Note,clock:MusicClock) {
        if note.pitch>highest {topPitch=min(127,note.pitch)}
        if note.pitch<lowest {topPitch=max(rows-1,note.pitch+rows-1)}
        let r=beats(clock)
        if barsPerPage>0 && (note.beat+note.length<=r.lowerBound || note.beat>=r.upperBound) {page=clock.bar(at:note.beat)/barsPerPage}
    }
    public static func ordered(_ notes:[Note])->[Note] {
        notes.sorted{a,b in a.beat != b.beat ? a.beat<b.beat:a.pitch != b.pitch ? a.pitch<b.pitch:a.id<b.id}
    }
}
