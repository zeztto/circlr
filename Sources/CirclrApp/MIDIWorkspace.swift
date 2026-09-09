import AppKit
import SwiftUI
import CirclrCore

extension AppStore {
    var midiEditorHasFocus:Bool {let responder=NSApp.keyWindow?.firstResponder;return responder is OrbitMIDIView || responder is PianoRollView || responder is StepGridView}
    func duplicateFocusedContent() {
        if automationVisible {if automationEditorHasFocus{duplicateAutomationPoint()};return}
        if midiEditorHasFocus {duplicateMIDINotes()}
        else if audioCommandAvailable {duplicateAudio()}
        else if !(NSApp.keyWindow?.firstResponder is NSTextView) {reuse()}
    }

    var selectedMIDIIDs:Set<ID> {
        Set((currentLane?.notes ?? []).filter{$0.id==selectedNoteID || additionalNoteIDs.contains($0.id)}.map(\.id))
    }
    func selectMIDINotes(_ ids:Set<ID>) {
        let notes=(currentLane?.notes ?? []).filter{ids.contains($0.id)}
        selectedNoteID=notes.first?.id;additionalNoteIDs=Set(notes.dropFirst().map(\.id))
        if let note=notes.first {selectedBeat=note.beat}
    }
    func toggleMIDISelection(_ id:ID) {var ids=selectedMIDIIDs;if ids.contains(id){ids.remove(id)}else{ids.insert(id)};selectMIDINotes(ids)}
    func beginMIDINoteDrag(_ note:Note)->MIDINoteDrag? {
        guard let lane=currentLane,lane.notes.contains(note) else{return nil}
        let ids=selectedMIDIIDs.contains(note.id) ? selectedMIDIIDs:[note.id]
        // Changing the anchor normally clears additional IDs; restore this gesture's selection.
        selectedNoteID=note.id;additionalNoteIDs=ids.subtracting([note.id]);selectedBeat=note.beat
        return try? MIDINoteDrag(lane:lane,ids:ids,beats:editorBeats,subdivisions:currentContext.beatGrid.subdivisions)
    }
    func commitMIDINoteDrag(_ lane:Lane,gesture:MIDINoteDrag) {
        guard currentLane==gesture.original,lane != gesture.original else{return}
        let anchor=selectedNoteID
        setLane(lane)
        if let anchor,gesture.ids.contains(anchor),let note=currentLane?.notes.first(where:{$0.id==anchor}) {
            selectedNoteID=anchor;additionalNoteIDs=gesture.ids.subtracting([anchor]);selectedBeat=note.beat
        }
    }
    func editMIDINotes(_ change:MIDIEditing.Change) {
        guard let lane=currentLane,!selectedMIDIIDs.isEmpty else{return}
        let ids=selectedMIDIIDs
        do {
            let next=try MIDIEditing.apply(change,to:lane,ids:ids,beats:editorBeats)
            if next != lane {setLane(next)}
            if case .duplicate=change {selectMIDINotes(Set(next.notes.map(\.id)).subtracting(lane.notes.map(\.id)))}
            else {selectMIDINotes(ids)}
        }catch{fail(error)}
    }
    func quantizeMIDI() {editMIDINotes(.quantize(subdivisions:midiQuantizeSubdivision,strength:midiQuantizeStrength))}
    func duplicateMIDINotes() {
        let ids=selectedMIDIIDs,notes=(currentLane?.notes ?? []).filter{ids.contains($0.id)}
        guard let start=notes.map(\.beat).min(),let end=notes.map({$0.beat+$0.length}).max() else{return}
        let grid=Double(midiQuantizeSubdivision)
        editMIDINotes(.duplicate(max(1/grid,ceil((end-start)*grid-1e-8)/grid)))
    }
    func handleMIDIBatchKey(_ event:NSEvent)->Bool {
        if event.modifierFlags.contains(.control){return false}
        if event.modifierFlags.contains(.command) {
            if event.keyCode==0 {selectMIDINotes(Set((currentLane?.notes ?? []).map(\.id)));return true}
            if event.keyCode==2 {duplicateMIDINotes();return true}
            return false
        }
        if event.keyCode==12 {quantizeMIDI();return true}
        return false
    }
}

struct MIDISelectionControls:View {
    @ObservedObject var store:AppStore
    var gridLabel:String {[1:"1/4",2:"1/8",3:"1/8 셋잇단",4:"1/16",6:"1/16 셋잇단",8:"1/32"][store.midiQuantizeSubdivision] ?? "1/16"}
    var body:some View {
        HStack(spacing:8) {
            Text("\(store.selectedMIDIIDs.count)개 선택").monospacedDigit().help("선택한 노트를 드래그하면 함께 이동 · 끝 손잡이로 함께 길이 조절")
            Button("퀀타이즈"){store.quantizeMIDI()}.help("선택 노트의 박자 맞춤 · Q")
            Menu {
                ForEach(StepGrid.resolutions,id:\.self){v in Button([1:"1/4",2:"1/8",3:"1/8 셋잇단",4:"1/16",6:"1/16 셋잇단",8:"1/32"][v]!){store.midiQuantizeSubdivision=v}}
                Divider();ForEach([25,50,75,100],id:\.self){v in Button("강도 \(v)%"){store.midiQuantizeStrength=Double(v)/100}}
            }label:{Text("\(gridLabel) · \(Int(store.midiQuantizeStrength*100))%").monospacedDigit()}
            Menu("이동") {
                Button("반음 위"){store.editMIDINotes(.transpose(1))};Button("반음 아래"){store.editMIDINotes(.transpose(-1))}
                Button("옥타브 위"){store.editMIDINotes(.transpose(12))};Button("옥타브 아래"){store.editMIDINotes(.transpose(-12))}
                Divider();Button("한 칸 앞"){store.editMIDINotes(.move(-1/Double(store.midiQuantizeSubdivision)))};Button("한 칸 뒤"){store.editMIDINotes(.move(1/Double(store.midiQuantizeSubdivision)))}
            }
            Button("복제"){store.duplicateMIDINotes()}.help("선택 구간 바로 뒤에 복제 · ⌘D")
            Button("삭제"){store.editMIDINotes(.delete)}
            Spacer(minLength:0)
        }.font(.system(size:13))
    }
}
