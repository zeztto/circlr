import Foundation

/// Describes the content that activating a take would replace, without storing selection state.
public struct RecordedTakeSummary: Equatable {
    public let noteCount:Int
    public let clipCount:Int
    public let matchesCurrentContent:Bool

    public static func make(_ take:RecordedTake,arrangementID:ID,useID:ID,laneID:ID,in project:Project)->Self? {
        // Keep legacy nil-owner and nil-target resolution identical to activateTake.
        guard take.useID==useID,
              let arrangement=project.arrangements.first(where:{
                  (take.arrangementID==nil || $0.id==take.arrangementID) && $0.uses.contains{$0.id==take.useID}
              }),arrangement.id==arrangementID,
              let use=arrangement.uses.first(where:{$0.id==take.useID}),
              let section=project.sections.first(where:{$0.id==use.sectionID}),
              let lanes=try? ArrangementCompiler.effectiveLanes(section:section,use:use),
              let target=take.targetLaneID.flatMap({id in lanes.first{$0.id==id}})
                ?? (take.targetLaneID==nil ? lanes.first{$0.trackID==take.lane.trackID}:nil),
              target.id==laneID,target.trackID==take.lane.trackID else{return nil}
        let replacesNotes = take.replacesMIDINotes == true || (take.replacesMIDINotes == nil && !take.lane.notes.isEmpty)
        let applied=ProjectEditing.laneByApplyingTake(take,to:target)
        let hasContent = replacesNotes || take.lane.pitchBend != nil || take.lane.sustain != nil || !take.lane.audio.isEmpty
        return Self(noteCount:take.lane.notes.count,clipCount:take.lane.audio.count,
                    matchesCurrentContent:hasContent
                    && (!replacesNotes || target.notes==applied.notes)
                    && (!(replacesNotes || take.lane.pitchBend != nil) || target.pitchBend==applied.pitchBend)
                    && (!(replacesNotes || take.lane.sustain != nil) || target.sustain==applied.sustain)
                    && (take.lane.audio.isEmpty || target.audio==take.lane.audio))
    }
}
