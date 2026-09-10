import CirclrCore

extension AppStore {
    var recordedTakeChoices:[RecordedTake] {
        (project.takes ?? []).filter{recordedTakeSummary($0) != nil}
    }
    func recordedTakeSummary(_ take:RecordedTake)->RecordedTakeSummary? {
        guard let use=selectedUse,let laneID=selectedLaneID else{return nil}
        return RecordedTakeSummary.make(take,arrangementID:project.activeArrangementID,useID:use.id,laneID:laneID,in:project)
    }
    func showRecordedTakes() {
        guard !trackBounceRecoveryLocked,midiImportDraft==nil,nameEditing.resolve() else{return}
        let identity=numberEditIdentity
        let commands=recordedTakeChoices.enumerated().compactMap{index,take -> StudioCommand? in
            guard let summary=recordedTakeSummary(take) else{return nil}
            let detail="노트 \(summary.noteCount)개 · 클립 \(summary.clipCount)개" + (summary.matchesCurrentContent ? " · 현재 내용과 일치":"")
            return StudioCommand(id:"recorded-take-"+take.id,title:"#\(index+1) · \(take.name)",detail:detail,run:{[weak self] in
                self?.applyRecordedTake(take.id,identity:identity)
            })
        }
        guard !commands.isEmpty else{status="이 서클의 녹음 테이크가 없습니다";return}
        arrangementPickerRequest=nil;soundPickerRequest=nil;libraryOpen=false;navigationOpen=false;keyboardHelp=false
        commandPalette=StudioPalette(commands:commands,title:"녹음 테이크 · 이번 사용에 적용",placeholder:"#번호 · 테이크 이름 · 노트 · 클립 검색",
            emptyMessage:"일치하는 테이크가 없습니다",footer:"↑ ↓ 선택 · Return 적용 · Esc 취소 · 공유 원본 유지",countUnit:"테이크",listHeight:min(360,Double(max(1,commands.count)*60+14)))
    }
    private func applyRecordedTake(_ id:ID,identity:NumberEditIdentity) {
        guard numberEditIdentity==identity,!trackBounceRecoveryLocked,midiImportDraft==nil,
              let live=project.takes?.first(where:{$0.id==id}),recordedTakeSummary(live) != nil else{
            status="편집 대상이 바뀌었습니다. 테이크 검색을 다시 여세요";return
        }
        activateTake(live)
    }
}
