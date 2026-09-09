import CirclrCore

struct EditorSelectionKey:Hashable {
    let project:ID
    let generation:Int
    let editor:EditorWorkspaceKey
}

extension AppStore {
    var editorSelectionKey:EditorSelectionKey? {
        editorWorkspaceKey.map{.init(project:project.id,generation:mediaImportGeneration,editor:$0)}
    }
    var selectionNotes:[Note] {
        switch selectedMusic?.content {case .midi,.rhythmMIDI:return currentLane?.notes ?? [];default:return []}
    }
    func validatedEditorSelection(_ value:EditorSelectionState)->EditorSelectionState {
        value.restored(notes:selectionNotes,beats:editorBeats,clip:currentAudioClip,automation:automationNode?.automation ?? [])
    }
    var capturedEditorSelection:EditorSelectionState {
        var value=editorSelectionKey.flatMap{editorSelectionStates[$0]} ?? .init()
        value.noteIDs=selectedMIDIIDs.sorted();value.anchorID=selectedNoteID;value.beat=selectedBeat
        value.audioClipID=currentAudioClip?.id;value.audioAssetID=currentAudioClip?.assetID
        value.audioSourcePosition=audioSplitOffset.flatMap{offset in currentAudioClip.map{$0.sourceStart+offset}}
        value.automationPoints[automationParameter.rawValue]=selectedAutomationPointID
        return validatedEditorSelection(value)
    }
    func rememberEditorSelection() {
        guard !resettingEditorSelection,let key=editorSelectionKey else{return}
        editorSelectionStates[key]=capturedEditorSelection
    }
    func restoreEditorSelection(_ saved:EditorSelectionState?=nil) {
        guard !resettingEditorSelection else{return}
        let value=validatedEditorSelection(saved ?? editorSelectionKey.flatMap{editorSelectionStates[$0]} ?? .init())
        selectedNoteID=value.anchorID;additionalNoteIDs=Set(value.noteIDs).subtracting(value.anchorID.map{[$0]} ?? [])
        selectedBeat=value.beat
        audioSplitOffset=value.audioSourcePosition.flatMap{position in currentAudioClip.map{position-$0.sourceStart}}
        selectedAutomationPointID=value.automationPoints[automationParameter.rawValue]
        if let key=editorSelectionKey {editorSelectionStates[key]=value}
    }
}
