import Foundation

/// Presentation state. References are validated against the current editing scope before use.
public struct EditorSelectionState:Codable,Equatable {
    public var noteIDs:[ID]=[]
    public var anchorID:ID?
    public var beat:Double=0
    public var audioClipID:ID?
    public var audioAssetID:ID?
    public var audioSourcePosition:Double?
    public var automationPoints:[String:ID]=[:]
    public init(){}
    public func restored(notes:[Note],beats:Double,clip:AudioClip?,automation:[AutomationLane])->Self {
        var next=self
        let valid=Set(notes.map(\.id)),selected=Set(noteIDs).intersection(valid)
        next.noteIDs=selected.sorted()
        next.anchorID=anchorID.flatMap{selected.contains($0) ? $0:nil} ?? MIDIOrbitViewport.ordered(notes.filter{selected.contains($0.id)}).first?.id
        let limit=beats.isFinite ? max(0,min(1_048_576,beats)):0
        next.beat=beat.isFinite ? min(limit,max(0,beat)):0
        if let clip,clip.id==audioClipID,clip.assetID==audioAssetID,let position=audioSourcePosition,position.isFinite {
            next.audioSourcePosition=min(clip.sourceStart+clip.duration,max(clip.sourceStart,position))
        } else {next.audioSourcePosition=nil}
        next.audioClipID=clip?.id;next.audioAssetID=clip?.assetID
        next.automationPoints=automationPoints.filter{key,id in automation.contains{$0.parameter.rawValue==key && $0.points.contains{$0.id==id}}}
        return next
    }
}
