import Foundation

/// The app creates this value for one trusted, in-process agent turn. It is
/// never serialized into a model tool argument or accepted from the MCP socket.
public struct AgentRunLease: Equatable, Sendable {
    public let id: ID
    public let sessionID: ID
    public let turnID: ID
    public let projectID: ID
    public let document: AgentRunDocumentBinding
    public let generation: Int
    public let expiresAt: Date
    public let methods: Set<String>
    public let targets: Set<AgentRunTarget>

    fileprivate init(id: ID, sessionID: ID, turnID: ID, document: AgentRunDocumentBinding,
                     generation: Int, expiresAt: Date, methods: Set<String>,
                     targets: Set<AgentRunTarget>) {
        self.id=id;self.sessionID=sessionID;self.turnID=turnID
        self.projectID=document.projectID;self.document=document
        self.generation=generation;self.expiresAt=expiresAt
        self.methods=methods;self.targets=targets
    }
}

/// App-owned document identity. Paths stay inside the gateway and are never
/// serialized into a model request or reply. Save As changes this binding even
/// when a copied document retains its musical project ID and revision.
public struct AgentRunDocumentBinding: Equatable, Sendable {
    public let projectID: ID
    public let projectURL: String?
    public let mediaRoot: String?

    public init(projectID: ID,projectURL: URL?,mediaRoot: URL?) {
        self.projectID=projectID
        self.projectURL=projectURL?.standardizedFileURL.path
        self.mediaRoot=mediaRoot?.standardizedFileURL.path
    }
}

public enum AgentRunTarget: Hashable, Sendable {
    case section(arrangementID: ID, useID: ID)
    case lane(arrangementID: ID, useID: ID, laneID: ID)
    case node(arrangementID: ID, useID: ID, nodeID: ID)
    case track(ID)
}

/// MainActor-owned state, separate from the user's explicit external MCP mode.
/// A completed turn can only finish a job that it already started.
public struct AgentRunLeaseController {
    public private(set) var generation = 0
    public private(set) var active: AgentRunLease?
    public private(set) var turnCompleted = false

    public init() {}

    public mutating func issue(sessionID: ID, turnID: ID,
                               document: AgentRunDocumentBinding,
                               methods: Set<String>, targets: Set<AgentRunTarget>,
                               ttl: TimeInterval, now: Date = Date()) throws -> AgentRunLease {
        let supported: Set<String> = ["snapshot", "apply", "bounce"]
        guard Self.safeIdentifier(sessionID),Self.safeIdentifier(turnID),
              Self.safeIdentifier(document.projectID),
              ttl.isFinite, (0...3600).contains(ttl), ttl > 0,
              !methods.isEmpty, methods.isSubset(of: supported),
              methods.isDisjoint(with: ["apply", "bounce"]) || !targets.isEmpty else {
            throw CirclrError("trusted_run_scope: 세션, 대상, 허용 명령과 만료 시간을 확인하세요")
        }
        revoke()
        let lease=AgentRunLease(id:newID(),sessionID:sessionID,turnID:turnID,
                                document:document,generation:generation,
                                expiresAt:now.addingTimeInterval(ttl),
                                methods:methods,targets:targets)
        active=lease;turnCompleted=false
        return lease
    }

    public mutating func complete(_ lease: AgentRunLease) throws {
        guard active==lease, !turnCompleted else {throw CirclrError("trusted_run_stale: 완료된 turn입니다")}
        turnCompleted=true
    }

    public mutating func revoke() {
        generation &+= 1
        active=nil
        turnCompleted=false
    }

    public func permitsCommit(_ lease: AgentRunLease,
                              document: AgentRunDocumentBinding,
                              now: Date = Date()) -> Bool {
        active==lease && generation==lease.generation &&
        lease.document==document && now < lease.expiresAt
    }

    public func permitsOwnedJobCommit(_ lease:AgentRunLease,jobID:ID,
                                      ownedLease:AgentRunLease?,ownedJobID:ID?,
                                      document:AgentRunDocumentBinding,
                                      now:Date=Date()) -> Bool {
        ownedLease==lease && ownedJobID==jobID &&
        permitsCommit(lease,document:document,now:now)
    }

