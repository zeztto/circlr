import Foundation

public struct AgentRequest:Codable {
    public var id:String
    public var method:String
    public var projectID:ID?
    public var expectedRevision:Int?
    public var arguments:AgentArguments?
    public init(method:String,id:String = newID()){self.id=id;self.method=method}
}
public struct AgentArguments:Codable {
    public var operations:[AgentOperation]?
    public var arrangementID:ID?
    public var useID:ID?
    public var trackID:ID?
    public var nodeID:ID?
    public var jobID:ID?
    public var path:String?
    public var afterSequence:Int?
    public var detail:Bool?
    public var minimized:Bool?
    public var follow:Bool?
    public var compositionID:ID?
    public init(){}
}
public struct AgentOperation:Codable {
    public var kind:String
    public var arrangementID:ID?
    public var useID:ID?
    public var laneID:ID?
    public var nodeID:ID?
    public var trackID:ID?
    public var name:String?
    public var notes:[Note]?
    public var pattern:MIDIPattern?
    public var append:Bool?
    public var instrument:Instrument?
    public var synthVoice:SynthVoice?
    public var effect:Effect?
    public var context:MusicContext?
    public var settings:ContextSettings?
    public var gain:Double?
    public var muted:Bool?
    public var startBeat:Double?
    public var lengthBeats:Double?
    public var repeatCount:Int?
    public var from:ID?
    public var to:ID?
    public var sidechain:Bool?
    public var bars:Int?
    public var stepIndex:Int?
    public var subdivisions:Int?
    public var pitch:Int?
    public var velocity:Int?
    public var gate:Double?
    public var enabled:Bool?
    public var noteIDs:[ID]?
    public var edit:String?
    public var semitones:Int?
    public var beatOffset:Double?
    public var strength:Double?
    public var clipID:ID?
    public var sourceStart:Double?
    public var duration:Double?
    public init(_ kind:String){self.kind=kind}
}

