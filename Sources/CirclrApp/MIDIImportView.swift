import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CirclrCore
import CirclrAudio

/// Transient return location for an abandoned import, never part of its music transaction.
struct MIDIImportReturnWorkspace {
    let address:CircleAddress
    let workspace:StudioWorkspace
    let midiStepMode:Bool
    let viewport:HierarchyViewport?
    let stepCursor:MIDIImportStepCursor?
}

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
    var returnWorkspace:MIDIImportReturnWorkspace? = nil
}
extension AppStore {
    func chooseMIDIImport() {
        var scope=numberEditIdentity
        guard resolveActiveNumericDraft(),nameEditing.resolve() else{return}
        scope.revision=project.musicRevision
        guard scope==numberEditIdentity else{return}
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
            // Capturing consumes pending canvas navigation, so recheck the document afterward.
            // Parsing failures and a cancelled file panel never move the current editor.
            let viewport=captureHierarchyViewport?()
            let returnWorkspace=hierarchySelection.map { address in
                MIDIImportReturnWorkspace(address:address,workspace:viewport?.workspace ?? capturedStudioWorkspace,midiStepMode:midiStepMode,viewport:viewport,stepCursor:captureStepCursor?())
            }
            guard canStartMediaImport,project.id==projectID,project.musicRevision==revision,mediaImportGeneration==generation,
                  project.arrangements.first(where:{$0.id==arrangementID})?.uses.contains(where:{$0.id==useID})==true else {throw CirclrError("대상이 변경됐습니다. 파일을 다시 선택하세요")}
            pendingMIDIImportStepCursor=nil
            hierarchySettingsOpen=false
            focusHierarchy(.section(arrangementID:arrangementID,useID:useID),detail:true)
            midiImportDraft=MIDIImportDraft(fileName:url.lastPathComponent,document:document,projectID:projectID,revision:revision,arrangementID:arrangementID,useID:useID,generation:generation,beat:beat,sectionBeats:clock.beats,position:position,returnWorkspace:returnWorkspace)
            return true
        }catch{status="MIDI 가져오기 실패: \(error.localizedDescription)";return false}
    }
    func cancelMIDIImport(_ draftID:UUID) {
        guard let draft=midiImportDraft,draft.id==draftID else{return}
        midiImportDraft=nil
        guard project.id==draft.projectID,project.musicRevision==draft.revision,mediaImportGeneration==draft.generation,
              project.activeArrangementID==draft.arrangementID,selectedUse?.id==draft.useID,
              let saved=draft.returnWorkspace else{return}
        guard (try? StudioNavigation.scene(revealing:saved.address,in:project)) != nil else {
            status="이전 편집 서클이 없어 현재 위치를 유지합니다"
            return
        }
        pendingMIDIImportStepCursor=saved.stepCursor
        if let viewport=saved.viewport {
            let wasUpdating=updatingHierarchyViewport
            updatingHierarchyViewport=true;project.hierarchyView=viewport;updatingHierarchyViewport=wasUpdating
            hierarchyCommand=HierarchyCommand(action:.restore)
        } else {
            let detail:Bool
            if case .music=saved.address {detail=true}else{detail=false}
            focusHierarchy(saved.address,detail:detail)
            midiStepMode=saved.midiStepMode
            restoreStudioWorkspace(saved.workspace)
            requestEditorNavigationFocus()
        }
    }

    func commitMIDIImport(_ draft:MIDIImportDraft,selected:Set<String>,extend:Bool,beat:Double,tempoPolicy:MIDIImportTempoPolicy,expressionPolicy:MIDIImportExpressionPolicy = .preserve)->String? {
        guard midiImportDraft?.id==draft.id,project.id==draft.projectID,project.musicRevision==draft.revision,mediaImportGeneration==draft.generation,selectedUse?.id==draft.useID,project.activeArrangementID==draft.arrangementID,canStartMediaImport else {return "프로젝트가 변경됐습니다. 파일을 다시 선택하세요"}
        do {
            let map=try draft.tempoMap(for:tempoPolicy)
            let parts=try draft.document.importParts(selectedIDs:selected,expressionPolicy:expressionPolicy)
            var candidate=project
            let ids=try MIDIImportEditing.apply(parts,useID:draft.useID,extendSection:extend,atBeat:beat,position:draft.position,tempoPolicy:tempoPolicy,tempoMap:map,in:&candidate)
            mutate("MIDI \(parts.count)개 트랙 가져오기"){$0=candidate}
            candidate.musicRevision += 1
            guard project==candidate else{return "가져오기를 적용하지 못했습니다. 현재 작업 상태를 확인하세요"}
            midiImportDraft=nil
            // Imported lanes belong to this use, irrespective of the previous editor's scope.
            editOriginal=false;midiStepMode=false;pitchBendOpen=false;sustainOpen=false
            if ids.count==1,let lane=ids.first {focusHierarchy(.music(arrangementID:draft.arrangementID,useID:draft.useID,nodeID:"midi:\(lane)"),detail:true)}
            else {focusHierarchy(.section(arrangementID:draft.arrangementID,useID:draft.useID),detail:false)}
            restoreStudioWorkspace(.init(page:.content))
            selectedBeat=beat
            if ids.count==1 {requestEditorNavigationFocus()}
            return nil
        }catch{return error.localizedDescription}
    }
}

