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

struct MIDIOrbitWorkspace:View {
    @ObservedObject var store:AppStore
    @Binding var viewport:MIDIOrbitViewport
    @Binding var scroll:EditorScrollPosition
    @State private var focusTarget=MIDIEditorFocus()
    var notes:[Note] {store.currentLane?.notes ?? []}
    var selected:Note? {notes.first{$0.id==store.selectedNoteID}}
    var clock:MusicClock? {store.orbitMIDIClock}
    func name(_ pitch:Int)->String {Scale.roots[pitch%12]+String(pitch/12-1)}
    private let keyHelp="선택 노트 드래그: 함께 이동 · 끝 손잡이: 함께 길이 · ⇧클릭: 선택 추가/해제 · Tab 노트 선택 · 방향키 이동 · ⇧ 좌우 길이 · ⌥ 상하 세기 · Return 입력 · Delete 삭제"
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            MIDIWorkspaceToolbar(store:store,focusTarget:focusTarget) {
                Spacer(minLength:0)
                Text("\(notes.count)개 노트").foregroundStyle(StudioTheme.secondary)
                Button{browse(-1)}label:{Image(systemName:"backward.end")}.accessibilityLabel("이전 MIDI 노트").help("이전 노트 선택·표시").disabled(notes.isEmpty)
                Button{browse(1)}label:{Image(systemName:"forward.end")}.accessibilityLabel("다음 MIDI 노트").help("다음 노트 선택·표시").disabled(notes.isEmpty)
            }
            HStack(alignment:.top,spacing:20) {
            ScrollView {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:8) {
                    Button{act{viewport.movePitches(-12)}}label:{Image(systemName:"minus")}.accessibilityLabel("표시 음역 한 옥타브 아래")
                    Text(name(viewport.lowest)+"–"+name(viewport.highest)).monospacedDigit()
                    Button{act{viewport.movePitches(12)}}label:{Image(systemName:"plus")}.accessibilityLabel("표시 음역 한 옥타브 위")
                    Spacer(minLength:0)
                    Button("맞춤"){act{viewport.fitPitches(notes)}}.fixedSize().accessibilityLabel("연주 음역 맞춤").help("연주의 음역에 맞춰 1옥타브 또는 2옥타브를 표시")
                }
                HStack(spacing:8) {
                    Picker("표시 음역",selection:$viewport.pitchRows){Text("1옥타브").tag(12);Text("2옥타브").tag(24)}.pickerStyle(.segmented).labelsHidden().frame(width:132)
                }
                MIDIPitchNavigator(viewport:$viewport,notes:notes,selected:selected,identity:store.numberEditIdentity,focusTarget:focusTarget).frame(height:37)
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
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,6).rememberEditorScroll($scroll)
            }.frame(maxHeight:.infinity)
            .frame(width:228,alignment:.leading)
            OrbitMIDIEditor(store:store,viewport:viewport,focusTarget:focusTarget).frame(minWidth:180,maxWidth:.infinity,maxHeight:.infinity).help(keyHelp)
            MIDINoteInspector(store:store,focusTarget:focusTarget,hint:"Tab 선택 · 방향키 편집",keyHelp:keyHelp)
            }
        }
        .environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focusTarget.focus()}))
        .onChange(of:selected){_,_ in reveal()}
    }
    func act(_ action:()->Void){action();focusTarget.focus()}
    func reveal(){if let selected,let clock {viewport.reveal(selected,clock:clock)}}
    func browse(_ delta:Int) {
        let sorted=MIDIOrbitViewport.ordered(notes);guard !sorted.isEmpty else{return}
        let i=sorted.firstIndex{$0.id==store.selectedNoteID} ?? (delta>0 ? -1:0)
        act{let note=sorted[(i+delta+sorted.count)%sorted.count];store.selectedNoteID=note.id;store.selectedBeat=note.beat}
    }
}
