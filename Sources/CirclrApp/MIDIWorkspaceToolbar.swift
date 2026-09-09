import SwiftUI
import CirclrCore

/// Shared actions use the whole workspace width, including the note inspector.
struct MIDIWorkspaceToolbar<Trailing:View>:View {
    @ObservedObject var store:AppStore
    let focusTarget:MIDIEditorFocus
    @ViewBuilder let trailing:()->Trailing
    var body:some View {
        HStack(spacing:10) {
            Picker("MIDI 편집 방식",selection:$store.midiStepMode) {
                Text(store.project.usesOrbits ? "궤도":"피아노 롤").tag(false)
                Text("스텝").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width:110)
            Menu("MIDI") {
                Button("MIDI 파일 가져오기"){store.chooseMIDIImport()}
                Button("MIDI 저장"){store.exportMIDI()}
                Menu("패턴 추가"){ForEach(MIDIPattern.allCases,id:\.self){pattern in Button(pattern.label){store.generateMIDI(pattern)}}}
                Button("전체 선택 · ⌘A"){store.chooseMIDINotes(.all);focusTarget.focus()}
                Button("선택 해제 · ⇧⌘A"){store.chooseMIDINotes(.clear);focusTarget.focus()}
            }.fixedSize()
            TrackBounceButton(store:store)
            Button{store.startMIDIRecording()}label:{Image(systemName:store.midiRecording ? "stop.circle":"record.circle")}
                .accessibilityLabel(store.midiRecording ? "MIDI 녹음 정지":"MIDI 녹음")
                .disabled(store.editPatternID != nil)
            trailing()
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
