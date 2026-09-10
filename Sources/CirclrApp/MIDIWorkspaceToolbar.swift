import SwiftUI
import CirclrCore

/// Shared actions use the whole workspace width, including the note inspector.
struct MIDIWorkspaceToolbar<Trailing:View>:View {
    @ObservedObject var store:AppStore
    let focusTarget:MIDIEditorFocus
    @ViewBuilder let trailing:()->Trailing
    private var sharedPattern:RhythmPattern? {store.editPatternID.flatMap{id in store.project.patterns.first{$0.id==id}}}
    var body:some View {
        MIDIWorkspaceToolbarLayout {
            HStack(spacing:10) {
            Picker("MIDI 편집 방식",selection:$store.midiStepMode) {
                Text(store.project.usesOrbits ? "궤도":"피아노 롤").tag(false)
                Text("스텝").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width:110)
            Menu(sharedPattern == nil ? "MIDI":"공유 리듬 MIDI") {
                Button("MIDI 파일 가져오기"){store.chooseMIDIImport()}
                Button("MIDI 저장"){store.exportMIDI()}
                Menu("패턴 추가"){ForEach(MIDIPattern.allCases,id:\.self){pattern in Button(pattern.label){store.generateMIDI(pattern)}}}
                Button("전체 선택 · ⌘A"){store.chooseMIDINotes(.all);focusTarget.focus()}
                Button("선택 해제 · ⇧⌘A"){store.chooseMIDINotes(.clear);focusTarget.focus()}
            }.fixedSize()
                .help(sharedPattern.map{"공유 리듬 · \($0.name) · 노트·클립 변경은 같은 패턴을 사용하는 모든 곳에 반영됩니다"} ?? "MIDI 가져오기·저장·노트 선택")
            TrackBounceButton(store:store)
            Button{store.startMIDIRecording()}label:{Image(systemName:store.midiRecording ? "stop.circle":"record.circle")}
                .accessibilityLabel(store.midiRecording ? "MIDI 녹음 정지":"MIDI 녹음")
                .disabled(store.editPatternID != nil)
            }
            HStack(spacing:10) {trailing()}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

/// Reflow existing groups without rebuilding controls or their editing state.
struct MIDIWorkspaceToolbarLayout:SwiftUI.Layout {
    private let gap:CGFloat=10
    private func arrangement(width:CGFloat,subviews:Subviews)->(positions:[CGPoint],height:CGFloat) {
        var positions:[CGPoint]=[],x:CGFloat=0,y:CGFloat=0,rowHeight:CGFloat=0
        for view in subviews {
            let size=view.sizeThatFits(.unspecified)
            if x>0 && x+size.width>width {x=0;y+=rowHeight+gap;rowHeight=0}
            positions.append(CGPoint(x:x,y:y))
            if size.width>0 {x+=size.width+gap}
            rowHeight=max(rowHeight,size.height)
        }
        return (positions,y+rowHeight)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) -> CGSize {
        let ideal=subviews.map{$0.sizeThatFits(.unspecified).width}.reduce(0,+)+CGFloat(max(0,subviews.count-1))*gap
        let width=proposal.width ?? ideal
        return CGSize(width:width,height:arrangement(width:width,subviews:subviews).height)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let positions=arrangement(width:bounds.width,subviews:subviews).positions
        for index in subviews.indices {
            let position=positions[index]
            let isLastOnRow=index==subviews.count-1 || positions[index+1].y != position.y
            let size=subviews[index].sizeThatFits(.unspecified)
            subviews[index].place(at:CGPoint(x:bounds.minX+position.x,y:bounds.minY+position.y),anchor:.topLeading,
                                 proposal:ProposedViewSize(width:isLastOnRow ? bounds.width-position.x:size.width,height:size.height))
        }
    }
}
