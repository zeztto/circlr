import SwiftUI
import CirclrCore

/// Length belongs to this section use; restoring inheritance never edits its shared source.
struct SectionLengthControl:View {
    @ObservedObject var store:AppStore
    @State private var error:String?
    private var snapshot:SectionLengthEditing.Snapshot? {
        guard let use=store.selectedUse else{return nil}
        return try? SectionLengthEditing.snapshot(arrangementID:store.project.activeArrangementID,useID:use.id,in:store.project)
    }
    var body:some View {
        let identity=store.numberEditIdentity
        let length=snapshot
        VStack(alignment:.leading,spacing:4) {
            MIDIWorkspaceToolbarLayout(gap:8) {
                CountControl(title:"길이",value:Binding(get:{length?.effectiveBars ?? 1},set:{value in
                    apply(value,identity:identity,length:length)
                }),range:1...4096,suffix:"마디",fieldWidth:64,validate:{value in
                    guard let length else{throw CirclrError("길이를 편집할 섹션 사용을 찾을 수 없습니다")}
                    _ = try store.sectionUseLengthCandidate(value,identity:identity,snapshot:length)
                })
                    .disabled(length == nil)
                if let length {
                    Text(length.barsOverride == nil ? "원본 \(length.sourceBars)마디 사용":"이번 사용 \(length.effectiveBars) · 원본 \(length.sourceBars)마디")
                        .font(.system(size:11)).foregroundStyle(StudioTheme.secondary).fixedSize()
                        .help("이번 섹션 사용의 길이만 변경합니다. 공유 원본과 다른 사용은 유지됩니다")
                }
                Button("원본 길이 사용") {
                    guard identity==store.numberEditIdentity,let length,length==snapshot else {
                        error="섹션이나 길이가 바뀌었습니다. 현재 길이를 다시 확인하세요";store.status=error!;return
                    }
                    var scope=identity
                    guard store.resolveActiveNumericDraft(),store.nameEditing.resolve() else {
                        error="입력 중인 수치나 이름을 먼저 확인하세요";store.status=error!;return
                    }
                    scope.revision=store.project.musicRevision
                    guard scope==store.numberEditIdentity else {
                        error="편집 대상이 바뀌었습니다. 현재 섹션을 다시 확인하세요";store.status=error!;return
                    }
                    apply(nil,identity:scope,length:snapshot)
                }.fixedSize().disabled(length?.barsOverride == nil)
                    .help("이번 사용의 길이 지정을 제거하고 공유 원본의 길이를 따릅니다. 원본 음악은 변경하지 않습니다")
            }
            if let error {Text(error).font(.system(size:11)).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
            else if length == nil {Text("섹션 길이를 확인할 수 없습니다").font(.system(size:11)).foregroundStyle(.red)}
        }
        .onChange(of:store.selectedUse?.id){_,_ in error=nil}
        .onChange(of:store.project.activeArrangementID){_,_ in error=nil}
    }
    private func apply(_ bars:Int?,identity:NumberEditIdentity,length:SectionLengthEditing.Snapshot?) {
        do {
            guard let length else{throw CirclrError("길이를 편집할 섹션 사용을 찾을 수 없습니다")}
            try store.setSectionUseLength(bars,identity:identity,snapshot:length)
            error=nil
        } catch {self.error=error.localizedDescription;store.fail(error)}
    }
}

extension AppStore {
    func setSectionUseLength(_ bars:Int?,identity:NumberEditIdentity,snapshot:SectionLengthEditing.Snapshot)throws {
        let candidate=try sectionUseLengthCandidate(bars,identity:identity,snapshot:snapshot)
        guard candidate != project else{return}
        mutate(bars == nil ? "원본 길이 사용":"섹션 길이"){$0=candidate}
    }
    /// Pure preflight shared by native field validation and the actual setter.
    func sectionUseLengthCandidate(_ bars:Int?,identity:NumberEditIdentity,snapshot:SectionLengthEditing.Snapshot)throws->Project {
        guard identity==numberEditIdentity,project.activeArrangementID==snapshot.arrangementID,
              selectedUse?.id==snapshot.useID,
              try SectionLengthEditing.snapshot(arrangementID:snapshot.arrangementID,useID:snapshot.useID,in:project)==snapshot else {
            throw CirclrError("섹션이나 길이가 바뀌었습니다. 현재 길이를 다시 확인하세요")
        }
        guard !midiRecording,!audioRecordingBusy else{throw CirclrError("녹음 정지와 파일 마무리 후 길이를 편집하세요")}
        var candidate=project
        try SectionLengthEditing.set(bars:bars,arrangementID:snapshot.arrangementID,useID:snapshot.useID,in:&candidate)
        try UseTempoOverrideEditing.validateChanges(from:project,to:candidate)
        return candidate
    }
}
