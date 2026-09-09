import AppKit
import UniformTypeIdentifiers
import SwiftUI
import Combine
import AVFAudio
import AVFoundation
import AudioToolbox
import CoreAudioKit
import CirclrCore
import CirclrAudio

@MainActor final class AppStore: ObservableObject {
    @Published var project = Project() { didSet { if !updatingHierarchyViewport { hierarchyRevision += 1 } } }
    var updatingHierarchyViewport = false
    var captureHierarchyViewport: (() -> HierarchyViewport?)?
    var hierarchyRevision = 0
    var hierarchyCacheRevision = -1
    var hierarchyCache: HierarchyScene?
    @Published var hierarchySelection: CircleAddress? = .album {didSet{if oldValue != hierarchySelection{automationViewport.reset();hierarchyRevision += 1}}}
    @Published var hierarchySelections: Set<CircleAddress> = [.album]
    @Published var hierarchyCommand: HierarchyCommand?
    @Published var moviePreparing=false
    @Published var movieWriter:CanvasMovieWriter?
    @Published var movieFinalizing:Task<Void,Never>?
    @Published var movieSeconds=0.0
    @Published var lastMovieURL:URL?
    var movieRevision=0
    var movieGeneration=0
    var captureMovieFrame:(()->CGImage?)?
    @Published var keyboardHelp=false
    @Published var commandPalette: StudioPalette?
    @Published var navigationOpen=false
    let library=MediaLibraryController()
    @Published var libraryOpen=false {didSet{if !libraryOpen{library.suspend()}}}
    @Published var libraryDestination:MediaImportRequest?
    @Published var midiStepMode=false
    var navigationCacheRevision = -1
    var navigationCache:[StudioSectionRoute]=[]
    var canvasCommands: (() -> [StudioCommand])?
    var focusCanvas: (() -> Void)?
    let nameEditing=NameEditingRegistry()
    @Published var hierarchyZoom = 1.0
    @Published var hierarchySettingsOpen = false
    @Published var hierarchyTransitionID: ID?
    @Published var waveforms: [ID: WaveformOverview] = [:]
    var waveformLoading = Set<ID>()
    var waveformGeneration = 0
    @Published var selection = Set<ID>()
    @Published var edgeSelection: ID?
    @Published var soundView = false
    @Published var focus: CanvasFocus?
    @Published var editorActivation = UUID()
    @Published var canvasCommand: CanvasCommand?
    @Published var embeddedPlugin: PluginEditorController?
    let meter = TransportMeter()
    @Published var playbackFollow: PlaybackFollowMode = .following
    @Published var playbackLocation = ""
    var capturePlaybackVisualization: (() -> [String: Any])?
    @Published var editOriginal = false {didSet{if oldValue != editOriginal{automationViewport.reset()}}}
    @Published var selectedTrackID: ID?
    @Published var selectedBeat = 0.0
    @Published var additionalNoteIDs:Set<ID>=[]
    @Published var selectedNoteID: ID? {didSet{additionalNoteIDs=[]}}
    @Published var midiQuantizeSubdivision=4
    @Published var midiQuantizeStrength=1.0
    @Published var midiImportDraft:MIDIImportDraft?
    @Published var selectedClipID: ID?
    @Published var audioSplitOffset:Double?
    @Published var automationOpen=false
    @Published var automationViewport=AutomationViewport()
    @Published var automationParameter:AutomationParameter = .gain {didSet{if oldValue != automationParameter{automationViewport.reset()}}}
    @Published var selectedAutomationPointID:ID?
    @Published var editPatternID: ID?
    @Published var insertMode = false
    @Published var panMode = false
    @Published var status = "섹션을 만들어 곡 구성을 시작하세요" {didSet{if status != oldValue{recordActivity("앱",status)}}}
    @Published var activity:[ActivityEvent]=[]
    @Published var consoleOpen=true
    @Published var consoleBounds = CGRect.zero
    @Published var agentJob:AgentJob? {didSet{if let job=agentJob {
        if agentJobs[job.id]==nil {agentJobOrder.append(job.id)}
        agentJobs[job.id]=job
        if agentJobOrder.count>64 {agentJobs.removeValue(forKey:agentJobOrder.removeFirst())}
    }}}
    var agentJobs:[String:AgentJob]=[:]
    var agentJobOrder:[String]=[]
    var activitySequence=0
    var agentSocket:AgentSocket?
    var agentReplies:[String:(String,[String:Any])]=[:]
    var agentReplyOrder:[String]=[]
    @Published var errorMessage: String?
    @Published var progress = 0.0
    @Published var preparing = false
    var transportSeconds: Double { meter.seconds }
    @Published var dirty = false
    @Published var midiRecording = false
    @Published var audioRecording = false
    @Published var instruments: [PluginDescriptor] = []
    @Published var effects: [PluginDescriptor] = []
    @Published var undoCount = 0
    @Published var redoCount = 0
    var projectURL: URL?
    var mediaRoot: URL?
    let playback = Playback()
    @Published var outputStatus=PlaybackOutputStatus()
    let recorder = AudioRecorder()
    var prepared: PreparedAudio?
    var preparedKey = ""
    private var renderTask: Task<Void,Never>?
    private var renderGeneration = 0
    private var renderWorker: Task<PreparedAudio,Error>?
    var productionTask: Task<Void,Never>?
    var productionWorker: Task<PCM,Error>?
    var agentOpenWorker: Task<LoadedProject,Error>?
    var mediaImportTask:Task<Void,Never>?
    var mediaImportWorker:Task<StagedAudioImport,Error>?
    var mediaImportGeneration=0
    var productionGeneration = 0
    var productionMediaRoot:URL {storageRoot.appendingPathComponent("Bounces")}
    private var recordRepeats = 1
    private var undoStack: [(String,Project,Bool)] = []
    private var redoStack: [(String,Project,Bool)] = []
    @Published var connectionsOpen = false
    @Published var connectionEditorIntent: ConnectionEditorIntent?
    private var timer: Timer?
    private var midiInput: MIDIInput?
    let auditionOutput=AuditionTransport()
    @Published var auditionStatus=AuditionStatus()
    @Published var audioRecordPending=false
    @Published var audioCapturePhase:AudioRecorder.Phase = .idle
    @Published var audioCaptureMessage=""
    @Published var audioInputLevel:Float=0
    @Published var audioInputSeconds=0.0
    @Published var audioInputFormat:CaptureFormat?
    @Published var audioRecoveryURL:URL?
    private var audioCaptureProjectID:ID?
    private var audioRequestClock:MusicClock?
    private var audioLastFrames:UInt64=0
    private var audioLastInputAt=0.0
    private var recordingAuthorization=RecordingAuthorization()
    private var recordStart: Double = 0
    private var recordClock: MusicClock?
    private var recordUseID: ID?
    private var recordLaneID: ID?
    private var recordArrangementID: ID?
    private var recordedNotes: [Note] = []
    private var heldNotes: [Int:(Double,Int)] = [:]
    private var recordIteration = 0
    private var recordingTrackID: ID?
    private var originalRecordProject: Project?
    private var audioRecordURL: URL?
    private var cachedPlanKey = ""
    private var cachedPlan: ExecutionPlan?
    private var contextKey = ""
    private var contexts: [ID:(CirclrCore.Section,MusicContext,MusicClock)] = [:]
    private var recoveryTask: Task<Void,Never>?
    private let storageRoot = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier == "com.circlr.integrationqa" ? "circlr-integration-qa" : Bundle.main.bundleIdentifier == "com.circlr.portsqa" ? "circlr-ports-qa" : Bundle.main.bundleIdentifier == "com.circlr.hierarchyqa" ? "circlr-hierarchy-qa" : "circlr")
    private var recoveryURL:URL { storageRoot.appendingPathComponent("recovery.json") }
    struct Recovery: Codable { var project: Project; var root: URL?; var date: Date }
    init() {
        playback.onOutputChange = {[weak self] in self?.refreshOutputStatus()}
        do { try FileManager.default.createDirectory(at:storageRoot,withIntermediateDirectories:true) } catch { status = "복구 폴더 준비 실패: \(error.localizedDescription)" }
        selectedTrackID = project.addTrack(name:"악기 1")
        _ = project.addTrack(name:"드럼",drums:true)
        project.enableAlbum(); project.name = "새 앨범"
        timer = Timer.scheduledTimer(withTimeInterval:1/30,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        do {
            let input = try MIDIInput()
            input.onMessage = { [weak self] status,pitch,velocity,_ in
                let now = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in self?.midi(status:status,pitch:Int(pitch),velocity:Int(velocity),time:now) }
            }
            midiInput = input
        } catch { status = error.localizedDescription }
        instruments = AudioUnitHost.installed(type:kAudioUnitType_MusicDevice)
        effects = AudioUnitHost.installed(type:kAudioUnitType_Effect)
        recorder.onChange = { [weak self] in self?.recordingStateChanged() }
        startAgentBridge()
    }
    var selectedUse: SectionUse? { project.active.uses.first { selection.contains($0.id) } }
    var selectedSignal: SignalNode? { project.signal.nodes.first { selection.contains($0.id) } }
    var selectedTrack: Track? { project.tracks.first { $0.id == selectedTrackID } }
    var layout: CirclrCore.Layout { soundView ? project.signal.layout : project.active.layout }
    var currentContext: MusicContext {
        guard let use = selectedUse, let (_,c,_) = context(for:use) else { return project.global }
        return selectedCircle?.context ?? c
    }
    var currentClock: MusicClock? { selectedCircle?.clock ?? sectionClock }
    var sectionClock: MusicClock? {
        guard let use = selectedUse else { return nil }
        return context(for:use)?.2
    }
    var currentLane: Lane? {selectedTrackID.flatMap{lane(for:$0)}}
    func lane(for trackID:ID)->Lane? {
        if let id = editPatternID, let pattern = project.patterns.first(where:{$0.id == id}) { var lane = Lane(trackID:pattern.trackID); lane.id = pattern.id; lane.notes = pattern.notes; lane.audio = pattern.audio; return lane }
        guard let use = selectedUse,let section = project.sections.first(where:{$0.id == use.sectionID}) else { return nil }
        let lanes = editOriginal ? section.lanes : ((try? ArrangementCompiler.effectiveLanes(section:section,use:use)) ?? [])
        return selectedLaneID.flatMap { id in lanes.first { $0.id == id } } ?? lanes.first { $0.trackID == trackID }
    }
    var editorBeats: Double { if let id = editPatternID { return project.patterns.first(where:{$0.id == id})?.length ?? 4 }; return selectedMusic?.lengthBeats ?? currentClock?.beats ?? 32 }
    var musicKey: String { "\(project.id):\(project.musicRevision):\(project.activeArrangementID)" }
    func context(for use:SectionUse) -> (CirclrCore.Section,MusicContext,MusicClock)? {
        if contextKey != musicKey { contextKey = musicKey; contexts = [:] }
        if let result = contexts[use.id] { return result }
        let result = try? ArrangementCompiler.context(project:project,use:use)
        contexts[use.id] = result
        return result
    }
    var plan: ExecutionPlan? {
        if cachedPlanKey != musicKey { cachedPlanKey = musicKey; cachedPlan = try? AlbumCompiler.executionPlan(project) }
        return cachedPlan
    }
    var isPlaying: Bool { playback.playing }
    var hasPendingMusic: Bool { playback.playing && prepared?.plan.revision != project.musicRevision }
    deinit {auditionOutput.shutdown()}
    func tick() {
        refreshAuditionStatus()
        refreshOutputStatus()
        meter.update(seconds:playback.seconds,playing:playback.playing)
        captureMovieTick()
        if recorder.recording {
            audioInputSeconds=recorder.seconds;audioInputLevel=recorder.takePeak()
            if recorder.frames != audioLastFrames {audioLastFrames=recorder.frames;audioLastInputAt=ProcessInfo.processInfo.systemUptime}
        }
        if midiRecording,let clock = recordClock,ProcessInfo.processInfo.systemUptime-recordStart >= clock.seconds*Double(recordRepeats) { stopRecording() }
        if audioRecording,recorder.reachedLimit { stopRecording() }
        if audioRecording,recorder.interrupted || ProcessInfo.processInfo.systemUptime-audioLastInputAt>5 {stopRecording();status="입력 장치가 변경되거나 frame이 중단되어 녹음을 마무리합니다";recordActivity("앱",status)}
    }
    func mutate(_ name: String, musical: Bool = true, portLayoutOnly: Bool = false, _ action: (inout Project) throws -> Void) {
        if musical && audioRecordPending {cancelRecordingRequest()}
        if musical && (midiRecording || audioRecordingBusy) { status = "녹음 정지와 파일 마무리 후 음악을 편집하세요"; return }
        do {
            var candidate = project; try action(&candidate)
            if candidate == project { return }
            undoStack.append((name,project,portLayoutOnly)); if undoStack.count > 80 { undoStack.removeFirst() }; redoStack = []
            if musical { candidate.musicRevision += 1 }
            project = candidate; dirty = true; undoCount = undoStack.count; redoCount = 0
            if musical { status = playback.playing ? "편집 내용은 다음 재생에 반영됩니다" : "\(name) 완료" }
            scheduleRecovery()
        } catch { fail(error) }
    }
    /// Only viewing preferences bypass history; actual positions, groups and ports remain undoable.
    func setCanvasViewPreferences(layout: CircleLayout? = nil, grid: Bool? = nil, snap: Bool? = nil) {
        var candidate = project
        if let layout { candidate.circleLayout = layout }
        if let grid { candidate.album?.layout.grid = grid }
        if let snap { candidate.album?.layout.snap = snap }
        guard candidate != project else { return }
        project = candidate; dirty = true; scheduleRecovery()
    }
    func undo() {
        cancelRecordingRequest();guard !midiRecording && !audioRecordingBusy else{status="녹음 정지와 파일 마무리 후 실행 취소하세요";return}
        guard let (name,previous,layoutOnly) = undoStack.last else { return }
        do {
            let restored = try CircleHistory.restore(previous, layoutOnly: layoutOnly, current: project)
            undoStack.removeLast(); redoStack.append((name,project,layoutOnly)); project = restored
        } catch { fail(error); return }
        undoCount = undoStack.count; redoCount = redoStack.count; dirty = true; status = "\(name) 실행 취소"; normalizeHierarchySelection(); scheduleRecovery()
    }
    func redo() {
        cancelRecordingRequest();guard !midiRecording && !audioRecordingBusy else{status="녹음 정지와 파일 마무리 후 다시 실행하세요";return}
        guard let (name,next,layoutOnly) = redoStack.last else { return }
        do {
            let restored = try CircleHistory.restore(next, layoutOnly: layoutOnly, current: project)
            redoStack.removeLast(); undoStack.append((name,project,layoutOnly)); project = restored
        } catch { fail(error); return }
        undoCount = undoStack.count; redoCount = redoStack.count; dirty = true; status = "\(name) 다시 실행"; normalizeHierarchySelection(); scheduleRecovery()
    }
    func fail(_ error:Error) { if moviePreparing {movieGeneration+=1;moviePreparing=false}; errorMessage = error.localizedDescription; status = error.localizedDescription }
    func addSection(at point:Point? = nil) {
        let name = "섹션 \(project.active.uses.count+1)"
        let target = point ?? Point(Double(project.active.uses.count%4)*1000,Double(project.active.uses.count/4)*1000)
        var id:ID?
        mutate("섹션 만들기") { id = $0.addSection(name:name,at:target); $0 = try SectionGraphMigration.migrate($0) }
        if let id { focusHierarchy(.section(arrangementID: project.activeArrangementID, useID: id)); status="서클을 확대해 MIDI·오디오·이펙트를 편집하세요" }
    }
    func select(_ id:ID,add:Bool = false) {
        var ids = add ? selection : []; if add && ids.contains(id) { ids.remove(id) } else { ids.insert(id) }; selectNodes(ids)
        edgeSelection = nil; selectedNoteID = nil; editPatternID = nil; selectedBeat = 0
        if let n = project.signal.nodes.first(where:{$0.id == id}),let track = n.trackID { selectedTrackID = track }
    }
    func connect(_ from:ID,_ to:ID,sidechain:Bool = false) {
        if soundView {
            mutate("사운드 연결") { p in
                var edge = SignalEdge(from:from,to:to); edge.sidechain = sidechain
                if !p.signal.edges.contains(where:{$0.from == from && $0.to == to && $0.sidechain == sidechain}) { p.signal.edges.append(edge) }
                _ = try SignalValidator.sorted(p.signal,tracks:p.tracks)
            }
        } else { mutate("섹션 연결") { try ProjectEditing.connect(from:from,to:to,in:&$0) } }
    }
    func insert(_ use:ID,on edge:ID) { mutate("섹션 순서 이동") { try ProjectEditing.insert(useID:use,on:edge,in:&$0) } }
    func setStart() { guard let id = selectedUse?.id else { return }; mutate("시작 지정") { $0.arrangements[$0.activeIndex].startID = id } }
    func setEnd() { updateUse("끝 지정") { $0.isEnd = true } }
    func updateUse(_ label:String,_ block:(inout SectionUse)->Void) {
        guard let id = selectedUse?.id else { return }
        mutate(label) { p in if let i = p.arrangements[p.activeIndex].uses.firstIndex(where:{$0.id == id}) { block(&p.arrangements[p.activeIndex].uses[i]); _ = try ArrangementCompiler.compile(p) } }
    }
    func updateTrack(_ label:String,_ block:(inout Track)->Void) {
        guard let id = selectedTrackID else { return }
        let previous=selectedTrack?.instrument
        mutate(label) { p in if let i = p.tracks.firstIndex(where:{$0.id == id}) { block(&p.tracks[i]); if let si = p.signal.nodes.firstIndex(where:{$0.trackID == id}) { p.signal.nodes[si].name = p.tracks[i].name } } }
        if selectedTrack?.instrument != previous {embeddedPlugin=nil;cancelAudition()}
    }
    func updateSignal(_ label:String,_ block:(inout SignalNode)->Void) {
        guard let id = selectedSignal?.id else { return }
        let previous=selectedSignal?.effect
        mutate(label) { p in if let i = p.signal.nodes.firstIndex(where:{$0.id == id}) { block(&p.signal.nodes[i]) } }
        if selectedSignal?.effect.kind != previous?.kind || selectedSignal?.effect.plugin?.id != previous?.plugin?.id {embeddedPlugin=nil}
    }
    func updateEdge(_ block:(inout FlowEdge)->Void) {
        guard let id = edgeSelection else { return }
        mutate("전환 편집") { p in if let i = p.arrangements[p.activeIndex].edges.firstIndex(where:{$0.id == id}) { block(&p.arrangements[p.activeIndex].edges[i]) } }
    }
    func removeSelection() {
        if let edge = edgeSelection {
            mutate("연결 삭제") { p in if soundView { p.signal.edges.removeAll{$0.id == edge} } else { p.arrangements[p.activeIndex].edges.removeAll{$0.id == edge}; p.arrangements[p.activeIndex].chosenEdges = p.active.chosenEdges.filter{$0.value != edge} } }; edgeSelection = nil; closeFocus(); return
        }
        if soundView {
            let ids = selection.subtracting(project.signal.nodes.filter{$0.kind == .source || $0.kind == .master}.map(\.id))
            mutate("사운드 노드 삭제") { p in p.signal.nodes.removeAll{ids.contains($0.id)}; p.signal.edges.removeAll{ids.contains($0.from)||ids.contains($0.to)}; for id in ids { p.signal.layout.positions.removeValue(forKey:id) } }
        } else { let ids = selection; mutate("서클 삭제") { ProjectEditing.removeUses(ids,in:&$0) } }
        selection = []; closeFocus()
    }
    func reuse() {
        guard let id = selectedUse?.id else { return }; let point = project.active.layout.positions[id] ?? Point(); var result:ID?
        let node=hierarchyScene?.node(.section(arrangementID:project.activeArrangementID,useID:id))
        let gap=max(1000,(node.map{$0.outerRadius/$0.scale} ?? 400)*2+120)
        mutate("섹션 다시 사용") { result = try ProjectEditing.reuse(id,in:&$0,at:Point(point.x+gap,point.y)) }
        if let result { focusHierarchy(.section(arrangementID:project.activeArrangementID,useID:result)) }
    }
    func detach() { guard let id = selectedUse?.id else { return }; mutate("독립 섹션으로 분리") { try ProjectEditing.detach(id,in:&$0) } }
    func unfold() { guard let id = selectedUse?.id else { return }; mutate("반복 펼치기") { try ProjectEditing.unfoldRepeats(id,in:&$0) } }
    func duplicateArrangement() { closeFocus(); let name = "편곡 \(project.arrangements.count+1)"; mutate("편곡안 복제") { ProjectEditing.duplicateArrangement(in:&$0,name:name) }; selection = [] }
    func editLayout(_ label:String,_ block:(inout CirclrCore.Layout)->Void) { mutate(label,musical:false) { p in if soundView { block(&p.signal.layout) } else { block(&p.arrangements[p.activeIndex].layout) } } }
    func makeGroup() {
        guard selection.count >= 2 else { return }; let name = "그룹 \(layout.groups.count+1)"; let ids = selection
        editLayout("그룹 만들기") { l in for i in l.groups.indices { l.groups[i].members.removeAll{ids.contains($0)} }; l.groups.removeAll{$0.members.isEmpty}; l.groups.append(CanvasGroup(name:name,members:Array(ids))) }
    }
    func toggleGroup(_ id:ID) { editLayout("그룹 접기/펼치기") { l in if let i = l.groups.firstIndex(where:{$0.id == id}) { l.groups[i].collapsed.toggle() } } }
    func ungroup(_ id:ID) { editLayout("그룹 해제") { $0.groups.removeAll{$0.id == id} } }
    func align(_ mode:Int) {
        let ids = selection.sorted { (layout.positions[$0]?.x ?? 0) < (layout.positions[$1]?.x ?? 0) }; guard ids.count > 1 else { return }
        editLayout("정렬") { l in
            let points = ids.compactMap{l.positions[$0]}; guard points.count == ids.count else { return }
            let x = points.map(\.x).reduce(0,+)/Double(points.count), y = points.map(\.y).reduce(0,+)/Double(points.count)
            for (i,id) in ids.enumerated() { var p = l.positions[id]!; if mode == 0 { p.y = y } else if mode == 1 { p.x = x } else { p.x = points.first!.x + Double(i)*(points.last!.x-points.first!.x)/Double(ids.count-1) }; l.positions[id] = p }
        }
    }
    func selectTrack(_ id:ID) {if selectedTrackID != id {cancelRecordingRequest()};cancelAudition();selectedTrackID=id;selectedNoteID=nil;selectedClipID=nil;embeddedPlugin=nil}
    func addTrack() { let name = "악기 \(project.tracks.count+1)"; var id:ID?; mutate("트랙 추가") { id = $0.addTrack(name:name) }; if let id {selectTrack(id)} }
    func addEffect(_ kind:EffectKind, at point:Point? = nil) {
        let pointOverride = point
        var node = SignalNode(kind:.effect,name:Self.effectName(kind)); node.effect = Effect(kind,amount:kind == .gain ? 1 : 0.5,secondary:0.3)
        let sourceID = (selectedSignal?.kind == .master ? nil:selectedSignal?.id) ?? project.signal.nodes.first(where:{$0.trackID == selectedTrackID})?.id
        mutate("Effect 추가") { p in
            p.signal.nodes.append(node); let point = sourceID.flatMap{p.signal.layout.positions[$0]} ?? Point()
            p.signal.layout.positions[node.id] = pointOverride ?? Point(point.x+240,point.y)
            if let sourceID {
                let outgoing = p.signal.edges.filter{$0.from == sourceID && !$0.sidechain}
                p.signal.edges.removeAll{$0.from == sourceID && !$0.sidechain}
                p.signal.edges.append(SignalEdge(from:sourceID,to:node.id))
                for e in outgoing { var copy = e; copy.from = node.id; p.signal.edges.append(copy) }
                if outgoing.isEmpty,let master = p.signal.nodes.first(where:{$0.kind == .master}),master.id != sourceID { p.signal.edges.append(SignalEdge(from:node.id,to:master.id)) }
            }
        }; soundView = true; select(node.id)
    }
    func addBus(at point:Point? = nil) { let name = "Bus \(project.signal.nodes.filter{$0.kind == .bus}.count+1)"; let node = SignalNode(kind:.bus,name:name); mutate("Bus 추가") { p in p.signal.nodes.append(node); p.signal.layout.positions[node.id] = point ?? Point(350,450+Double(p.signal.nodes.filter{$0.kind == .bus}.count-1)*220); if let master = p.signal.nodes.first(where:{$0.kind == .master}) { p.signal.edges.append(SignalEdge(from:node.id,to:master.id)) } }; soundView = true; select(node.id) }
    static func effectName(_ kind:EffectKind) -> String { switch kind { case .gain:return "Gain"; case .lowpass:return "Low-pass"; case .delay:return "Delay"; case .reverb:return "Reverb"; case .drive:return "Drive"; case .pan:return "Pan"; case .compressor:return "Compressor"; case .audioUnit:return "Audio Unit" } }
    func setLane(_ lane:Lane) {
        if let id = editPatternID { mutate("리듬 패턴 편집") { p in if let i = p.patterns.firstIndex(where:{$0.id == id}) { p.patterns[i].notes = lane.notes; p.patterns[i].audio = lane.audio } }; return }
        guard let id = selectedUse?.id else { return }; let original = editOriginal
        mutate(original ? "원본 연주 편집" : "이번 사용 연주 편집") { try ProjectEditing.setLane(lane,for:id,original:original,in:&$0) }
    }
    func addNote(beat:Double,pitch:Int,length:Double = 0.5) {
        guard let trackID = selectedTrackID else { return }; var lane = currentLane ?? Lane(trackID:trackID)
        let note = Note(beat:max(0,beat),length:max(0.03125,min(length,editorBeats-beat)),pitch:max(0,min(127,pitch)))
        lane.notes.append(note); setLane(lane); selectedNoteID = note.id
        if let token=audition(pitch:note.pitch,velocity:note.velocity,on:true) {
            Task { try? await Task.sleep(nanoseconds:180_000_000); auditionOutput.release(token) }
        }
    }
    func removeNote() {editMIDINotes(.delete)}
    func makePattern() {
        guard let track = project.tracks.first(where:{$0.instrument.drums}) ?? selectedTrack else { return }; let name = "리듬 \(project.patterns.count+1)"
        var pattern = RhythmPattern(name:name,trackID:track.id); pattern.meter = currentContext.meter; pattern.length = currentContext.meter.quarters
        mutate("패턴 만들기") { $0.patterns.append(pattern) }; openPattern(pattern.id)
    }
    func importAudio(at point:Point? = nil) {
        guard canStartMediaImport,let destination=audioImportDestination(at:point) else {status="재생·녹음을 정지하고 오디오를 넣을 섹션을 선택하세요";return}
        let request=mediaImportRequest(destination)
        let panel=NSOpenPanel();panel.title="오디오 가져오기";panel.allowedContentTypes=[.audio];panel.allowsMultipleSelection=true
        guard panel.runModal() == .OK else{return}
        beginAudioImport(panel.urls,request:request)
    }
    func play(onlySelection:Bool = false) {
        library.stopPreview()
        if auditionOutput.status.pending {stop();return}
        cancelAudition()
        if moviePreparing {stop();return}
        if midiRecording || audioRecording || audioRecordPending {stop();return}
        if playback.playing { stop(); return }
        if preparing { stop(); return }
        playbackFollow = playbackFollow.startingPlayback()
        prepare(onlySelection:onlySelection,autoplay:true)
    }
    func prepare(onlySelection:Bool,autoplay:Bool,includeStems:Bool = false,completion:((PreparedAudio)->Void)? = nil) {
        library.stopPreview()
        do {
            let snapshot = project,root = mediaRoot,plan = try onlySelection ? ArrangementCompiler.compile(snapshot,onlyUseID:selectedUse?.id) : AlbumCompiler.executionPlan(snapshot)
            let key = "\(snapshot.musicRevision):\(snapshot.activeArrangementID):\(onlySelection ? selectedUse?.id ?? "" : "all"):\(includeStems)"
            if key == preparedKey,let prepared {
                if !autoplay { completion?(prepared); return }
                renderGeneration += 1; let generation = renderGeneration
                preparing = true; status = "오디오 출력 연결 중"
                renderTask = Task { [weak self] in
                    guard let self else { return }
                    do { try await self.playback.play(prepared)
                        guard generation == self.renderGeneration else { return }
                        self.preparing = false; self.status = "재생 중"; completion?(prepared)
                    } catch { if generation == self.renderGeneration {self.preparing=false;self.handlePlaybackError(error)} }
                }
                return
            }
            guard plan.duration > 0 else { throw CirclrError("섹션을 먼저 만드세요") }
            renderGeneration += 1; let generation = renderGeneration
            preparing = true; progress = 0; status = "오디오 준비"; renderTask?.cancel(); renderWorker?.cancel()
            renderTask = Task { [weak self] in
                do {
                    let worker = Task.detached(priority:.userInitiated) {
                        try await ArrangementRenderer.render(project:snapshot,root:root,plan:plan,includeStems:includeStems,includeVisualization:true) { message,value in DispatchQueue.main.async { [weak self] in guard let self,self.renderGeneration == generation else { return }; self.status = message; self.progress = value } }
                    }
                    self?.renderWorker = worker
                    let result = try await worker.value
                    guard let self,self.renderGeneration == generation,!Task.isCancelled else { return }
                    self.prepared = result; self.preparedKey = key
                    self.status = result.peak > 1 ? "출력이 0 dBFS를 넘습니다. Gain을 낮추세요" : (plan.warnings.first ?? "재생 준비 완료")
                    if autoplay { self.status="오디오 출력 연결 중";try await self.playback.play(result);self.status="재생 중" }
                    guard self.renderGeneration == generation else { return }
                    self.preparing = false; completion?(result)
                } catch { guard let self,self.renderGeneration == generation else { return }; self.preparing = false; self.handlePlaybackError(error) }
            }
        } catch { fail(error) }
    }
    func stop() { library.stopPreview(); cancelMediaImport(); cancelRecordingRequest(); finishMovieRecording(); if agentJob?.state == "running" {agentJob?.state="cancelled";agentJob?.message="사용자가 정지했습니다";recordActivity("앱","작업 취소")}; productionGeneration += 1; productionTask?.cancel(); productionWorker?.cancel(); agentOpenWorker?.cancel(); cancelAudition(); renderGeneration += 1; renderTask?.cancel(); renderWorker?.cancel(); renderTask = nil; preparing = false; playback.stop(); meter.update(seconds:0,playing:false); if midiRecording || audioRecording { stopRecording() }; status = "정지" }
    func export(stems:Bool = false) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = project.name + (stems ? "-stems" : ".wav"); panel.title = stems ? "Stem 저장 폴더" : "WAV 내보내기"
        if !stems { panel.allowedContentTypes = [UTType(filenameExtension:"wav")!] }
        guard panel.runModal() == .OK,let url = panel.url else { return }
        let names = Dictionary(uniqueKeysWithValues:project.tracks.map{($0.id,$0.name)})
        prepare(onlySelection:false,autoplay:false,includeStems:stems) { [weak self] audio in
            do {
                try AudioExport.save(audio,to:url,stemNames:stems ? names:nil)
                self?.status = "내보내기 완료 · \(url.lastPathComponent)"
            } catch { self?.fail(error) }
        }
    }
    func save(as saveAs:Bool = false) {
        guard nameEditing.resolve() else{return}
        captureViewport()
        var target = projectURL
        if saveAs || target == nil { let panel = NSSavePanel(); panel.nameFieldStringValue = project.name+".circlr"; panel.title = "앨범 저장"; guard panel.runModal() == .OK else { return }; target = panel.url }
        guard let target else { return }
        do { project = try ProjectStore.saveSession(project,to:target,mediaRoot:mediaRoot); projectURL = target; mediaRoot = target; dirty = false; recoveryTask?.cancel(); recoveryTask = nil; status = "저장 완료 · \(target.lastPathComponent)"; try? FileManager.default.removeItem(at:recoveryURL) }
        catch { fail(error) }
    }
    func clearSavedRecovery(){recoveryTask?.cancel();recoveryTask=nil;try? FileManager.default.removeItem(at:recoveryURL)}
    func confirmDiscard() -> Bool {
        guard nameEditing.resolve() else{return false}
        guard dirty else { return true }; let a = NSAlert(); a.messageText = "저장하지 않은 변경이 있습니다"; a.informativeText = "현재 곡을 저장한 뒤 계속하거나 변경을 버릴 수 있습니다."; a.addButton(withTitle:"저장"); a.addButton(withTitle:"취소"); a.addButton(withTitle:"변경 버리기")
        let r = a.runModal(); if r == .alertFirstButtonReturn { save(); return !dirty }; return r == .alertThirdButtonReturn
    }
    func newProject() { guard confirmDiscard() else { return }; stop(); var p = Project(); selectedTrackID = p.addTrack(name:"악기 1"); _ = p.addTrack(name:"드럼",drums:true); p.enableAlbum(); p.name = "새 앨범"; project = p; projectURL = nil; mediaRoot = nil; resetSession(); status = "새 앨범" }
    func open(_ url:URL? = nil) {
        guard confirmDiscard() else { return }; var target = url
        if target == nil { let panel = NSOpenPanel(); panel.message = ".circlr 곡 파일 또는 manifest.json이 있는 곡 폴더를 선택하세요"; panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; guard panel.runModal() == .OK else { return }; target = panel.url }
        guard let target else { return }
        do { let loaded = try ProjectStore.load(target); stop(); var migrated = loaded.project; migrated.enableAlbum(); migrated = try SectionGraphMigration.migrate(migrated); project = migrated; projectURL = migrated == loaded.project ? target : nil; mediaRoot = target; selectedTrackID = project.tracks.first?.id; resetSession(); dirty = migrated != loaded.project; status = dirty ? "앨범으로 확장했습니다 · 새 위치에 저장하세요" : "\(project.name) 열기 완료" }
        catch { fail(error) }
    }
    func resetSession() { libraryOpen=false;libraryDestination=nil;cancelMediaImport(); if !recorder.busy && audioRecoveryURL==nil {audioCaptureMessage="";audioInputSeconds=0;audioInputFormat=nil}; connectionEditorIntent=nil;connectionsOpen=false;automationOpen=false;automationViewport.reset();selectedAutomationPointID=nil;cancelRecordingRequest(); audioSplitOffset=nil;midiImportDraft=nil;selectedNoteID=nil; navigationOpen=false; commandPalette=nil; soundView=false; hierarchyTransitionID=nil; hierarchySelection = .album; hierarchySelections = [.album]; hierarchySettingsOpen = false; hierarchyCommand = HierarchyCommand(action: .restore); waveformGeneration += 1; waveforms = [:]; waveformLoading = []; focus = nil; embeddedPlugin = nil; recoveryTask?.cancel(); recoveryTask = nil; try? FileManager.default.removeItem(at:recoveryURL); selection = []; edgeSelection = nil; editPatternID = nil; prepared = nil; preparedKey = ""; dirty = false; undoStack = []; redoStack = []; undoCount = 0; redoCount = 0 }
    func scheduleViewportRecovery() { captureViewport(); scheduleRecovery() }
    private func scheduleRecovery() {
        recoveryTask?.cancel(); let snapshot = project,root = mediaRoot,url = recoveryURL
        recoveryTask = Task { try? await Task.sleep(nanoseconds:800_000_000); guard !Task.isCancelled else { return }; do { let data = try JSONEncoder().encode(Recovery(project:snapshot,root:root,date:Date())); try data.write(to:url,options:.atomic) } catch { status = "자동 복구 저장 실패: \(error.localizedDescription)" } }
    }
    func offerRecovery() {
        guard let data = try? Data(contentsOf:recoveryURL),let recovery = try? JSONDecoder().decode(Recovery.self,from:data) else { return }
        let alert = NSAlert(); alert.messageText = "저장되지 않은 곡을 복구할까요?"; alert.informativeText = recovery.project.name; alert.addButton(withTitle:"복구"); alert.addButton(withTitle:"새로 시작")
        if alert.runModal() == .alertFirstButtonReturn { do { var restored = recovery.project; restored.enableAlbum(); project = try SectionGraphMigration.migrate(restored) } catch { fail(error); return }; mediaRoot = recovery.root; selectedTrackID = project.tracks.first?.id; dirty = true; status = "복구 완료 · 새 위치에 저장하세요" }
        else { try? FileManager.default.removeItem(at:recoveryURL) }
    }
    func midi(status:UInt8,pitch:Int,velocity:Int,time:Double) {
        let type = status & 0xF0
        guard type == 0x90 || type == 0x80 else { return }
        let on = type == 0x90 && velocity > 0
        audition(pitch:pitch,velocity:velocity,on:on)
        guard midiRecording,let clock = recordClock else { return }
        let elapsed = max(0,time-recordStart)
        if on { heldNotes[pitch] = (elapsed,velocity) }
        else if let (start,v) = heldNotes.removeValue(forKey:pitch) { appendRecorded(pitch:pitch,velocity:v,start:start,end:elapsed,clock:clock) }
    }
    private func appendRecorded(pitch:Int,velocity:Int,start:Double,end:Double,clock:MusicClock) {
        let first = Int(start/clock.seconds),last = Int(max(start,end-0.000001)/clock.seconds)
        for iteration in first...max(first,last) {
            let s = max(0,start-Double(iteration)*clock.seconds), e = min(clock.seconds,end-Double(iteration)*clock.seconds)
            if e > s { recordedNotes.append(Note(beat:Double(iteration)*clock.beats+clock.beat(atSeconds:s),length:max(0.03125,clock.beat(atSeconds:e)-clock.beat(atSeconds:s)),pitch:pitch,velocity:velocity)) }
        }
    }
    func startMIDIRecording() {
        guard !recorder.busy else{status="오디오 녹음을 먼저 정지하고 파일 마무리를 기다리세요";return}
        if midiRecording { stopRecording(); return }
        guard let use = selectedUse,let clock = recordingClock,let track = selectedTrackID else { status = "녹음할 서클과 트랙을 선택하세요"; return }
        stop(); recordClock = clock; recordUseID = use.id; recordLaneID = selectedLaneID; recordArrangementID = project.activeArrangementID; recordingTrackID = track; originalRecordProject = project
        recordRepeats = selectedMusic?.repeatCount ?? use.repeatCount; recordedNotes = []; heldNotes = [:]; recordStart = ProcessInfo.processInfo.systemUptime; midiRecording = true; status = "MIDI 녹음 중 · MIDI 장치 또는 화면 건반을 연주하세요"
    }
    private func recordingStateChanged() {
        audioCapturePhase=recorder.phase;audioCaptureMessage=recorder.message;audioRecording=recorder.recording;audioInputFormat=recorder.format
        audioRecordPending=recordingAuthorization.pending != nil || recorder.phase == .starting
        if !recorder.recording {audioInputLevel=0}
        if recorder.phase == .failed,let url=audioRecordURL,FileManager.default.fileExists(atPath:url.path){audioRecoveryURL=url}
        recordActivity("앱",recorder.message)
    }
    func cancelRecordingRequest() {
        let permissionOnly=recordingAuthorization.pending != nil && !recorder.busy
        recordingAuthorization.cancel();audioRequestClock=nil;audioRecordPending=false;recorder.cancelStart()
        if permissionOnly {audioCaptureMessage="녹음 시작 취소"}
    }
    func startAudioRecording() {
        if audioRecording {stopRecording();return}
        if audioRecordPending {cancelRecordingRequest();status="녹음 시작 취소";return}
        guard !recorder.busy else{status=recorder.message;return}
        guard editPatternID==nil,let use=selectedUse,let clock=recordingClock,let address=hierarchySelection,let track=selectedTrackID else {status="녹음할 서클과 트랙을 선택하세요";return}
        stop()
        let request=recordingAuthorization.begin(projectID:project.id,revision:project.musicRevision,address:address,trackID:track,laneID:selectedLaneID)
        let arrangement=project.activeArrangementID,repeats=selectedMusic?.repeatCount ?? use.repeatCount,useID=use.id
        audioRequestClock=clock
        audioRecordPending=true;audioRecoveryURL=nil;audioInputSeconds=0;audioInputLevel=0;audioCaptureMessage="마이크 접근 확인 중";status=audioCaptureMessage
        AVCaptureDevice.requestAccess(for:.audio) { [weak self] allowed in Task { @MainActor in
            guard let self,self.recordingAuthorization.pending?.id==request.id else{return}
            guard self.recordingAuthorization.matches(request,projectID:self.project.id,revision:self.project.musicRevision,address:self.hierarchySelection,trackID:self.selectedTrackID,laneID:self.selectedLaneID),let clock=self.audioRequestClock else{self.cancelRecordingRequest();self.status="대상이 변경되어 녹음 시작을 취소했습니다";return}
            guard allowed else {self.cancelRecordingRequest();self.audioCaptureMessage="마이크 접근이 허용되지 않았습니다";self.fail(CirclrError("시스템 설정에서 써클러의 마이크 접근을 허용하세요"));return}
            let url=self.storageRoot.appendingPathComponent("takes/\(newID()).caf");self.audioRecordURL=url
            do {try self.recorder.start(to:url,maximumSeconds:clock.seconds*Double(repeats)){[weak self] result in
                guard let self,self.recordingAuthorization.pending?.id==request.id else{return}
                let valid=self.recordingAuthorization.consume(request,projectID:self.project.id,revision:self.project.musicRevision,address:self.hierarchySelection,trackID:self.selectedTrackID,laneID:self.selectedLaneID)
                self.audioRecordPending=false
                switch result {
                case .success:
                    guard valid else {self.recorder.stop{_ in};self.audioRecoveryURL=url;return}
                    self.recordStart=ProcessInfo.processInfo.systemUptime;self.audioLastInputAt=self.recordStart;self.audioLastFrames=0;self.recordClock=clock;self.recordUseID=useID;self.recordLaneID=request.laneID;self.recordArrangementID=arrangement;self.recordingTrackID=track;self.audioCaptureProjectID=request.projectID;self.recordRepeats=repeats;self.status="오디오 녹음 중"
                case .failure(let error):if !(error is CancellationError){self.fail(error)}
                }
            }} catch {self.cancelRecordingRequest();self.fail(error)}
        }}
    }
    private func finishAudioRecording() {
        guard let projectID=audioCaptureProjectID,let arrangementID=recordArrangementID,let useID=recordUseID,let trackID=recordingTrackID,let clock=recordClock else{return}
        let laneID=recordLaneID,url=audioRecordURL
        recorder.stop{[weak self] result in
            guard let self else{return}
            do {
                guard let audio=try result.get() else{throw CirclrError("입력 오디오가 없어 take를 만들지 않았습니다")}
                self.audioInputSeconds=audio.duration
                let asset=Asset(name:"녹음 \(Date().formatted(date:.omitted,time:.shortened))",path:audio.url.path,duration:audio.duration,sampleRate:audio.format.sampleRate)
                self.mutate("오디오 take 저장"){try AudioTakeEditing.save(asset:asset,projectID:projectID,arrangementID:arrangementID,useID:useID,trackID:trackID,laneID:laneID,clock:clock,in:&$0)}
                if self.project.assets.contains(where:{$0.id==asset.id}) {self.audioRecoveryURL=nil;self.audioCaptureMessage="오디오 take 저장 완료";self.status=self.audioCaptureMessage}
                else {self.audioRecoveryURL=audio.url;self.audioCaptureMessage="원래 대상에 넣지 못한 녹음 파일을 보존했습니다";self.recordActivity("앱",self.audioCaptureMessage+" · "+audio.url.path)}
            }catch {if let url,FileManager.default.fileExists(atPath:url.path){self.audioRecoveryURL=url};self.audioCaptureMessage=error.localizedDescription;self.fail(error)}
        }
        recordClock=nil;recordUseID=nil;audioCaptureProjectID=nil;originalRecordProject=nil
    }
    func stopRecording() {
        cancelRecordingRequest()
        if audioRecording {finishAudioRecording();return}
        guard midiRecording || audioRecording,let useID = recordUseID,let trackID = recordingTrackID,let clock = recordClock else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime-recordStart
        if midiRecording {
            for (pitch,(start,v)) in heldNotes { appendRecorded(pitch:pitch,velocity:v,start:start,end:elapsed,clock:clock) }; heldNotes = [:]
            let all = recordedNotes; midiRecording = false
            let iterations = max(1,Int(ceil(elapsed/clock.seconds)))
            mutate("MIDI take 저장") { p in
                for iteration in 0..<iterations {
                    let notes = all.filter{ $0.beat >= Double(iteration)*clock.beats && $0.beat < Double(iteration+1)*clock.beats }.map{ n -> Note in var copy = n; copy.beat -= Double(iteration)*clock.beats; return copy }
                    if !notes.isEmpty { var lane = Lane(trackID:trackID); lane.notes = notes; var takes = p.takes ?? []; var take=RecordedTake(useID:useID,name:"MIDI \(Date().formatted(date:.omitted,time:.shortened)) · \(iteration+1)회",lane:lane); take.targetLaneID=self.recordLaneID; take.arrangementID=self.recordArrangementID; takes.append(take); p.takes = takes }
                }
            }
            if !all.isEmpty,let take = project.takes?.last(where:{$0.useID == useID && $0.lane.trackID == trackID}) { activateTake(take) }
            status = "MIDI 녹음 저장 · \(all.count)개 note"
        }
        recordClock = nil; recordUseID = nil; originalRecordProject = nil
    }
    func activateTake(_ take:RecordedTake) {
        mutate("Take 선택") { try ProjectEditing.activateTake(take,in:&$0) }
    }
    func showPluginEditor(effect:Bool) {
        let descriptor = effect ? selectedSignal?.effect.plugin : selectedTrack?.instrument.plugin
        guard let descriptor else { return }; let nodeID = selectedSignal?.id,trackID = selectedTrackID, requestedFocus = focus, requestedAddress = hierarchySelection
        Task {
            do {
                let unit = try await AudioUnitHost.instantiate(descriptor)
                guard let controller = await unit.auAudioUnit.requestViewController() else { status = "이 Audio Unit은 편집 화면을 제공하지 않습니다"; return }
                guard self.focus == requestedFocus, self.hierarchySelection == requestedAddress,
                      (effect ? self.selectedSignal?.id==nodeID:self.selectedTrackID==trackID),
                      (effect ? self.selectedSignal?.effect.kind == .audioUnit:self.selectedTrack?.instrument.kind == .audioUnit),
                      (effect ? self.selectedSignal?.effect.plugin?.id:self.selectedTrack?.instrument.plugin?.id)==descriptor.id else { return }
                let wrapper = PluginEditorController(plugin:controller,unit:unit,onApply:{ [weak self] in
                    guard let self,self.focus==requestedFocus,self.hierarchySelection==requestedAddress,
                          (effect ? self.selectedSignal?.id==nodeID:self.selectedTrackID==trackID),
                          (effect ? self.selectedSignal?.effect.kind == .audioUnit:self.selectedTrack?.instrument.kind == .audioUnit),
                          (effect ? self.selectedSignal?.effect.plugin?.id:self.selectedTrack?.instrument.plugin?.id)==descriptor.id else { return }
                    do { let state = try AudioUnitHost.capture(unit); self.mutate("Audio Unit 설정") { p in if effect,let i = p.signal.nodes.firstIndex(where:{$0.id == nodeID}) { p.signal.nodes[i].effect.plugin?.state = state } else if let i = p.tracks.firstIndex(where:{$0.id == trackID}) { p.tracks[i].instrument.plugin?.state = state } }; self.cancelAudition() }
                    catch { self.fail(error) }
                })
                self.embeddedPlugin = wrapper

            } catch { fail(error) }
        }
    }
}

@MainActor final class PluginEditorController:NSViewController {
    let plugin:NSViewController; let unit:AVAudioUnit; let onApply:()->Void
    init(plugin:NSViewController,unit:AVAudioUnit,onApply:@escaping()->Void) { self.plugin = plugin; self.unit = unit; self.onApply = onApply; super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError() }
    override func loadView() {
        let root = NSView(frame:NSRect(x:0,y:0,width:700,height:500)); self.view = root; addChild(plugin)
        plugin.view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(plugin.view)
        let button = NSButton(title:"설정 적용",target:self,action:#selector(apply)); button.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(button)
        NSLayoutConstraint.activate([plugin.view.topAnchor.constraint(equalTo:root.topAnchor),plugin.view.leadingAnchor.constraint(equalTo:root.leadingAnchor),plugin.view.trailingAnchor.constraint(equalTo:root.trailingAnchor),plugin.view.bottomAnchor.constraint(equalTo:button.topAnchor,constant:-10),button.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-16),button.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-12)])
    }
    @objc func apply() { onApply() }
}
