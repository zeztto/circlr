import Foundation

/// Captures the document and native job that produced an asynchronous result.
/// This is a local commit guard, not an authorization token for MCP clients.
public struct AgentJobCommitLease: Sendable {
    public let projectID:ID
    public let revision:Int
    public let generation:Int
    public let jobID:ID

    public init(projectID:ID,revision:Int,generation:Int,jobID:ID) {
        self.projectID=projectID;self.revision=revision;self.generation=generation;self.jobID=jobID
    }

    public func permits(projectID:ID,revision:Int,generation:Int,jobID:ID?,jobState:String?)->Bool {
        self.projectID==projectID && self.revision==revision && self.generation==generation &&
        self.jobID==jobID && jobState=="running"
    }
    /// MIDI import prepares a full Project copy. Music revision alone does not
    /// cover layout-only edits, so the candidate may replace only its snapshot.
    public static func requireUnchanged(current:Project,snapshot:Project)throws {
        guard current.id==snapshot.id,current.musicRevision==snapshot.musicRevision,
              current.portLayout?.revision==snapshot.portLayout?.revision,
              current==snapshot else {
            throw CirclrError("stale_document: 가져오는 동안 문서가 변경되었습니다. 다시 시도하세요")
        }
    }
}

/// Shared chunk boundary used by native agent staging. The caller supplies its
/// own cancellation check and encoder; no file is published by this helper.
public enum AgentStageChunks {
    public static func isPrivateBounceStageName(_ name:String)->Bool {
        let prefix=".circlr-agent-",suffix=".wav"
        guard name.hasPrefix(prefix),name.hasSuffix(suffix) else {return false}
        let id=String(name.dropFirst(prefix.count).dropLast(suffix.count))
        return UUID(uuidString:id) != nil
    }
    public static func process(totalFrames:Int,chunkFrames:Int,
                               check:()throws->Void,write:(Range<Int>)throws->Void)throws {
        precondition(totalFrames>=0 && chunkFrames>0)
        var start=0
        while start<totalFrames {
            try check()
            let end=start+min(chunkFrames,totalFrames-start)
            try write(start..<end)
            start=end
        }
        try check()
    }
    /// Scan the render without monopolizing the UI actor. Cancellation is
    /// observed between chunks, including after the final frame.
    public static func requireSafePCM(left:[Float],right:[Float],chunkFrames:Int,
                                      check:()throws->Void)throws {
        guard left.count==right.count else {throw CirclrError("스테레오 렌더 길이가 다릅니다")}
        try process(totalFrames:left.count,chunkFrames:chunkFrames,check:check) {range in
            for i in range {
                let l=left[i],r=right[i]
                guard l.isFinite,r.isFinite else {throw CirclrError("렌더 결과에 유효하지 않은 오디오 값이 있습니다")}
                guard abs(l)<=1,abs(r)<=1 else {throw CirclrError("출력이 0 dBFS를 넘습니다. Gain을 낮추세요")}
            }
        }
    }
}
