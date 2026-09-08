import Foundation

public enum AudioTakeEditing {
    /// Finalizing a file must never insert it into a different or deleted destination.
    @discardableResult public static func save(asset:Asset,projectID:ID,arrangementID:ID,useID:ID,trackID:ID,laneID:ID?,clock:MusicClock,in project:inout Project)throws->ID {
        guard project.id==projectID,project.tracks.contains(where:{$0.id==trackID}),
              let arrangement=project.arrangements.first(where:{$0.id==arrangementID}),let use=arrangement.uses.first(where:{$0.id==useID}),let section=project.sections.first(where:{$0.id==use.sectionID}),
              asset.duration.isFinite,asset.duration>0,asset.sampleRate.isFinite,asset.sampleRate>0,
              asset.duration<=clock.seconds*256, !project.assets.contains(where:{$0.id==asset.id}) else{throw CirclrError("녹음 파일과 원래 프로젝트·서클·트랙을 확인하세요")}
        let lanes=try ArrangementCompiler.effectiveLanes(section:section,use:use)
        let target=laneID.flatMap{id in lanes.first{$0.id==id && $0.trackID==trackID}} ?? (laneID==nil ? lanes.first{$0.trackID==trackID}:nil)
        guard laneID==nil || target != nil else{throw CirclrError("녹음 대상 서클이 삭제되었습니다. 원본 파일은 보존됩니다")}
        var candidate=project,takes=project.takes ?? []
        if let target,!target.audio.isEmpty,!takes.contains(where:{$0.useID==useID && $0.arrangementID==arrangementID && $0.targetLaneID==target.id && $0.lane==target}) {
            var baseline=RecordedTake(useID:useID,name:"녹음 전 · \(asset.name)",lane:target);baseline.targetLaneID=target.id;baseline.arrangementID=arrangementID;takes.append(baseline)
        }
        candidate.assets.append(asset)
        let count=max(1,Int(ceil(asset.duration/clock.seconds-1e-9)))
        for iteration in 0..<count {
            let start=Double(iteration)*clock.seconds,duration=min(clock.seconds,asset.duration-start)
            guard duration>0 else{continue}
            var clip=AudioClip(assetID:asset.id,duration:duration);clip.sourceStart=start;clip.sourceBPM=clock.bpm(at:0);clip.preservesTail=true
            var lane=Lane(trackID:trackID);lane.audio=[clip]
            var take=RecordedTake(useID:useID,name:"\(asset.name) · \(iteration+1)회",lane:lane);take.targetLaneID=target?.id;take.arrangementID=arrangementID;takes.append(take)
        }
        guard let latest=takes.last,latest.lane.audio.first?.assetID==asset.id else{throw CirclrError("녹음된 오디오가 없습니다")}
        candidate.takes=takes;try ProjectEditing.activateTake(latest,in:&candidate);project=candidate;return latest.id
    }
}
