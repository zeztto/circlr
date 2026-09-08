import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CirclrCore
import CirclrAudio

struct MIDIImportDraft {
    let id=UUID()
    var fileName:String
    var document:ImportedMIDI
    var projectID:ID
    var revision:Int
    var arrangementID:ID
    var useID:ID
    var generation:Int
    var beat:Double
    var sectionBeats:Double
    var position:Point?
}
extension AppStore {
    func chooseMIDIImport() {
        guard let use=selectedUse,canStartMediaImport else {status="MIDI를 넣을 섹션을 선택하고 재생·녹음을 정지하세요";return}
        let projectID=project.id,revision=project.musicRevision,arrangementID=project.activeArrangementID,generation=mediaImportGeneration,beat=selectedBeat
        let panel=NSOpenPanel();panel.title="MIDI 노트 가져오기";panel.allowedContentTypes=[UTType(filenameExtension:"mid")!,UTType(filenameExtension:"midi")!];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        _=previewMIDIImport(url,projectID:projectID,revision:revision,generation:generation,arrangementID:arrangementID,useID:use.id,beat:beat)
    }
    @discardableResult func previewMIDIImport(_ url:URL,projectID:ID,revision:Int,generation:Int,arrangementID:ID,useID:ID,beat:Double=0,position:Point?=nil)->Bool {
        guard canStartMediaImport,project.id==projectID,project.musicRevision==revision,mediaImportGeneration==generation,
              project.arrangements.first(where:{$0.id==arrangementID})?.uses.contains(where:{$0.id==useID}) == true else {status="대상이 변경됐습니다. 파일을 다시 선택하세요";return false}
        let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
        do {
            guard let use=project.arrangements.first(where:{$0.id==arrangementID})?.uses.first(where:{$0.id==useID}) else {throw CirclrError("대상 섹션을 찾을 수 없습니다")}
            let clock=try ArrangementCompiler.context(project:project,use:use,arrangementID:arrangementID).2
            guard beat.isFinite,beat>=0,beat<clock.beats else {throw CirclrError("MIDI 시작 위치는 현재 섹션 안으로 지정하세요")}
            guard url.isFileURL else{throw CirclrError("로컬 MIDI 파일을 선택하세요")}
            let values=try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
            guard values.isRegularFile==true,let size=values.fileSize,size>0,size<=16_777_216 else {throw CirclrError("16 MiB 이하의 MIDI 파일을 선택하세요")}
            let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
            let document=try MIDIImport.read(handle.read(upToCount:16_777_217) ?? Data())
            hierarchySettingsOpen=false
            focusHierarchy(.section(arrangementID:arrangementID,useID:useID),detail:true)
            midiImportDraft=MIDIImportDraft(fileName:url.lastPathComponent,document:document,projectID:projectID,revision:revision,arrangementID:arrangementID,useID:useID,generation:generation,beat:beat,sectionBeats:clock.beats,position:position)
            return true
        }catch{status="MIDI 가져오기 실패: \(error.localizedDescription)";return false}
    }
    func commitMIDIImport(_ draft:MIDIImportDraft,selected:Set<String>,extend:Bool,beat:Double) {
        guard midiImportDraft?.id==draft.id,project.id==draft.projectID,project.musicRevision==draft.revision,mediaImportGeneration==draft.generation,selectedUse?.id==draft.useID,project.activeArrangementID==draft.arrangementID,canStartMediaImport else {fail(CirclrError("프로젝트가 변경됐습니다. 파일을 다시 선택하세요"));return}
        do {
            let parts=draft.document.tracks.filter{selected.contains($0.id)}.map{MIDIImportPart(name:$0.name,notes:$0.notes,drums:$0.channel==9)}
            var candidate=project
            let ids=try MIDIImportEditing.apply(parts,useID:draft.useID,extendSection:extend,atBeat:beat,position:draft.position,in:&candidate)
            mutate("MIDI \(parts.count)개 트랙 가져오기"){$0=candidate};midiImportDraft=nil
            if ids.count==1,let lane=ids.first {focusHierarchy(.music(arrangementID:draft.arrangementID,useID:draft.useID,nodeID:"midi:\(lane)"),detail:true)}
            else {focusHierarchy(.section(arrangementID:draft.arrangementID,useID:draft.useID),detail:false)}
            selectedBeat=beat
        }catch{fail(error)}
    }
}

