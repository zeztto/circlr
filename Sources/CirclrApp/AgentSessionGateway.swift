import Foundation
import CryptoKit
import CirclrCore

/// A job already accepted by the trusted gateway retains only its commit
/// authority. The lease itself remains app-owned and is not a model argument.
struct TrustedAgentJob {
    let id: ID
    let lease: AgentRunLease
}

enum TrustedAgentReply {
    case success([String:Any])
    case failure(String)
    case notReplayable

    func value() throws -> [String:Any] {
        switch self {
        case .success(let result): return result
        case .failure(let message): throw CirclrError(message)
        case .notReplayable: throw CirclrError("trusted_run_replay: snapshot은 새 request id로 다시 조회하세요")
        }
    }
}

@MainActor extension AppStore {
    var currentTrustedDocument:AgentRunDocumentBinding {
        AgentRunDocumentBinding(projectID:project.id,projectURL:projectURL,mediaRoot:mediaRoot)
    }

    /// Only an app-owned authenticated session may call this API. This does not
    /// treat the same-UID external MCP socket as a trusted Codex session.
    func beginTrustedAgentTurn(sessionID: ID,turnID: ID,
                               methods: Set<String>,targets: Set<AgentRunTarget>,
                               ttl: TimeInterval = 300) throws -> AgentRunLease {
        stopTrustedAgentTurn()
        trustedAgentJob=nil
        let lease=try trustedRun.issue(sessionID:sessionID,turnID:turnID,
                                       document:currentTrustedDocument,methods:methods,
                                       targets:targets,ttl:ttl)
        trustedDocumentBinding=currentTrustedDocument
        recordActivity("내장 AI","turn 시작 · \(turnID)")
        return lease
    }

    func completeTrustedAgentTurn(_ lease: AgentRunLease) throws {
        try trustedRun.complete(lease)
        recordActivity("내장 AI","turn 완료 · \(lease.turnID)")
    }

    /// AI STOP revokes writes and its owned background job, not DAW transport.
    func stopTrustedAgentTurn() {
        let owned=trustedAgentJob
        trustedRun.revoke()
        trustedDocumentBinding=nil
        trustedReplies=AgentRunReplayLedger()
        if let owned,agentJob?.id==owned.id,agentJob?.state=="running" {
            _=try? cancelAgentJob(owned.id,source:"내장 AI")
        }
    }

    /// This is the only ingress for the future trusted session. A request must
    /// carry the revision it observed; the gateway never refreshes it for AI.
    func executeTrustedAgent(_ request: AgentRequest, lease: AgentRunLease) throws -> [String:Any] {
        guard !request.id.isEmpty,request.id.count<=128 else {
            throw CirclrError("trusted_run_scope: request id를 확인하세요")
        }
        guard trustedRun.active==lease else {
            throw CirclrError("trusted_run_stale: 이전 turn의 요청입니다")
        }
        guard trustedDocumentBinding==currentTrustedDocument,
              trustedRun.permitsCommit(lease,document:currentTrustedDocument) else {
            stopTrustedAgentTurn()
            throw CirclrError("trusted_run_stale: turn이 중단, 완료 또는 만료되었습니다")
        }
        guard !trustedRun.turnCompleted else {
            throw CirclrError("trusted_run_stale: 완료된 turn은 새 요청을 실행할 수 없습니다")
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let encoded=try encoder.encode(request)
        let fingerprint=SHA256.hash(data:encoded).map{String(format:"%02x",$0)}.joined()
        if let replay=try trustedReplies.replay(id:request.id,fingerprint:fingerprint) {
            return try replay.value()
        }
        try trustedRun.authorize(request,lease:lease,project:project,
                                 document:currentTrustedDocument)
        do {
            let result:[String:Any]
            if request.method=="snapshot" {
                let data=try JSONEncoder().encode(AgentRunSnapshot(project))
                guard data.count<=1_048_576,
                      let snapshot=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {
                    throw CirclrError("trusted_run_snapshot: 응답을 인코딩할 수 없습니다")
                }
                result=snapshot
            } else {
                // executeAgent retains the explicit external MCP contract,
                // which returns raw agentState (including local media paths).
                // Trusted callers receive a small path-free receipt instead.
                let native=try executeAgent(request,source:"내장 AI",trustedLease:lease)
                result=try AgentRunReplyProjection.afterWrite(method:request.method,
                                                               native:native,project:project)
            }
            if let jobID=result["jobID"] as? ID {
                trustedAgentJob=TrustedAgentJob(id:jobID,lease:lease)
            }
            let recorded:TrustedAgentReply=request.method=="snapshot" ? .notReplayable:.success(result)
            try trustedReplies.remember(id:request.id,fingerprint:fingerprint,value:recorded)
            return result
        } catch {
            let safe=AgentRunReplyProjection.safeFailure(error)
            try? trustedReplies.remember(id:request.id,fingerprint:fingerprint,
                                         value:.failure(safe))
            throw CirclrError(safe)
        }
    }

    func checkTrustedAgentJobCommit(_ lease:AgentRunLease,jobID: ID) throws {
        guard let owned=trustedAgentJob,owned.id==jobID,owned.lease==lease else {
            throw CancellationError()
        }
        guard trustedDocumentBinding==currentTrustedDocument,
              trustedRun.permitsOwnedJobCommit(lease,jobID:jobID,
                  ownedLease:owned.lease,ownedJobID:owned.id,
                  document:currentTrustedDocument) else {
            stopTrustedAgentTurn()
            throw CancellationError()
        }
    }

    func checkTrustedAgentDocument(_ snapshot: Project,mediaRoot snapshotRoot: URL?,
                                   trustedLease:AgentRunLease?,jobID: ID) throws {
        guard let trustedLease else {return}
        try checkTrustedAgentJobCommit(trustedLease,jobID:jobID)
        try AgentJobCommitLease.requireUnchanged(current:project,snapshot:snapshot)
        guard mediaRoot==snapshotRoot else {
            throw CirclrError("stale_document: 렌더 중 프로젝트의 미디어 위치가 바뀌었습니다")
        }
    }

}
