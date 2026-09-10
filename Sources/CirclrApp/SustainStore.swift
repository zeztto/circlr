import AppKit
import CirclrCore

struct SustainEditIdentity:Equatable {
    let number:NumberEditIdentity
    let index:Int?
    let sequence:MIDISustainSequence?
}
extension AppStore {
    func sustainSource(at key:EditorWorkspaceKey,in source:Project)->MIDISustainSequence? {
        guard case .music(let arrangementID,let useID,let nodeID)=key.node,
              let use=source.arrangements.first(where:{$0.id==arrangementID})?.uses.first(where:{$0.id==useID}),
              let section=source.sections.first(where:{$0.id==use.sectionID}),
              let graph=try? SectionGraphEditing.effective(section:section,use:use),
              let node=graph.nodes.first(where:{$0.id==nodeID}) else{return nil}
        switch node.content {
        case .midi(let laneID):
            let lanes=key.original ? section.lanes:((try? ArrangementCompiler.effectiveLanes(section:section,use:use)) ?? [])
            return lanes.first(where:{$0.id==laneID})?.sustain
        case .rhythmMIDI(let trackID):
            guard let context=try? ArrangementCompiler.context(project:source,use:use,arrangementID:arrangementID).1,
                  let resolved=try? ContextResolver.inheriting(global:source.global,parent:context,settings:node.settings) else{return nil}
            return source.patterns.first(where:{$0.id==resolved.rhythm.patternID && $0.trackID==trackID})?.sustain
        default:return nil
        }
    }
    func reconcileSustainSelections(from previous:Project) {
        guard !resettingEditorSelection else{return}
        if previous.id != project.id {
            sustainState.selectedIndex=nil;sustainViewStates=[:]
            return
        }
        func reconciled(_ state:SustainWorkspaceState,key:EditorWorkspaceKey)->SustainWorkspaceState {
            state.reconciled(from:sustainSource(at:key,in:previous),to:sustainSource(at:key,in:project))
        }
        if sustainState.selectedIndex != nil,let key=editorWorkspaceKey {sustainState=reconciled(sustainState,key:key)}
        for (key,state) in sustainViewStates where state.selectedIndex != nil {sustainViewStates[key]=reconciled(state,key:key)}
        for (id,memory) in arrangementWorkspaces {
            guard let state=memory.workspace.sustain,state.selectedIndex != nil else{continue}
            var workspace=memory.workspace
            workspace.sustain=reconciled(state,key:.init(node:memory.address,original:workspace.original))
            arrangementWorkspaces[id]=ArrangementWorkspaceMemory(projectID:memory.projectID,arrangementID:memory.arrangementID,compositionID:memory.compositionID,
                address:memory.address,workspace:workspace,midiStepMode:memory.midiStepMode,capturedAt:memory.capturedAt)
        }
    }
    var sustainSelectionReadout:String {
        let value=selectedSustainEvent?.rawValue ?? currentLane?.sustain?.initialValue ?? 0
        let index=sustainState.selectedIndex.map{"\($0+1)/\(currentLane?.sustain?.events.count ?? 0)"} ?? "초기 상태"
        return index+" · raw \(value) · "+(value>=64 ? "눌림 (64 이상)":"해제 (63 이하)")
    }
    var sustainIdentity:SustainEditIdentity {.init(number:numberEditIdentity,index:sustainState.selectedIndex,sequence:currentLane?.sustain)}
    var selectedSustainEvent:MIDISustainEvent? {
        guard let events=currentLane?.sustain?.events,let index=sustainState.selectedIndex,events.indices.contains(index) else{return nil}
        return events[index]
    }
    var sustainDisplayBeats:Double {sustainState.displayedBeats ?? max(0.03125,min(131072,editorBeats))}
    func switchSustainWorkspace() {
        guard !resettingEditorSelection else{sustainWorkspaceKey=nil;return}
        if let key=sustainWorkspaceKey,sustainWorkspaceProjectID==project.id,sustainWorkspaceGeneration==mediaImportGeneration {
            sustainViewStates[key]=sustainState.validated()
        }
        sustainWorkspaceProjectID=project.id;sustainWorkspaceGeneration=mediaImportGeneration
        sustainWorkspaceKey=editorWorkspaceKey
        sustainState=(editorWorkspaceKey.flatMap{sustainViewStates[$0]} ?? .init()).validated()
    }
    func validateSustainIdentity(_ identity:SustainEditIdentity)throws {
        guard identity==sustainIdentity else{throw CirclrError("편집 대상이나 페달가 변경되었습니다. Esc로 취소하고 다시 선택하세요")}
    }
    func editSustain(_ change:MIDISustainEditing.Change,identity:SustainEditIdentity) {
        do {
            try validateSustainIdentity(identity)
            guard var lane=currentLane else{throw CirclrError("MIDI 연주를 선택하세요")}
            var source=lane.sustain
            if source==nil,case .insert=change {source=MIDISustainSequence(channel:lane.pitchBend?.channel ?? 0)}
            let result=try MIDISustainEditing.apply(change,to:source)
            if result.sequence != lane.sustain {
                lane.sustain=result.sequence;setLane(lane)
                guard currentLane?.sustain==result.sequence else{return}
            }
            sustainState.selectedIndex=result.selectedIndex
            revealSustainSelection()
        }catch{status=error.localizedDescription}
    }
    func selectSustain(_ index:Int?) {
        sustainState.selectedIndex=index
        sustainState=sustainState.validated(count:currentLane?.sustain?.events.count ?? 0)
        revealSustainSelection()
    }
    func revealSustainSelection() {
        if let event=selectedSustainEvent,event.beat>sustainDisplayBeats {sustainState.displayedBeats=max(event.beat,0.03125)}
    }
    func chooseSustain(_ delta:Int) {
        guard let events=currentLane?.sustain?.events,!events.isEmpty else{return}
        let index=sustainState.selectedIndex ?? (delta>0 ? -1:0)
        selectSustain((index+delta+events.count)%events.count)
    }
    func addSustain() {
        let sequence=currentLane?.sustain
        let beat=min(131072,max(0,selectedSustainEvent?.beat ?? selectedBeat))
        let raw=(try? sequence?.state(atBeat:beat).rawValue) ?? 0
        editSustain(.insert(.init(beat:beat,rawValue:raw)),identity:sustainIdentity)
    }
}
