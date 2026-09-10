import Foundation
import CirclrCore

/// One transient round trip. Settings edits may change revision; source identity may not drift.
struct SectionSettingsReturnState {
    let projectID:ID
    let generation:Int
    let sectionAddress:CircleAddress
    let sourceAddress:CircleAddress
    let title:String
    let workspace:StudioWorkspace
    let midiStepMode:Bool
    let viewport:HierarchyViewport?
    let stepCursor:MIDIImportStepCursor?
    let trackID:ID?
    let pitchBend:MIDIPitchBendSequence?
}

extension AppStore {
    private var sectionSettingsNavigationIdle:Bool {
        canStartMediaImport && midiImportDraft==nil && mediaImportTask==nil
    }
    var canOpenCurrentSectionSettings:Bool {
        guard sectionSettingsNavigationIdle,case .music(let ai,let ui,_)=hierarchySelection,
              ai==project.activeArrangementID,selectedUse?.id==ui,
              let address=hierarchySelection,
              (try? StudioNavigation.scene(revealing:address,in:project)) != nil else{return false}
        return true
    }
    var canReturnFromSectionSettings:Bool {
        guard sectionSettingsNavigationIdle,let saved=sectionSettingsReturn,
              saved.projectID==project.id,saved.generation==mediaImportGeneration,
              hierarchySelection==saved.sectionAddress,
              case .section(let ai,let ui)=saved.sectionAddress,
              ai==project.activeArrangementID,selectedUse?.id==ui,
              (try? StudioNavigation.scene(revealing:saved.sourceAddress,in:project)) != nil else{return false}
        return true
    }
    func openCurrentSectionSettings() {
        guard canOpenCurrentSectionSettings else{return}
        var identity=numberEditIdentity
        guard resolveActiveNumericDraft(),nameEditing.resolve() else{return}
        identity.revision=project.musicRevision
        guard identity==numberEditIdentity,canOpenCurrentSectionSettings,
              case .music(let ai,let ui,_)=hierarchySelection,let address=hierarchySelection else{return}
        let viewport=captureHierarchyViewport?()
        guard identity==numberEditIdentity,canOpenCurrentSectionSettings else{return}
        rememberCircleWorkspace()
        let workspace=viewport?.workspace ?? capturedStudioWorkspace
        let section=CircleAddress.section(arrangementID:ai,useID:ui)
        let saved=SectionSettingsReturnState(projectID:project.id,generation:mediaImportGeneration,
            sectionAddress:section,sourceAddress:address,title:selectedCircle?.title ?? "이전 편집",
            workspace:workspace,midiStepMode:midiStepMode,viewport:viewport,stepCursor:captureStepCursor?(),
            trackID:selectedTrackID,pitchBend:pitchBendSource(at:.init(node:address,original:workspace.original),in:project))
        navigationOpen=false;connectionsOpen=false;automationOpen=false;pitchBendOpen=false;hierarchyTransitionID=nil
        focusHierarchy(section,detail:true)
        hierarchySettingsOpen=true
        sectionSettingsReturn=saved
    }
    func returnFromSectionSettings() {
        guard canReturnFromSectionSettings,let saved=sectionSettingsReturn else{return}
        var identity=numberEditIdentity
        guard resolveActiveNumericDraft(),nameEditing.resolve() else{return}
        identity.revision=project.musicRevision
        guard identity==numberEditIdentity,canReturnFromSectionSettings else{return}
        var workspace=saved.workspace.restored(at:saved.sourceAddress,in:project)
        let key=EditorWorkspaceKey(node:saved.sourceAddress,original:workspace.original)
        if let state=workspace.pitchBend {
            workspace.pitchBend=state.reconciled(from:saved.pitchBend,to:pitchBendSource(at:key,in:project))
        }
        sectionSettingsReturn=nil
        hierarchySettingsOpen=false
        focusHierarchy(saved.sourceAddress,detail:true)
        // Source and instrument nodes already resolved their current owner during
        // selection. Only routing nodes need the remembered ambiguous output choice.
        if let track=saved.trackID,let node=selectedMusic,let graph=selectedGraph {
            switch node.content {
            case .effect,.mix,.router:
                if StudioNavigation.outputTracks(from:node.id,graph:graph).contains(track),
                   project.tracks.contains(where:{$0.id==track}) {selectedTrackID=track}
            default:break
            }
        }
        midiStepMode=saved.midiStepMode
        restoreStudioWorkspace(workspace)
        // Reissue the keyboard cursor for this revision only after destination
        // resolution. Its grid/page must match the newly clamped editor viewport.
        if let cursor=saved.stepCursor,cursor.scope==stepRowScope,
           let grid=try? StepGrid(subdivisions:cursor.grid.subdivisions,beats:editorBeats) {
            let page=min(cursor.page,max(0,grid.pageCount-1))
            let columns=min(16,grid.stepCount-page*16)
            pendingMIDIImportStepCursor=MIDIImportStepCursor(scope:cursor.scope,revision:project.musicRevision,
                grid:grid,page:page,pitch:cursor.pitch,column:min(cursor.column,max(0,columns-1)))
        }
        if var viewport=saved.viewport {
            viewport.selection=saved.sourceAddress;viewport.settingsOpen=hierarchySettingsOpen
            viewport.midiStepMode=midiStepMode;viewport.workspace=capturedStudioWorkspace
            let previous=updatingHierarchyViewport
            updatingHierarchyViewport=true;project.hierarchyView=viewport;updatingHierarchyViewport=previous
            hierarchyCommand=HierarchyCommand(action:.restore)
        }
    }
}
