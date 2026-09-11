import Foundation

public struct StepEditorState:Codable,Equatable {
    public var subdivisions=4
    public var page=0
    public var drumMode=false
    public var extraPitches:Set<Int>=[]
    public var newPitch=36
    public var rowQuery=""
    public init(){}
    enum CodingKeys:String,CodingKey {case subdivisions,page,drumMode,extraPitches,newPitch,rowQuery}
    public init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        subdivisions=try c.decodeIfPresent(Int.self,forKey:.subdivisions) ?? 4
        page=try c.decodeIfPresent(Int.self,forKey:.page) ?? 0
        drumMode=try c.decodeIfPresent(Bool.self,forKey:.drumMode) ?? false
        extraPitches=Set(try c.decodeIfPresent([Int].self,forKey:.extraPitches) ?? [])
        newPitch=try c.decodeIfPresent(Int.self,forKey:.newPitch) ?? 36
        rowQuery=try c.decodeIfPresent(String.self,forKey:.rowQuery) ?? ""
    }
    public func encode(to encoder:Encoder)throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(subdivisions,forKey:.subdivisions);try c.encode(page,forKey:.page)
        try c.encode(drumMode,forKey:.drumMode);try c.encode(extraPitches.sorted(),forKey:.extraPitches)
        try c.encode(newPitch,forKey:.newPitch);try c.encode(rowQuery,forKey:.rowQuery)
    }
}

public struct EditorScrollPosition:Codable,Equatable {
    public var x:Double
    public var y:Double
    public init(x:Double=0,y:Double=0){self.x=x;self.y=y}
    public func clamped(width:Double,height:Double,visibleWidth:Double,visibleHeight:Double)->Self {
        func offset(_ value:Double,_ size:Double,_ visible:Double)->Double {
            guard value.isFinite,size.isFinite,visible.isFinite else{return 0}
            return min(max(0,size-visible),max(0,value))
        }
        return .init(x:offset(x,width,visibleWidth),y:offset(y,height,visibleHeight))
    }
}

/// Presentation only. The full lane, clip and its time domain remain unchanged.
public struct EditorViewportState:Codable,Equatable {
    public var topPitch=72
    public var orbit=MIDIOrbitViewport()
    public var steps=StepEditorState()
    public var audio=AudioSourceViewport()
    public var audioAssetID:ID?
    public var scrolls:[String:EditorScrollPosition]=[:]
    public init(){}
    public func restored(beats:Double,clock:MusicClock?,assetID:ID?,assetDuration:Double?)->Self {
        var next=self
        next.topPitch=min(128,max(12,topPitch))
        next.orbit.pitchRows=orbit.rows;next.orbit.topPitch=orbit.highest
        next.orbit.barsPerPage=[0,1,2,4,8].contains(orbit.barsPerPage) ? orbit.barsPerPage:4
        next.orbit.page=max(0,min(next.orbit.page,clock.map{next.orbit.pageCount($0)-1} ?? 0))
        next.steps.subdivisions=StepGrid.resolutions.contains(steps.subdivisions) ? steps.subdivisions:4
        let count=(try? StepGrid(subdivisions:next.steps.subdivisions,beats:beats).pageCount) ?? 1
        next.steps.page=min(count-1,max(0,steps.page))
        next.steps.newPitch=min(127,max(0,steps.newPitch));next.steps.extraPitches=Set(steps.extraPitches.filter{(0...127).contains($0)})
        next.steps.rowQuery=String(steps.rowQuery.prefix(256))
        if audioAssetID != assetID {next.audio.showAll()}
        next.audioAssetID=assetID
        if let duration=assetDuration,duration.isFinite,duration>0 {next.audio.clamp(to:duration)} else {next.audio.showAll()}
        next.scrolls=scrolls.filter{["piano","steps","settings","instrument","effect","output","router","orbitControls"].contains($0.key)}
            .mapValues{.init(x:$0.x.isFinite ? max(0,min(1e9,$0.x)):0,y:$0.y.isFinite ? max(0,min(1e9,$0.y)):0)}
        return next
    }
}
