import Foundation
import CirclrCore

/// Sample-frame scheduler shared by the live queue and deterministic offline tests.
/// A change takes effect at the next boundary not already submitted to the player.
struct PlaybackLoopSchedule {
    struct Source: Equatable, Sendable {let id:UUID;let frames:Int;let tailFrames:Int}
    struct Change: Equatable, Sendable {let id:UUID;let replacement:Source?}
    struct Boundary: Equatable, Sendable {let change:Change;let elapsedFrame:Int64;let sourceFrames:Int}
    struct Chunk: Equatable, Sendable {
        let source:Source;let tail:Bool;let sourceFrame:Int;let count:Int;let elapsedFrame:Int64
    }
    struct Step: Equatable, Sendable {let boundary:Boundary?;let chunk:Chunk?;let ended:Bool}
    private(set) var source:Source
    private(set) var elapsedFrame:Int64=0
    private(set) var pending:Change?
    private var cursor:Int
    private var tail=false
    private var cancelled=false
    private var atBoundary=false
    init(source:Source,fromFrame:Int=0)throws {
        guard source.frames>0,source.tailFrames>=0,fromFrame>=0,fromFrame<source.frames else{throw PlaybackTransportError.invalidPosition}
        self.source=source;cursor=fromFrame
    }
    @discardableResult mutating func request(_ change:Change)throws->Boundary {
        guard !cancelled,!tail,pending==nil else{throw PlaybackTransportError.busy}
        if let replacement=change.replacement {guard replacement.frames>0,replacement.tailFrames>=0 else{throw PlaybackTransportError.invalidPosition}}
        let remaining=atBoundary ? 0:source.frames-cursor
        guard elapsedFrame<=Int64.max-Int64(remaining) else{throw PlaybackTransportError.invalidPosition}
        pending=change
        return Boundary(change:change,elapsedFrame:elapsedFrame+Int64(remaining),sourceFrames:change.replacement?.frames ?? source.frames)
    }
    mutating func cancel(){cancelled=true;pending=nil}
    mutating func next(maxFrames:Int)throws->Step {
        guard maxFrames>0 else{throw PlaybackTransportError.invalidPosition}
        guard !cancelled else{return Step(boundary:nil,chunk:nil,ended:true)}
        var boundary:Boundary?
        if atBoundary {
            if let change=pending {
                pending=nil;boundary=Boundary(change:change,elapsedFrame:elapsedFrame,sourceFrames:change.replacement?.frames ?? source.frames)
                if let replacement=change.replacement {source=replacement;tail=false}
                else {tail=true}
            }
            cursor=0;atBoundary=false
        }
        let length=tail ? source.tailFrames:source.frames
        guard cursor<length else{return Step(boundary:boundary,chunk:nil,ended:true)}
        let count=min(maxFrames,length-cursor)
        guard elapsedFrame<=Int64.max-Int64(count) else{throw PlaybackTransportError.invalidPosition}
        let chunk=Chunk(source:source,tail:tail,sourceFrame:cursor,count:count,elapsedFrame:elapsedFrame)
        cursor+=count;elapsedFrame+=Int64(count)
        if cursor==length,!tail {atBoundary=true}
        return Step(boundary:boundary,chunk:chunk,ended:tail && cursor==length)
    }
}
