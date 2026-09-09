import SwiftUI
import CirclrCore

struct StepEditorState {
    var subdivisions=4
    var page=0
    var drumMode=false
    var extraPitches:Set<Int>=[]
    var newPitch=36
    var rowQuery=""
}

struct MIDIGridWorkspace:View {
    @ObservedObject var store:AppStore
    @Binding var topPitch:Int
    @Binding var steps:StepEditorState
    @State private var focusTarget=MIDIEditorFocus()
    var selected:Note? {store.currentLane?.notes.first{$0.id==store.selectedNoteID}}
    var keyHelp:String {store.midiStepMode ? "방향키 셀 선택 · Return 켜기/끄기 · Delete 지우기 · 행 이름 선택 · Home/End 첫·끝 행 · PageUp/Down 화면 이동 · Tab 수치 입력":"선택 노트 드래그: 함께 이동 · 끝 손잡이: 함께 길이 · ⇧클릭: 선택 추가/해제 · Tab 노트 선택 · 방향키 이동 · ⇧ 좌우 길이 · ⌥ 상하 세기 · Return 입력 · Delete 삭제"}
    var body:some View {
        HStack(alignment:.top,spacing:20) {
            VStack(alignment:.leading,spacing:10) {
                HStack(spacing:10) {
                    Picker("MIDI 편집 방식",selection:$store.midiStepMode){Text(store.project.usesOrbits ? "궤도":"피아노 롤").tag(false);Text("스텝").tag(true)}.pickerStyle(.segmented).labelsHidden().frame(width:110)
                    Menu("MIDI") {
                        Button("MIDI 파일 가져오기"){store.chooseMIDIImport()};Button("MIDI 저장"){store.exportMIDI()}
                        Menu("패턴 추가"){ForEach(MIDIPattern.allCases,id:\.self){pattern in Button(pattern.label){store.generateMIDI(pattern)}}}
                        Button("전체 선택 · ⌘A"){store.selectMIDINotes(Set((store.currentLane?.notes ?? []).map(\.id)));focusTarget.focus()}
                        Button("선택 해제"){store.selectedNoteID=nil;focusTarget.focus()}
                    }
                    Button("바운스"){store.bounceTrack()}.disabled(store.preparing)
                    Button{store.startMIDIRecording()}label:{Image(systemName:store.midiRecording ? "stop.circle":"record.circle")}.accessibilityLabel(store.midiRecording ? "MIDI 녹음 정지":"MIDI 녹음").disabled(store.editPatternID != nil)
                    Spacer(minLength:0)
                    if store.midiStepMode && steps.drumMode {StepRowSearch(store:store,state:$steps,focusTarget:focusTarget)}
                    else {
                        Button{topPitch=max(store.midiStepMode ? 12:27,topPitch-12);focusTarget.focus()}label:{Image(systemName:"minus")}.accessibilityLabel("표시 음역 한 옥타브 아래")
                        Text(Scale.roots[(topPitch-1)%12]+String((topPitch-1)/12-1)).monospacedDigit().help("표시 범위의 가장 높은 음")
                        Button{topPitch=min(128,topPitch+12);focusTarget.focus()}label:{Image(systemName:"plus")}.accessibilityLabel("표시 음역 한 옥타브 위")
                    }
                }
                if store.midiStepMode {StepEditor(store:store,topPitch:topPitch,state:$steps,focusTarget:focusTarget)}
                else {
                    GeometryReader { geometry in
                        ScrollView([.horizontal,.vertical]) {
                            PianoRoll(store:store,topPitch:topPitch-1,focusTarget:focusTarget)
                                .frame(width:max(geometry.size.width,store.editorBeats*48+64),height:562)
                        }.background(StudioTheme.canvas)
                    }
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            MIDINoteInspector(store:store,focusTarget:focusTarget,hint:store.midiStepMode ? "방향키 선택 · Return 켜기/끄기":"Tab 선택 · 방향키 편집",keyHelp:keyHelp)
        }
        .environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focusTarget.focus()}))
        .onAppear{revealPitch()}
        .onChange(of:selected){_,_ in revealPitch()}
        .onChange(of:store.midiStepMode){_,_ in revealPitch()}
        .onChange(of:store.stepRowScope){_,_ in steps.rowQuery="";steps.extraPitches=[]}
    }
    func revealPitch() {
        guard let selected else{return};let rows=store.midiStepMode ? 12:27
        if selected.pitch>=topPitch {topPitch=min(128,selected.pitch+1)}
        if selected.pitch<topPitch-rows {topPitch=max(rows,selected.pitch+rows)}
    }
}