public enum AgentProjectEditing {
    public static func check(_ request:AgentRequest,project:Project) throws {
        guard request.projectID==project.id,request.expectedRevision==project.musicRevision else {throw CirclrError("stale_revision: projectID와 expectedRevision이 현재 문서와 다릅니다. snapshot을 다시 읽으세요")}
    }
    /// All operations commit together. Stable IDs and expected revision prevent stale writes.
    public static func apply(_ request:AgentRequest,to input:Project) throws -> Project {
        try check(request,project:input)
        guard let operations=request.arguments?.operations,!operations.isEmpty,operations.count<=128 else {throw CirclrError("operations는 1–128개가 필요합니다")}
        var p=input
        for op in operations {
            p.activeArrangementID=input.activeArrangementID
            if let ai=op.arrangementID {guard p.arrangements.contains(where:{$0.id==ai}) else {throw CirclrError("편곡 ID를 찾을 수 없습니다")};p.activeArrangementID=ai}
            switch op.kind {
            case "set_global":guard let context=op.context else {throw CirclrError("context가 필요합니다")};p.global=context
            case "rename_project":guard let name=op.name,!name.isEmpty,name.count<=256 else {throw CirclrError("name이 필요합니다")};p.name=name
            case "set_instrument":
                guard let id=op.trackID,let instrument=op.synthVoice.map({Instrument.synthesizer($0)}) ?? op.instrument,let i=p.tracks.firstIndex(where:{$0.id==id}) else {throw CirclrError("trackID와 instrument 또는 synthVoice가 필요합니다")};p.tracks[i].instrument=instrument
            case "set_track":
                guard let id=op.trackID,let i=p.tracks.firstIndex(where:{$0.id==id}) else {throw CirclrError("trackID가 필요합니다")}
                if let gain=op.gain{p.tracks[i].gain=gain};if let muted=op.muted{p.tracks[i].muted=muted};if let name=op.name{p.tracks[i].name=name}
            case "add_section":
                guard let name=op.name,!name.isEmpty else {throw CirclrError("name이 필요합니다")}
                _=p.addSection(name:name,at:Point(Double(p.active.uses.count)*1000,0),bars:op.bars ?? 8);p=try SectionGraphMigration.migrate(p)
            case "connect_sections":
                guard let from=op.from,let to=op.to else {throw CirclrError("from과 to가 필요합니다")};try ProjectEditing.connect(from:from,to:to,in:&p)
            case "reorder_section":
                guard let id=op.useID else {throw CirclrError("useID가 필요합니다")}
                try OrbitEditing.reorderSection(.section(arrangementID:p.activeArrangementID,useID:id),before:op.to,in:&p)
            case "set_clip":
                guard let id=op.useID,let use=p.active.uses.first(where:{$0.id==id}),let section=p.sections.first(where:{$0.id==use.sectionID}),
                      let laneID=op.laneID,var lane=try ArrangementCompiler.effectiveLanes(section:section,use:use).first(where:{$0.id==laneID}),
                      let clipID=op.clipID,let i=lane.audio.firstIndex(where:{$0.id==clipID}) else {throw CirclrError("useID·laneID·clipID를 확인하세요")}
                if let start=op.sourceStart {lane.audio[i].sourceStart=start}
                if let duration=op.duration {lane.audio[i].duration=duration}
                if let beat=op.startBeat {lane.audio[i].beat=beat}
                if let gain=op.gain {lane.audio[i].gain=gain}
                let clip=lane.audio[i]
                guard let asset=p.assets.first(where:{$0.id==clip.assetID}),clip.sourceStart+clip.duration<=asset.duration+1/max(1,asset.sampleRate) else {throw CirclrError("오디오 구간이 원본 파일 길이를 넘습니다")}
                try ProjectEditing.setLane(lane,for:id,original:false,in:&p)
            case "set_section":
                guard let id=op.useID,let i=p.arrangements[p.activeIndex].uses.firstIndex(where:{$0.id==id}) else {throw CirclrError("useID가 필요합니다")}
                if let name=op.name{p.arrangements[p.activeIndex].uses[i].name=name};if let bars=op.bars{p.arrangements[p.activeIndex].uses[i].barsOverride=bars}
                if let repeats=op.repeatCount{p.arrangements[p.activeIndex].uses[i].repeatCount=repeats};if let settings=op.settings{p.arrangements[p.activeIndex].uses[i].settings=settings}
            case "set_step":
                guard let id=op.useID,let use=p.active.uses.first(where:{$0.id==id}),let section=p.sections.first(where:{$0.id==use.sectionID}),
                      let laneID=op.laneID,let lane=try ArrangementCompiler.effectiveLanes(section:section,use:use).first(where:{$0.id==laneID}),
                      let index=op.stepIndex,let pitch=op.pitch,let enabled=op.enabled else{throw CirclrError("useID·laneID·stepIndex·pitch·enabled가 필요합니다")}
                let (_,_,clock)=try ArrangementCompiler.context(project:p,use:use,arrangementID:p.activeArrangementID)
                var beats=clock.beats
                if let nodeID=op.nodeID {
                    guard let graph=try SectionGraphEditing.effective(section:section,use:use),let node=graph.nodes.first(where:{$0.id==nodeID}),
                          case .midi(let owner)=node.content,owner==laneID else{throw CirclrError("nodeID가 선택한 MIDI lane을 참조하지 않습니다")}
                    beats=node.lengthBeats ?? beats
                }
                let grid=try StepGrid(subdivisions:op.subdivisions ?? 4,beats:beats)
                let next=try StepEditing.set(lane,grid:grid,index:index,pitch:pitch,enabled:enabled,velocity:op.velocity,gate:op.gate)
                if next != lane {try ProjectEditing.setLane(next,for:id,original:false,in:&p)}
            case "edit_notes":
                guard let id=op.useID,let use=p.active.uses.first(where:{$0.id==id}),let section=p.sections.first(where:{$0.id==use.sectionID}),
                      let laneID=op.laneID,let lane=try ArrangementCompiler.effectiveLanes(section:section,use:use).first(where:{$0.id==laneID}),let ids=op.noteIDs,ids.count<=100000,Set(ids).count==ids.count else {throw CirclrError("useID·laneID·중복 없는 noteIDs가 필요합니다")}
                var beats=try ArrangementCompiler.context(project:p,use:use).2.beats
                if let nodeID=op.nodeID {
                    guard let node=try SectionGraphEditing.effective(section:section,use:use)?.nodes.first(where:{$0.id==nodeID}),case .midi(let owner)=node.content,owner==laneID else {throw CirclrError("nodeID가 MIDI lane과 일치하지 않습니다")}
                    beats=node.lengthBeats ?? beats
                }
                let change:MIDIEditing.Change
                switch op.edit {
                case "transpose":guard let value=op.semitones else{throw CirclrError("semitones가 필요합니다")};change = .transpose(value)
                case "move":guard let value=op.beatOffset else{throw CirclrError("beatOffset이 필요합니다")};change = .move(value)
                case "duplicate":guard let value=op.beatOffset else{throw CirclrError("beatOffset이 필요합니다")};change = .duplicate(value)
                case "quantize":change = .quantize(subdivisions:op.subdivisions ?? 4,strength:op.strength ?? 1)
                case "velocity":guard let value=op.velocity else{throw CirclrError("velocity가 필요합니다")};change = .velocity(value)
                case "delete":change = .delete
                default:throw CirclrError("edit: transpose/move/duplicate/quantize/velocity/delete를 선택하세요")
                }
                let next=try MIDIEditing.apply(change,to:lane,ids:Set(ids),beats:beats)
                if next != lane {try ProjectEditing.setLane(next,for:id,original:false,in:&p)}
            case "set_notes","generate_midi","add_midi":
                guard let id=op.useID,let use=p.active.uses.first(where:{$0.id==id}),let section=p.sections.first(where:{$0.id==use.sectionID}) else {throw CirclrError("useID가 필요합니다")}
                var lane:Lane
                if op.kind=="add_midi" {
                    let track=op.trackID ?? p.addTrack(name:op.name ?? "에이전트 MIDI")
                    guard p.tracks.contains(where:{$0.id==track}) else {throw CirclrError("트랙을 찾을 수 없습니다")}
                    if let instrument=op.synthVoice.map({Instrument.synthesizer($0)}) ?? op.instrument,let i=p.tracks.firstIndex(where:{$0.id==track}){p.tracks[i].instrument=instrument}
                    lane=Lane(trackID:track)
                }else{
                    guard let laneID=op.laneID,let found=try ArrangementCompiler.effectiveLanes(section:section,use:use).first(where:{$0.id==laneID}) else {throw CirclrError("laneID가 필요합니다")};lane=found
                }
                let notes:[Note]
                if op.kind=="generate_midi" && op.pattern==nil {throw CirclrError("pattern이 필요합니다")}
                if op.kind=="set_notes" && op.notes==nil {throw CirclrError("notes가 필요합니다")}
                if let pattern=op.pattern {
                    let (_,context,clock)=try ArrangementCompiler.context(project:p,use:use,arrangementID:p.activeArrangementID)
                    notes=try MIDIGenerator.notes(pattern:pattern,context:context,beats:op.lengthBeats ?? clock.beats)
                }else{notes=op.notes ?? []}
                guard notes.count<=100000 else {throw CirclrError("한 명령의 MIDI 노트 한도를 넘습니다")}
                if op.append==true{lane.notes+=notes}else{lane.notes=notes}
                try ProjectEditing.setLane(lane,for:id,original:false,in:&p)
            case "connect","set_node","set_effect","add_effect":
                guard let id=op.useID,let use=p.active.uses.first(where:{$0.id==id}),let section=p.sections.first(where:{$0.id==use.sectionID}),var graph=try SectionGraphEditing.effective(section:section,use:use) else {throw CirclrError("useID와 음악 그래프가 필요합니다")}
                if op.kind=="connect" {
                    guard let from=op.from,let to=op.to else {throw CirclrError("from과 to가 필요합니다")};try SectionGraphEditing.connect(from:from,to:to,sidechain:op.sidechain ?? false,in:&graph)
                }else if op.kind=="add_effect" {
                    guard let from=op.from,graph.nodes.first(where:{$0.id==from})?.content.output == .audio,let effect=op.effect else {throw CirclrError("오디오 from 서클과 effect가 필요합니다")}
                    let node=MusicCircle(name:op.name ?? "이펙터",content:.effect(effect))
                    for i in graph.edges.indices where graph.edges[i].from==from && !graph.edges[i].sidechain{graph.edges[i].from=node.id}
                    graph.nodes.append(node);graph.edges.append(MusicConnection(from:from,to:node.id,signal:.audio))
                    let position=graph.layout.positions[from] ?? Point();graph.layout.positions[node.id]=Point(position.x+250,position.y)
                }else{
                    guard let nodeID=op.nodeID,let i=graph.nodes.firstIndex(where:{$0.id==nodeID}) else {throw CirclrError("nodeID가 필요합니다")}
                    if op.kind=="set_effect" {guard case .effect = graph.nodes[i].content,let effect=op.effect else {throw CirclrError("이펙터 서클과 effect가 필요합니다")};graph.nodes[i].content = .effect(effect)}
                    if let name=op.name{graph.nodes[i].name=name};if let gain=op.gain{graph.nodes[i].gain=gain};if let muted=op.muted{graph.nodes[i].muted=muted}
                    if let start=op.startBeat{graph.nodes[i].startBeat=start};if let length=op.lengthBeats{graph.nodes[i].lengthBeats=length};if let repeats=op.repeatCount{graph.nodes[i].repeatCount=repeats}
                    if let settings=op.settings{graph.nodes[i].settings=settings}
                }
                try SectionGraphEditing.set(graph,useID:id,original:false,in:&p)
            default:throw CirclrError("지원하지 않는 operation: \(op.kind)")
            }
        }
        // An agent's working arrangement must not navigate the musician's current canvas.
        p.activeArrangementID=input.activeArrangementID
        try ProjectStore.validateStructure(p)
        return p
    }
}
