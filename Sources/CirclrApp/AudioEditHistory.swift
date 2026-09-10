import AppKit
import CirclrCore

struct AudioEditHistoryContext {
    let projectID:ID
    let generation:Int
    let address:CircleAddress
    let original:Bool
    let clipID:ID?
    let workspace:StudioWorkspace
    let steps:Bool
}
struct AudioEditHistory {
    let before:AudioEditHistoryContext
    let after:AudioEditHistoryContext
}
struct StudioHistoryEntry {
    let id:UUID
    let name:String
    var project:Project
    let layoutOnly:Bool
    let colorsOnly:Bool
    var audio:AudioEditHistory?
}

extension AppStore {
    func capturedAudioHistoryContext()->AudioEditHistoryContext? {
        guard let address=hierarchySelection else{return nil}
        return .init(projectID:project.id,generation:mediaImportGeneration,address:address,original:editOriginal,
            clipID:currentAudioClip?.id,workspace:capturedStudioWorkspace,steps:midiStepMode)
    }
    func matchesAudioHistoryContext(_ context:AudioEditHistoryContext)->Bool {
        guard context.projectID==project.id,context.generation==mediaImportGeneration,
              hierarchySelection==context.address,editOriginal==context.original,currentAudioClip?.id==context.clipID,
              !navigationOpen,!libraryOpen,!outputPreferencesOpen,embeddedPlugin==nil,commandPalette==nil,!keyboardHelp,soundPickerRequest==nil,
              arrangementPickerRequest==nil,midiImportDraft==nil,!bounceTailEditing,
              NSApp.modalWindow==nil,NSApp.keyWindow?.attachedSheet==nil,
              !(NSApp.keyWindow?.firstResponder is NSTextView) else{return false}
        return capturedStudioWorkspace.page==context.workspace.page
    }
    func restoreAudioHistoryContext(_ context:AudioEditHistoryContext) {
        guard context.projectID==project.id,context.generation==mediaImportGeneration,
              (try? StudioNavigation.scene(revealing:context.address,in:project)) != nil else{return}
        focusHierarchy(context.address,detail:{if case .music=context.address{return true};return false}())
        midiStepMode=context.steps
        restoreStudioWorkspace(context.workspace)
        requestEditorNavigationFocus()
    }
}
