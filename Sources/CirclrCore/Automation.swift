import Foundation

public enum AutomationParameter:String,Codable,CaseIterable {case gain,pan
    public var neutral:Double {self == .gain ? 1:0}
    public var range:ClosedRange<Double> {self == .gain ? 0...4 : -1...1}
    public var label:String {self == .gain ? "볼륨":"팬"}
}
public enum AutomationShape:String,Codable,CaseIterable {case linear,hold}
public struct AutomationPoint:Codable,Equatable,Identifiable {
    public var id:ID=newID()
    public var beat:Double
    public var value:Double
    public var shape:AutomationShape = .linear
    public init(beat:Double,value:Double,shape:AutomationShape = .linear){self.beat=beat;self.value=value;self.shape=shape}
    enum CodingKeys:String,CodingKey {case id,beat,value,shape}
    public init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decodeIfPresent(ID.self,forKey:.id) ?? newID();beat=try c.decode(Double.self,forKey:.beat);value=try c.decode(Double.self,forKey:.value);shape=try c.decodeIfPresent(AutomationShape.self,forKey:.shape) ?? .linear
    }
}
public struct AutomationLane:Codable,Equatable {
    public var parameter:AutomationParameter
    public var enabled:Bool=true
    public var points:[AutomationPoint]
    public init(parameter:AutomationParameter,points:[AutomationPoint],enabled:Bool=true){self.parameter=parameter;self.points=points;self.enabled=enabled}
    private func index(at beat:Double)->Int {
        var lo=0,hi=points.count
        while lo<hi {let m=(lo+hi)/2;if points[m].beat<=beat {lo=m+1}else{hi=m}}
        return lo-1
    }
    public func value(at beat:Double)->Double {
        guard let first=points.first,let last=points.last else{return parameter.neutral}
        if beat<=first.beat{return first.value};if beat>=last.beat{return last.value}
        let i=max(0,index(at:beat)),a=points[i],b=points[i+1]
        return a.shape == .hold ? a.value:a.value+(b.value-a.value)*(beat-a.beat)/(b.beat-a.beat)
    }
    public func shape(at beat:Double)->AutomationShape {
        let i=index(at:beat);return i>=0 && i<points.count-1 ? points[i].shape:.hold
    }
}
public extension MusicCircle {
    var supportsAutomation:Bool {content.output != .midi}
}
public struct AutomationSpan {
    public var start:Double,end:Double,from:Double,to:Double
    public var shape:AutomationShape
    public func value(at seconds:Double)->Double {
        if seconds>=end{return to}
        return shape == .hold ? from:from+(to-from)*max(0,seconds-start)/(end-start)
    }
}
public struct AutomationPlan {
    public var parameter:AutomationParameter
    public var spans:[AutomationSpan]
}
public enum AutomationCompiler {
    /// Editing uses the same local beat clock for sources and processing circles.
    public static func editingClock(_ node:MusicCircle,context:MusicContext,parent:MusicClock)throws->MusicClock {
        try validate(node)
        return try MusicClock(parent:parent,start:node.startBeat,length:node.lengthBeats ?? parent.beats,context:context,
                              inheritTempo:node.settings.tempo.source == .inherit,inheritMeter:node.settings.meter.source == .inherit)
    }
    public static func validate(_ node:MusicCircle)throws {
        let lanes=node.automation ?? []
        guard node.startBeat.isFinite,node.startBeat>=0,node.lengthBeats.map({$0.isFinite && $0>0 && $0<=1_048_576}) ?? true,
              (1...256).contains(node.repeatCount),lanes.isEmpty || node.supportsAutomation,lanes.count<=2,Set(lanes.map(\.parameter)).count==lanes.count else {throw CirclrError("오토메이션의 서클 시간과 오디오 신호의 볼륨·팬 대상을 확인하세요")}
        for lane in lanes {
            guard !lane.points.isEmpty,lane.points.count<=4096,Set(lane.points.map(\.id)).count==lane.points.count,
                  lane.points.allSatisfy({!$0.id.isEmpty && $0.id.count<=128 && $0.beat.isFinite && (0...1_048_576).contains($0.beat) && $0.value.isFinite && lane.parameter.range.contains($0.value)}),
                  zip(lane.points,lane.points.dropFirst()).allSatisfy({$0.beat<$1.beat}),
                  lane.points.count*node.repeatCount<=65536 else {throw CirclrError("오토메이션 점의 ID·시간·값·반복 크기를 확인하세요")}
        }
    }
    /// Piecewise seconds include tempo boundaries so linear interpolation remains linear in beats.
    public static func compile(_ node:MusicCircle,context:MusicContext,clock:MusicClock)throws->[AutomationPlan] {
        try validate(node)
        let lanes=(node.automation ?? []).filter(\.enabled)
        guard !lanes.isEmpty else{return []}
        try ContextResolver.validate(context)
        let own=node.settings.tempo.source != .inherit,offset=clock.seconds(at:node.startBeat)
        func time(_ q:Double)->Double {own ? offset+q*60/context.tempo:clock.seconds(at:node.startBeat+q)}
        func beat(_ t:Double)->Double {own ? (t-offset)*context.tempo/60:clock.beat(atSeconds:t)-node.startBeat}
        return try lanes.map { lane in
            var boundaries:Set<Double>=[0,clock.seconds]
            func add(_ t:Double){if t>0 && t<clock.seconds{boundaries.insert(t)}}
            add(offset)
            if !own {for tempo in clock.tempos {add(clock.seconds(at:tempo.beat))}}
            if let length=node.lengthBeats {
                for i in 0..<node.repeatCount {
                    let start=Double(i)*length;add(time(start));add(time(start+length))
                    for p in lane.points where p.beat<=length {add(time(start+p.beat))}
                }
            } else {for p in lane.points {add(time(p.beat))}}
            guard boundaries.count<=131072 else{throw CirclrError("오토메이션 시간 구간이 너무 많습니다")}
            let times=boundaries.sorted()
            let spans=zip(times,times.dropFirst()).map { a,b -> AutomationSpan in
                let mid=beat((a+b)/2);let qa:Double,qb:Double
                if mid<0 {qa=0;qb=0}
                else if let length=node.lengthBeats {
                    if mid>=length*Double(node.repeatCount) {qa=length;qb=length}
                    else {let cycle=floor(mid/length)*length;qa=max(0,beat(a)-cycle);qb=min(length,beat(b)-cycle)}
                } else {qa=max(0,beat(a));qb=max(0,beat(b))}
                return AutomationSpan(start:a,end:b,from:lane.value(at:qa),to:lane.value(at:qb),shape:lane.shape(at:(qa+qb)/2))
            }
            return AutomationPlan(parameter:lane.parameter,spans:spans)
        }
    }
}
public enum AutomationEditing {
    public static func set(parameter:AutomationParameter,points:[AutomationPoint]?=nil,enabled:Bool?=nil,nodeID:ID,useID:ID,original:Bool=false,in project:inout Project)throws {
        guard points != nil || enabled != nil,let use=project.active.uses.first(where:{$0.id==useID}),let section=project.sections.first(where:{$0.id==use.sectionID}),
              var graph=try original ? section.graph:SectionGraphEditing.effective(section:section,use:use),let i=graph.nodes.firstIndex(where:{$0.id==nodeID}),graph.nodes[i].supportsAutomation else {throw CirclrError("오디오 신호 서클과 오토메이션 편집 내용을 지정하세요")}
        var lanes=graph.nodes[i].automation ?? []
        if let points,points.isEmpty {lanes.removeAll{$0.parameter==parameter}}
        else if let li=lanes.firstIndex(where:{$0.parameter==parameter}) {
            if let points {lanes[li].points=points.sorted{$0.beat<$1.beat}}
            if let enabled {lanes[li].enabled=enabled}
        } else {
            guard let points else{throw CirclrError("먼저 오토메이션 점을 추가하세요")}
            lanes.append(AutomationLane(parameter:parameter,points:points.sorted{$0.beat<$1.beat},enabled:enabled ?? true))
        }
        let value=lanes.isEmpty ? nil:lanes.sorted{$0.parameter.rawValue<$1.parameter.rawValue}
        if value==graph.nodes[i].automation{return}
        graph.nodes[i].automation=value
        try AutomationCompiler.validate(graph.nodes[i])
        try SectionGraphEditing.set(graph,useID:useID,original:original,in:&project)
    }
}
