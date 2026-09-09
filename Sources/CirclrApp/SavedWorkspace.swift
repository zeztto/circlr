import CirclrCore

extension AppStore {
    var capturedStudioWorkspace:StudioWorkspace {
        var saved=StudioWorkspace()
        if connectionsOpen {saved.page = .connections}
        else if hierarchyTransitionID != nil && hierarchyTransitionID==recentTransitionID {saved.page = .transition}
        else if hierarchySettingsOpen {saved.page = .settings}
        else if automationVisible {saved.page = .automation}
        saved.original=editOriginal
        saved.transitionID=recentTransitionID;saved.automationParameter=automationParameter
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
        connectionEditorIntent=nil;connectionsOpen=view.page == .connections
        hierarchySettingsOpen=view.page == .settings || view.page == .transition
        automationOpen=view.page == .automation;embeddedPlugin=nil
        hierarchyTransitionID=view.page == .transition ? view.transitionID:nil
        edgeSelection=hierarchyTransitionID
        if let id=view.transitionID {recentTransitions[address]=id}
        if let connection=view.connection {connectionWorkspaceStates[.init(node:address,original:view.original)]=connection}
    }
}
