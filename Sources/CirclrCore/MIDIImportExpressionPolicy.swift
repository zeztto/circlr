import Foundation

/// File adapters must omit expression explicitly before constructing Core parts.
public enum MIDIImportExpressionPolicy:String,Codable,CaseIterable {case preserve,omit}

struct MIDIImportExtent {
    let noteEndBeat:Double
    let lastExpressionBeat:Double?
    var endBeat:Double {max(noteEndBeat,lastExpressionBeat ?? noteEndBeat)}
    let initialClock:MusicClock
    let clock:MusicClock
    let bars:Int
    let barsOverride:Int?
    let section:Section
    static func resolve(_ parts:[MIDIImportPart],useID:ID,extendSection:Bool,atBeat:Double,in project:Project)throws->Self {
        guard !parts.isEmpty,parts.count<=256,parts.reduce(0,{$0+$1.notes.count})<=100000,
              let use=project.active.uses.first(where:{$0.id==useID}) else{throw CirclrError("가져올 MIDI와 대상 섹션을 확인하세요")}
        guard parts.reduce(0,{$0+($1.pitchBend?.events.count ?? 0)})<=1_000_000 else{throw CirclrError("가져올 피치 벤드 이벤트 합계가 1,000,000개를 넘습니다")}
        var lastExpression:Double?
        for part in parts {
            guard !part.notes.isEmpty,!part.name.isEmpty,part.name.count<=1024 else{throw CirclrError("트랙 이름과 MIDI 노트가 필요합니다")}
            for note in part.notes {try ArrangementCompiler.validateNote(note)}
            if let expression=part.pitchBend {
                try expression.validate()
                guard !part.drums else{throw CirclrError("드럼 트랙의 피치 벤드 가져오기는 아직 지원하지 않습니다. 표현 제외를 선택하세요")}
                let end=atBeat+(expression.events.last?.beat ?? 0)
                guard end.isFinite,end<=131072 else{throw CirclrError("이동한 피치 벤드 위치가 131072박 한도를 넘습니다")}
                lastExpression=max(lastExpression ?? end,end)
            }
        }
        let noteEnd=atBeat+(parts.flatMap(\.notes).map{$0.beat+$0.length}.max() ?? 0)
        let (section,_,initial)=try ArrangementCompiler.context(project:project,use:use,arrangementID:project.activeArrangementID)
        guard atBeat.isFinite,atBeat>=0,atBeat<initial.beats,noteEnd.isFinite,noteEnd>atBeat,noteEnd<=131072 else{throw CirclrError("MIDI 시작 위치와 길이 한도를 확인하세요")}
        func contains(_ clock:MusicClock)->Bool {clock.beats+1e-8>=noteEnd && (lastExpression.map{$0<clock.beats} ?? true)}
        var extended=use,bars=use.barsOverride ?? section.bars,clock=initial
        if !contains(clock) {
            guard extendSection else{throw CirclrError("MIDI 연주 또는 마지막 피치 벤드가 섹션 끝에 닿거나 넘습니다. 섹션 길이 늘리기를 선택하세요")}
            while !contains(clock),bars<1024 {bars+=1;extended.barsOverride=bars;clock=try ArrangementCompiler.context(project:project,use:extended,arrangementID:project.activeArrangementID).2}
            guard contains(clock) else{throw CirclrError("MIDI 연주를 최대 1,024마디 안에 배치할 수 없습니다")}
        }
        return Self(noteEndBeat:noteEnd,lastExpressionBeat:lastExpression,initialClock:initial,clock:clock,bars:bars,barsOverride:extended.barsOverride,section:section)
    }
}
