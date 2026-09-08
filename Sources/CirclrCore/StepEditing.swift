import Foundation

/// A view of ordinary quarter-note beats. Changing resolution never rewrites existing notes.
public struct StepGrid:Equatable {
    public static let resolutions=[1,2,3,4,6,8]
    public static let pageSize=16
    public let subdivisions:Int
    public let beats:Double
    public var stepLength:Double {1/Double(subdivisions)}
    public var stepCount:Int {max(1,Int(ceil(beats*Double(subdivisions)-1e-9)))}
    public var pageCount:Int {(stepCount+Self.pageSize-1)/Self.pageSize}
    public init(subdivisions:Int=4,beats:Double)throws {
        guard Self.resolutions.contains(subdivisions),beats.isFinite,beats>0,beats<=131072 else{throw CirclrError("스텝 길이 또는 분할을 확인하세요")}
        self.subdivisions=subdivisions;self.beats=beats
    }
    public func start(_ index:Int)->Double {Double(index)*stepLength}
    public func contains(_ beat:Double,in index:Int)->Bool {
        guard beat.isFinite,(0..<stepCount).contains(index) else{return false}
        return beat>=start(index)-1e-9 && beat<min(beats,start(index+1))-1e-9
    }
    public func onsets(in lane:Lane,pitch:Int,index:Int)->[Note] {lane.notes.filter{$0.pitch==pitch && contains($0.beat,in:index)}}
}

public enum StepEditing {
    /// Setting an existing step is idempotent. Unspecified values preserve timing, gate and velocity.
    public static func set(_ lane:Lane,grid:StepGrid,index:Int,pitch:Int,enabled:Bool,velocity:Int?=nil,gate:Double?=nil)throws->Lane {
        guard (0..<grid.stepCount).contains(index),(0...127).contains(pitch),velocity.map({(1...127).contains($0)}) ?? true,
              gate.map({$0.isFinite && (0.01...16).contains($0)}) ?? true else{throw CirclrError("스텝·음높이·세기·길이 범위를 확인하세요")}
        var result=lane
        let matching=Set(grid.onsets(in:lane,pitch:pitch,index:index).map(\.id))
        if !enabled {result.notes.removeAll{matching.contains($0.id)};return result}
        if matching.isEmpty {
            let start=grid.start(index),length=min(grid.beats-start,(gate ?? 0.9)*grid.stepLength)
            result.notes.append(Note(beat:start,length:length,pitch:pitch,velocity:velocity ?? 96))
        } else {
            for i in result.notes.indices where matching.contains(result.notes[i].id) {
                if let velocity {result.notes[i].velocity=velocity}
                if let gate {result.notes[i].length=min(grid.beats-result.notes[i].beat,gate*grid.stepLength)}
            }
        }
        guard result.notes.count<=100000 else{throw CirclrError("트랙의 MIDI 노트 한도를 넘습니다")}
        return result
    }
    public static func clearPage(_ lane:Lane,grid:StepGrid,page:Int)throws->Lane {
        guard (0..<grid.pageCount).contains(page) else{throw CirclrError("스텝 페이지를 확인하세요")}
        let start=grid.start(page*StepGrid.pageSize),end=min(grid.beats,grid.start((page+1)*StepGrid.pageSize))
        var result=lane;result.notes.removeAll{$0.beat>=start-1e-9 && $0.beat<end-1e-9};return result
    }
    /// Replaces destination onsets in one edit; earlier sustaining notes and all audio remain intact.
    public static func copyPage(_ lane:Lane,grid:StepGrid,from:Int,to:Int)throws->Lane {
        guard (0..<grid.pageCount).contains(from),(0..<grid.pageCount).contains(to) else{throw CirclrError("복제할 스텝 페이지를 확인하세요")}
        if from==to{return lane}
        let start=grid.start(from*StepGrid.pageSize),end=min(grid.beats,grid.start((from+1)*StepGrid.pageSize)),target=grid.start(to*StepGrid.pageSize)
        var result=try clearPage(lane,grid:grid,page:to)
        for note in lane.notes where note.beat>=start-1e-9 && note.beat<end-1e-9 {
            let beat=target+note.beat-start
            guard beat<grid.beats-1e-9 else{continue}
            var copy=note;copy.id=newID();copy.beat=max(0,beat);copy.length=min(note.length,grid.beats-copy.beat);result.notes.append(copy)
        }
        guard result.notes.count<=100000 else{throw CirclrError("트랙의 MIDI 노트 한도를 넘습니다")}
        return result
    }
}
