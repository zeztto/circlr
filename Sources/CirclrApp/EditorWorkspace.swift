import CirclrCore

struct EditorWorkspaceKey:Hashable {
    let node:CircleAddress
    let original:Bool
}
struct AutomationWorkspaceKey:Hashable {
    let editor:EditorWorkspaceKey
    let parameter:AutomationParameter
}

extension AppStore {
    var editorWorkspaceKey:EditorWorkspaceKey? {hierarchySelection.map{.init(node:$0,original:editOriginal)}}
    func validatedEditorViewport(_ value:EditorViewportState)->EditorViewportState {
        let asset=currentAudioClip.flatMap{clip in project.assets.first{$0.id==clip.assetID}}
        var restored=value.restored(beats:editorBeats,clock:orbitMIDIClock,assetID:asset?.id,assetDuration:asset?.duration)
        if !midiStepMode && !project.usesOrbits {restored.topPitch=max(27,restored.topPitch)}
        return restored
    }
    func initialEditorViewport()->EditorViewportState {
        if let key=editorWorkspaceKey,let saved=editorViewStates[key] {return validatedEditorViewport(saved)}
        var value=EditorViewportState()
        value.topPitch=currentLane?.notes.map(\.pitch).max().map{min(128,max(12,$0+1))} ?? (selectedTrack?.instrument.drums==true ? 48:72)
        value.orbit.fitPitches(currentLane?.notes ?? [])
        value.steps.drumMode=selectedTrack?.instrument.drums==true
        value.steps.newPitch=selectedTrack?.instrument.sample?.rootPitch ?? 36
        value.audioAssetID=currentAudioClip?.assetID
        return validatedEditorViewport(value)
    }
    func switchAutomationViewport() {
        switchPitchBendWorkspace()
        // Changing targets cannot carry an instrument-only parameter into another kind of circle.
        // The parameter observer re-enters once with gain and saves the outgoing viewport normally.
        if automationParameter != .gain,
           automationNode.map({automationParameter.supports(node:$0,in:project)}) != true {
            automationParameter = .gain
            return
        }
        if automationWorkspaceProjectID==project.id,automationWorkspaceGeneration==mediaImportGeneration,let key=automationWorkspaceKey {
            automationViewStates[key]=automationViewport.validated
        }
        automationWorkspaceProjectID=project.id;automationWorkspaceGeneration=mediaImportGeneration
        automationWorkspaceKey=editorWorkspaceKey.map{.init(editor:$0,parameter:automationParameter)}
        automationViewport=automationWorkspaceKey.flatMap{automationViewStates[$0]}?.validated ?? .init()
    }
}
