import Foundation
import CirclrCore

enum CircleWorkspaceIntent {case content,steps}
struct CircleEditorWorkspaceMemory {
    let projectID:ID
    let generation:Int
    let key:EditorWorkspaceKey
    let workspace:StudioWorkspace
    let steps:Bool
    let cursor:MIDIImportStepCursor?
    let trackID:ID?
    let pitchBend:MIDIPitchBendSequence?
    let capturedAt:TimeInterval
}

extension AppStore {
    func rememberCircleWorkspace() {
        guard case .music=hierarchySelection,let key=editorWorkspaceKey else{return}
        let workspace=capturedStudioWorkspace
        circleEditorWorkspaces=circleEditorWorkspaces.filter{_,memory in
            memory.projectID==project.id && memory.generation==mediaImportGeneration &&
            (try? StudioNavigation.scene(revealing:memory.key.node,in:project)) != nil
        }
        circleEditorWorkspaces[key]=CircleEditorWorkspaceMemory(projectID:project.id,generation:mediaImportGeneration,
            key:key,workspace:workspace,steps:midiStepMode,cursor:captureStepCursor?(),trackID:selectedTrackID,
            pitchBend:pitchBendSource(at:key,in:project),capturedAt:ProcessInfo.processInfo.systemUptime)
        while circleEditorWorkspaces.count>128 {
            guard let oldest=circleEditorWorkspaces.min(by:{$0.value.capturedAt<$1.value.capturedAt})?.key else{break}
            circleEditorWorkspaces.removeValue(forKey:oldest)
        }
    }
    @discardableResult func selectUserWorkspace(_ address:CircleAddress,explicitIntent:CircleWorkspaceIntent?=nil)->Bool {
        var identity=numberEditIdentity
        guard resolveActiveNumericDraft(),nameEditing.resolve() else{return false}
        identity.revision=project.musicRevision
        guard identity==numberEditIdentity else{return false}
        do {_ = try StudioNavigation.scene(revealing:address,in:project)}catch{fail(error);return false}
        if address==hierarchySelection,explicitIntent==nil {return true}
        _=captureHierarchyViewport?()
        guard identity==numberEditIdentity else{return false}
        rememberCircleWorkspace()
        let memory=circleEditorWorkspaces.values.filter{$0.projectID==project.id && $0.generation==mediaImportGeneration && $0.key.node==address}.max{$0.capturedAt<$1.capturedAt}
        selectHierarchy(address)
        var workspace=memory?.workspace ?? StudioWorkspace()
        if explicitIntent != nil {workspace.page = .content}
        if let state=workspace.pitchBend,let memory {
            workspace.pitchBend=state.reconciled(from:memory.pitchBend,to:pitchBendSource(at:memory.key,in:project))
        }
        midiStepMode=explicitIntent.map{if case .steps=$0{return true};return false} ?? memory?.steps ?? false
        restoreStudioWorkspace(workspace)
        if let memory,let track=memory.trackID,let node=selectedMusic,let graph=selectedGraph {
            switch node.content {
            case .effect,.mix,.router:
                if StudioNavigation.outputTracks(from:node.id,graph:graph).contains(track),project.tracks.contains(where:{$0.id==track}) {selectedTrackID=track}
            default:break
            }
        }
        pendingMIDIImportStepCursor=nil
        if midiStepMode,let cursor=memory?.cursor,cursor.scope==stepRowScope,
           let grid=try? StepGrid(subdivisions:cursor.grid.subdivisions,beats:editorBeats) {
            let page=min(cursor.page,max(0,grid.pageCount-1)),columns=min(16,grid.stepCount-min(cursor.page,max(0,grid.pageCount-1))*16)
            pendingMIDIImportStepCursor=MIDIImportStepCursor(scope:cursor.scope,revision:project.musicRevision,grid:grid,page:page,pitch:cursor.pitch,column:min(cursor.column,max(0,columns-1)))
        }
        return true
    }
    @discardableResult func focusUserWorkspace(_ address:CircleAddress,detail:Bool=false,explicitIntent:CircleWorkspaceIntent?=nil)->Bool {
        guard selectUserWorkspace(address,explicitIntent:explicitIntent) else{return false}
        hierarchyCommand=HierarchyCommand(action:.focus(address,detail));return true
    }
}
