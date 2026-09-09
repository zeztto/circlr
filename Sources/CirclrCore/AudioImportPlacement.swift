import Foundation

public enum AudioImportPlacement {
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
        func folded(_ value:String)->String {value.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX")).precomposedStringWithCanonicalMapping}
        let terms=folded(query).split(whereSeparator:{$0.isWhitespace})
        return routes.filter{route in let text=folded(route.path+" "+route.name);return terms.allSatisfy{text.contains($0)}}
    }
}
