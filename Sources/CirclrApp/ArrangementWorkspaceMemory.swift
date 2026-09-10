import Foundation
import CirclrCore

/// Session-only navigation state, separate from the document and its Undo history.
struct ArrangementWorkspaceMemory {
    let projectID:ID
    let arrangementID:ID
    let compositionID:ID
    let address:CircleAddress
    let workspace:StudioWorkspace
    let midiStepMode:Bool
    let capturedAt:TimeInterval
}

extension AppStore {
    func capturedArrangementWorkspace()->ArrangementWorkspaceMemory? {
        guard let address=hierarchySelection else{return nil}
        var scope=address
        while case .group(let parent,_)=scope {scope=parent}
        let arrangementID:ID
        switch scope {
        case .section(let id,_),.music(let id,_,_):arrangementID=id
        case .composition(let ownerID):
            // A composition itself is an overview, but its arrangement group is precise.
            guard case .group(_,let groupID)=address,
                  let owner=project.album?.composition(ownerID),let id=owner.selectedArrangementID,
                  project.arrangements.first(where:{$0.id==id})?.layout.groups.contains(where:{$0.id==groupID})==true else{return nil}
            arrangementID=id
        default:return nil
        }
        guard let owner=project.album?.owner(of:arrangementID),owner.selectedArrangementID==arrangementID,
              (try? StudioNavigation.scene(revealing:address,in:project)) != nil else{return nil}
        return ArrangementWorkspaceMemory(projectID:project.id,arrangementID:arrangementID,compositionID:owner.id,
            address:address,workspace:capturedStudioWorkspace,midiStepMode:midiStepMode,capturedAt:ProcessInfo.processInfo.systemUptime)
    }

    /// Invoke only after a committed, explicit arrangement switch.
    func restoreArrangementWorkspace(_ arrangementID:ID,compositionID:ID,leaving captured:ArrangementWorkspaceMemory?) {
        guard let owner=project.album?.owner(of:arrangementID),owner.id==compositionID,
              owner.selectedArrangementID==arrangementID else{return}
        arrangementWorkspaces=arrangementWorkspaces.filter {id,memory in
            memory.projectID==project.id && project.album?.owner(of:id)?.id==memory.compositionID
        }
        if let captured,captured.projectID==project.id,
           project.album?.owner(of:captured.arrangementID)?.id==captured.compositionID {
            arrangementWorkspaces[captured.arrangementID]=captured
        }
        while arrangementWorkspaces.count>128 {
            guard let oldest=arrangementWorkspaces.min(by:{$0.value.capturedAt<$1.value.capturedAt})?.key else{break}
            arrangementWorkspaces.removeValue(forKey:oldest)
        }
        if let memory=arrangementWorkspaces[arrangementID],memory.compositionID==compositionID,
           (try? StudioNavigation.scene(revealing:memory.address,in:project)) != nil {
            let detail:Bool
            if case .music=memory.address {detail=true}else{detail=false}
            focusHierarchy(memory.address,detail:detail)
            midiStepMode=memory.midiStepMode
            restoreStudioWorkspace(memory.workspace)
        }else{
            focusHierarchy(.composition(compositionID))
            restoreStudioWorkspace(.init())
        }
    }
}
