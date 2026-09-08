import AppKit
import CirclrCore

extension AppStore {
    /// Shared by orbital and rectangular editors so changing layout keeps the key map.
    func handleMIDIKey(_ event:NSEvent,topPitch:Int)->Bool {
        if handleMIDIBatchKey(event){return true}
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control){return false}
        let notes=(currentLane?.notes ?? []).sorted{$0.beat == $1.beat ? $0.pitch<$1.pitch:$0.beat<$1.beat}
        let step=1/Double(currentContext.beatGrid.subdivisions)
        switch event.keyCode {
        case 48:
            guard !notes.isEmpty else{return false}
            let forward = !event.modifierFlags.contains(.shift)
            let current=notes.firstIndex{$0.id==selectedNoteID} ?? (forward ? -1:0)
            let next=notes[(current+(forward ? 1:-1)+notes.count)%notes.count]
            selectedNoteID=next.id;selectedBeat=next.beat
        case 36,76:
            addNote(beat:min(max(0,selectedBeat),max(0,editorBeats-step)),pitch:notes.first(where:{$0.id==selectedNoteID})?.pitch ?? min(127,max(0,topPitch-12)),length:step)
            cancelAudition()
        case 123,124,125,126:
            let sign=event.keyCode==123 || event.keyCode==125 ? -1.0:1.0
            guard var lane=currentLane,let i=lane.notes.firstIndex(where:{$0.id==selectedNoteID}) else {
                if event.keyCode==123 || event.keyCode==124 {selectedBeat=max(0,min(editorBeats-step,selectedBeat+sign*step))}
                return true
            }
            let change:KeyboardEditing.NoteChange
            if event.keyCode==123 || event.keyCode==124 {change=event.modifierFlags.contains(.shift) ? .length(sign*step):.time(sign*step)}
            else if event.modifierFlags.contains(.option){change = .velocity(Int(sign)*5)}
            else {change = .pitch(Int(sign)*(event.modifierFlags.contains(.shift) ? 12:1))}
            if selectedMIDIIDs.count>1 {
                switch change {
                case .pitch(let delta):editMIDINotes(.transpose(delta))
                case .time(let delta):editMIDINotes(.move(delta))
                default:
                    let ids=selectedMIDIIDs
                    for index in lane.notes.indices where ids.contains(lane.notes[index].id) {lane.notes[index]=KeyboardEditing.changed(lane.notes[index],by:change,beats:editorBeats)}
                    setLane(lane);selectMIDINotes(ids)
                }
                return true
            }
            lane.notes[i]=KeyboardEditing.changed(lane.notes[i],by:change,beats:editorBeats)
            selectedBeat=lane.notes[i].beat;setLane(lane)
        case 51,117:removeNote()
        case 49:play()
        default:return false
        }
        return true
    }
    func handleAudioTrimKey(_ event:NSEvent,clipID:ID?)->Bool {
        guard !event.modifierFlags.contains(.command),!event.modifierFlags.contains(.control),[123,124].contains(event.keyCode) else{return false}
        guard var lane=currentLane,let i=lane.audio.firstIndex(where:{$0.id==clipID}),let asset=project.assets.first(where:{$0.id==lane.audio[i].assetID}) else{return true}
        var value=lane.audio[i]
        let delta=(event.keyCode==123 ? -1.0:1.0)*(event.modifierFlags.contains(.shift) ? 0.1:0.01)
        if event.modifierFlags.contains(.option){value.duration=max(0.01,min(asset.duration-value.sourceStart,value.duration+delta))}
        else{let end=value.sourceStart+value.duration;value.sourceStart=max(0,min(end-0.01,value.sourceStart+delta));value.duration=end-value.sourceStart}
        lane.audio[i]=value;setLane(lane);return true
    }
}
