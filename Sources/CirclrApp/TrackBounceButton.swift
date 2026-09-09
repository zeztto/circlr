import SwiftUI
import CirclrCore

extension AppStore {
    var trackBounceIssue:String? {
        guard let use=selectedUse,let track=selectedTrack else{return "바운스할 출력 트랙을 선택하세요"}
        do {_=try BounceEditing.target(trackID:track.id,useID:use.id,arrangementID:project.activeArrangementID,in:project);return nil}
        catch{return error.localizedDescription}
    }
}

struct TrackBounceButton:View {
    @ObservedObject var store:AppStore
    var body:some View {
        let issue=store.trackBounceIssue
        let title=store.selectedTrack.map{"바운스 · \($0.name)"} ?? "바운스 · 트랙 선택"
        Button {store.bounceTrack()} label:{Text(issue==nil || store.selectedTrack==nil ? title:"바운스 · 연결 확인").lineLimit(1).truncationMode(.middle)}
            .frame(maxWidth:170)
            .disabled(store.preparing || issue != nil)
            .accessibilityLabel(title)
            .help(issue ?? "\(store.selectedTrack?.name ?? "트랙") · 이번 섹션 사용의 출력 앞 경로와 이펙트를 오디오로 만듭니다. 출력 볼륨·오토메이션과 전역 처리는 유지하며 원본 복원으로 되돌릴 수 있습니다.")
    }
}
