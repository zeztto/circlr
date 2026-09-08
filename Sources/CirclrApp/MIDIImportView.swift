import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CirclrCore
import CirclrAudio

struct MIDIImportDraft {
    var fileName:String
    var document:ImportedMIDI
    var projectID:ID
    var revision:Int
    var arrangementID:ID
    var useID:ID
}
extension AppStore {
    func chooseMIDIImport() {
        guard let use=selectedUse,canStartMediaImport else {status="MIDI를 넣을 섹션을 선택하고 재생·녹음을 정지하세요";return}
        let projectID=project.id,revision=project.musicRevision,arrangementID=project.activeArrangementID,generation=mediaImportGeneration
        let panel=NSOpenPanel();panel.title="MIDI 노트 가져오기";panel.allowedContentTypes=[UTType(filenameExtension:"mid")!,UTType(filenameExtension:"midi")!];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        _=previewMIDIImport(url,projectID:projectID,revision:revision,generation:generation,arrangementID:arrangementID,useID:use.id)
    }
    @discardableResult func previewMIDIImport(_ url:URL,projectID:ID,revision:Int,generation:Int,arrangementID:ID,useID:ID)->Bool {
        guard canStartMediaImport,project.id==projectID,project.musicRevision==revision,mediaImportGeneration==generation,
              project.arrangements.first(where:{$0.id==arrangementID})?.uses.contains(where:{$0.id==useID}) == true else {status="대상이 변경됐습니다. 파일을 다시 선택하세요";return false}
        let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
        do {
            guard url.isFileURL else{throw CirclrError("로컬 MIDI 파일을 선택하세요")}
            let values=try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
            guard values.isRegularFile==true,let size=values.fileSize,size>0,size<=16_777_216 else {throw CirclrError("16 MiB 이하의 MIDI 파일을 선택하세요")}
            let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
            let document=try MIDIImport.read(handle.read(upToCount:16_777_217) ?? Data())
            hierarchySettingsOpen=false
            focusHierarchy(.section(arrangementID:arrangementID,useID:useID),detail:true)
            midiImportDraft=MIDIImportDraft(fileName:url.lastPathComponent,document:document,projectID:projectID,revision:revision,arrangementID:arrangementID,useID:useID)
            return true
        }catch{status="MIDI 가져오기 실패: \(error.localizedDescription)";return false}
    }
    func commitMIDIImport(_ draft:MIDIImportDraft,selected:Set<String>,extend:Bool) {
        guard project.id==draft.projectID,project.musicRevision==draft.revision,selectedUse?.id==draft.useID,project.activeArrangementID==draft.arrangementID,!midiRecording,!audioRecordPending,!audioRecordingBusy,!preparing else {fail(CirclrError("프로젝트가 변경됐습니다. 파일을 다시 선택하세요"));return}
        do {
            let parts=draft.document.tracks.filter{selected.contains($0.id)}.map{MIDIImportPart(name:$0.name,notes:$0.notes,drums:$0.channel==9)}
            var candidate=project
            let ids=try MIDIImportEditing.apply(parts,useID:draft.useID,extendSection:extend,in:&candidate)
            mutate("MIDI \(parts.count)개 트랙 가져오기"){$0=candidate};midiImportDraft=nil
            if let lane=ids.first {focusHierarchy(.music(arrangementID:draft.arrangementID,useID:draft.useID,nodeID:"midi:\(lane)"),detail:true)}
        }catch{fail(error)}
    }
}

struct MIDIImportView:View {
    @ObservedObject var store:AppStore
    let draft:MIDIImportDraft
    @State private var selected:Set<String>=[]
    @State private var extend=true
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("MIDI 노트 가져오기").font(.system(size:16,weight:.semibold));Spacer();Button("취소"){store.midiImportDraft=nil}}
            Text(draft.fileName).lineLimit(1)
            Text("노트의 위치·길이·세기를 새 MIDI 서클에 추가합니다. 현재 섹션의 템포·박자를 사용합니다.").foregroundStyle(StudioTheme.secondary)
            if let tempo=draft.document.tempo {Text("파일의 첫 템포 \(tempo,format:.number.precision(.fractionLength(1))) BPM · 현재 섹션 \(store.currentContext.tempo,format:.number.precision(.fractionLength(1))) BPM").foregroundStyle(StudioTheme.secondary)}
            if draft.document.ignoredPerformanceEvents>0 {Text("CC·프로그램 변경 등 \(draft.document.ignoredPerformanceEvents)개 이벤트는 가져오지 않습니다. 페달·피치 벤드가 있는 연주는 가져온 뒤 확인하세요.").foregroundStyle(StudioTheme.secondary)}
            ScrollView {VStack(alignment:.leading,spacing:10) {ForEach(draft.document.tracks){track in
                Toggle(isOn:Binding(get:{selected.contains(track.id)},set:{if $0{selected.insert(track.id)}else{selected.remove(track.id)}})) {
                    HStack{Text(track.name).lineLimit(1);Spacer();Text("\(track.notes.count)개 노트 · 채널 \(track.channel+1)").foregroundStyle(StudioTheme.secondary)}
                }
            }}}
            Toggle("필요하면 이번 섹션의 길이 늘리기",isOn:$extend)
            HStack {Text("기존 트랙과 노트는 유지됩니다").foregroundStyle(StudioTheme.secondary);Spacer();Button("\(selected.count)개 서클 가져오기"){store.commitMIDIImport(draft,selected:selected,extend:extend)}.disabled(selected.isEmpty)}
        }.font(.system(size:13)).onAppear{selected=Set(draft.document.tracks.map(\.id))}
    }
}