    public func authorize(_ request: AgentRequest, lease: AgentRunLease,
                          project: Project, document: AgentRunDocumentBinding,
                          now: Date = Date()) throws {
        guard project.id==document.projectID,
              permitsCommit(lease,document:document,now:now), !turnCompleted else {
            throw CirclrError("trusted_run_stale: turn이 중단, 완료 또는 만료되었습니다")
        }
        guard lease.methods.contains(request.method) else {
            throw CirclrError("trusted_run_scope: 이 명령은 허용되지 않았습니다")
        }
        // A first snapshot needs no revision. If supplied, stale values still
        // fail; writes must carry the revision they actually observed.
        if request.method=="snapshot" {
            guard request.projectID == nil || request.projectID == project.id,
                  request.expectedRevision == nil || request.expectedRevision == project.musicRevision else {
                throw CirclrError("stale_revision: snapshot 대상 문서가 바뀌었습니다")
            }
        } else {
            try AgentProjectEditing.check(request,project:project)
        }
        let targets=try Self.targets(for:request)
        guard targets.isSubset(of:lease.targets) else {
            throw CirclrError("trusted_run_scope: 대상 서클 또는 트랙이 허용 범위를 벗어났습니다")
        }
    }

    public static func targets(for request: AgentRequest) throws -> Set<AgentRunTarget> {
        switch request.method {
        case "snapshot":
            guard request.arguments == nil else {throw CirclrError("trusted_run_scope: snapshot에는 인수가 없습니다")}
            return []
        case "bounce":
            guard let args=request.arguments,
                  let arrangementID=args.arrangementID,let useID=args.useID,
                  let trackID=args.trackID, args.path == nil else {
                throw CirclrError("trusted_run_scope: bounce의 편곡·섹션·트랙을 명시하고 파일 경로는 생략하세요")
            }
            try requireOnlyArguments(args,["arrangementID","useID","trackID","tailSeconds"])
            return [.section(arrangementID:arrangementID,useID:useID),.track(trackID)]
        case "apply":
            guard let args=request.arguments, let operations=args.operations,
                  !operations.isEmpty,operations.count<=128 else {
                throw CirclrError("trusted_run_scope: 1–128개 편집이 필요합니다")
            }
            try requireOnlyArguments(args,["operations"])
            var targets:Set<AgentRunTarget>=[]
            for op in operations {
                guard op.original != true,
                      let arrangementID=op.arrangementID,let useID=op.useID,
                      !arrangementID.isEmpty,!useID.isEmpty else {
                    throw CirclrError("trusted_run_scope: 공유 원본이나 모호한 편집 대상을 허용하지 않습니다")
                }
                targets.insert(.section(arrangementID:arrangementID,useID:useID))
                switch op.kind {
                case "set_step", "set_notes", "generate_midi", "edit_notes":
                    guard let laneID=op.laneID,!laneID.isEmpty else {
                        throw CirclrError("trusted_run_scope: MIDI laneID가 필요합니다")
                    }
                    targets.insert(.lane(arrangementID:arrangementID,useID:useID,laneID:laneID))
                    if let nodeID=op.nodeID {
                        targets.insert(.node(arrangementID:arrangementID,useID:useID,nodeID:nodeID))
                    }
                    switch op.kind {
                    case "set_step": try requireOnlyOperation(op,["kind","arrangementID","useID","laneID","nodeID","stepIndex","pitch","enabled","velocity","gate","subdivisions"])
                    case "set_notes": try requireOnlyOperation(op,["kind","arrangementID","useID","laneID","notes","append"])
                    case "generate_midi": try requireOnlyOperation(op,["kind","arrangementID","useID","laneID","pattern","lengthBeats","append"])
                    default: try requireOnlyOperation(op,["kind","arrangementID","useID","laneID","nodeID","noteIDs","edit","semitones","beatOffset","subdivisions","strength","velocity","velocityOffset"])
                    }
                case "set_automation", "set_effect", "set_node":
                    guard let nodeID=op.nodeID,!nodeID.isEmpty else {
                        throw CirclrError("trusted_run_scope: nodeID가 필요합니다")
                    }
                    targets.insert(.node(arrangementID:arrangementID,useID:useID,nodeID:nodeID))
                    switch op.kind {
                    case "set_automation": try requireOnlyOperation(op,["kind","arrangementID","useID","nodeID","parameter","automationPoints","enabled","original"])
                    case "set_effect": try requireOnlyOperation(op,["kind","arrangementID","useID","nodeID","effect"])
                    default: try requireOnlyOperation(op,["kind","arrangementID","useID","nodeID","name","gain","muted","startBeat","lengthBeats","repeatCount","settings"])
                    }
                default:
                    throw CirclrError("trusted_run_scope: 이 편집 종류는 아직 허용되지 않았습니다")
                }
            }
            return targets
        default:
            throw CirclrError("trusted_run_scope: 이 명령은 아직 지원되지 않습니다")
        }
    }

    private static func requireOnlyArguments(_ args: AgentArguments,
                                             _ allowed: Set<String>) throws {
        let data=try JSONEncoder().encode(args)
        guard let fields=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(fields.keys).isSubset(of:allowed) else {
            throw CirclrError("trusted_run_scope: 이 명령에 허용되지 않은 인수가 있습니다")
        }
    }

