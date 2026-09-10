import SwiftUI
import CirclrCore

/// Shared actions use the whole workspace width, including the note inspector.
struct MIDIWorkspaceToolbar<Trailing:View>:View {
    @ObservedObject var store:AppStore
    let focusTarget:MIDIEditorFocus
    @ViewBuilder let trailing:()->Trailing
    var body:some View {
        MIDIWorkspaceToolbarLayout {
            MIDIWorkspaceActions(store:store,focusTarget:focusTarget)
            HStack(spacing:10) {trailing()}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

/// One instance of the shared actions in either editor's wrapping toolbar.
struct MIDIWorkspaceActions:View {
    @ObservedObject var store:AppStore
    let focusTarget:MIDIEditorFocus
    private var sharedPattern:RhythmPattern? {store.editPatternID.flatMap{id in store.project.patterns.first{$0.id==id}}}
    var body:some View {
        Group {
            MIDIWorkspaceFileActions(store:store)
            let generation=store.midiGenerationRequest
            Menu("노트 작업") {
                if let generation {
                    Text(generation.rangeLabel).help("4분음표를 1박으로 표시합니다")
                    Text("기존 노트 유지 · 겹쳐 추가")
                    ForEach(MIDIPattern.allCases,id:\.self){pattern in
                        Button(pattern.label+" 추가"){store.generateMIDI(pattern,request:generation)}
                            .disabled(store.trackBounceRecoveryLocked || store.midiImportDraft != nil)
                    }
                } else {Text("MIDI를 추가할 편집 대상을 선택하세요")}
                Divider()
                Button("전체 선택 · ⌘A"){store.chooseMIDINotes(.all);focusTarget.focus()}
                Button("선택 해제 · ⇧⌘A"){store.chooseMIDINotes(.clear);focusTarget.focus()}
            }.id(MIDIGenerationMenuIdentity(request:generation)).fixedSize()
                .help(sharedPattern.map{"공유 리듬 · \($0.name) · 노트·클립 변경은 같은 패턴을 사용하는 모든 곳에 반영됩니다"} ?? "노트 생성·전체 선택·선택 해제")
            Button{store.startMIDIRecording()}label:{Image(systemName:store.midiRecording ? "stop.circle":"record.circle")}
                .accessibilityLabel(store.midiRecording ? "MIDI 녹음 정지":"MIDI 녹음")
                .disabled(store.editPatternID != nil)
        }
    }
}

/// Group intentionally exposes each action to the enclosing eager wrapping Layout.
struct MIDIWorkspaceFileActions:View {
    @ObservedObject var store:AppStore
    var body:some View {
        Group {
            MIDIEditorModeControls(store:store)
            Button("MIDI 가져오기…"){store.chooseMIDIImport()}
                .fixedSize().disabled(!store.midiImportActionAvailable)
                .help("현재 섹션에 새 MIDI 서클로 가져오기 · ⌥⌘I")
            Button("MIDI 저장…"){store.exportMIDI()}
                .fixedSize().disabled(!store.midiExportActionAvailable)
                .help(store.midiExportActionHelp)
            TrackBounceButton(store:store)
        }
    }
}

extension AppStore {
    var midiImportActionAvailable:Bool {selectedUse != nil && canStartMediaImport && midiImportDraft == nil}
    var midiExportActionAvailable:Bool {currentLane != nil && currentClock != nil && midiImportDraft == nil}
    var midiExportActionHelp:String {
        let scope=editPatternID.flatMap{id in project.patterns.first{$0.id==id}}.map{"공유 리듬 · "+$0.name}
            ?? ((editOriginal ? "공유 원본":"이번 사용")+" · "+(selectedUse?.name ?? "MIDI"))
        return scope+"의 현재 MIDI를 파일로 저장 · ⌥⌘E"
    }
    var midiTrackBounceActionAvailable:Bool {
        !trackBounceRecoveryLocked && trackBounceIssue == nil && !bounceTailEditing && bounceTailAssessment != nil
    }
}

/// Reflow existing groups without rebuilding controls or their editing state.
struct MIDIWorkspaceToolbarLayout:SwiftUI.Layout {
    var gap:CGFloat=10
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

struct MIDIEditorModeControls:View {
    @ObservedObject var store:AppStore
    var body:some View {
        HStack(spacing:4) {
            mode(store.project.usesOrbits ? "궤도":"피아노 롤",selected:!store.sustainOpen && !store.pitchBendOpen && !store.midiStepMode){store.sustainOpen=false;store.pitchBendOpen=false;store.midiStepMode=false}
            mode("스텝",selected:!store.sustainOpen && !store.pitchBendOpen && store.midiStepMode){store.sustainOpen=false;store.pitchBendOpen=false;store.midiStepMode=true}
            mode("피치 벤드",selected:store.pitchBendOpen && !store.sustainOpen){store.sustainOpen=false;store.pitchBendOpen=true;store.automationOpen=false}
            mode("페달",selected:store.sustainOpen){store.sustainOpen=true;store.pitchBendOpen=false;store.automationOpen=false}
        }.fixedSize()
    }
    private func mode(_ title:String,selected:Bool,action:@escaping()->Void)->some View {
        StudioModeButton(title:title,label:"MIDI 편집 방식 · "+title,selected:selected,help:title+" 편집") {
            var identity=store.numberEditIdentity
            guard store.resolveActiveNumericDraft(),store.nameEditing.resolve() else{return}
            identity.revision=store.project.musicRevision
            guard identity==store.numberEditIdentity else{return}
            action();store.requestEditorNavigationFocus()
        }.frame(width:CGFloat(title.count)*12+18,height:28)
    }
}
