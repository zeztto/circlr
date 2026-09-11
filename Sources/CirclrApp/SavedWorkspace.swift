import CirclrCore

extension AppStore {
    var capturedStudioWorkspace:StudioWorkspace {
        var saved=StudioWorkspace()
        if connectionsOpen {saved.page = .connections}
        else if hierarchyTransitionID != nil && hierarchyTransitionID==recentTransitionID {saved.page = .transition}
        else if hierarchySettingsOpen {saved.page = .settings}
        else if automationVisible {saved.page = .automation}
        else if sustainOpen {
            switch selectedMusic?.content {case .midi,.rhythmMIDI:saved.page = .sustain;default:break}
        }
        else if pitchBendOpen {
            switch selectedMusic?.content {case .midi,.rhythmMIDI:saved.page = .pitchBend;default:break}
        }
        switch selectedMusic?.content {
        case .midi,.rhythmMIDI:
            if sustainOpen || sustainState != .init() {saved.sustain=sustainState.validated(count:currentLane?.sustain?.events.count ?? 0)}
            if pitchBendOpen || pitchBendState != .init() {saved.pitchBend=pitchBendState.validated(count:currentLane?.pitchBend?.events.count ?? 0)}
        default:break
        }
        saved.selection=capturedEditorSelection
        saved.original=editOriginal
        saved.transitionID=recentTransitionID;saved.automationParameter=automationParameter
        saved.automationViewport=automationViewport.validated
        if let key=editorWorkspaceKey,let value=editorViewStates[key] {saved.editor=validatedEditorViewport(value)}
        if let address=hierarchySelection {
            saved.connection=connectionWorkspaceStates[.init(node:address,original:editOriginal)]
            return saved.restored(at:address,in:project)
        }
        return saved
    }
    func restoreStudioWorkspace(_ saved:StudioWorkspace) {
        guard let address=hierarchySelection else{return}
        let view=saved.restored(at:address,in:project)
        editOriginal=view.original;automationParameter=view.automationParameter
        sustainOpen=view.page == .sustain
        sustainState=(view.sustain ?? .init()).validated(count:currentLane?.sustain?.events.count ?? 0)
        if let key=editorWorkspaceKey {sustainViewStates[key]=sustainState}
        pitchBendOpen=view.page == .pitchBend
        pitchBendState=(view.pitchBend ?? .init()).validated(count:currentLane?.pitchBend?.events.count ?? 0)
        if let key=editorWorkspaceKey {pitchBendViewStates[key]=pitchBendState}
        if let key=editorWorkspaceKey,let editor=view.editor {editorViewStates[key]=validatedEditorViewport(editor)}
        if let viewport=view.automationViewport {automationViewport=viewport.validated}
        if let key=automationWorkspaceKey {automationViewStates[key]=automationViewport.validated}
        connectionEditorIntent=nil;connectionsOpen=view.page == .connections
        hierarchySettingsOpen=view.page == .settings || view.page == .transition
        automationOpen=view.page == .automation;embeddedPlugin=nil
        hierarchyTransitionID=view.page == .transition ? view.transitionID:nil
        edgeSelection=hierarchyTransitionID
        restoreEditorSelection(view.selection ?? .init())
        if let id=view.transitionID {recentTransitions[address]=id}
        if let connection=view.connection {connectionWorkspaceStates[.init(node:address,original:view.original)]=connection}
    }
}