private extension MIDIImportDraft {
    func tempoMap(for policy:MIDIImportTempoPolicy)throws->MIDIImportTempoMap? {
        guard policy == .applyFile else{return nil}
        if let issue=document.tempoImportIssue {throw CirclrError(issue)}
        guard let first=document.tempoChanges.first,first.beat==0 else {throw CirclrError("파일의 초기 템포를 확인할 수 없습니다")}
        return MIDIImportTempoMap(initialBPM:first.bpm,changes:Array(document.tempoChanges.dropFirst()))
    }
}

private struct MIDIImportImpact {
    let minimumBPM:Double,maximumBPM:Double
    let previousRegionSeconds:Double,regionSeconds:Double
    let previousSectionSeconds:Double,sectionSeconds:Double
}

private struct MIDIImportBendSummary {
    let values:Int
    let rangeChanges:Int
    let initialRange:Double
}

struct MIDIImportView:View {
    @ObservedObject var store:AppStore
    let draft:MIDIImportDraft
    @State private var bendSummaries:[Int:MIDIImportBendSummary]=[:]
    @State private var selected:Set<String>=[]
    @State private var extend=true
    @State private var start:Double
    @State private var tempoPolicy:MIDIImportTempoPolicy = .keepCurrent
    @State private var omitExpression=false
    @State private var impact:MIDIImportImpact?
    @State private var previewError:String?
    @State private var commitError:String?
    @State private var startError:String?
    @State private var startCommit=NumberFieldCommitTarget()
    init(store:AppStore,draft:MIDIImportDraft) {self.store=store;self.draft=draft;_start=State(initialValue:draft.beat)}
    private var beats:Double {draft.sectionBeats}
    private var expressionPolicy:MIDIImportExpressionPolicy {omitExpression ? .omit:.preserve}
    private var selectedTracks:[ImportedMIDITrack] {draft.document.tracks.filter{selected.contains($0.id)}}
    private var hasExpression:Bool {selectedTracks.contains{$0.pitchBend != nil || $0.sustain != nil} || !draft.document.issues(selectedIDs:selected).isEmpty}
    private var end:Double {
        let noteEnd=selectedTracks.flatMap(\.notes).map{$0.beat+$0.length}.max() ?? 0
        return start+max(noteEnd,lastExpressionBeat ?? 0)
    }
    private var lastExpressionBeat:Double? {
        guard !omitExpression else{return nil}
        return selectedTracks.flatMap{[$0.pitchBend?.events.last?.beat,$0.sustain?.events.last?.beat].compactMap{$0}}.max()
    }
    private var exceeds:Bool {end>beats+1e-8 || lastExpressionBeat.map{start+$0>=beats}==true}
    private var current:Bool {store.midiImportDraft?.id==draft.id && store.project.id==draft.projectID && store.project.musicRevision==draft.revision && store.mediaImportGeneration==draft.generation && store.project.activeArrangementID==draft.arrangementID && store.selectedUse?.id==draft.useID}
    private var ready:Bool {!selected.isEmpty && impact != nil && previewError==nil && startError==nil && (omitExpression || draft.document.issues(selectedIDs:selected).isEmpty) && store.canStartMediaImport && current}
    private var target:String {
        guard let arrangement=store.project.arrangements.first(where:{$0.id==draft.arrangementID}),let index=arrangement.uses.firstIndex(where:{$0.id==draft.useID}) else{return "대상 섹션을 찾을 수 없습니다"}
        return arrangement.name+" · "+arrangement.uses[index].name+" · \(index+1)번째 사용"
    }
    private var targetIdentity:String {"편곡 ID · \(draft.arrangementID) · 사용 ID · \(draft.useID)"}
    private var targetLabel:some View {
        Text("대상 · "+target).lineLimit(1).truncationMode(.middle)
            .help("대상 · "+target+" · "+targetIdentity)
            .accessibilityLabel("대상 · "+target)
            .accessibilityHint(Text(targetIdentity))
    }
    private var errorSummary:String? {
        if !current {return "대상이나 프로젝트가 변경됐습니다. 취소하고 파일을 다시 선택하세요."}
        if !store.canStartMediaImport {return "재생·녹음을 정지한 뒤 가져오세요."}
        if let startError {return "시작 위치 · "+startError}
        if !omitExpression,let first=draft.document.issues(selectedIDs:selected).first {
            let count=draft.document.issues(selectedIDs:selected).count
            return "MIDI 표현 · "+(first.channel.map{"채널 \($0+1) · "} ?? "")+first.message+(count>1 ? " · 추가 \(count-1)개 문제":"")
        }
        return commitError ?? previewError
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("MIDI 노트 가져오기").font(.system(size:16,weight:.semibold))
                Spacer(minLength:8)
                Button("취소"){store.cancelMIDIImport(draft.id)}
                Button(omitExpression ? "표현 제외하고 가져오기":"\(selected.count)개 서클 가져오기") {
                    guard startCommit.commit() else{return}
                    refreshPreview()
                    guard ready else{return}
                    commitError=store.commitMIDIImport(draft,selected:selected,extend:extend,beat:start,tempoPolicy:tempoPolicy,expressionPolicy:expressionPolicy)
                }.disabled(!ready)
            }
            HStack(spacing:12) {
                Text(draft.fileName).lineLimit(1).truncationMode(.middle)
                    .help(draft.fileName).accessibilityLabel("파일 · "+draft.fileName)
                    .frame(maxWidth:.infinity,alignment:.leading)
                targetLabel.frame(maxWidth:.infinity,alignment:.leading)
            }.font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
            if let message=errorSummary {
                Text(message).foregroundStyle(Color.orange).fixedSize(horizontal:false,vertical:true)
                    .accessibilityLabel("MIDI 가져오기 오류 · "+message)
            }
            if hasExpression {
                Toggle("피치 벤드·페달을 제외하고 노트만 가져오기",isOn:$omitExpression)
                    .help("이 선택은 피치 벤드·범위 변경과 서스테인 페달을 제외합니다. 템포 가져오기 선택과는 별개입니다.")
            }
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    Text("가져올 트랙 · \(selected.count)/\(draft.document.tracks.count)").fontWeight(.semibold)
                    ForEach(draft.document.tracks) {track in
                        Toggle(isOn:Binding(get:{selected.contains(track.id)},set:{if $0{selected.insert(track.id)}else{selected.remove(track.id)}})) {
                            VStack(alignment:.leading,spacing:4) {
                                HStack {Text(track.name).lineLimit(2).help(track.name);Spacer();Text("\(track.notes.count)개 노트 · 채널 \(track.channel+1)").foregroundStyle(StudioTheme.secondary)}
                                Text(expressionSummary(track)).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
                            }
                        }
                    }
                    Divider()
                    MIDIWorkspaceToolbarLayout {
                        Text("시작 위치")
                        CommittedNumberField(title:"MIDI 가져오기 시작 박",value:$start,range:0...beats,width:80,presentation:.beatPosition,validate:{value in guard value<beats else{throw CirclrError("MIDI 시작 위치는 현재 섹션 안으로 지정하세요")}},commitTarget:startCommit,onValidityChange:{startError=$0})
                        Text("박 · 4분음표 기준").foregroundStyle(StudioTheme.secondary)
                        Button("섹션 처음"){start=0}
                        Toggle("필요하면 길이 늘리기",isOn:$extend).fixedSize()
                    }
                    Text("적용 구간 · \(BeatPosition.text(start))–\(BeatPosition.text(end))박 · 현재 섹션 길이 \(beats.formatted())박"+(exceeds ? (extend ? " · 이번 사용 연장":" · 길이 초과"):""))
                        .foregroundStyle(exceeds && !extend ? Color.orange:StudioTheme.secondary)
                    Picker("템포 가져오기",selection:$tempoPolicy) {
                        Text("현재 템포 유지").tag(MIDIImportTempoPolicy.keepCurrent)
                        Text("파일 템포 적용").tag(MIDIImportTempoPolicy.applyFile)
                    }.pickerStyle(.segmented).frame(maxWidth:420)
                    if let impact {
                        Text("적용 구간 템포 · \(number(impact.minimumBPM))–\(number(impact.maximumBPM)) BPM")
                        Text("구간 시간 · 기존 \(seconds(impact.previousRegionSeconds))초 → 적용 후 \(seconds(impact.regionSeconds))초")
                        Text("섹션 전체 · 기존 \(seconds(impact.previousSectionSeconds))초 → 적용 후 \(seconds(impact.sectionSeconds))초")
                    }
                    Text(tempoPolicy == .applyFile
                         ? "이번 사용의 기존 MIDI·오디오·오토메이션도 바뀐 시간 기준을 따릅니다. 공유 원본과 다른 사용은 유지합니다. 선택 연주(노트·피치 벤드·페달)의 끝에서 기존 템포로 돌아가며, 그 뒤의 파일 템포 이벤트는 적용하지 않습니다."
                         : "노트의 선행 쉼표·박 위치를 유지하고 현재 섹션의 템포를 사용합니다. 파일 템포는 적용하지 않습니다.")
                        .foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
                    Text("박자표는 현재 섹션을 사용합니다. 피치 벤드 범위 RPN·서스테인 CC64와 CC121 페달 초기화를 반영합니다. 그 외 CC·프로그램 변경은 가져오지 않습니다.")
                        .foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
                    if draft.document.ignoredPerformanceEvents>0 {Text("\(draft.document.ignoredPerformanceEvents)개 기타 연주 이벤트 제외 · 페달 등 제외된 연주를 확인하세요").foregroundStyle(StudioTheme.secondary)}
                    if let issue=draft.document.tempoImportIssue,tempoPolicy == .keepCurrent {
                        Text("파일 템포 사용 불가 · "+issue+" · 현재 템포로 노트는 가져올 수 있습니다.").foregroundStyle(StudioTheme.secondary)
                    }
                    if hasExpression {
                        Text("범위 정보가 없는 채널은 기본 ±2반음을 사용합니다. 피치 벤드와 페달은 같은 채널의 연주 전체에 적용됩니다. 페달 raw 64 이상은 누름, 63 이하는 뗌이며 원래 값을 보존합니다.")
                            .foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
                        let issues=draft.document.issues(selectedIDs:selected)
                        ForEach(Array(issues.enumerated()),id:\.offset) {_,issue in
                            let location=[issue.channel.map{"채널 \($0+1)"},issue.beat.map{BeatPosition.text($0)+"박"}].compactMap{$0}.joined(separator:" · ")
                            Text(location.isEmpty ? issue.message:location+" · "+issue.message).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,8)
            }
        }.font(.system(size:13))
            .onExitCommand{store.cancelMIDIImport(draft.id)}
            .onAppear{cacheBendSummaries();selected=Set(draft.document.tracks.map(\.id));refreshPreview()}
            .onChange(of:selected){_,_ in refreshPreview()}
            .onChange(of:start){_,_ in refreshPreview()}
            .onChange(of:extend){_,_ in refreshPreview()}
            .onChange(of:tempoPolicy){_,_ in refreshPreview()}
            .onChange(of:omitExpression){_,_ in refreshPreview()}
            .onChange(of:current){_,_ in refreshPreview()}
    }
    private func cacheBendSummaries() {
        // This view is keyed by draft.id. A shared channel is scanned once per draft,
        // never once per track or on each body evaluation.
        var summaries=bendSummaries
        for track in draft.document.tracks {
            guard let bend=track.pitchBend,summaries[bend.channel]==nil else{continue}
            let changes=bend.events.reduce(0){count,event in if case .range=event.kind{return count+1};return count}
            summaries[bend.channel]=MIDIImportBendSummary(values:bend.events.count-changes,rangeChanges:changes,initialRange:bend.initialRange.totalSemitones)
        }
        bendSummaries=summaries
    }
    private func expressionSummary(_ track:ImportedMIDITrack)->String {
        var parts:[String]=[]
        if let bend=track.pitchBend {
            if let summary=bendSummaries[bend.channel] {
                parts.append("피치 벤드 \(summary.values)개 · 범위 변경 \(summary.rangeChanges)개 · 초기 범위 ±\(number(summary.initialRange))반음")
            }else{parts.append("피치 벤드 있음")}
        }
        if let sustain=track.sustain {
            let state=sustain.initialValue>=64 ? "누름":"뗌"
            parts.append("페달 CC64 \(sustain.events.count)개 · 초기 raw \(sustain.initialValue) · \(state)")
        }
        if parts.isEmpty {return draft.document.issues(selectedIDs:[track.id]).isEmpty ? "피치 벤드·페달 없음":"MIDI 표현 가져오기 문제 있음 · 위 안내 확인"}
        return parts.joined(separator:"\n")+(omitExpression ? " · 제외":" · 보존")
    }
    private func number(_ value:Double)->String {String(format:"%.2f",locale:Locale(identifier:"en_US_POSIX"),value)}
    private func seconds(_ value:Double)->String {String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),value)}
    private func refreshPreview() {
        impact=nil;previewError=nil;commitError=nil
        guard current else{return}
        guard !selected.isEmpty else {previewError="가져올 트랙을 하나 이상 선택하세요";return}
        do {
            let map=try draft.tempoMap(for:tempoPolicy)
            let parts=try draft.document.importParts(selectedIDs:selected,expressionPolicy:expressionPolicy)
            let result=try MIDITempoImport.preview(parts,useID:draft.useID,extendSection:extend,atBeat:start,tempoPolicy:tempoPolicy,tempoMap:map,in:store.project)
            impact=MIDIImportImpact(minimumBPM:result.minimumBPM,maximumBPM:result.maximumBPM,previousRegionSeconds:result.previousRegionSeconds,regionSeconds:result.regionSeconds,previousSectionSeconds:result.previousSectionSeconds,sectionSeconds:result.sectionSeconds)
        } catch {previewError=error.localizedDescription}
    }
}
