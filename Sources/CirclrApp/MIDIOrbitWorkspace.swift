import AppKit
import SwiftUI
import CirclrCore

extension AppStore {
    var orbitMIDIClock:MusicClock? {
        guard let base=currentClock else{return nil}
        if abs(base.beats-editorBeats)<1e-8{return base}
        return try? MusicClock(parent:base,start:0,length:editorBeats,context:currentContext,inheritTempo:true,inheritMeter:true)
    }
}

@MainActor final class MIDIOrbitFocus {
    weak var view:OrbitMIDIView?
    func focus(){guard let view else{return};view.window?.makeFirstResponder(view)}
}

struct MIDIOrbitWorkspace:View {
    @ObservedObject var store:AppStore
    @Binding var viewport:MIDIOrbitViewport
    @State private var focusTarget=MIDIOrbitFocus()
    var notes:[Note] {store.currentLane?.notes ?? []}
    var selected:Note? {notes.first{$0.id==store.selectedNoteID}}
    var clock:MusicClock? {store.orbitMIDIClock}
    func name(_ pitch:Int)->String {Scale.roots[pitch%12]+String(pitch/12-1)}
    func division(_ value:Int)->String {[1:"1/4",2:"1/8",3:"1/8 셋잇단",4:"1/16",6:"1/16 셋잇단",8:"1/32"][value] ?? "1/16"}
    private let keyHelp="Tab 노트 선택 · 방향키 이동 · ⇧ 좌우 길이 · ⌥ 상하 세기 · Return 입력 · Delete 삭제"
    var body:some View {
        HStack(alignment:.top,spacing:20) {
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Picker("MIDI 편집 방식",selection:$store.midiStepMode){Text("궤도").tag(false);Text("스텝").tag(true)}.pickerStyle(.segmented).labelsHidden().frame(width:110)
                    Text("\(notes.count)개 노트").foregroundStyle(StudioTheme.secondary)
                }
                HStack(spacing:8) {
                    Button{act{viewport.topPitch=max(viewport.rows-1,viewport.highest-12)}}label:{Image(systemName:"minus")}.accessibilityLabel("표시 음역 한 옥타브 아래")
                    Text(name(viewport.lowest)+"–"+name(viewport.highest)).monospacedDigit()
                    Button{act{viewport.topPitch=min(127,viewport.highest+12)}}label:{Image(systemName:"plus")}.accessibilityLabel("표시 음역 한 옥타브 위")
                }
                HStack(spacing:8) {
                    Picker("표시 음역",selection:$viewport.pitchRows){Text("1옥타브").tag(12);Text("2옥타브").tag(24)}.pickerStyle(.segmented).labelsHidden().frame(width:132)
                    Button("연주 음역"){act{viewport.fitPitches(notes)}}
                }
                if let clock {
                    let bars=viewport.bars(clock)
                    HStack(spacing:10) {
                        Button{act{viewport.page=max(0,viewport.page-1)}}label:{Image(systemName:"chevron.left")}.accessibilityLabel("이전 MIDI 마디 범위").disabled(bars.lowerBound==0)
                        Text("\(bars.lowerBound+1)–\(bars.upperBound)마디 / \(clock.meters.count)").monospacedDigit()
                        Button{act{viewport.page=min(viewport.pageCount(clock)-1,viewport.page+1)}}label:{Image(systemName:"chevron.right")}.accessibilityLabel("다음 MIDI 마디 범위").disabled(bars.upperBound==clock.meters.count)
                    }
                    let outside=notes.filter{!viewport.visible($0,clock:clock)}.count
                    HStack(spacing:8) {
                        Menu(viewport.barsPerPage==0 ? "전체 길이":"\(viewport.barsPerPage)마디씩 보기") {
                            ForEach([1,2,4,8,0],id:\.self){bars in Button(bars==0 ? "전체 길이":"\(bars)마디씩 보기"){act{viewport.barsPerPage=bars;viewport.page=0}}}
                        }.fixedSize()
                        if let selected,!viewport.visible(selected,clock:clock) {Button("선택 보기"){act{viewport.reveal(selected,clock:clock)}}}
                        else if outside>0 {Text("범위 밖 \(outside)개").font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(1)}
                    }
                }
                HStack(spacing:12) {
                    Button("이전 노트"){browse(-1)}.disabled(notes.isEmpty)
                    Button("다음 노트"){browse(1)}.disabled(notes.isEmpty)
                }
                HStack {
                    Menu("MIDI") {
                        Button("MIDI 파일 가져오기"){store.chooseMIDIImport()}
                        Button("MIDI 저장"){store.exportMIDI()}
                        Menu("패턴 추가"){ForEach(MIDIPattern.allCases,id:\.self){pattern in Button(pattern.label){store.generateMIDI(pattern)}}}
                        Button("전체 선택 · ⌘A"){act{store.selectMIDINotes(Set(notes.map(\.id)))}}
                        Button("선택 해제"){act{store.selectedNoteID=nil}}
                    }
                    Button("바운스"){store.bounceTrack()}.disabled(store.preparing)
                    Button{store.startMIDIRecording()}label:{Image(systemName:store.midiRecording ? "stop.circle":"record.circle")}.accessibilityLabel(store.midiRecording ? "MIDI 녹음 정지":"MIDI 녹음").disabled(store.editPatternID != nil)
                }
                Spacer(minLength:0)
            }.frame(width:228,alignment:.leading)
            OrbitMIDIEditor(store:store,viewport:viewport,focusTarget:focusTarget).frame(minWidth:180,maxWidth:.infinity,maxHeight:.infinity).help(keyHelp)
            VStack(alignment:.leading,spacing:8) {
                if let note=selected,store.selectedMIDIIDs.count==1 {
                    HStack(spacing:8) {Text("음높이").foregroundStyle(StudioTheme.secondary);CommittedNumberField(title:"MIDI 음높이",value:integer(note,\.pitch),range:0...127,integerOnly:true,width:64);Text(name(note.pitch)).monospacedDigit()}
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
                    }
                    HStack(spacing:12) {Text("\(store.selectedMIDIIDs.count)개 선택").foregroundStyle(StudioTheme.secondary);Button("복제"){act{store.duplicateMIDINotes()}};Button("삭제"){act{store.editMIDINotes(.delete)}}}
                } else {Text("원호를 클릭하거나 Tab으로 노트를 선택하세요").foregroundStyle(StudioTheme.secondary)}
                Text("Tab 선택 · 방향키 편집").font(.system(size:12)).foregroundStyle(StudioTheme.secondary).help(keyHelp)
                Spacer(minLength:0)
            }.frame(width:252,alignment:.leading)
        }
        .environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focusTarget.focus()}))
        .onAppear{reveal()}
        .onChange(of:selected){_,_ in reveal()}
    }
    func field(_ title:String,value:Binding<Double>,range:ClosedRange<Double>,integer:Bool=false)->some View {
        HStack(spacing:12){Text(title).foregroundStyle(StudioTheme.secondary).frame(width:58,alignment:.leading);CommittedNumberField(title:"MIDI "+title,value:value,range:range,integerOnly:integer,width:88)}
    }
    func act(_ action:()->Void){action();focusTarget.focus()}
    func reveal(){if let selected,let clock {viewport.reveal(selected,clock:clock)}}
    func browse(_ delta:Int) {
        let sorted=MIDIOrbitViewport.ordered(notes);guard !sorted.isEmpty else{return}
        let i=sorted.firstIndex{$0.id==store.selectedNoteID} ?? (delta>0 ? -1:0)
        act{let note=sorted[(i+delta+sorted.count)%sorted.count];store.selectedNoteID=note.id;store.selectedBeat=note.beat}
    }
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
