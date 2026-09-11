import Foundation

public enum CirclePortDirection:String,Codable,Sendable {case input,output}
public enum CirclePortSignal:String,Codable,Sendable {case audio,midi,flow}
public enum CirclePortPolicy:String,Codable,Sendable {case audioSum,midiMerge,route,broadcast}

/// Describes an implemented engine endpoint. Display octants never create extra buses.
public struct CirclePort:Codable,Equatable,Identifiable,Sendable {
    public let id:String
    public let direction:CirclePortDirection
    public let signal:CirclePortSignal
    public let name:String
    public let policy:CirclePortPolicy
    public var bindingTarget:CirclePortEndpoint? = nil
    public var bindingIndex:Int? = nil
    public var isSidechain:Bool {(bindingTarget?.portID ?? id)==Self.sidechainInput}
    public static let audioInput="in.audio.main",audioOutput="out.audio.main",sidechainInput="in.audio.sidechain"
    public static let midiInput="in.midi.main",midiOutput="out.midi.main"
    public static let flowInput="in.flow.previous",flowOutput="out.flow.next"
    public var defaultOctant:PortOctant {direction == .input ? .west:.east}
    private static func pair(_ signal:CirclePortSignal,input:Bool,output:Bool,sidechain:Bool=false)->[CirclePort] {
        let inputID=signal == .audio ? audioInput:signal == .midi ? midiInput:flowInput
        let outputID=signal == .audio ? audioOutput:signal == .midi ? midiOutput:flowOutput
        let label=signal == .audio ? "오디오 메인 · 스테레오":signal == .midi ? "MIDI 연주":"재생 경로"
        let policy:CirclePortPolicy=signal == .audio ? .audioSum:signal == .midi ? .midiMerge:.route
        var result:[CirclePort]=[]
        if input {result.append(.init(id:inputID,direction:.input,signal:signal,name:"IN \(label)",policy:policy))}
        if sidechain {result.append(.init(id:sidechainInput,direction:.input,signal:.audio,name:"IN 사이드체인 · 스테레오",policy:.audioSum))}
        if output {result.append(.init(id:outputID,direction:.output,signal:signal,name:"OUT \(label)",policy:signal == .flow ? .route:.broadcast))}
        return result
    }
    public static func ports(for content:MusicCircleContent)->[CirclePort] {
        switch content {
        case .midi,.rhythmMIDI:return pair(.midi,input:false,output:true)
        case .audio,.rhythmAudio:return pair(.audio,input:false,output:true)
        case .instrument:return pair(.midi,input:true,output:false)+pair(.audio,input:false,output:true)
        case .effect(let effect):return pair(.audio,input:true,output:true,sidechain:effect.kind == .compressor)
        case .mix:return pair(.audio,input:true,output:true)
        case .router:
            return AudioRouter.inputs.enumerated().map { .init(id:$0.element,direction:.input,signal:.audio,name:"IN \($0.offset+1) · 스테레오",policy:.audioSum) } +
                AudioRouter.outputs.enumerated().map { .init(id:$0.element,direction:.output,signal:.audio,name:"OUT \($0.offset+1) · 스테레오",policy:.broadcast) }
        case .output:return pair(.audio,input:true,output:false)
        }
    }
    public static func ports(for node:SignalNode)->[CirclePort] {
        pair(.audio,input:node.kind != .source,output:node.kind != .master,sidechain:node.kind == .effect && node.effect.kind == .compressor)
    }
    public static var flowPorts:[CirclePort] {pair(.flow,input:true,output:true)}
}

public struct CirclePortEndpoint:Codable,Hashable,Sendable {
    public var node:CircleAddress
    public var portID:String
    public init(node:CircleAddress,portID:String){self.node=node;self.portID=portID}
}
/// Includes logical owner addresses: reused sections can share edge IDs without sharing placement.
public struct CircleConnectionID:Codable,Hashable,Sendable {
    public var edgeID:ID
    public var from:CircleAddress
    public var to:CircleAddress
    public init(edgeID:ID,from:CircleAddress,to:CircleAddress){self.edgeID=edgeID;self.from=from;self.to=to}
}
public struct CirclePortConnection:Codable,Equatable,Sendable {
    public var id:CircleConnectionID
    public var from:CirclePortEndpoint
    public var to:CirclePortEndpoint
    public var signal:CirclePortSignal
    public var gain:Double
    public var sidechain:Bool {to.portID==CirclePort.sidechainInput}
    init(edgeID:ID,from:CircleAddress,to:CircleAddress,signal:CirclePortSignal,sidechain:Bool=false,gain:Double=1,fromPortID:String?=nil,toPortID:String?=nil) {
        id = .init(edgeID:edgeID,from:from,to:to);self.signal=signal;self.gain=gain
        self.from = .init(node:from,portID:fromPortID ?? (signal == .audio ? CirclePort.audioOutput:signal == .midi ? CirclePort.midiOutput:CirclePort.flowOutput))
        self.to = .init(node:to,portID:toPortID ?? (sidechain ? CirclePort.sidechainInput:signal == .audio ? CirclePort.audioInput:signal == .midi ? CirclePort.midiInput:CirclePort.flowInput))
    }
}
public struct NormalizedPortConnection:Equatable,Sendable {
    public let from:CirclePortEndpoint,to:CirclePortEndpoint
    public let signal:CirclePortSignal
    public var sidechain:Bool {to.portID==CirclePort.sidechainInput}
}

