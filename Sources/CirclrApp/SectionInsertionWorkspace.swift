import Foundation
import CirclrCore

struct SectionInsertionContext {
    let identity:NumberEditIdentity
    let arrangementID:ID
    let useID:ID
}

extension AppStore {
    var sectionInsertionLocked:Bool {
        preparing || midiRecording || audioRecordingBusy || audioRecordPending || mediaImportTask != nil || moviePreparing || movieWriter != nil
    }
    func sectionInsertionContext(at address:CircleAddress?=nil)->SectionInsertionContext? {
        guard let address=address ?? hierarchySelection else{return nil}
        let arrangement:ID,use:ID
        switch address {
        case .section(let a,let u),.music(let a,let u,_):arrangement=a;use=u
        default:return nil
        }
        guard project.arrangements.first(where:{$0.id==arrangement})?.uses.contains(where:{$0.id==use}) == true else{return nil}
        return SectionInsertionContext(identity:numberEditIdentity,arrangementID:arrangement,useID:use)
    }
    func sectionInsertionAssessment(_ context:SectionInsertionContext)->SectionInsertionAssessment {
        SectionInsertion.assess(arrangementID:context.arrangementID,afterUseID:context.useID,in:project)
    }
    private func sectionInsertionCurrent(_ context:SectionInsertionContext)->Bool {
        guard !sectionInsertionLocked else{status="재생 준비·녹음·가져오기가 끝난 뒤 섹션을 삽입하세요";return false}
        guard nameEditing.resolve() else{return false}
        guard numberEditIdentity==context.identity else{status="대상이나 음악이 바뀌었습니다. 삽입할 섹션에서 다시 실행하세요";return false}
        return true
    }
    func insertSection(after context:SectionInsertionContext) {
        guard sectionInsertionCurrent(context) else{return}
        let assessment=sectionInsertionAssessment(context)
        if let issue=assessment.issue {openSectionInsertionConnections(context,reason:issue.message);return}
        guard let arrangement=project.arrangements.first(where:{$0.id==context.arrangementID}) else{return}
        let origin=arrangement.layout.positions[context.useID] ?? Point()
        let position:Point
        if let successor=assessment.successorID,let next=arrangement.layout.positions[successor] {
            position=Point((origin.x+next.x)/2,(origin.y+next.y)/2+200)
        }else{position=Point(origin.x+650,origin.y)}
        do {
            var candidate=project
            let id=try SectionInsertion.insert(arrangementID:context.arrangementID,afterUseID:context.useID,
                name:"섹션 \(arrangement.uses.count+1)",bars:8,at:position,in:&candidate)
            mutate("선택 섹션 뒤에 삽입"){$0=candidate}
            guard project.arrangements.first(where:{$0.id==context.arrangementID})?.uses.contains(where:{$0.id==id}) == true else{return}
            hierarchySettingsOpen=true;automationOpen=false;connectionsOpen=false;commandPalette=nil
            focusHierarchy(.section(arrangementID:context.arrangementID,useID:id),detail:true)
            status="섹션을 재생 순서에 삽입했습니다. 이름을 입력하세요"
        }catch{fail(error)}
    }
    func recoverSectionInsertion(_ context:SectionInsertionContext) {
        guard sectionInsertionCurrent(context) else{return}
        let reason=sectionInsertionAssessment(context).issue?.message ?? "삽입할 섹션의 다음 연결을 확인하세요"
        openSectionInsertionConnections(context,reason:reason)
    }
    private func openSectionInsertionConnections(_ context:SectionInsertionContext,reason:String) {
        let address=CircleAddress.section(arrangementID:context.arrangementID,useID:context.useID)
        do {
            _ = try StudioNavigation.scene(revealing:address,in:project)
            commandPalette=nil;automationOpen=false;hierarchySettingsOpen=false
            focusHierarchy(address,detail:true);showConnections(portID:CirclePort.flowOutput)
            status=reason
        }catch{fail(error)}
    }
}
