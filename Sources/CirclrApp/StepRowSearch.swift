import SwiftUI
import CirclrCore

struct StepRowSearch:View {
    @ObservedObject var store:AppStore
    @Binding var state:StepEditorState
    let focusTarget:MIDIEditorFocus
    var rows:[StepRow] {StepRows.filter(store.stepRows(extra:state.extraPitches),query:state.rowQuery)}
    var hiddenSelection:Bool {store.currentLane?.notes.first{$0.id==store.selectedNoteID}.map{note in !rows.contains{$0.pitch==note.pitch}} ?? false}
    var body:some View {
        HStack(spacing:5) {
            TextField("드럼 행 찾기",text:$state.rowQuery).textFieldStyle(.plain)
                .accessibilityLabel("드럼 행 검색").help("현재 행 이름·샘플 이름·MIDI 번호 검색 · Return 격자 · Esc 검색 해제")
                .onSubmit{if !rows.isEmpty {focusTarget.focus()}}
                .onExitCommand{state.rowQuery="";focusTarget.focus()}
            if !state.rowQuery.isEmpty {Button{state.rowQuery="";focusTarget.focus()}label:{Image(systemName:"xmark")}.accessibilityLabel("드럼 행 검색 지우기")}
            if hiddenSelection {Button{state.rowQuery="";focusTarget.focus()}label:{Image(systemName:"scope")}.accessibilityLabel("선택한 드럼 행 보기")}
        }.padding(.horizontal,8).padding(.vertical,5).background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:5))
            .frame(minWidth:100,maxWidth:220)
    }
}
