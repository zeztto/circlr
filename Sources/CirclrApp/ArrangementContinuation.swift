import CirclrCore

/// Captured only for lane-backed editors whose copied use can be edited independently.
struct ArrangementContinuationSource {
    let address:CircleAddress
    let workspace:StudioWorkspace
    let kind:String
    let name:String
}
struct ArrangementContinuation {
    let destination:CircleAddress
    let workspace:StudioWorkspace
    let kind:String
    let name:String
}

extension AppStore {
    func captureArrangementContinuation(currentID:ID?)->ArrangementContinuationSource? {
        guard let currentID,case .music(let arrangement,_,_)=hierarchySelection,arrangement==currentID,
              let address=hierarchySelection,let node=selectedMusic else{return nil}
        let kind:String
        switch node.content {case .audio:kind="오디오";case .midi:kind="MIDI";default:return nil}
        var workspace=capturedStudioWorkspace
        // Continuing a variant always edits this copied use, never the shared source.
        workspace.original=false
        workspace.connection=nil;workspace.transitionID=nil
        if workspace.page == .connections || workspace.page == .transition {workspace.page = .content}
        return ArrangementContinuationSource(address:address,workspace:workspace,kind:kind,name:node.name)
    }
    func continueArrangementEditing(_ request:ArrangementPickerRequest)throws {
        guard arrangementPickerCurrent(request),let continuation=request.continuation,
              case .music(let arrangement,_,_)=continuation.destination,arrangement==request.currentID,
              let scene=try? StudioNavigation.scene(revealing:continuation.destination,in:project),
              let node=scene.node(continuation.destination)?.music else{
            throw CirclrError("복제한 편집 대상이 바뀌었습니다. 편곡안을 다시 여세요.")
        }
        switch node.content {case .audio,.midi:break;default:throw CirclrError("복제한 MIDI·오디오 서클을 다시 선택하세요.")}
        guard nameEditing.resolve(),arrangementPickerCurrent(request) else{throw CirclrError("편집 대상이 바뀌었습니다. 편곡안을 다시 여세요.")}
        arrangementPickerRequest=nil
        focusHierarchy(continuation.destination,detail:true)
        restoreStudioWorkspace(continuation.workspace)
        focusCanvas?()
    }
}
