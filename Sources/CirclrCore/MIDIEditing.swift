import Foundation

/// Batch edits preserve note identities and the relative shape of a selection.
public enum MIDIEditing {
    public enum Change {
        case transpose(Int), move(Double), quantize(subdivisions:Int,strength:Double)
        case velocity(Int), duplicate(Double), delete
    }
    public static func apply(_ change:Change,to lane:Lane,ids:Set<ID>,beats:Double)throws->Lane {
        guard beats.isFinite,beats>0,beats<=131072,!ids.isEmpty,ids.isSubset(of:Set(lane.notes.map(\.id))) else {throw CirclrError("편집할 MIDI 노트와 서클 길이를 확인하세요")}
        var result=lane
        let selected=lane.notes.filter{ids.contains($0.id)}
        if case .delete=change {result.notes.removeAll{ids.contains($0.id)};return result}
        func changed(_ note:Note)throws->Note {
            var n=note
            switch change {
            case .transpose(let delta):
                guard (-127...127).contains(delta),(0...127).contains(n.pitch+delta) else {throw CirclrError("음정 간격을 유지하려면 MIDI 0–127 안에서 이동하세요")}
                n.pitch+=delta
            case .move(let delta),.duplicate(let delta):
                guard delta.isFinite,abs(delta)<=131072,n.beat+delta>=0,n.beat+delta<beats,n.beat+delta+n.length<=beats+1e-8 else {throw CirclrError("선택한 노트가 서클 길이를 넘습니다. 길이를 늘리거나 이동 간격을 줄이세요")}
                n.beat+=delta
            case .quantize(let subdivisions,let strength):
                guard StepGrid.resolutions.contains(subdivisions),strength.isFinite,(0...1).contains(strength) else {throw CirclrError("퀀타이즈 분할과 강도를 확인하세요")}
                if strength==0 {return n}
                let target=(n.beat*Double(subdivisions)).rounded()/Double(subdivisions)
                n.beat=max(0,min(max(0,beats-n.length),n.beat+(target-n.beat)*strength))
            case .velocity(let value):
                guard (1...127).contains(value) else {throw CirclrError("MIDI 세기는 1–127입니다")};n.velocity=value
            case .delete:break
            }
            try ArrangementCompiler.validateNote(n);return n
        }
        if case .duplicate=change {
            guard result.notes.count+selected.count<=100000 else {throw CirclrError("MIDI 노트 한도를 넘습니다")}
            for note in selected {var n=try changed(note);n.id=newID();result.notes.append(n)}
        } else {
            for i in result.notes.indices where ids.contains(result.notes[i].id) {result.notes[i]=try changed(result.notes[i])}
        }
        return result
    }
}

public struct MIDIImportPart {
    public var name:String
    public var notes:[Note]
    public var drums:Bool
    public init(name:String,notes:[Note],drums:Bool=false){self.name=name;self.notes=notes;self.drums=drums}
}
public enum MIDIImportEditing {
    /// Adds independent MIDI circles to one use in a single transaction, preserving all existing lanes.
    public static func apply(_ parts:[MIDIImportPart],useID:ID,extendSection:Bool,atBeat:Double=0,position:Point?=nil,in project:inout Project)throws->[ID] {
        guard !parts.isEmpty,parts.count<=256,parts.reduce(0,{$0+$1.notes.count})<=100000 else {throw CirclrError("가져올 트랙과 노트 수를 확인하세요")}
        var p=project;let previousSignalPositions=p.signal.layout.positions
        guard let useIndex=p.active.uses.firstIndex(where:{$0.id==useID}) else {throw CirclrError("대상 섹션을 찾을 수 없습니다")}
        for part in parts {guard !part.notes.isEmpty,!part.name.isEmpty,part.name.count<=1024 else {throw CirclrError("트랙 이름과 MIDI 노트가 필요합니다")};for note in part.notes {try ArrangementCompiler.validateNote(note)}}
        let extent=atBeat+(parts.flatMap(\.notes).map{$0.beat+$0.length}.max() ?? 0)
        guard extent<=131072 else {throw CirclrError("MIDI 길이 한도를 넘습니다")}
        var use=p.active.uses[useIndex]
        let (section,_,initial)=try ArrangementCompiler.context(project:p,use:use)
        guard atBeat.isFinite,atBeat>=0,atBeat<initial.beats else {throw CirclrError("MIDI 시작 위치는 현재 섹션 안으로 지정하세요")}
        if let position {guard position.x.isFinite,position.y.isFinite else {throw CirclrError("MIDI 서클 배치 위치를 확인하세요")}}
        if extent>initial.beats+1e-8 {
            guard extendSection else {throw CirclrError("MIDI가 섹션보다 깁니다. 섹션 길이 늘리기를 선택하세요")}
            var bars=use.barsOverride ?? section.bars,clock=initial
            while clock.beats+1e-8<extent,bars<1024 {bars+=1;use.barsOverride=bars;clock=try ArrangementCompiler.context(project:p,use:use).2}
            guard clock.beats+1e-8>=extent else {throw CirclrError("MIDI 길이가 최대 1,024마디를 넘습니다")}
            p.arrangements[p.activeIndex].uses[useIndex].barsOverride=bars
        }
        var ids:[ID]=[]
        for (index,part) in parts.enumerated() {
            let track=p.addTrack(name:part.name,drums:part.drums)
            var lane=Lane(trackID:track);lane.notes=part.notes.map{var n=$0;n.id=newID();n.beat+=atBeat;return n}
            try ProjectEditing.setLane(lane,for:useID,original:false,in:&p);ids.append(lane.id)
            if let position,!p.usesOrbits,let definition=p.sections.first(where:{$0.id==section.id}),
               var graph=try SectionGraphEditing.effective(section:definition,use:p.active.uses[useIndex]) {
                graph.layout.positions["midi:\(lane.id)"]=Point(position.x+Double(index%4)*220,position.y+Double(index/4)*220)
                try SectionGraphEditing.set(graph,useID:useID,original:false,in:&p)
            }
        }
        p.signal.layout.positions.merge(previousSignalPositions){_,previous in previous}
        try ProjectStore.validateStructure(p);project=p;return ids
    }
}