struct MIDIImportView:View {
    @ObservedObject var store:AppStore
    let draft:MIDIImportDraft
    @State private var selected:Set<String>=[]
    @State private var extend=true
    @State private var start:Double
    init(store:AppStore,draft:MIDIImportDraft) {self.store=store;self.draft=draft;_start=State(initialValue:draft.beat+1)}
    private var beats:Double {draft.sectionBeats}
    private var end:Double {start-1+(draft.document.tracks.filter{selected.contains($0.id)}.flatMap(\.notes).map{$0.beat+$0.length}.max() ?? 0)}
    private var exceeds:Bool {end>beats+1e-8}
    private var current:Bool {store.project.id==draft.projectID && store.project.musicRevision==draft.revision && store.mediaImportGeneration==draft.generation}
    private var ready:Bool {!selected.isEmpty && (!exceeds || extend) && store.canStartMediaImport && current}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Text("MIDI 노트 가져오기").font(.system(size:16,weight:.semibold));Spacer();Button("취소"){store.midiImportDraft=nil};Button("\(selected.count)개 서클 가져오기"){store.commitMIDIImport(draft,selected:selected,extend:extend,beat:start-1)}.disabled(!ready)}
            HStack {Text(draft.fileName).lineLimit(1).help(draft.fileName);Spacer();Text("이번 섹션에 새 트랙").foregroundStyle(StudioTheme.secondary)}
            HStack(spacing:10) {
                Text("시작 위치")
                CommittedNumberField(title:"MIDI 가져오기 시작 박",value:$start,range:1...max(1,beats+1-0.001),width:80)
                Text("박 · 4분음표 기준").foregroundStyle(StudioTheme.secondary)
                Button("섹션 처음"){start=1}
                Spacer(minLength:0)
                Toggle("필요하면 길이 늘리기",isOn:$extend)
            }
            HStack {Text("끝 위치 \((end+1).formatted(.number.precision(.fractionLength(0...3))))박 · 현재 \(beats.formatted())박 길이"+(exceeds ? (extend ? " · 이번 섹션 연장":" · 길이 초과"):""));Spacer();Text("섹션 \(store.currentContext.tempo.formatted()) BPM")}.foregroundStyle(exceeds && !extend ? Color.orange:StudioTheme.secondary)
            Text("파일의 선행 쉼표·노트 간격을 유지합니다. 섹션의 템포·박자를 사용합니다.").foregroundStyle(StudioTheme.secondary)
            if let tempo=draft.document.tempo,abs(tempo-store.currentContext.tempo)>0.01 {Text("파일의 첫 템포 \(tempo,format:.number.precision(.fractionLength(1))) BPM").foregroundStyle(StudioTheme.secondary)}
            if draft.document.ignoredPerformanceEvents>0 {Text("CC·프로그램 변경 등 \(draft.document.ignoredPerformanceEvents)개 이벤트 제외 · 페달·피치 벤드 연주는 확인하세요").foregroundStyle(StudioTheme.secondary)}
            if !current {Text("프로젝트가 변경됐습니다. 취소하고 파일을 다시 선택하세요.").foregroundStyle(Color.orange)}
            ScrollView {VStack(alignment:.leading,spacing:10) {ForEach(draft.document.tracks){track in
                Toggle(isOn:Binding(get:{selected.contains(track.id)},set:{if $0{selected.insert(track.id)}else{selected.remove(track.id)}})) {
                    HStack{Text(track.name).lineLimit(2).help(track.name);Spacer();Text("\(track.notes.count)개 노트 · 채널 \(track.channel+1)").foregroundStyle(StudioTheme.secondary)}
                }
            }}}
        }.font(.system(size:13)).onAppear{selected=Set(draft.document.tracks.map(\.id))}
    }
}
