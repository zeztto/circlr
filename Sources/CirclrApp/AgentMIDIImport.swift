import Foundation
import Darwin
import CirclrCore
import CirclrAudio

struct AgentMIDIImportResult:Codable {
    struct PitchBend:Codable {
        var eventCount:Int
        var initialValue:Int
        var initialRange:MIDIPitchBendRange
        var ranges:[MIDIPitchBendRange]
        var rangeChangeCount:Int
        var uniqueRangeCount:Int
        var hasMoreRanges:Bool
        init(_ sequence:MIDIPitchBendSequence)throws {
            struct RangeKey:Hashable {var semitones:Int;var cents:Int}
            eventCount=sequence.events.count;initialValue=sequence.initialValue;initialRange=sequence.initialRange
            ranges=[sequence.initialRange];rangeChangeCount=0
            var seen:Set<RangeKey>=[.init(semitones:initialRange.semitones,cents:initialRange.cents)]
            for (index,event) in sequence.events.enumerated() {
                if index%256==0 {try Task.checkCancellation()}
                if case .range(let range)=event.kind {
                    rangeChangeCount+=1
                    if seen.insert(.init(semitones:range.semitones,cents:range.cents)).inserted,ranges.count<16 {ranges.append(range)}
                }
            }
            uniqueRangeCount=seen.count;hasMoreRanges=uniqueRangeCount>ranges.count
        }
    }

    struct Issue:Codable {var channel:Int?;var beat:Double?;var code:String;var message:String}
    struct Track:Codable {var id:String;var name:String;var channel:Int;var noteCount:Int;var beats:Double;var pitchBend:PitchBend?}
    var tracks:[Track]
    var selectedTrackIDs:[String]
    var laneIDs:[ID]
    var tempoChanges:[TempoChange]
    var tempoImportIssue:String?
    var ignoredPerformanceEvents:Int
    var previewOnly:Bool
    var expressionPolicy:MIDIImportExpressionPolicy
    var selectedIssues:[Issue]
    var tempoPolicy:MIDIImportTempoPolicy
    var previousSectionSeconds:Double
    var sectionSeconds:Double?
    var previewIssue:String?
}

