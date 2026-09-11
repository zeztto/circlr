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
    public var soundTarget:String?
    public var query:String?
    public var category:String?
    public var bankDrums:Bool?
    public var offset:Int?
    public var limit:Int?
    public var catalogID:String?
    public var node:CircleAddress?
    public var first:CirclePortEndpoint?
    public var second:CirclePortEndpoint?
    public var firstOctant:PortOctant?
    public var secondOctant:PortOctant?
    public var connectionID:CircleConnectionID?
    public var moves:[PlacedCircleConnection]?
    public var expectedLayoutRevision:Int?
    public var target:CirclePortEndpoint?
    public var portID:String?
    public var name:String?
    public var operations:[AgentOperation]?
    public var arrangementID:ID?
    public var useID:ID?
    public var trackID:ID?
    public var tailSeconds:Double?
    public var nodeID:ID?
    public var jobID:ID?
    public var path:String?
    public var trackIDs:[String]?
    public var atBeat:Double?
    public var extendSection:Bool?
    public var tempoPolicy:MIDIImportTempoPolicy?
    public var expressionPolicy:MIDIImportExpressionPolicy?
    public var previewOnly:Bool?
    public var afterSequence:Int?
    public var detail:Bool?
    public var minimized:Bool?
    public var follow:Bool?
    public var followSettings:PlaybackFollowSettings?
    public var viewingMode:Bool?
    public var loopMode:PlaybackLoopMode?
    public var compositionID:ID?
    public init(){}
}
public struct AgentOperation:Codable {
    public var kind:String
    public var at:Point?
    public var compositionID:ID?
    public var arrangementID:ID?
    public var useID:ID?
    public var laneID:ID?
    public var nodeID:ID?
    public var trackID:ID?
    public var name:String?
    public var notes:[Note]?
    public var pattern:MIDIPattern?
    public var patternID:ID?
    public var original:Bool?
    public var change:AgentPitchBendChange?
    public var sustainChange:AgentSustainChange?
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
    public var velocityOffset:Int?
    public var semitones:Int?
    public var beatOffset:Double?
    public var strength:Double?
    public var clipID:ID?
    public var sourceStart:Double?
    public var duration:Double?
    public var sourceOffset:Double?
    public var fadeIn:Double?
    public var fadeOut:Double?
    public var parameter:AutomationParameter?
    public var automationPoints:[AutomationPoint]?
    public init(_ kind:String){self.kind=kind}

