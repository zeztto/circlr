import SwiftUI
import CirclrCore

/// Clip selection stays in the same canvas; editing remains owned by the shared pattern.
struct SharedRhythmAudioWorkspace:View {
    @ObservedObject var store:AppStore
    @Binding var viewport:AudioSourceViewport
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if let pattern=store.sharedRhythmAudioPattern {
                let identity=store.numberEditIdentity
                HStack(spacing:8) {
                    Picker("공유 오디오 클립",selection:Binding(get:{store.selectedClipID ?? ""},set:{id in
                        guard store.numberEditIdentity==identity,store.nameEditing.resolve() else{return}
                        var current=store.numberEditIdentity;current.revision=identity.revision
                        guard current==identity,store.sharedRhythmAudioPattern?.id==pattern.id,
                              pattern.audio.contains(where:{$0.id==id}) else{return}
                        store.selectedClipID=id;store.audioSplitOffset=nil
                    })) {
                        ForEach(Array(pattern.audio.enumerated()),id:\.element.id) {index,clip in
                            Text("#\(index+1) · "+(store.project.assets.first{$0.id==clip.assetID}?.name ?? "미디어 없음")).tag(clip.id)
                        }
                    }.accessibilityLabel("공유 오디오 클립 선택").help("클립을 선택한 뒤 Tab으로 파형과 수치 편집에 이동합니다")
                    Text("\(pattern.audio.count)개").foregroundStyle(StudioTheme.secondary).fixedSize()
                }
                if let clip=store.currentAudioClip,let asset=store.project.assets.first(where:{$0.id==clip.assetID}) {
                    AudioWorkspaceView(store:store,clip:clip,asset:asset,viewport:$viewport)
                        .id(clip.id)
                } else {
                    Text(pattern.audio.isEmpty ? "이 공유 리듬 패턴에는 오디오 클립이 없습니다":"선택한 클립의 미디어를 찾을 수 없습니다")
                        .foregroundStyle(StudioTheme.secondary)
                    Text("패턴의 오디오 변경은 이 패턴을 사용하는 모든 섹션에 반영됩니다.").font(.system(size:12))
                    Spacer()
                }
            } else {
                Text("이 서클의 트랙과 일치하는 리듬 패턴을 선택하세요").foregroundStyle(StudioTheme.secondary)
                Spacer()
            }
        }
        .disabled(store.trackBounceRecoveryLocked)
        .onAppear{validateSelection()}
        .onChange(of:store.currentAudioClip?.assetID){_,_ in viewport.showAll()}
        .onChange(of:store.sharedRhythmAudioPattern?.audio.map(\.id)){_,_ in validateSelection()}
        .onChange(of:store.editPatternID){_,_ in validateSelection()}
    }
    private func validateSelection() {
        guard let pattern=store.sharedRhythmAudioPattern else{return}
        if !pattern.audio.contains(where:{$0.id==store.selectedClipID}) {
            store.selectedClipID=pattern.audio.first?.id;store.audioSplitOffset=nil
        }
    }
}

/// Unobserved, bounded presentation cache; mutation handlers always validate again.
struct SharedAudioPreflightKey:Equatable {
    enum Operation:Equatable {case split(Double),duplicate(Double?)}
    let projectID:ID
    let revision:Int
    let generation:Int
    let patternID:ID
    let trackID:ID
    let clipID:ID
    let operation:Operation
}
struct SharedAudioPreflightEntry {
    let key:SharedAudioPreflightKey
    let issue:String?
}