extension AppStore {
    func beginAgentMIDIImport(_ request:AgentRequest,source:String)throws->[String:Any] {
        try AgentProjectEditing.check(request,project:project)
        guard canStartMediaImport else{throw CirclrError("재생·녹음·가져오기 작업을 정지한 뒤 MIDI를 가져오세요")}
        guard let args=request.arguments,let path=args.path,let arrangementID=args.arrangementID,let useID=args.useID,
              project.arrangements.first(where:{$0.id==arrangementID})?.uses.contains(where:{$0.id==useID}) == true else{throw CirclrError("path·arrangementID·useID를 확인하세요")}
        let url=try agentPath(path),beat=args.atBeat ?? 0,extend=args.extendSection ?? false,preview=args.previewOnly ?? false,policy=args.tempoPolicy ?? .keepCurrent
        let expressionPolicy=args.expressionPolicy ?? .preserve
        guard beat.isFinite,beat>=0,beat<=131072 else{throw CirclrError("MIDI 시작 박을 확인하세요")}
        if let ids=args.trackIDs {guard !ids.isEmpty,ids.count<=256,Set(ids).count==ids.count else{throw CirclrError("중복 없는 MIDI trackIDs 1–256개를 지정하세요")}}
        productionGeneration+=1;let generation=productionGeneration,jobID=newID()
        preparing=true;progress=0
        agentJob=AgentJob(id:jobID,kind:"import_midi",state:"running",message:preview ? "MIDI 파일 미리 읽는 중":"MIDI 파일 가져오는 중")
        productionTask=Task { [weak self] in
            guard let self,!Task.isCancelled,self.productionGeneration==generation else{return}
            let worker=Task.detached(priority:.userInitiated){
                try Task.checkCancellation()
                let document=try Self.readAgentMIDI(url)
                var summaries:[Int:AgentMIDIImportResult.PitchBend]=[:]
                // The raw parser merges controller state per channel; note tracks
                // on that channel share it. Summarize each sequence once off-main.
                for track in document.tracks {
                    try Task.checkCancellation()
                    if summaries[track.channel]==nil,let expression=track.pitchBend {
                        summaries[track.channel]=try AgentMIDIImportResult.PitchBend(expression)
                    }
                }
                try Task.checkCancellation()
                return (document,summaries)
            }
            do {
                let (document,summaries)=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
                guard !Task.isCancelled,self.productionGeneration==generation else{return}
                try AgentProjectEditing.check(request,project:self.project)
                let currentActive=self.project.activeArrangementID
                let ids=args.trackIDs ?? document.tracks.map(\.id)
                guard Set(ids).isSubset(of:Set(document.tracks.map(\.id))) else{throw CirclrError("파일에 없는 MIDI trackID가 있습니다. previewOnly로 다시 확인하세요")}
                let selectedIDs=Set(ids)
                let selectedIssues=document.issues(selectedIDs:selectedIDs).map{AgentMIDIImportResult.Issue(channel:$0.channel,beat:$0.beat,code:$0.code,message:$0.message)}
                let map=document.tempoChanges.first.map{first in MIDIImportTempoMap(initialBPM:first.bpm,changes:Array(document.tempoChanges.dropFirst()))}
                var candidate=self.project;candidate.activeArrangementID=arrangementID
                guard let use=candidate.active.uses.first(where:{$0.id==useID}) else{throw CirclrError("대상 섹션이 변경되었습니다")}
                let before=try ArrangementCompiler.context(project:candidate,use:use,arrangementID:arrangementID).2.seconds
                var after:Double?,previewIssue:String?,laneIDs:[ID]=[]
                do {
                    let parts=try document.importParts(selectedIDs:selectedIDs,expressionPolicy:expressionPolicy)
                    if policy == .applyFile,let issue=document.tempoImportIssue {throw CirclrError(issue)}
                    if policy == .applyFile,map==nil {throw CirclrError("적용할 MIDI 템포 맵이 없습니다")}
                    if preview {
                        after=try MIDITempoImport.preview(parts,useID:useID,extendSection:extend,atBeat:beat,tempoPolicy:policy,tempoMap:map,in:candidate).sectionSeconds
                    }else{
                        laneIDs=try MIDIImportEditing.apply(parts,useID:useID,extendSection:extend,atBeat:beat,tempoPolicy:policy,tempoMap:map,in:&candidate)
                        let updated=candidate.active.uses.first(where:{$0.id==useID})!
                        after=try ArrangementCompiler.context(project:candidate,use:updated,arrangementID:arrangementID).2.seconds
                    }
                }catch{if preview{previewIssue=error.localizedDescription}else{throw error}}
                candidate.activeArrangementID=currentActive
                try Task.checkCancellation()
                let result=AgentMIDIImportResult(tracks:document.tracks.map{.init(id:$0.id,name:$0.name,channel:$0.channel,noteCount:$0.notes.count,beats:$0.notes.map{$0.beat+$0.length}.max() ?? 0,pitchBend:$0.pitchBend == nil ? nil:summaries[$0.channel])},selectedTrackIDs:ids,laneIDs:preview ? []:laneIDs,tempoChanges:document.tempoChanges,tempoImportIssue:document.tempoImportIssue,ignoredPerformanceEvents:document.ignoredPerformanceEvents,previewOnly:preview,expressionPolicy:expressionPolicy,selectedIssues:selectedIssues,tempoPolicy:policy,previousSectionSeconds:before,sectionSeconds:after,previewIssue:previewIssue)
                if !preview {
                    try UseTempoOverrideEditing.validateChanges(from:self.project,to:candidate)
                    let revision=self.project.musicRevision
                    self.mutate("\(source) MIDI 가져오기"){$0=candidate}
                    var expected=candidate;expected.musicRevision=revision+1
                    guard self.project==expected else{throw CirclrError("MIDI 가져오기 변경을 적용하지 못했습니다")}
                }
                self.preparing=false;self.progress=1;self.agentJob?.state="completed";self.agentJob?.progress=1;self.agentJob?.midiImport=result
                self.agentJob?.message=preview ? "미리 읽기 완료 · 문서 변경 없음":"MIDI 가져오기 완료"
                self.status=self.agentJob?.message ?? "완료"
                self.recordActivity(source,"완료 · import_midi · \(jobID)")
            }catch{
                guard self.productionGeneration==generation else{return}
                self.preparing=false;self.agentJob?.state=error is CancellationError ? "cancelled":"failed";self.agentJob?.message=error.localizedDescription
                self.status=error.localizedDescription;self.recordActivity(source,"실패 · import_midi · \(error.localizedDescription)")
            }
        }
        return ["jobID":jobID,"state":"running"]
    }

    nonisolated private static func readAgentMIDI(_ url:URL)throws->ImportedMIDI {
        let descriptor=Darwin.open(url.path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK)
        guard descriptor>=0 else{throw CirclrError("읽을 수 있는 로컬 MIDI 일반 파일을 선택하세요")}
        let file=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true);defer{try? file.close()}
        var metadata=stat()
        guard fstat(descriptor,&metadata)==0,metadata.st_mode&S_IFMT==S_IFREG,
              metadata.st_size>=14,metadata.st_size<=16_777_216 else{throw CirclrError("16 MiB 이하의 MIDI 일반 파일이 필요합니다")}
        let data=try file.read(upToCount:16_777_217) ?? Data()
        try Task.checkCancellation()
        return try MIDIImport.read(data)
    }
}
