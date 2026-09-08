import AppKit
import SwiftUI
import CirclrCore

@MainActor final class MIDIEditorFocus {
    weak var view:NSView?
    func focus(){guard let view else{return};view.window?.makeFirstResponder(view)}
}

/// Shared values and commit semantics for the three MIDI editing surfaces.
struct MIDINoteInspector:View {
    @ObservedObject var store:AppStore
    let focusTarget:MIDIEditorFocus
    let hint:String
    let keyHelp:String
    @State private var fieldFocus=NumberFieldFocus(["MIDI 음높이","MIDI 시작 박","MIDI 길이 박","MIDI 세기"])
    var notes:[Note] {store.currentLane?.notes ?? []}
    var selected:Note? {notes.first{$0.id==store.selectedNoteID}}
    func name(_ pitch:Int)->String {Scale.roots[pitch%12]+String(pitch/12-1)}
    func division(_ value:Int)->String {[1:"1/4",2:"1/8",3:"1/8 셋잇단",4:"1/16",6:"1/16 셋잇단",8:"1/32"][value] ?? "1/16"}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if let note=selected,store.selectedMIDIIDs.count==1 {
                HStack(spacing:8){Text("음높이").foregroundStyle(StudioTheme.secondary);CommittedNumberField(title:"MIDI 음높이",value:integer(note,\.pitch),range:0...127,integerOnly:true,width:64);Text(name(note.pitch)).monospacedDigit()}
                field("시작 박",value:number(note,\.beat),range:0...max(0,store.editorBeats-note.length))
                field("길이 박",value:number(note,\.length),range:0.03125...max(0.03125,store.editorBeats-note.beat))
                field("세기",value:integer(note,\.velocity),range:1...127,integer:true)
            }
            if !store.selectedMIDIIDs.isEmpty {
                HStack(spacing:10) {
                    Button("퀀타이즈"){act{store.quantizeMIDI()}}.help("선택 노트 · Q")
                    Menu(division(store.midiQuantizeSubdivision)) {
                        ForEach(StepGrid.resolutions,id:\.self){v in Button(division(v)){store.midiQuantizeSubdivision=v}}
                        Divider();ForEach([25,50,75,100],id:\.self){value in Button("강도 \(value)%"){store.midiQuantizeStrength=Double(value)/100}}
                    }.help("강도 \(Int(store.midiQuantizeStrength*100))%")
                    Menu("이동") {
                        Button("반음 위"){act{store.editMIDINotes(.transpose(1))}};Button("반음 아래"){act{store.editMIDINotes(.transpose(-1))}}
                        Button("옥타브 위"){act{store.editMIDINotes(.transpose(12))}};Button("옥타브 아래"){act{store.editMIDINotes(.transpose(-12))}}
                        Divider();Button("한 칸 앞"){act{store.editMIDINotes(.move(-1/Double(store.midiQuantizeSubdivision)))}};Button("한 칸 뒤"){act{store.editMIDINotes(.move(1/Double(store.midiQuantizeSubdivision)))}}
                    }
                }
                HStack(spacing:12){Text("\(store.selectedMIDIIDs.count)개 선택").foregroundStyle(StudioTheme.secondary);Button("복제"){act{store.duplicateMIDINotes()}};Button("삭제"){act{store.editMIDINotes(.delete)}}}
            } else {Text("노트를 선택하면 음높이·시작·길이·세기를 편집합니다").foregroundStyle(StudioTheme.secondary)}
            Text(hint).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).help(keyHelp)
            Spacer(minLength:0)
        }.frame(width:252,alignment:.leading)
        .environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focusTarget.focus()},fieldFocus:fieldFocus))
    }
    func field(_ title:String,value:Binding<Double>,range:ClosedRange<Double>,integer:Bool=false)->some View {
        HStack(spacing:12){Text(title).foregroundStyle(StudioTheme.secondary).frame(width:58,alignment:.leading);CommittedNumberField(title:"MIDI "+title,value:value,range:range,integerOnly:integer,width:88)}
    }
    func act(_ action:()->Void){action();focusTarget.focus()}
    func edit(_ note:Note,_ change:@escaping(inout Note)->Void) {
        guard var lane=store.currentLane,let i=lane.notes.firstIndex(where:{$0.id==note.id}) else{return}
        change(&lane.notes[i]);store.setLane(lane)
    }
    func number(_ note:Note,_ key:WritableKeyPath<Note,Double>)->Binding<Double> {
        let identity=store.numberEditIdentity
        return Binding(get:{notes.first{$0.id==note.id}?[keyPath:key] ?? note[keyPath:key]},set:{v in
            var current=store.numberEditIdentity;current.revision=identity.revision
            guard current==identity else{return};edit(note){$0[keyPath:key]=v}
        })
    }
    func integer(_ note:Note,_ key:WritableKeyPath<Note,Int>)->Binding<Double> {
        let identity=store.numberEditIdentity
        return Binding(get:{Double(notes.first{$0.id==note.id}?[keyPath:key] ?? note[keyPath:key])},set:{v in
            var current=store.numberEditIdentity;current.revision=identity.revision
            guard current==identity,v.isFinite else{return};edit(note){$0[keyPath:key]=Int(v)}
        })
    }
}
