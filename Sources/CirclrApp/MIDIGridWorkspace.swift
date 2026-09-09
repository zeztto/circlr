import SwiftUI
import CirclrCore

struct MIDIGridWorkspace:View {
    @ObservedObject var store:AppStore
    @Binding var topPitch:Int
    @Binding var steps:StepEditorState
    @Binding var pianoScroll:EditorScrollPosition
    @Binding var stepScroll:EditorScrollPosition
    @State private var focusTarget=MIDIEditorFocus()
    @State private var revealRequest=0
    var selected:Note? {store.currentLane?.notes.first{$0.id==store.selectedNoteID}}
    var keyHelp:String {store.midiStepMode ? "방향키 셀 선택 · Return 켜기/끄기 · Delete 지우기 · 행 이름 선택 · Home/End 첫·끝 행 · PageUp/Down 화면 이동 · Tab 수치 입력":"선택 노트 드래그: 함께 이동 · 끝 손잡이: 함께 길이 · ⇧클릭: 선택 추가/해제 · F 선택 보기 · Tab 노트 선택 · 방향키 이동 · ⇧ 좌우 길이 · ⌥ 상하 세기 · Return 입력 · Delete 삭제"}
    var body:some View {
        GeometryReader { geometry in
        let compact=geometry.size.width<700
        VStack(alignment:.leading,spacing:10) {
            MIDIWorkspaceToolbar(store:store,focusTarget:focusTarget) {
                if !store.midiStepMode {Button("선택 보기"){revealSelectedNotes()}.disabled(selected==nil).help("선택한 MIDI 노트로 이동 · F")}
                Spacer(minLength:0)
                    if store.midiStepMode && steps.drumMode {StepRowSearch(store:store,state:$steps,focusTarget:focusTarget)}
                    else {
                        Button{topPitch=max(store.midiStepMode ? 12:27,topPitch-12);focusTarget.focus()}label:{Image(systemName:"minus")}.accessibilityLabel("표시 음역 한 옥타브 아래")
                        Text(Scale.roots[(topPitch-1)%12]+String((topPitch-1)/12-1)).monospacedDigit().help("표시 범위의 가장 높은 음")
                        Button{topPitch=min(128,topPitch+12);focusTarget.focus()}label:{Image(systemName:"plus")}.accessibilityLabel("표시 음역 한 옥타브 위")
                    }
                }
            HStack(alignment:.top,spacing:compact ? 12:20) {
                VStack(alignment:.leading,spacing:10) {
                if store.midiStepMode {StepEditor(store:store,topPitch:topPitch,state:$steps,focusTarget:focusTarget,scroll:$stepScroll)}
                else {
                    GeometryReader { geometry in
                        ScrollView([.horizontal,.vertical]) {
                            PianoRoll(store:store,topPitch:topPitch-1,focusTarget:focusTarget,revealRequest:revealRequest,requestReveal:revealSelectedNotes)
                                .frame(width:max(geometry.size.width,store.editorBeats*48+64),height:562)
                                .rememberEditorScroll($pianoScroll)
                        }.background(StudioTheme.canvas)
                    }
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            MIDINoteInspector(store:store,focusTarget:focusTarget,hint:store.midiStepMode ? "방향키 선택 · Return 켜기/끄기":"Tab 선택 · 방향키 편집",keyHelp:keyHelp,width:compact ? 210:252)
            }
        }
        .environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focusTarget.focus()}))
        .onChange(of:selected){_,_ in revealPitch()}
        .onChange(of:store.midiStepMode){_,_ in topPitch=max(store.midiStepMode ? 12:27,topPitch);revealPitch()}
        }
    }
    func revealSelectedNotes() {
        guard let selected else{return}
        let notes=(store.currentLane?.notes ?? []).filter{store.selectedMIDIIDs.contains($0.id)}
        let low=notes.map(\.pitch).min() ?? selected.pitch,high=notes.map(\.pitch).max() ?? selected.pitch
        if high-low<27 {
            topPitch=min(128,max(high+1,min(topPitch,low+27)))
        } else {
            topPitch=min(128,max(selected.pitch+1,min(topPitch,selected.pitch+27)))
        }
        revealRequest &+= 1;focusTarget.focus()
    }
    func revealPitch() {
        guard let selected else{return};let rows=store.midiStepMode ? 12:27
        if selected.pitch>=topPitch {topPitch=min(128,selected.pitch+1)}
        if selected.pitch<topPitch-rows {topPitch=max(rows,selected.pitch+rows)}
    }
}
