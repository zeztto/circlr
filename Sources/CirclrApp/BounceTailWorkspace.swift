import Foundation
import CirclrCore
import CirclrAudio

struct BounceTailCacheKey:Equatable {
    let projectID:ID
    let revision:Int
    let arrangementID:ID
    let useID:ID?
    let trackID:ID?
    let requestedBits:UInt64?
}
struct BounceTailCache {
    let key:BounceTailCacheKey
    let plan:TailPlan?
    let error:String?
}

extension AppStore {
    // Session preference only: resetSession clears it on new/open; MCP omission is always automatic.
    func setBounceTailSeconds(_ seconds:Double?,identity:NumberEditIdentity)throws {
        guard identity==numberEditIdentity,!trackBounceRecoveryLocked else {
            throw CirclrError("대상이나 음악이 바뀌었거나 다른 작업 중입니다. 현재 서클에서 다시 설정하세요")
        }
        if let seconds {
            guard seconds.isFinite,(0...RenderTailPlanner.maximumTailSeconds).contains(seconds) else {
                throw CirclrError("여운은 0–120초로 입력하세요")
            }
        }
        bounceTailSeconds=seconds
    }
    private var currentBounceTailCache:BounceTailCache {
        let key=BounceTailCacheKey(projectID:project.id,revision:project.musicRevision,
            arrangementID:project.activeArrangementID,useID:selectedUse?.id,trackID:selectedTrack?.id,
            requestedBits:bounceTailSeconds?.bitPattern)
        if let cache=bounceTailCache,cache.key==key {return cache}
        let cache:BounceTailCache
        do {
            guard let use=selectedUse,let track=selectedTrack else {throw CirclrError("바운스할 출력 트랙을 선택하세요")}
            _=try BounceEditing.target(trackID:track.id,useID:use.id,arrangementID:project.activeArrangementID,in:project)
            let (section,context,clock)=try ArrangementCompiler.context(project:project,use:use,arrangementID:project.activeArrangementID)
            guard let graph=try SectionGraphCompiler.compile(project:project,section:section,use:use,context:context,clock:clock) else {
                throw CirclrError("음악 그래프가 없습니다")
            }
            let plan=try RenderTailPlanner.section(graph,project:project,clock:clock,trackID:track.id,requestedSeconds:bounceTailSeconds)
            cache=BounceTailCache(key:key,plan:plan,error:nil)
        }catch {cache=BounceTailCache(key:key,plan:nil,error:error.localizedDescription)}
        bounceTailCache=cache;return cache
    }
    var bounceTailAssessment:TailPlan? {currentBounceTailCache.plan}
    var bounceTailAssessmentError:String? {currentBounceTailCache.error}
}
