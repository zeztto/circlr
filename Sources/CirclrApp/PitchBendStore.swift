import AppKit
import CirclrCore

struct PitchBendEditIdentity:Equatable {
    let number:NumberEditIdentity
    let index:Int?
    let sequence:MIDIPitchBendSequence?
}
extension AppStore {
    func pitchBendSource(at key:EditorWorkspaceKey,in source:Project)->MIDIPitchBendSequence? {
        guard case .music(let arrangementID,let useID,let nodeID)=key.node,
              let use=source.arrangements.first(where:{$0.id==arrangementID})?.uses.first(where:{$0.id==useID}),
              let section=source.sections.first(where:{$0.id==use.sectionID}),
              let graph=try? SectionGraphEditing.effective(section:section,use:use),
              let node=graph.nodes.first(where:{$0.id==nodeID}) else{return nil}
        switch node.content {
        case .midi(let laneID):
            let lanes=key.original ? section.lanes:((try? ArrangementCompiler.effectiveLanes(section:section,use:use)) ?? [])
            return lanes.first(where:{$0.id==laneID})?.pitchBend
        case .rhythmMIDI(let trackID):
            guard let context=try? ArrangementCompiler.context(project:source,use:use,arrangementID:arrangementID).1,
                  let resolved=try? ContextResolver.inheriting(global:source.global,parent:context,settings:node.settings) else{return nil}
            return source.patterns.first(where:{$0.id==resolved.rhythm.patternID && $0.trackID==trackID})?.pitchBend
        default:return nil
        }
    }
    func reconcilePitchBendSelections(from previous:Project) {
        pitchBendReadoutIdentity=nil
        guard !resettingEditorSelection else{return}
        if previous.id != project.id {
            pitchBendState.selectedIndex=nil;pitchBendViewStates=[:]
            return
        }
        func reconciled(_ state:PitchBendWorkspaceState,key:EditorWorkspaceKey)->PitchBendWorkspaceState {
            state.reconciled(from:pitchBendSource(at:key,in:previous),to:pitchBendSource(at:key,in:project))
        }
        if pitchBendState.selectedIndex != nil,let key=editorWorkspaceKey {pitchBendState=reconciled(pitchBendState,key:key)}
        for (key,state) in pitchBendViewStates where state.selectedIndex != nil {pitchBendViewStates[key]=reconciled(state,key:key)}
        for (id,memory) in arrangementWorkspaces {
            guard let state=memory.workspace.pitchBend,state.selectedIndex != nil else{continue}
            var workspace=memory.workspace
            workspace.pitchBend=reconciled(state,key:.init(node:memory.address,original:workspace.original))
            arrangementWorkspaces[id]=ArrangementWorkspaceMemory(projectID:memory.projectID,arrangementID:memory.arrangementID,compositionID:memory.compositionID,
                address:memory.address,workspace:workspace,midiStepMode:memory.midiStepMode,capturedAt:memory.capturedAt)
        }
    }
    var pitchBendSelectionReadout:String {
        let identity=numberEditIdentity,index=pitchBendState.selectedIndex
        if pitchBendReadoutIdentity==identity,pitchBendReadoutIndex==index {return pitchBendReadoutText}
        pitchBendReadoutIdentity=identity;pitchBendReadoutIndex=index
        guard let sequence=currentLane?.pitchBend,let index,sequence.events.indices.contains(index) else {
            pitchBendReadoutText="초기 상태 · 채널 전체에 적용"
            return pitchBendReadoutText
        }
        var raw=sequence.initialValue,range=sequence.initialRange
        for i in 0...index {
            switch sequence.events[i].kind {case .value(let value):raw=value;case .range(let value):range=value}
        }
        let semitones=Double(raw-8192)/8192*range.totalSemitones
        let kind:String
        switch sequence.events[index].kind {case .value:kind="값";case .range:kind="범위"}
        pitchBendReadoutText=kind+String(format:" · %+.3f반음 · 범위 ±%.2f",locale:Locale(identifier:"en_US_POSIX"),semitones,range.totalSemitones)
        return pitchBendReadoutText
    }
    var pitchBendIdentity:PitchBendEditIdentity {.init(number:numberEditIdentity,index:pitchBendState.selectedIndex,sequence:currentLane?.pitchBend)}
    var selectedPitchBendEvent:MIDIPitchBendEvent? {
        guard let events=currentLane?.pitchBend?.events,let index=pitchBendState.selectedIndex,events.indices.contains(index) else{return nil}
        return events[index]
    }
    var pitchBendDisplayBeats:Double {pitchBendState.displayedBeats ?? max(0.03125,min(131072,editorBeats))}
    func switchPitchBendWorkspace() {
        guard !resettingEditorSelection else{pitchBendWorkspaceKey=nil;return}
        if let key=pitchBendWorkspaceKey,pitchBendWorkspaceProjectID==project.id,pitchBendWorkspaceGeneration==mediaImportGeneration {
            pitchBendViewStates[key]=pitchBendState.validated()
        }
        pitchBendWorkspaceProjectID=project.id;pitchBendWorkspaceGeneration=mediaImportGeneration
        pitchBendWorkspaceKey=editorWorkspaceKey
        pitchBendState=(editorWorkspaceKey.flatMap{pitchBendViewStates[$0]} ?? .init()).validated()
    }
    func validatePitchBendIdentity(_ identity:PitchBendEditIdentity)throws {
        guard identity==pitchBendIdentity else{throw CirclrError("편집 대상이나 피치 벤드가 변경되었습니다. Esc로 취소하고 다시 선택하세요")}
    }
    func editPitchBend(_ change:MIDIPitchBendEditing.Change,identity:PitchBendEditIdentity) {
        do {
            try validatePitchBendIdentity(identity)
            guard var lane=currentLane else{throw CirclrError("MIDI 연주를 선택하세요")}
            let result=try MIDIPitchBendEditing.apply(change,to:lane.pitchBend)
            if result.sequence != lane.pitchBend {
                lane.pitchBend=result.sequence;setLane(lane)
                guard currentLane?.pitchBend==result.sequence else{return}
            }
            pitchBendState.selectedIndex=result.selectedIndex
            revealPitchBendSelection()
        }catch{status=error.localizedDescription}
    }
    func selectPitchBend(_ index:Int?) {
        pitchBendState.selectedIndex=index
        pitchBendState=pitchBendState.validated(count:currentLane?.pitchBend?.events.count ?? 0)
        revealPitchBendSelection()
    }
    func revealPitchBendSelection() {
        if let event=selectedPitchBendEvent,event.beat>pitchBendDisplayBeats {pitchBendState.displayedBeats=max(event.beat,0.03125)}
    }
    func choosePitchBend(_ delta:Int) {
        guard let events=currentLane?.pitchBend?.events,!events.isEmpty else{return}
        let index=pitchBendState.selectedIndex ?? (delta>0 ? -1:0)
        selectPitchBend((index+delta+events.count)%events.count)
    }
    func addPitchBend(range:Bool=false) {
        let sequence=currentLane?.pitchBend
        let beat=min(131072,max(0,selectedPitchBendEvent?.beat ?? selectedBeat))
        let state=(try? sequence?.state(atBeat:beat)) ?? MIDIPitchBendState(rawValue:8192,range:.init())
        editPitchBend(.insert(.init(beat:beat,kind:range ? .range(state.range):.value(state.rawValue))),identity:pitchBendIdentity)
    }
}
