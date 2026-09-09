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
    @State private var fieldFocus=NumberFieldFocus(["MIDI 음높이","MIDI 시작 박","MIDI 길이 박","MIDI 세기","MIDI 선택 음정 이동","MIDI 선택 시작 이동","MIDI 선택 길이 변경","MIDI 선택 세기 변경"])
    var notes:[Note] {store.currentLane?.notes ?? []}
    var selected:Note? {notes.first{$0.id==store.selectedNoteID}}
    func name(_ pitch:Int)->String {Scale.roots[pitch%12]+String(pitch/12-1)}
    func division(_ value:Int)->String {[1:"1/4",2:"1/8",3:"1/8 셋잇단",4:"1/16",6:"1/16 셋잇단",8:"1/32"][value] ?? "1/16"}
    var body:some View {
        ScrollView {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:6) {
                MIDINoteSelectionMenu(store:store,focusTarget:focusTarget)
                Spacer(minLength:0)
                if !store.selectedMIDIIDs.isEmpty {
                    Button{act{store.duplicateMIDINotes()}}label:{Image(systemName:"plus.square.on.square")}
                        .accessibilityLabel("선택 MIDI 노트 복제").help("선택 노트 복제 · ⌘D")
                    Button{act{store.editMIDINotes(.delete)}}label:{Image(systemName:"trash")}
                        .accessibilityLabel("선택 MIDI 노트 삭제").help("선택 노트 삭제 · Delete")
                }
            }
            if let note=selected,store.selectedMIDIIDs.count==1 {
                Grid(alignment:.leading,horizontalSpacing:10,verticalSpacing:8) {
                    GridRow {
                        compactField("음높이 · "+name(note.pitch),title:"MIDI 음높이",value:integer(note,\.pitch),range:0...127,integer:true)
                        compactField("시작 · 박",title:"MIDI 시작 박",value:number(note,\.beat),range:0...max(0,store.editorBeats-note.length),presentation:.beatPosition)
                    }
                    GridRow {
                        compactField("길이 · 박",title:"MIDI 길이 박",value:number(note,\.length),range:0.03125...max(0.03125,store.editorBeats-note.beat))
                        compactField("세기",title:"MIDI 세기",value:integer(note,\.velocity),range:1...127,integer:true)
                    }
                }
            } else if store.selectedMIDIIDs.count>1 {
                let ids=store.selectedMIDIIDs,selectedNotes=notes.filter{ids.contains($0.id)}
                if let low=selectedNotes.map(\.pitch).min(),let high=selectedNotes.map(\.pitch).max(),
                   let quiet=selectedNotes.map(\.velocity).min(),let loud=selectedNotes.map(\.velocity).max() {
                    Text("\(name(low))–\(name(high)) · 세기 \(quiet)–\(loud)")
                        .font(.system(size:11)).monospacedDigit().foregroundStyle(StudioTheme.secondary)
                        .accessibilityLabel("MIDI 선택 범위 · \(name(low))–\(name(high)) · 세기 \(quiet)–\(loud)")
                }
                Grid(alignment:.leading,horizontalSpacing:10,verticalSpacing:8) {
                    GridRow {
                        deltaField("음정 이동","반음",range:-127...127,integer:true){.transpose(Int($0))}
                        deltaField("시작 이동","박",range:-131072...131072){.move($0)}
                    }
                    GridRow {
                        deltaField("길이 변경","박",range:-131072...131072){.lengthDelta($0)}
                        deltaField("세기 변경","단계",range:-126...126,integer:true){.velocityDelta(Int($0))}
                    }
                }
                Text("입력값만큼 함께 조절 · 0은 변경 없음").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
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
            } else {Text("노트를 선택하면 음높이·시작·길이·세기를 편집합니다").foregroundStyle(StudioTheme.secondary)}
            if store.selectedMIDIIDs.isEmpty {Text(hint).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).help(keyHelp)}
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,6)
        }.frame(width:252,alignment:.leading)
        .environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focusTarget.focus()},fieldFocus:fieldFocus))
    }
    func compactField(_ label:String,title:String,value:Binding<Double>,range:ClosedRange<Double>,integer:Bool=false,presentation:NumberEditPresentation = .number,validate:((Double)throws->Void)?=nil)->some View {
        VStack(alignment:.leading,spacing:3) {
            Text(label).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(1)
            CommittedNumberField(title:title,value:value,range:range,integerOnly:integer,width:112,presentation:presentation,validate:validate)
        }
    }
    func deltaField(_ label:String,_ unit:String,range:ClosedRange<Double>,integer:Bool=false,change:@escaping(Double)->MIDIEditing.Change)->some View {
        let identity=store.numberEditIdentity
        let binding=Binding<Double>(get:{0},set:{value in
            var current=store.numberEditIdentity;current.revision=identity.revision
            guard current==identity,value != 0 else{return}
            store.editMIDINotes(change(value))
        })
        return compactField(label+" · "+unit,title:"MIDI 선택 "+label,value:binding,range:range,integer:integer,validate:{value in
            guard let lane=store.currentLane else {throw CirclrError("편집할 MIDI 노트를 선택하세요")}
            _=try MIDIEditing.apply(change(value),to:lane,ids:store.selectedMIDIIDs,beats:store.editorBeats)
        })
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
