import Foundation

public enum PortOctant:Int,Codable,CaseIterable,Sendable {
    case north=0,northeast,east,southeast,south,southwest,west,northwest
    public var label:String {["위","오른쪽 위","오른쪽","오른쪽 아래","아래","왼쪽 아래","왼쪽","왼쪽 위"][rawValue]}
}
public struct CircleConnectionPlacement:Codable,Equatable,Sendable {
    public var from:PortOctant
    public var to:PortOctant
    public init(from:PortOctant = .east,to:PortOctant = .west){self.from=from;self.to=to}
}
public struct PlacedCircleConnection:Codable,Equatable,Sendable {
    public var id:CircleConnectionID
    public var placement:CircleConnectionPlacement
    public init(id:CircleConnectionID,placement:CircleConnectionPlacement){self.id=id;self.placement=placement}
}
public struct CirclePortLayout:Codable,Equatable,Sendable {
    public var revision:Int=0
    public var connections:[PlacedCircleConnection]=[]
    public var bindings:[GroupPortBinding]?
    public init(){}
    public func placement(for id:CircleConnectionID)->CircleConnectionPlacement {connections.first{$0.id==id}?.placement ?? .init()}
    public func validate()throws {
        guard revision>=0,revision<Int.max,connections.count<=16_384,Set(connections.map(\.id)).count==connections.count else{throw CirclrError("포트 배치 revision·개수·중복을 확인하세요")}
        func id(_ value:String)throws {guard !value.isEmpty,value.utf8.count<=1024 else{throw CirclrError("포트 배치의 ID 길이를 확인하세요")}}
        func address(_ value:CircleAddress)throws {
            switch value {
            case .signal(let value),.composition(let value):try id(value)
            case .section(let ai,let ui):try id(ai);try id(ui)
            case .music(let ai,let ui,let ni):try id(ai);try id(ui);try id(ni)
            default:throw CirclrError("포트 배치는 원래 연결의 서클 주소를 사용해야 합니다")
            }
        }
        for entry in connections {try id(entry.id.edgeID);try address(entry.id.from);try address(entry.id.to);guard entry.id.from != entry.id.to else{throw CirclrError("같은 서클의 연결 배치입니다")}}
        let bindings=bindings ?? []
        guard bindings.count<=16_384,Set(bindings.map(\.id)).count==bindings.count else {throw CirclrError("노출 포트의 개수·중복을 확인하세요")}
        var targets:[CircleAddress:Set<CirclePortEndpoint>]=[:]
        for binding in bindings {
            try id(binding.id);try address(binding.target.node);try id(binding.target.portID)
            guard !binding.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,binding.name.count<=128,
                  case .group(let parent,let groupID)=binding.group else {throw CirclrError("노출 포트의 이름·그룹 주소를 확인하세요")}
            try id(groupID)
            switch parent {
            case .album,.sound:break
            case .section,.composition:try address(parent)
            default:throw CirclrError("노출 포트의 그룹 부모를 확인하세요")
            }
            guard targets[binding.group,default:[]].insert(binding.target).inserted,targets[binding.group,default:[]].count<=64 else {throw CirclrError("한 그룹의 노출 포트 대상은 중복 없이 최대 64개입니다")}
        }
    }
}

public enum CirclePortLayoutEditing {
    private static func check(projectID:ID,musicRevision:Int,layoutRevision:Int,project:Project)throws {
        guard projectID==project.id,musicRevision==project.musicRevision,layoutRevision==(project.portLayout?.revision ?? 0) else{throw CirclrError("stale_layout: 프로젝트·음악·배치 revision을 다시 확인하세요")}
        try project.portLayout?.validate()
    }
    /// Returns false for a no-op; no music data, gain, route or musicRevision is changed.
    @discardableResult public static func apply(_ moves:[PlacedCircleConnection],projectID:ID,expectedMusicRevision:Int,expectedLayoutRevision:Int,in project:inout Project)throws->Bool {
        try check(projectID:projectID,musicRevision:expectedMusicRevision,layoutRevision:expectedLayoutRevision,project:project)
        guard !moves.isEmpty,moves.count<=128,Set(moves.map(\.id)).count==moves.count else{throw CirclrError("포트 배치는 중복 없이 1–128개를 지정하세요")}
        let available=Set(try CirclePortCatalog.connections(in:project).map(\.id))
        guard moves.allSatisfy({available.contains($0.id)}) else{throw CirclrError("이동할 원래 연결을 찾을 수 없습니다")}
        var layout=project.portLayout ?? CirclePortLayout(),changed=false
        for move in moves where layout.placement(for:move.id) != move.placement {
            changed=true;layout.connections.removeAll{$0.id==move.id}
            if move.placement != CircleConnectionPlacement() {layout.connections.append(move)}
        }
        guard changed else{return false}
        layout.revision += 1;try layout.validate();project.portLayout=layout;return true
    }
    /// Used by layout Undo/Redo. Preserve concurrent music changes and advance the layout revision.
    @discardableResult public static func restore(_ saved:CirclePortLayout?,projectID:ID,expectedMusicRevision:Int,expectedLayoutRevision:Int,in project:inout Project)throws->Bool {
        try check(projectID:projectID,musicRevision:expectedMusicRevision,layoutRevision:expectedLayoutRevision,project:project)
        try saved?.validate()
        let old=Dictionary(uniqueKeysWithValues:(project.portLayout?.connections ?? []).map{($0.id,$0.placement)})
        let next=Dictionary(uniqueKeysWithValues:(saved?.connections ?? []).map{($0.id,$0.placement)})
        guard old != next || (saved?.bindings ?? []) != (project.portLayout?.bindings ?? []) else{return false}
        var layout=saved ?? CirclePortLayout();layout.revision=expectedLayoutRevision+1
        try layout.validate();project.portLayout=layout;return true
    }
}
