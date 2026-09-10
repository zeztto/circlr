import Foundation

@main struct AuditionPresentationQA {
    static func main() throws {
        var checks=0, failures:[String]=[], fixtures:[[String:Any]]=[]
        func expect(_ value:Bool,_ message:String) {checks+=1;if !value {failures.append(message)}}
        func make(_ phase:String,_ stage:String?,_ seconds:Int=17,_ stagePhase:String="entered",_ interruption:String?=nil,_ interrupted:String?=nil)->AuditionPresentation {
            AuditionPresentation(phase:phase,stage:stage,stagePhase:stagePhase,elapsedSeconds:seconds,
                message:nil,interruption:interruption,interruptedStage:interrupted)
        }
        func record(_ name:String,_ p:AuditionPresentation) {
            var value:[String:Any]=["name":name,"time":"00:00.0","detail":p.detail]
            if let label=p.label {value["label"]=label};if let footer=p.footer {value["footer"]=footer}
            fixtures.append(value)
        }
        let labels=["backendPreparation":"준비","sourceLoad":"음원","auInstantiation":"AU",
                    "engineCreation":"연결","mixerAcquisition":"연결","routing":"연결",
                    "engineStart":"시작","cleanup":"정리"]
        for (stage,label) in labels.sorted(by:{$0.key<$1.key}) {
            let p=make("preparing",stage)
            expect(p.pending && p.canCancel,"\(stage) pending/cancel")
            expect(p.label=="미리 듣기 · "+label,"\(stage) label")
            expect(p.footer=="전체 17초 · 취소","elapsed must remain whole attempt time")
            expect(p.detail.contains("[\(stage)]") && p.detail.contains("전체 17초"),"\(stage) detailed origin")
            expect(p.detail.contains("Space 또는 정지 버튼") && !p.detail.contains("Esc"),"correct cancellation instruction")
            expect(p.preferredLabel(over:"이전 출력 실패")==p.label,"new audition overrides old output failure label")
            expect(p.preferredDetail(over:"이전 outputNodeAcquisition 시간 초과")==p.detail,"new audition overrides old output detail")
            expect(p.logIdentity==make("preparing",stage,99).logIdentity,"elapsed must not spam log")
            expect(p.logIdentity==make("preparing",stage,17,"completed").logIdentity,"completed event must not spam log")
            record("preparing-"+stage,p)
        }
        expect(make("preparing","sourceLoad").logIdentity != make("preparing","auInstantiation").logIdentity,"stage changes must log")
        expect(make("preparing","note").logIdentity==make("preparing",nil).logIdentity,"note traffic excluded from log key")
        for phase in ["idle","ready","failed"] {
            let p=make(phase,"note")
            expect(!p.pending && !p.canCancel,"\(phase) not pending")
            expect(p.preferredLabel(over:"이전 출력 실패")=="이전 출력 실패","\(phase) fallback priority")
            expect(p.preferredDetail(over:"output detail")=="output detail","\(phase) fallback detail")
            expect(p.footer==nil,"\(phase) no footer")
            record(phase,p)
        }
        for reason in ["cancelled","timedOut","superseded","failed"] {
            let p=make("stopping","cleanup",123,"entered",reason,"mixerAcquisition")
            expect(p.pending && !p.canCancel,"stopping is cleanup, not second cancel")
            expect(p.label=="미리 듣기 · 정리" && p.footer=="전체 123초 · 정리 중","cleanup label/time")
            expect(p.detail.contains("현재 단계: 오디오 정리 [cleanup]") && p.detail.contains("중단 요청 당시 단계: 믹서 연결 [mixerAcquisition]"),"frozen interruption distinct from current cleanup")
            expect(p.preferredLabel(over:"old failed")==p.label,"stopping owns readout")
            record("stopping-"+reason,p)
        }
        expect(make("preparing",nil,-5).footer=="전체 0초 · 취소","negative elapsed clamped")
        // Actual diagnostic model retains interruption origin while cleanup proceeds.
        var trace=AuditionTrace(sessionID:UUID())
        trace.record(.mixerAcquisition,.entered,elapsed:16.5)
        trace.interrupt(.cancelled,elapsed:17)
        trace.record(.cleanup,.entered,elapsed:18)
        expect(trace.interruption?.inFlight?.stage == .mixerAcquisition,"frozen origin survives cleanup")
        expect(trace.interruption?.elapsedSeconds == 17 && trace.inFlight?.elapsedSeconds == 18,"distinct attempt-relative event times")
        trace.interrupt(.failed,elapsed:20)
        expect(trace.interruption?.reason == .cancelled,"first interruption immutable")
        if CommandLine.arguments.count == 2 {
            let path=URL(fileURLWithPath:CommandLine.arguments[1])
            let data=try JSONSerialization.data(withJSONObject:["scope":"actual production AuditionPresentation fixtures; no audio backend","scenarios":fixtures],options:[.prettyPrinted,.sortedKeys])
            try data.write(to:path,options:.withoutOverwriting)
        }
        let result:[String:Any]=["status":failures.isEmpty ? "passed":"failed","checks":checks,"failures":failures,"presentationFixtures":fixtures.count,"audioBackendConstructed":false]
        print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:.sortedKeys),as:UTF8.self))
        if !failures.isEmpty {exit(1)}
    }
}
