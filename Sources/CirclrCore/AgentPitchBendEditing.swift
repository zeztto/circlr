import Foundation

public struct AgentPitchBendChange:Codable {
    public var kind:String
    public var beat:Double?
    public var rawValue:Int?
    public var range:MIDIPitchBendRange?
    public var index:Int?
    public var channel:Int?
    public init(kind:String){self.kind=kind}
    private enum CodingKeys:String,CodingKey {case kind,beat,rawValue,range,index,channel}
    private struct Key:CodingKey {
        var stringValue:String;var intValue:Int?{nil}
        init?(stringValue:String){self.stringValue=stringValue}
        init?(intValue:Int){return nil}
    }
    public init(from decoder:Decoder)throws {
        let raw=try decoder.container(keyedBy:Key.self)
        let allowed:Set<String>=["kind","beat","rawValue","range","index","channel"]
        guard raw.allKeys.allSatisfy({allowed.contains($0.stringValue)}) else{throw CirclrError("알 수 없는 피치 벤드 change 필드입니다")}
        let c=try decoder.container(keyedBy:CodingKeys.self)
        kind=try c.decode(String.self,forKey:.kind)
        beat=try c.decodeIfPresent(Double.self,forKey:.beat);rawValue=try c.decodeIfPresent(Int.self,forKey:.rawValue)
        range=try c.decodeIfPresent(MIDIPitchBendRange.self,forKey:.range);index=try c.decodeIfPresent(Int.self,forKey:.index);channel=try c.decodeIfPresent(Int.self,forKey:.channel)
        guard try raw.allKeys.allSatisfy({try !raw.decodeNil(forKey:$0)}) else{throw CirclrError("피치 벤드 change에는 null을 지정할 수 없습니다")}
    }
    public func resolved()throws->MIDIPitchBendEditing.Change {
        func invalid()->CirclrError {CirclrError("피치 벤드 change의 종류와 필드를 확인하세요")}
        switch kind {
        case "insert","update":
            guard channel==nil,let beat,(rawValue==nil) != (range==nil),kind=="update" ? index != nil:index==nil else{throw invalid()}
            let event=MIDIPitchBendEvent(beat:beat,kind:rawValue.map{.value($0)} ?? .range(range!))
            return kind=="insert" ? .insert(event):.update(index:index!,event:event)
        case "remove":guard let index,beat==nil,rawValue==nil,range==nil,channel==nil else{throw invalid()};return .remove(index:index)
        case "setInitial":guard let channel,let rawValue,let range,index==nil,beat==nil else{throw invalid()};return .setInitial(channel:channel,value:rawValue,range:range)
        case "clear":guard beat==nil,rawValue==nil,range==nil,index==nil,channel==nil else{throw invalid()};return .clear
        default:throw invalid()
        }
    }
}

/// Agent addresses stay explicit so a background edit never follows UI selection.
public enum AgentPitchBendEditing {
    public static func apply(_ op:AgentOperation,in project:inout Project)throws {
        guard let requestChange=op.change,op.nodeID==nil,op.compositionID==nil,op.clipID==nil else{throw CirclrError("피치 벤드 change와 명확한 MIDI 주소가 필요합니다")}
        let change=try requestChange.resolved()
        if let patternID=op.patternID {
            guard op.arrangementID==nil,op.useID==nil,op.laneID==nil,op.original==nil,
                  let trackID=op.trackID,let i=project.patterns.firstIndex(where:{$0.id==patternID && $0.trackID==trackID}) else{throw CirclrError("공유 피치 벤드는 patternID·trackID만 지정하세요")}
            let result=try MIDIPitchBendEditing.apply(change,to:project.patterns[i].pitchBend)
            project.patterns[i].pitchBend=result.sequence
            try MIDIPitchBendStorage.promote(in:&project)
        }else{
            guard op.trackID==nil,let arrangementID=op.arrangementID,project.activeArrangementID==arrangementID,
                  let useID=op.useID,let laneID=op.laneID,let original=op.original,
                  let use=project.active.uses.first(where:{$0.id==useID}),
                  let section=project.sections.first(where:{$0.id==use.sectionID}) else{throw CirclrError("arrangementID·useID·laneID·original을 지정하세요")}
            let lanes=original ? section.lanes:try ArrangementCompiler.effectiveLanes(section:section,use:use)
            guard var lane=lanes.first(where:{$0.id==laneID}) else{throw CirclrError("MIDI 원본 주소를 찾을 수 없습니다")}
            lane.pitchBend=try MIDIPitchBendEditing.apply(change,to:lane.pitchBend).sequence
            try ProjectEditing.setLane(lane,for:useID,original:original,in:&project)
        }
    }
}
