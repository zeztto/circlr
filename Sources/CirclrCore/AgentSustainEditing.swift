import Foundation

public struct AgentSustainChange:Codable {
    public var kind:String
    public var beat:Double?
    public var rawValue:Int?
    public var index:Int?
    public var channel:Int?
    public init(kind:String){self.kind=kind}
    private enum CodingKeys:String,CodingKey {case kind,beat,rawValue,index,channel}
    private struct Key:CodingKey {var stringValue:String;var intValue:Int?{nil};init?(stringValue:String){self.stringValue=stringValue};init?(intValue:Int){return nil}}
    public init(from decoder:Decoder)throws {
        let raw=try decoder.container(keyedBy:Key.self)
        let allowed:Set<String>=["kind","beat","rawValue","index","channel"]
        guard try raw.allKeys.allSatisfy({key in guard allowed.contains(key.stringValue) else{return false};return try !raw.decodeNil(forKey:key)}) else{throw CirclrError("알 수 없는 sustainChange 필드 또는 null입니다")}
        let c=try decoder.container(keyedBy:CodingKeys.self)
        kind=try c.decode(String.self,forKey:.kind)
        beat=try c.decodeIfPresent(Double.self,forKey:.beat);rawValue=try c.decodeIfPresent(Int.self,forKey:.rawValue)
        index=try c.decodeIfPresent(Int.self,forKey:.index);channel=try c.decodeIfPresent(Int.self,forKey:.channel)
    }
    public func resolved()throws->MIDISustainEditing.Change {
        func invalid()->CirclrError {CirclrError("sustainChange 종류와 필드를 확인하세요")}
        switch kind {
        case "insert","update":
            guard let beat,let rawValue,channel==nil,kind=="update" ? index != nil:index==nil else{throw invalid()}
            let event=MIDISustainEvent(beat:beat,rawValue:rawValue)
            return kind=="insert" ? .insert(event):.update(index:index!,event:event)
        case "remove":guard let index,beat==nil,rawValue==nil,channel==nil else{throw invalid()};return .remove(index:index)
        case "setInitial":guard let channel,let rawValue,beat==nil,index==nil else{throw invalid()};return .setInitial(channel:channel,value:rawValue)
        case "clear":guard beat==nil,rawValue==nil,index==nil,channel==nil else{throw invalid()};return .clear
        default:throw invalid()
        }
    }
}

public enum AgentSustainEditing {
    public static func apply(_ op:AgentOperation,in project:inout Project)throws {
        let keys=try JSONSerialization.jsonObject(with:JSONEncoder().encode(op)) as? [String:Any] ?? [:]
        let allowed:Set<String>=["kind","arrangementID","useID","laneID","original","patternID","trackID","sustainChange"]
        guard op.kind=="edit_sustain",Set(keys.keys).isSubset(of:allowed),let requested=op.sustainChange else{throw CirclrError("edit_sustain 주소와 sustainChange를 확인하세요")}
        let change=try requested.resolved()
        func edited(_ sequence:MIDISustainSequence?,bend:MIDIPitchBendSequence?)throws->MIDISustainSequence? {
            try MIDISustainStorage.validate(sustain:sequence,pitchBend:bend)
            // New insert follows the existing source's controller channel. Other nil operations retain helper semantics.
            let source=sequence ?? (requested.kind=="insert" ? MIDISustainSequence(channel:bend?.channel ?? 0):nil)
            return try MIDISustainEditing.apply(change,to:source).sequence
        }
        var candidate=project
        if let patternID=op.patternID {
            guard op.arrangementID==nil,op.useID==nil,op.laneID==nil,op.original==nil,
                  let trackID=op.trackID,let i=candidate.patterns.firstIndex(where:{$0.id==patternID && $0.trackID==trackID}) else{throw CirclrError("공유 sustain은 patternID·trackID만 지정하세요")}
            let previous=candidate.patterns[i].sustain
            let next=try edited(previous,bend:candidate.patterns[i].pitchBend)
            guard next != previous else{return}
            candidate.patterns[i].sustain=next
            try MIDISustainStorage.promote(in:&candidate)
        } else {
            guard op.trackID==nil,let arrangementID=op.arrangementID,
                  candidate.arrangements.contains(where:{$0.id==arrangementID}),let useID=op.useID,let laneID=op.laneID,let original=op.original else{throw CirclrError("arrangementID·useID·laneID·original을 지정하세요")}
            let active=candidate.activeArrangementID;candidate.activeArrangementID=arrangementID
            guard let use=candidate.active.uses.first(where:{$0.id==useID}),let section=candidate.sections.first(where:{$0.id==use.sectionID}) else{throw CirclrError("대상 섹션이 없습니다")}
            let lanes=original ? section.lanes:try ArrangementCompiler.effectiveLanes(section:section,use:use)
            guard var lane=lanes.first(where:{$0.id==laneID}) else{throw CirclrError("MIDI lane 주소를 찾을 수 없습니다")}
            let next=try edited(lane.sustain,bend:lane.pitchBend)
            guard next != lane.sustain else{return}
            lane.sustain=next
            try ProjectEditing.setLane(lane,for:useID,original:original,in:&candidate)
            candidate.activeArrangementID=active
        }
        project=candidate
    }
}