    private static func requireOnlyOperation(_ op: AgentOperation,
                                             _ allowed: Set<String>) throws {
        let data=try JSONEncoder().encode(op)
        guard let fields=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(fields.keys).isSubset(of:allowed) else {
            throw CirclrError("trusted_run_scope: 편집 종류와 관계없는 필드는 허용하지 않습니다")
        }
    }

    private static func safeIdentifier(_ value:String) -> Bool {
        !value.isEmpty && value.utf8.count<=128 && value.unicodeScalars.allSatisfy {
            (0x21...0x7e).contains($0.value)
        }
    }
}

/// Path-free projection for the trusted session. Do not add raw Project,
/// Asset, job, plugin state, or local media URLs to this response.
public struct AgentRunSnapshot: Encodable {
    public struct TrackSummary: Encodable {
        public let id: ID
        public let name: String
        public let instrumentKind: Instrument.Kind
    }
    public struct UseSummary: Encodable {
        public let id: ID
        public let name: String
        public let sectionID: ID
    }
    public struct ArrangementSummary: Encodable {
        public let id: ID
        public let name: String
        public let uses: [UseSummary]
    }
    public struct LaneSummary: Encodable {
        public let id: ID
        public let trackID: ID
    }
    public struct SectionSummary: Encodable {
        public let id: ID
        public let name: String
        public let bars: Int
        public let lanes: [LaneSummary]
    }
    public struct AssetSummary: Encodable {
        public let id: ID
        public let name: String
        public let duration: Double
        public let sampleRate: Double
    }

    public let projectID: ID
    public let revision: Int
    public let name: String
    public let global: MusicContext
    public let tracks: [TrackSummary]
    public let arrangements: [ArrangementSummary]
    public let sections: [SectionSummary]
    public let assets: [AssetSummary]

    public init(_ project: Project) {
        projectID=project.id;revision=project.musicRevision
        name=project.name;global=project.global
        tracks=project.tracks.map{TrackSummary(id:$0.id,name:$0.name,instrumentKind:$0.instrument.kind)}
        arrangements=project.arrangements.map{arrangement in
            ArrangementSummary(id:arrangement.id,name:arrangement.name,
                uses:arrangement.uses.map{UseSummary(id:$0.id,name:$0.name,sectionID:$0.sectionID)})
        }
        sections=project.sections.map{section in
            SectionSummary(id:section.id,name:section.name,bars:section.bars,
                lanes:section.lanes.map{LaneSummary(id:$0.id,trackID:$0.trackID)})
        }
        assets=project.assets.map{AssetSummary(id:$0.id,name:$0.name,
                                                duration:$0.duration,sampleRate:$0.sampleRate)}
    }
}

/// Bounded replay book for one lease. Exhaustion closes the turn instead of
/// evicting an old request ID and allowing its side effect to run again.
public struct AgentRunReplayLedger<Value> {
    private var entries:[ID:(fingerprint:String,value:Value)]=[:]
    public let limit:Int

    public init(limit:Int=256) {precondition(limit>0);self.limit=limit}

    public func replay(id:ID,fingerprint:String)throws->Value? {
        if let entry=entries[id] {
            guard entry.fingerprint==fingerprint else {
                throw CirclrError("trusted_run_replay: 같은 request id에 다른 명령을 사용할 수 없습니다")
            }
            return entry.value
        }
        guard entries.count<limit else {
            throw CirclrError("trusted_run_replay: turn의 요청 한도를 넘었습니다. 새 turn을 시작하세요")
        }
        return nil
    }

    public mutating func remember(id:ID,fingerprint:String,value:Value)throws {
        guard entries[id]==nil,entries.count<limit else {
            throw CirclrError("trusted_run_replay: 요청 ID 충돌 또는 한도 초과")
        }
        entries[id]=(fingerprint,value)
    }
}

/// The external MCP dispatcher may return agentState with local paths. A
/// trusted write exposes only these explicit receipts to its model session.
public enum AgentRunReplyProjection {
    public static func afterWrite(method:String,native:[String:Any],
                                  project:Project) throws -> [String:Any] {
        switch method {
        case "apply":
            return ["state":"applied","projectID":project.id,
                    "revision":project.musicRevision]
        case "bounce":
            guard let jobID=native["jobID"] as? ID,
                  !jobID.isEmpty,jobID.utf8.count<=128 else {
                throw CirclrError("trusted_run_job: 작업 ID를 받지 못했습니다")
            }
            return ["jobID":jobID,"state":"running",
                    "projectID":project.id,"revision":project.musicRevision]
        default:
            throw CirclrError("trusted_run_scope: 이 쓰기는 아직 지원되지 않습니다")
        }
    }

    public static func safeFailure(_ error:Error) -> String {
        error is CancellationError ? "trusted_run_cancelled" : "trusted_run_execution_failed"
    }
}