    private enum CodingKeys:String,CodingKey {case kind,at,compositionID,arrangementID,useID,laneID,nodeID,trackID,name,notes,pattern,patternID,original,change,sustainChange,append,instrument,synthVoice,effect,context,settings,gain,muted,startBeat,lengthBeats,repeatCount,from,to,sidechain,bars,stepIndex,subdivisions,pitch,velocity,gate,enabled,noteIDs,edit,velocityOffset,semitones,beatOffset,strength,clipID,sourceStart,duration,sourceOffset,fadeIn,fadeOut,parameter,automationPoints}
    private struct RawKey:CodingKey {var stringValue:String;var intValue:Int?{nil};init?(stringValue:String){self.stringValue=stringValue};init?(intValue:Int){return nil}}
    public init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        kind=try c.decode(String.self,forKey:.kind)
        if kind=="edit_sustain" {
            let raw=try decoder.container(keyedBy:RawKey.self)
            let allowed:Set<String>=["kind","arrangementID","useID","laneID","original","patternID","trackID","sustainChange"]
            guard try raw.allKeys.allSatisfy({key in guard allowed.contains(key.stringValue) else{return false};return try !raw.decodeNil(forKey:key)}) else {throw CirclrError("edit_sustain 필드와 null 여부를 확인하세요")}
        }
        at=try c.decodeIfPresent(Point.self,forKey:.at)
        compositionID=try c.decodeIfPresent(ID.self,forKey:.compositionID)
        arrangementID=try c.decodeIfPresent(ID.self,forKey:.arrangementID)
        useID=try c.decodeIfPresent(ID.self,forKey:.useID)
        laneID=try c.decodeIfPresent(ID.self,forKey:.laneID)
        nodeID=try c.decodeIfPresent(ID.self,forKey:.nodeID)
        trackID=try c.decodeIfPresent(ID.self,forKey:.trackID)
        name=try c.decodeIfPresent(String.self,forKey:.name)
        notes=try c.decodeIfPresent([Note].self,forKey:.notes)
        pattern=try c.decodeIfPresent(MIDIPattern.self,forKey:.pattern)
        patternID=try c.decodeIfPresent(ID.self,forKey:.patternID)
        original=try c.decodeIfPresent(Bool.self,forKey:.original)
        change=try c.decodeIfPresent(AgentPitchBendChange.self,forKey:.change)
        sustainChange=try c.decodeIfPresent(AgentSustainChange.self,forKey:.sustainChange)
        append=try c.decodeIfPresent(Bool.self,forKey:.append)
        instrument=try c.decodeIfPresent(Instrument.self,forKey:.instrument)
        synthVoice=try c.decodeIfPresent(SynthVoice.self,forKey:.synthVoice)
        effect=try c.decodeIfPresent(Effect.self,forKey:.effect)
        context=try c.decodeIfPresent(MusicContext.self,forKey:.context)
        settings=try c.decodeIfPresent(ContextSettings.self,forKey:.settings)
        gain=try c.decodeIfPresent(Double.self,forKey:.gain)
        muted=try c.decodeIfPresent(Bool.self,forKey:.muted)
        startBeat=try c.decodeIfPresent(Double.self,forKey:.startBeat)
        lengthBeats=try c.decodeIfPresent(Double.self,forKey:.lengthBeats)
        repeatCount=try c.decodeIfPresent(Int.self,forKey:.repeatCount)
        from=try c.decodeIfPresent(ID.self,forKey:.from)
        to=try c.decodeIfPresent(ID.self,forKey:.to)
        sidechain=try c.decodeIfPresent(Bool.self,forKey:.sidechain)
        bars=try c.decodeIfPresent(Int.self,forKey:.bars)
        stepIndex=try c.decodeIfPresent(Int.self,forKey:.stepIndex)
        subdivisions=try c.decodeIfPresent(Int.self,forKey:.subdivisions)
        pitch=try c.decodeIfPresent(Int.self,forKey:.pitch)
        velocity=try c.decodeIfPresent(Int.self,forKey:.velocity)
        gate=try c.decodeIfPresent(Double.self,forKey:.gate)
        enabled=try c.decodeIfPresent(Bool.self,forKey:.enabled)
        noteIDs=try c.decodeIfPresent([ID].self,forKey:.noteIDs)
        edit=try c.decodeIfPresent(String.self,forKey:.edit)
        velocityOffset=try c.decodeIfPresent(Int.self,forKey:.velocityOffset)
        semitones=try c.decodeIfPresent(Int.self,forKey:.semitones)
        beatOffset=try c.decodeIfPresent(Double.self,forKey:.beatOffset)
        strength=try c.decodeIfPresent(Double.self,forKey:.strength)
        clipID=try c.decodeIfPresent(ID.self,forKey:.clipID)
        sourceStart=try c.decodeIfPresent(Double.self,forKey:.sourceStart)
        duration=try c.decodeIfPresent(Double.self,forKey:.duration)
        sourceOffset=try c.decodeIfPresent(Double.self,forKey:.sourceOffset)
        fadeIn=try c.decodeIfPresent(Double.self,forKey:.fadeIn)
        fadeOut=try c.decodeIfPresent(Double.self,forKey:.fadeOut)
        parameter=try c.decodeIfPresent(AutomationParameter.self,forKey:.parameter)
        automationPoints=try c.decodeIfPresent([AutomationPoint].self,forKey:.automationPoints)
    }


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
        var explicitSelection:ID?
        for op in operations {
            guard op.original==nil || ["set_automation","edit_pitch_bend","edit_sustain"].contains(op.kind) else{throw CirclrError("original은 set_automation·edit_pitch_bend에만 지정할 수 있습니다")}
            guard op.patternID==nil || ["edit_shared_audio","edit_pitch_bend","edit_sustain"].contains(op.kind) else{throw CirclrError("patternID는 edit_shared_audio·edit_pitch_bend에만 지정할 수 있습니다")}
            guard op.change==nil || op.kind=="edit_pitch_bend" else{throw CirclrError("change는 edit_pitch_bend에만 지정하세요")}
            guard op.sustainChange==nil || op.kind=="edit_sustain" else{throw CirclrError("sustainChange는 edit_sustain에만 지정하세요")}
            if op.kind=="edit_shared_audio" {
                guard op.arrangementID==nil,op.useID==nil,op.nodeID==nil,op.laneID==nil,op.compositionID==nil else{throw CirclrError("공유 오디오에는 patternID·trackID·clipID만 대상으로 지정하세요")}
            }
            p.activeArrangementID=input.activeArrangementID
            if let ai=op.arrangementID {guard p.arrangements.contains(where:{$0.id==ai}) else {throw CirclrError("편곡 ID를 찾을 수 없습니다")};p.activeArrangementID=ai}
            switch op.kind {
            case "edit_sustain":try AgentSustainEditing.apply(op,in:&p)
            case "edit_pitch_bend":try AgentPitchBendEditing.apply(op,in:&p)
            case "duplicate_arrangement", "rename_arrangement":
                guard let compositionID=op.compositionID,let arrangementID=op.arrangementID,let name=op.name else {
                    throw CirclrError("compositionID, arrangementID, name이 필요합니다")
                }
                if op.kind == "duplicate_arrangement" {
                    let previousSelection=p.album?.composition(compositionID)?.selectedArrangementID
                    try ArrangementSelection.duplicate(arrangementID,compositionID:compositionID,name:name,in:&p)
                    // Background copies must preserve the playback choice too: hierarchy
                    // normalization follows that choice and would otherwise close editors.
                    if let ownerIndex=p.album?.compositions.firstIndex(where:{$0.id==compositionID}) {
                        p.album?.compositions[ownerIndex].selectedArrangementID=previousSelection
                    }
                } else {
                    try ArrangementSelection.rename(arrangementID,compositionID:compositionID,name:name,in:&p)
                }
            case "select_arrangement":
                guard let compositionID=op.compositionID,let arrangementID=op.arrangementID else {
                    throw CirclrError("compositionID, arrangementID가 필요합니다")
                }
                try ArrangementSelection.select(arrangementID,compositionID:compositionID,in:&p)
                explicitSelection=arrangementID
            case "set_use_length_override","clear_use_length_override":
                let encoded=try JSONEncoder().encode(op)
                let fields=try JSONSerialization.jsonObject(with:encoded) as? [String:Any] ?? [:]
                let expected:Set<String>=op.kind=="set_use_length_override" ? ["kind","arrangementID","useID","bars"]:["kind","arrangementID","useID"]
                guard Set(fields.keys)==expected,let arrangementID=op.arrangementID,let useID=op.useID else {
                    throw CirclrError("섹션 길이 operation에는 arrangementID·useID와 해당 종류의 필드만 지정하세요")
                }
                _ = try SectionLengthEditing.set(bars:op.bars,arrangementID:arrangementID,useID:useID,in:&p)
            case "clear_use_tempo_override":
                guard op.arrangementID != nil,let useID=op.useID else{throw CirclrError("arrangementID·useID가 필요합니다")}
                try UseTempoOverrideEditing.clear(useID:useID,in:&p)
            case "set_global":guard let context=op.context else {throw CirclrError("context가 필요합니다")};p.global=context
            case "rename_project":guard let name=op.name,!name.isEmpty,name.count<=256 else {throw CirclrError("name이 필요합니다")};p.name=name
            case "set_instrument":
                guard let id=op.trackID,let instrument=op.synthVoice.map({Instrument.synthesizer($0)}) ?? op.instrument,let i=p.tracks.firstIndex(where:{$0.id==id}) else {throw CirclrError("trackID와 instrument 또는 synthVoice가 필요합니다")};p.tracks[i].instrument=instrument
            case "set_track":
                guard let id=op.trackID,let i=p.tracks.firstIndex(where:{$0.id==id}) else {throw CirclrError("trackID가 필요합니다")}
                if let gain=op.gain{p.tracks[i].gain=gain};if let muted=op.muted{p.tracks[i].muted=muted};if let name=op.name{p.tracks[i].name=name}
            case "insert_section":
                guard let arrangementID=op.arrangementID,let useID=op.useID,let name=op.name,let bars=op.bars,let at=op.at else {
                    throw CirclrError("insert_section에는 arrangementID, useID, name, bars, at이 필요합니다")
                }
                try SectionInsertion.insert(arrangementID:arrangementID,afterUseID:useID,name:name,bars:bars,at:at,in:&p)
            case "add_section":
                guard let name=op.name,!name.isEmpty else {throw CirclrError("name이 필요합니다")}
                _=p.addSection(name:name,at:Point(Double(p.active.uses.count)*1000,0),bars:op.bars ?? 8);p=try SectionGraphMigration.migrate(p)
            case "connect_sections":
                guard let from=op.from,let to=op.to else {throw CirclrError("from과 to가 필요합니다")};try ProjectEditing.connect(from:from,to:to,in:&p)
            case "reorder_section":
                guard let id=op.useID else {throw CirclrError("useID가 필요합니다")}
                try OrbitEditing.reorderSection(.section(arrangementID:p.activeArrangementID,useID:id),before:op.to,in:&p)
            case "edit_audio":
                guard let id=op.useID,let nodeID=op.nodeID else{throw CirclrError("useID와 audio nodeID가 필요합니다")}
                let change:AudioEditing.Change
                switch op.edit {
                case "split":guard let offset=op.sourceOffset else{throw CirclrError("원본 초 단위 sourceOffset이 필요합니다")};change = .split(sourceOffset:offset)
                case "duplicate":change = .duplicate(beatOffset:op.beatOffset)
                case "fade":guard let input=op.fadeIn,let output=op.fadeOut else{throw CirclrError("원본 초 단위 fadeIn과 fadeOut이 필요합니다")};change = .fade(input:input,output:output)
                case "delete":change = .delete
                default:throw CirclrError("edit: split/duplicate/fade/delete를 선택하세요")
                }
                _=try AudioEditing.apply(change,nodeID:nodeID,useID:id,in:&p)
            case "edit_shared_audio":
                guard let pattern=op.patternID,let track=op.trackID,let clip=op.clipID else{throw CirclrError("patternID·trackID·clipID가 필요합니다")}
                let change:AudioEditing.Change
                switch op.edit {
                case "split":guard let offset=op.sourceOffset else{throw CirclrError("원본 초 단위 sourceOffset이 필요합니다")};change = .split(sourceOffset:offset)
                case "duplicate":change = .duplicate(beatOffset:op.beatOffset)
                case "fade":guard let input=op.fadeIn,let output=op.fadeOut else{throw CirclrError("원본 초 단위 fadeIn과 fadeOut이 필요합니다")};change = .fade(input:input,output:output)
                case "delete":change = .delete
                default:throw CirclrError("edit: split/duplicate/fade/delete를 선택하세요")
                }
                _=try SharedRhythmAudioEditing.apply(change,patternID:pattern,trackID:track,clipID:clip,in:&p)
            case "set_automation":
                guard let id=op.useID,let node=op.nodeID,let parameter=op.parameter else{throw CirclrError("useID·nodeID·parameter가 필요합니다")}
                try AutomationEditing.set(parameter:parameter,points:op.automationPoints,enabled:op.enabled,nodeID:node,useID:id,original:op.original ?? false,in:&p)
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
                try clip.validateEditing(asset:asset)
                try ProjectEditing.setLane(lane,for:id,original:false,in:&p)
            case "set_section":
                guard let id=op.useID,let i=p.arrangements[p.activeIndex].uses.firstIndex(where:{$0.id==id}) else {throw CirclrError("useID가 필요합니다")}
                if let name=op.name{p.arrangements[p.activeIndex].uses[i].name=name}
                if let bars=op.bars {p.arrangements[p.activeIndex].uses[i].barsOverride=bars}
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
                case "length_delta":guard let value=op.beatOffset else{throw CirclrError("beatOffset이 필요합니다")};change = .lengthDelta(value)
                case "velocity_delta":guard let value=op.velocityOffset else{throw CirclrError("velocityOffset이 필요합니다")};change = .velocityDelta(value)
                case "velocity":guard let value=op.velocity else{throw CirclrError("velocity가 필요합니다")};change = .velocity(value)
                case "delete":change = .delete
                default:throw CirclrError("edit: transpose/move/duplicate/quantize/velocity/length_delta/velocity_delta/delete를 선택하세요")
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
                    try SectionGraphEditing.insertEffect(node,from:from,in:&graph)
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
        // Only an explicit selection may navigate the musician's current canvas.
        p.activeArrangementID=explicitSelection ?? input.activeArrangementID
        try UseTempoOverrideEditing.validateChanges(from:input,to:p)
        try ProjectStore.validateStructure(p)
        return p
    }
}