public enum CirclePortCatalog {
    public static func ports(at address:CircleAddress,in project:Project)throws->[CirclePort] {
        switch address {
        case .signal(let id):
            guard let node=project.signal.nodes.first(where:{$0.id==id}) else{throw CirclrError("사운드 서클을 찾을 수 없습니다")}
            return CirclePort.ports(for:node)
        case .music(let ai,let ui,let id):
            guard let use=project.arrangements.first(where:{$0.id==ai})?.uses.first(where:{$0.id==ui}),let section=project.sections.first(where:{$0.id==use.sectionID}),let node=try SectionGraphEditing.effective(section:section,use:use)?.nodes.first(where:{$0.id==id}) else{throw CirclrError("음악 서클을 찾을 수 없습니다")}
            return CirclePort.ports(for:node.content)
        case .section(let ai,let ui):
            guard project.arrangements.first(where:{$0.id==ai})?.uses.contains(where:{$0.id==ui}) == true else{throw CirclrError("섹션을 찾을 수 없습니다")}
            return CirclePort.flowPorts
        case .composition(let id):
            guard project.album?.composition(id) != nil else{throw CirclrError("곡·악장을 찾을 수 없습니다")}
            return CirclePort.flowPorts
        case .group:return try GroupPortEditing.ports(at:address,in:project)
        case .album,.sound:return []
        }
    }
    /// Orients a gesture begun at either endpoint. The graph editor still checks cycles and routes.
    public static func normalize(_ first:CirclePortEndpoint,_ second:CirclePortEndpoint,in project:Project)throws->NormalizedPortConnection {
        let first = try GroupPortEditing.resolve(first,in:project), second = try GroupPortEditing.resolve(second,in:project)
        guard first.node != second.node,
              let a=try ports(at:first.node,in:project).first(where:{$0.id==first.portID}),
              let b=try ports(at:second.node,in:project).first(where:{$0.id==second.portID}),a.direction != b.direction,a.signal==b.signal else{throw CirclrError("호환되는 OUT과 IN을 선택하세요")}
        let from=a.direction == .output ? first:second,to=a.direction == .input ? first:second
        let sameScope:Bool
        switch (from.node,to.node) {
        case (.signal,.signal):sameScope=true
        case let (.music(a,u,_),.music(b,v,_)):sameScope=a==b && u==v
        case let (.section(a,_),.section(b,_)):sameScope=a==b
        case let (.composition(a),.composition(b)):sameScope=project.album?.parent(of:a)==project.album?.parent(of:b)
        default:sameScope=false
        }
        guard sameScope else{throw CirclrError("같은 그래프의 포트를 연결하세요. 그룹 경계에는 노출 binding이 필요합니다")}
        return .init(from:from,to:to,signal:a.signal)
    }
    public static func connections(in project:Project)throws->[CirclePortConnection] {
        var result=project.signal.edges.map{CirclePortConnection(edgeID:$0.id,from:.signal($0.from),to:.signal($0.to),signal:.audio,sidechain:$0.sidechain,gain:$0.gain)}
        for arrangement in project.arrangements {
            result += arrangement.edges.map{.init(edgeID:$0.id,from:.section(arrangementID:arrangement.id,useID:$0.from),to:.section(arrangementID:arrangement.id,useID:$0.to),signal:.flow)}
            for use in arrangement.uses {
                guard let section=project.sections.first(where:{$0.id==use.sectionID}) else{throw CirclrError("섹션 원본을 찾을 수 없습니다")}
                for edge in try SectionGraphEditing.effective(section:section,use:use)?.edges ?? [] {
                    result.append(.init(edgeID:edge.id,from:.music(arrangementID:arrangement.id,useID:use.id,nodeID:edge.from),to:.music(arrangementID:arrangement.id,useID:use.id,nodeID:edge.to),signal:edge.signal == .audio ? .audio:.midi,sidechain:edge.sidechain,gain:edge.gain,fromPortID:edge.fromPortID,toPortID:edge.toPortID))
                }
            }
        }
        if let album=project.album {
            for siblings in [album.children]+album.compositions.map(\.children) {
                for (from,to) in zip(siblings,siblings.dropFirst()) {result.append(.init(edgeID:"composition-flow:\(from):\(to)",from:.composition(from),to:.composition(to),signal:.flow))}
            }
        }
        return result
    }
}
