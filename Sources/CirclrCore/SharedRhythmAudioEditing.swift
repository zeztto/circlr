import Foundation

/// Edits only the addressed shared pattern. Returned identity is a clip, never a graph node.
public enum SharedRhythmAudioEditing {
    @discardableResult public static func apply(_ change:AudioEditing.Change,patternID:ID,trackID:ID,clipID:ID,in project:inout Project)throws->ID? {
        var p=project
        guard let pi=p.patterns.firstIndex(where:{$0.id==patternID && $0.trackID==trackID}),
              let ci=p.patterns[pi].audio.firstIndex(where:{$0.id==clipID}),
              let asset=p.assets.first(where:{$0.id==p.patterns[pi].audio[ci].assetID}) else {throw CirclrError("편집할 공유 오디오 구간이 변경되었습니다")}
        var pattern=p.patterns[pi],clip=pattern.audio[ci]
        try ArrangementCompiler.validatePattern(pattern,project:p)
        try clip.validateEditing(asset:asset)
        var result:ID?=clip.id
        switch change {
        case .replace(let replacement):
            guard replacement.id==clip.id,replacement.assetID==clip.assetID else{throw CirclrError("공유 오디오 원본이 변경되었습니다")}
            pattern.audio[ci]=replacement
        case .fade(let input,let output):
            clip.fadeIn=input;clip.fadeOut=output;pattern.audio[ci]=clip
        case .delete:
            pattern.audio.remove(at:ci);result=nil
        case .duplicate(let offset):
            let delta:Double
            if let offset {guard offset.isFinite else{throw CirclrError("복제 이동 박을 확인하세요")};delta=offset}
            else {let tempos=try consumerTempos(pattern:pattern,in:p);delta=try beatDelta(seconds:clip.duration,clip:clip,tempos:tempos)}
            var copy=clip;copy.id=newID();copy.beat+=delta
            if copy.renderWindow != nil {copy.renderWindow?.cycleBeat+=delta}
            guard copy.beat.isFinite,copy.beat>=0,copy.beat<pattern.length else{throw CirclrError("공유 패턴 안에 복제할 공간이 없습니다")}
            pattern.audio.append(copy);result=copy.id
        case .split(let offset):
            guard offset.isFinite,offset>0,offset<clip.duration else{throw CirclrError("분할 위치를 공유 오디오 구간 안에 지정하세요")}
            let tempos=try consumerTempos(pattern:pattern,in:p)
            let rate=clip.followsTempo ? tempos[0]/clip.sourceBPM:1
            let cut=(offset/rate*48000).rounded()/48000*rate
            // One source cut must land on the same output-frame boundary in every consumer.
            for tempo in tempos {
                let speed=clip.followsTempo ? tempo/clip.sourceBPM:1
                let frames=cut/speed*48000
                guard abs(frames-frames.rounded())<1e-7 else{throw CirclrError("공유된 템포마다 분할 샘플 위치가 다릅니다. 공통 샘플 경계를 선택하세요")}
            }
            let delta=try beatDelta(seconds:cut,clip:clip,tempos:tempos)
            guard cut>0,cut<clip.duration,clip.beat+delta<pattern.length else{throw CirclrError("분할 위치가 공유 패턴 밖입니다")}
            var window=clip.renderWindow ?? AudioRenderWindow(sourceStart:clip.sourceStart,duration:clip.duration,cycleBeat:clip.beat,automaticEdges:clip.explicitEnvelope==nil && clip.preservesTail != true,envelopes:[])
            if let e=clip.explicitEnvelope,e.fadeIn>0 || e.fadeOut>0 {window.envelopes.append(e)}
            var right=clip;right.id=newID();right.sourceStart+=cut;right.duration-=cut;right.beat+=delta
            clip.duration=cut;clip.renderWindow=window;right.renderWindow=window
            clip.fadeIn=0;clip.fadeOut=0;right.fadeIn=0;right.fadeOut=0
            pattern.audio[ci]=clip;pattern.audio.insert(right,at:ci+1);result=right.id
        }
        for value in pattern.audio {
            guard value.beat.isFinite,value.beat>=0,value.beat<pattern.length else{throw CirclrError("공유 오디오 시작 박은 패턴 안에 있어야 합니다")}
            guard let source=p.assets.first(where:{$0.id==value.assetID}) else{throw CirclrError("공유 오디오 파일을 찾을 수 없습니다")}
            try value.validateEditing(asset:source)
        }
        try ArrangementCompiler.validatePattern(pattern,project:p)
        p.patterns[pi]=pattern;try ProjectStore.validateStructure(p);project=p
        return result
    }
    private static func beatDelta(seconds:Double,clip:AudioClip,tempos:[Double])throws->Double {
        if clip.followsTempo,tempos.contains(where:{!(0.25...4).contains($0/clip.sourceBPM)}) {throw CirclrError("오디오 템포 추종은 원속도의 0.25–4배 범위에서 지원합니다")}
        if !clip.followsTempo,tempos.contains(where:{abs($0-tempos[0])>1e-8}) {throw CirclrError("공유 구간마다 템포가 달라 분할·복제 위치를 보존할 수 없습니다. 템포 추종을 사용하거나 이동 박을 지정하세요")}
        return seconds*(clip.followsTempo ? clip.sourceBPM:tempos[0])/60
    }
    private static func consumerTempos(pattern:RhythmPattern,in p:Project)throws->[Double] {
        var tempos:[Double]=[]
        for arrangement in p.arrangements {for use in arrangement.uses {
            let (section,context,clock)=try ArrangementCompiler.context(project:p,use:use,arrangementID:arrangement.id)
            if let graph=try SectionGraphEditing.effective(section:section,use:use) {
                for node in graph.nodes {
                    guard case .rhythmAudio(let track)=node.content,track==pattern.trackID else{continue}
                    let resolved=try ContextResolver.inheriting(global:p.global,parent:context,settings:node.settings)
                    guard resolved.rhythm.patternID==pattern.id else{continue}
                    if node.settings.tempo.source == .inherit,clock.tempos.contains(where:{abs($0.bpm-resolved.tempo)>1e-8}) {throw CirclrError("공유 오디오의 템포 변경 구간에서는 분할·기본 복제를 보존할 수 없습니다")}
                    tempos.append(resolved.tempo)
                }
            } else if context.rhythm.patternID==pattern.id {
                guard !clock.tempos.contains(where:{abs($0.bpm-context.tempo)>1e-8}) else{throw CirclrError("공유 오디오의 템포 변경 구간에서는 분할·기본 복제를 보존할 수 없습니다")}
                tempos.append(context.tempo)
            }
        }}
        guard !tempos.isEmpty,tempos.allSatisfy({$0.isFinite && $0>0}) else{throw CirclrError("공유 오디오가 사용되는 템포 문맥을 찾을 수 없습니다")}
        return tempos
    }
}
