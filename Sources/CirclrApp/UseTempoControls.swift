import SwiftUI
import CirclrCore

/// Per-use tempo map controls; instrument and source-node tempo settings remain independent.
struct UseTempoControls:View {
    @ObservedObject var store:AppStore
    let useID:ID
    let arrangementID:ID
    let tempo:UseTempoOverride
    let identity:NumberEditIdentity
    var requiredAddress:CircleAddress? = nil

    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            Text("가져온 템포 사용 · 시작 \(NumberEditSession<Int>.format(tempo.initialBPM)) BPM · \(tempo.changes.count)회 변화")
                .font(.system(size:13)).fixedSize(horizontal:false,vertical:true)
            Text("이번 섹션 사용에만 적용 · 기존 템포 설정은 보관됩니다")
                .font(.system(size:11)).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
            Button("이전 템포 설정으로 복귀",action:clear)
                .help("이번 사용의 가져온 템포 맵을 해제합니다. 다른 사용과 공유 원본은 유지합니다")
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func clear() {
        guard identity==store.numberEditIdentity,(requiredAddress==nil || requiredAddress==store.hierarchySelection),store.project.activeArrangementID==arrangementID,
              store.selectedUse?.id==useID,store.selectedUse?.tempoOverride==tempo else {
            store.status="편집 대상이 바뀌었습니다. 설정을 다시 여세요";return
        }
        guard store.nameEditing.resolve() else{return}
        var resolved=identity;resolved.revision=store.project.musicRevision
        guard resolved==store.numberEditIdentity,store.project.activeArrangementID==arrangementID,
              store.selectedUse?.id==useID,store.selectedUse?.tempoOverride==tempo else {
            store.status="편집 대상이 바뀌었습니다. 설정을 다시 여세요";return
        }
        store.mutate("이전 템포 설정으로 복귀") {project in
            guard resolved==store.numberEditIdentity,project.activeArrangementID==arrangementID,
                  project.active.uses.first(where:{$0.id==useID})?.tempoOverride==tempo else {
                throw CirclrError("편집 대상이 바뀌었습니다. 설정을 다시 여세요")
            }
            try UseTempoOverrideEditing.clear(useID:useID,in:&project)
        }
    }
}
