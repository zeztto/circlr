import Foundation

public struct UseTempoOverride:Codable,Equatable {
    public var initialBPM:Double
    public var changes:[TempoChange]
    public init(initialBPM:Double,changes:[TempoChange]=[]){self.initialBPM=initialBPM;self.changes=changes}
    public func validate(beats:Double)throws {
        guard initialBPM.isFinite,(1...999).contains(initialBPM),beats.isFinite,beats>0,changes.count<=4096,
              changes.allSatisfy({$0.beat.isFinite && $0.beat>0 && $0.beat<beats && $0.bpm.isFinite && (1...999).contains($0.bpm)}),
              zip(changes,changes.dropFirst()).allSatisfy({$0.beat<$1.beat}) else{throw CirclrError("이번 사용 템포 맵의 BPM·박 위치·이벤트 수를 확인하세요")}
    }
}
public enum MIDIImportTempoPolicy:String,Codable,CaseIterable {case keepCurrent,applyFile}
public struct MIDIImportTempoMap:Codable,Equatable {
    public var initialBPM:Double
    public var changes:[TempoChange]
    public init(initialBPM:Double,changes:[TempoChange]=[]){self.initialBPM=initialBPM;self.changes=changes}
    public func validate()throws {try UseTempoOverride(initialBPM:initialBPM,changes:changes).validate(beats:1_048_577)}
}
public struct MIDITempoImportPreview {
    public let startBeat:Double,endBeat:Double,minimumBPM:Double,maximumBPM:Double
    public let previousRegionSeconds:Double,regionSeconds:Double,previousSectionSeconds:Double,sectionSeconds:Double
    public let bars:Int
    public let tempoOverride:UseTempoOverride?
}
public enum MIDITempoImport {
    public static func preview(_ parts:[MIDIImportPart],useID:ID,extendSection:Bool,atBeat:Double=0,tempoPolicy:MIDIImportTempoPolicy = .applyFile,tempoMap:MIDIImportTempoMap?=nil,in project:Project)throws->MIDITempoImportPreview {
        guard !parts.isEmpty,parts.count<=256,parts.reduce(0,{$0+$1.notes.count})<=100000,
              let use=project.active.uses.first(where:{$0.id==useID}) else{throw CirclrError("가져올 MIDI와 대상 섹션을 확인하세요")}
        for part in parts {guard !part.notes.isEmpty else{throw CirclrError("가져올 MIDI 노트가 없습니다")};for note in part.notes {try ArrangementCompiler.validateNote(note)}}
        let end=atBeat+(parts.flatMap(\.notes).map{$0.beat+$0.length}.max() ?? 0)
        let (section,_,initial)=try ArrangementCompiler.context(project:project,use:use,arrangementID:project.activeArrangementID)
        guard atBeat.isFinite,atBeat>=0,atBeat<initial.beats,end.isFinite,end>atBeat,end<=131072 else{throw CirclrError("MIDI 템포 적용 구간을 확인하세요")}
        var extended=use,bars=use.barsOverride ?? section.bars,clock=initial
        if end>initial.beats+1e-8 {
            guard extendSection else{throw CirclrError("MIDI가 섹션보다 깁니다. 섹션 길이 늘리기를 선택하세요")}
            while clock.beats+1e-8<end,bars<1024 {bars+=1;extended.barsOverride=bars;clock=try ArrangementCompiler.context(project:project,use:extended,arrangementID:project.activeArrangementID).2}
            guard clock.beats+1e-8>=end else{throw CirclrError("MIDI 길이가 최대 1,024마디를 넘습니다")}
        }
        if tempoPolicy == .keepCurrent {
            let values=[clock.bpm(at:atBeat)]+clock.tempos.filter{$0.beat>atBeat && $0.beat<end}.map(\.bpm)
            let duration=clock.seconds(at:end)-clock.seconds(at:atBeat)
            return MIDITempoImportPreview(startBeat:atBeat,endBeat:end,minimumBPM:values.min()!,maximumBPM:values.max()!,previousRegionSeconds:duration,regionSeconds:duration,
                previousSectionSeconds:initial.seconds,sectionSeconds:clock.seconds,bars:bars,tempoOverride:use.tempoOverride)
        }
        guard let tempoMap else{throw CirclrError("파일 템포 맵이 필요합니다")}
        try tempoMap.validate()
        var events=clock.tempos.filter{$0.beat<atBeat || $0.beat>end}
        events.append(.init(beat:atBeat,bpm:tempoMap.initialBPM))
        events+=tempoMap.changes.filter{$0.beat<end-atBeat}.map{.init(beat:atBeat+$0.beat,bpm:$0.bpm)}
        if end<clock.beats {events.append(.init(beat:end,bpm:clock.bpm(at:end)))}
        events.sort{$0.beat<$1.beat}
        var normalized:[TempoChange]=[]
        for event in events where event.beat<clock.beats {
            if normalized.last?.bpm != event.bpm {normalized.append(event)}
        }
        guard let first=normalized.first,first.beat==0 else{throw CirclrError("템포 맵 시작을 계산하지 못했습니다")}
        let mapOverride=UseTempoOverride(initialBPM:first.bpm,changes:Array(normalized.dropFirst()))
        try mapOverride.validate(beats:clock.beats)
        var candidate=project;candidate.schemaVersion=max(4,candidate.schemaVersion)
        let index=candidate.active.uses.firstIndex{$0.id==useID}!
        candidate.arrangements[candidate.activeIndex].uses[index].barsOverride=extended.barsOverride
        candidate.arrangements[candidate.activeIndex].uses[index].tempoOverride=mapOverride
        let updated=try ArrangementCompiler.context(project:candidate,use:candidate.active.uses[index],arrangementID:candidate.activeArrangementID).2
        try UseTempoOverrideEditing.validateAudio(in:candidate,useID:useID)
        let values=[tempoMap.initialBPM]+tempoMap.changes.filter{$0.beat<end-atBeat}.map(\.bpm)
        return MIDITempoImportPreview(startBeat:atBeat,endBeat:end,minimumBPM:values.min()!,maximumBPM:values.max()!,
            previousRegionSeconds:clock.seconds(at:end)-clock.seconds(at:atBeat),regionSeconds:updated.seconds(at:end)-updated.seconds(at:atBeat),
            previousSectionSeconds:initial.seconds,sectionSeconds:updated.seconds,bars:bars,tempoOverride:mapOverride)
    }
}
public enum UseTempoOverrideEditing {
    public static func validateChanges(from previous:Project,to candidate:Project)throws {
        for arrangement in candidate.arrangements {for use in arrangement.uses {
            if let before=previous.arrangements.first(where:{$0.id==arrangement.id})?.uses.first(where:{$0.id==use.id}),before.tempoOverride != nil,use.tempoOverride != nil,before.settings.tempo != use.settings.tempo {
                throw CirclrError("이번 사용 템포 맵을 먼저 해제한 뒤 BPM·상속 출처를 변경하세요")
            }
        }}
    }
    public static func clear(useID:ID,in project:inout Project)throws {
        guard let index=project.active.uses.firstIndex(where:{$0.id==useID}) else{throw CirclrError("대상 섹션을 찾을 수 없습니다")}
        guard project.active.uses[index].tempoOverride != nil else{return}
        var candidate=project;candidate.arrangements[candidate.activeIndex].uses[index].tempoOverride=nil
        try ProjectStore.validateStructure(candidate)
        try validateAudio(in:candidate,useID:useID)
        project=candidate
    }
    public static func validateAudio(in project:Project,useID:ID,arrangementID:ID?=nil)throws {
        guard let arrangement=project.arrangements.first(where:{$0.id==(arrangementID ?? project.activeArrangementID)}),let use=arrangement.uses.first(where:{$0.id==useID}) else{throw CirclrError("대상 섹션을 찾을 수 없습니다")}
        let (section,context,clock)=try ArrangementCompiler.context(project:project,use:use,arrangementID:arrangement.id)
        var definition=section,instance=use
        if section.graph==nil {
            definition.graph=SectionGraphMigration.graph(lanes:try ArrangementCompiler.effectiveLanes(section:section,use:use),tracks:project.tracks,effects:use.effects)
            instance.effects=[];instance.graphEdits=nil
        }
        guard let plan=try SectionGraphCompiler.compile(project:project,section:definition,use:instance,context:context,clock:clock) else{throw CirclrError("오디오 템포 검증 그래프를 만들지 못했습니다")}
        for node in plan.orderedNodes {
            guard let resolved=plan.contexts[node.id] else{continue}
            let timing=AudioClipTiming(node:node,context:resolved,clock:clock)
            for clip in plan.audio[node.id] ?? [] where clip.followsTempo {
                let rate=timing.rate(clip)
                guard rate.isFinite,(0.25...4).contains(rate) else{throw CirclrError("파일 템포가 기존 오디오의 템포 추종 범위를 벗어납니다")}
                try timing.validateTempoFollowing(clip)
            }
        }
    }
}
