import Foundation

public struct AudioImportTrackChoice:Equatable {
    public var trackID:ID?
    public var name:String
    public var detail:String
}

public enum AudioImportPlacement {
    public static func trackLabel(_ id:ID?,in project:Project)->String {
        guard let id else{return "새 트랙"}
        guard let index=project.tracks.firstIndex(where:{$0.id==id}) else{return "삭제된 트랙"}
        return "\(index+1) · \(project.tracks[index].name)"
    }
    public static func beat(_ target:AudioImportDestination)->Double {
        switch target {case .pattern(_,let beat),.section(_,_,_,let beat,_,_):return beat}
    }
    public static func clock(_ target:AudioImportDestination,in project:Project)throws->MusicClock {
        switch target {
        case .pattern(let id,_):
            guard let pattern=project.patterns.first(where:{$0.id==id}) else{throw CirclrError("대상 리듬 패턴을 찾을 수 없습니다")}
            return try MusicClock(beats:pattern.length,context:project.global)
        case .section(let a,let u,let track,_,_,_):
            guard let use=project.arrangements.first(where:{$0.id==a})?.uses.first(where:{$0.id==u}),
                  track==nil || project.tracks.contains(where:{$0.id==track}) else{throw CirclrError("대상 섹션과 트랙을 확인하세요")}
            return try ArrangementCompiler.context(project:project,use:use,arrangementID:a).2
        }
    }
    public static func start(_ beat:Double,of target:AudioImportDestination,in project:Project)throws->AudioImportDestination {
        let clock=try clock(target,in:project)
        guard beat.isFinite,beat>=0,beat<clock.beats else{throw CirclrError("시작 위치는 대상 섹션 또는 패턴의 길이 안으로 지정하세요")}
        switch target {
        case .pattern(let id,_):return .pattern(id:id,beat:beat)
        case .section(let a,let u,let t,_,let p,let original):return .section(arrangementID:a,useID:u,trackID:t,beat:beat,position:p,original:original)
        }
    }
    public static func track(_ id:ID?,of target:AudioImportDestination,in project:Project)throws->AudioImportDestination {
        guard case .section(let a,let u,_,let beat,let p,let original)=target else{throw CirclrError("리듬 패턴의 트랙은 여기에서 변경할 수 없습니다")}
        let result=AudioImportDestination.section(arrangementID:a,useID:u,trackID:id,beat:beat,position:p,original:original)
        return try start(beat,of:result,in:project)
    }
    public static func sections(_ routes:[StudioSectionRoute],query:String)->[StudioSectionRoute] {
        let terms=folded(query).split(whereSeparator:{$0.isWhitespace})
        return routes.filter{route in let text=folded(route.path+" "+route.name);return terms.allSatisfy{text.contains($0)}}
    }
    public static func tracks(for target:AudioImportDestination,in project:Project,query:String)throws->[AudioImportTrackChoice] {
        _=try clock(target,in:project)
        guard case .section(let a,let u,_,_,_,let original)=target,
              let use=project.arrangements.first(where:{$0.id==a})?.uses.first(where:{$0.id==u}),
              let section=project.sections.first(where:{$0.id==use.sectionID}) else{throw CirclrError("오디오를 넣을 섹션을 선택하세요")}
        let lanes=original ? section.lanes:try ArrangementCompiler.effectiveLanes(section:section,use:use)
        let byTrack=Dictionary(grouping:lanes,by:\.trackID)
        let terms=folded(query).split(whereSeparator:{$0.isWhitespace})
        func matches(_ text:String)->Bool {let text=folded(text);return terms.allSatisfy{text.contains($0)}}
        var choices:[AudioImportTrackChoice]=[]
        if matches("새 트랙") {choices.append(.init(trackID:nil,name:"새 트랙",detail:"선택한 오디오를 새 트랙에 배치"))}
        for (index,track) in project.tracks.enumerated() {
            let number="\(index+1)번 트랙"
            guard matches(track.name+" "+number) else{continue}
            let lanes=byTrack[track.id] ?? [],audio=lanes.reduce(0){$0+$1.audio.count},notes=lanes.reduce(0){$0+$1.notes.count}
            let usage=audio==0 && notes==0 ? "이 섹션에서 아직 사용하지 않음":"오디오 \(audio)개 · MIDI 노트 \(notes)개"
            choices.append(.init(trackID:track.id,name:track.name,detail:number+" · "+usage))
        }
        return choices
    }
    private static func folded(_ value:String)->String {
        value.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX")).precomposedStringWithCanonicalMapping
    }
}
