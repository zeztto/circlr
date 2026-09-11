import Foundation
import CirclrCore

extension ProductionInstrument {
    /// `notes` contains the complete legacy fan-in in its original order.
    /// Performance notes are a multiset subset, not additional notes to mix.
    public static func synth(_ notes:[Note],patch:SynthPatch,clock:MusicClock,tail:Double,
                             automation:[AutomationPlan] = [],performances:[MIDIPerformanceStream],
                             blockSize:Int = 1024) throws -> PCM {
        try MIDIPitchBendRenderer.render(notes,patch:patch,clock:clock,tail:tail,automation:automation,
                                        performances:performances,blockSize:blockSize)
    }
}

enum MIDIPitchBendRenderer {
    static func hasPitchExpression(_ stream:MIDIPerformanceStream)->Bool {
        stream.hasPitchBendExpression || stream.initialPitchBend.rawValue != 8192 ||
        stream.initialPitchBend.range != MIDIPitchBendRange() || !stream.pitchBendStates.isEmpty
    }
    static func hasActiveSustain(_ stream:MIDIPerformanceStream)->Bool {
        stream.initialSustain.isDown || stream.sustainStates.contains{$0.state.isDown}
    }
    /// Validate every packet before backend selection; all-off packets are effect-free.
    static func validateSustain(_ streams:[MIDIPerformanceStream],supportsSustain:Bool=false)throws {
        var budget=0,ids=Set<ID>()
        for stream in streams {
            try Task.checkCancellation()
            guard stream.notes.count<=500000,stream.pitchBendStates.count<=1_000_000,
                  stream.sustainStates.count<=1_000_000 else {throw CirclrError("서스테인(Sustain) 연주 이벤트 수를 확인하세요")}
            let cost=stream.notes.count*2+stream.pitchBendStates.count+stream.sustainStates.count+1+(hasActiveSustain(stream) ? 2:0)
            guard cost<=1_000_000-budget else {throw CirclrError("서스테인(Sustain)·피치 벤드 연주 이벤트가 너무 많습니다")}
            budget+=cost
            guard !stream.id.isEmpty,!stream.sourceNodeID.isEmpty,ids.insert(stream.id).inserted,
                  (0...15).contains(stream.sourceChannel),stream.startSeconds.isFinite,stream.endSeconds.isFinite,
                  stream.startSeconds>=0,stream.endSeconds>stream.startSeconds,
                  (0...127).contains(stream.initialSustain.rawValue) else {throw CirclrError("서스테인(Sustain) 연주 초기값·시간을 확인하세요")}
            var previous=stream.startSeconds,down=stream.initialSustain.isDown
            for (index,event) in stream.sustainStates.enumerated() {
                if index%256==0 {try Task.checkCancellation()}
                guard event.seconds.isFinite,event.seconds>=previous,event.seconds<stream.endSeconds,
                      (0...127).contains(event.state.rawValue) else {throw CirclrError("서스테인(Sustain) 연주 값·시간순서·범위를 확인하세요")}
                previous=event.seconds;down = down || event.state.isDown
            }
            if down && !supportsSustain {throw CirclrError("서스테인(Sustain)(CC64) 연주는 내장 신스에서만 렌더할 수 있습니다")}
        }
    }
    private struct NoteKey:Hashable {
        let id:ID; let beat:Double; let length:Double; let pitch:Int; let velocity:Int
        init(_ note:Note) {id=note.id;beat=note.beat;length=note.length;pitch=note.pitch;velocity=note.velocity}
    }
    private enum Action {
        case off(stream:UInt64,voice:UInt64,pitch:Int)
        case bend(stream:UInt64,semitones:Double)
        case pedal(stream:UInt64,down:Bool)
        case on(stream:UInt64,voice:UInt64,pitch:Int,velocity:Int)
        var priority:Int {switch self {case .off:return 0;case .bend,.pedal:return 1;case .on:return 2}}
    }
    private struct Event {let frame:Int;let order:Int;let action:Action}

    static func render(_ notes:[Note],patch:SynthPatch,clock:MusicClock,tail:Double,
                       automation:[AutomationPlan],performances:[MIDIPerformanceStream],blockSize:Int) throws -> PCM {
        guard (1...65536).contains(blockSize),notes.count<=500000,performances.count<=1_000_000 else {
            throw CirclrError("신스 연주 event 수·렌더 block 크기를 확인하세요")
        }
        guard patch.engineVersion>=2 || !automation.contains(where:{$0.parameter == .synthResonance}) else {throw CirclrError("Resonance 오토메이션은 내장 신스 engine 2·3에서만 지원합니다")}
        try validateSustain(performances,supportsSustain:true)
        let frames=try ProductionInstrument.frameCount(clock:clock,tail:tail)
        var budget=notes.count*2, available:[NoteKey:Int]=[:]
        for note in notes {
            try ArrangementCompiler.validateNote(note)
            guard (note.beat+note.length).isFinite else {throw CirclrError("MIDI note 종료 위치를 확인하세요")}
            available[NoteKey(note),default:0]+=1
        }
        var identities=Set<ID>(),allCenter=true
        let anyPedal=performances.contains(where:hasActiveSustain)
        var owners:[NoteKey:[UInt64]]=[:]
        func validateState(_ state:MIDIPitchBendState)throws {
            guard (0...16383).contains(state.rawValue) else {throw CirclrError("피치 벤드 raw 값을 확인하세요")}
            try state.range.validate()
        }
        for (streamIndex,stream) in performances.enumerated() {
            try Task.checkCancellation()
            guard !stream.id.isEmpty,!stream.sourceNodeID.isEmpty,identities.insert(stream.id).inserted,
                  (0...15).contains(stream.sourceChannel),stream.startSeconds.isFinite,stream.endSeconds.isFinite,
                  stream.startSeconds>=0,stream.endSeconds>stream.startSeconds,stream.endSeconds<=clock.seconds else {
                throw CirclrError("피치 벤드 연주 출처·시간 범위를 확인하세요")
            }
            guard stream.pitchBendStates.count<=1_000_000-budget-1 else {throw CirclrError("피치 벤드 연주 event가 너무 많습니다")}
            budget+=1+stream.pitchBendStates.count
            guard stream.sustainStates.count<=1_000_000-budget else {throw CirclrError("서스테인(Sustain)·피치 벤드 연주 이벤트가 너무 많습니다")}
            budget+=stream.sustainStates.count
            if hasActiveSustain(stream) {
                guard budget<=999998 else {throw CirclrError("서스테인 종료 이벤트를 포함한 연주 이벤트가 너무 많습니다")}
                budget+=2 // initial pedal and synthetic end release
            }
            try validateState(stream.initialPitchBend)
            allCenter = allCenter && stream.initialPitchBend.semitones == 0
            var previous=stream.startSeconds
            for timed in stream.pitchBendStates {
                guard timed.seconds.isFinite,timed.seconds>=previous,timed.seconds<stream.endSeconds else {throw CirclrError("피치 벤드 상태의 시간순서·범위를 확인하세요")}
                try validateState(timed.state)
                allCenter = allCenter && timed.state.semitones == 0
                previous=timed.seconds
            }
            for note in stream.notes {
                try ArrangementCompiler.validateNote(note)
                let onset=clock.seconds(at:note.beat)
                guard note.beat<clock.beats,onset+1e-9>=stream.startSeconds,onset<stream.endSeconds,(note.beat+note.length).isFinite,
                      let remaining=available[NoteKey(note)],remaining>0 else {
                    throw CirclrError("피치 벤드 연주의 MIDI note 출처·위치를 확인하세요")
                }
                available[NoteKey(note)]=remaining-1
                owners[NoteKey(note),default:[]].append(UInt64(streamIndex+2))
            }
        }
        // This exact old path preserves allocation/order/phase/limiter behavior.
        if allCenter && !anyPedal {return try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:tail,automation:automation,blockSize:blockSize)}
        var events:[Event]=[]
        func append(_ frame:Int,_ action:Action) {events.append(.init(frame:frame,order:events.count,action:action))}
        func frame(_ seconds:Double)throws->Int {
            guard seconds.isFinite,seconds>=0,seconds<=clock.seconds else {throw CirclrError("MIDI event 렌더 시간을 확인하세요")}
            return Int((seconds*PCM.rate).rounded())
        }
        var voice:UInt64=0
        func addNote(_ note:Note,stream:UInt64)throws {
            guard note.beat<clock.beats else{return}
            voice+=1
            let first=try frame(clock.seconds(at:note.beat))
            let last=try frame(clock.seconds(at:min(clock.beats,note.beat+note.length)))
            append(first,.on(stream:stream,voice:voice,pitch:note.pitch,velocity:note.velocity))
            append(max(first+1,last),.off(stream:stream,voice:voice,pitch:note.pitch))
        }
        for (index,stream) in performances.enumerated() {
            try Task.checkCancellation()
            let owner=UInt64(index+2)
            append(try frame(stream.startSeconds),.bend(stream:owner,semitones:stream.initialPitchBend.semitones))
            for (index,state) in stream.pitchBendStates.enumerated() {
                if index%256==0 {try Task.checkCancellation()}
                append(try frame(state.seconds),.bend(stream:owner,semitones:state.state.semitones))
            }
            if hasActiveSustain(stream) {
                append(try frame(stream.startSeconds),.pedal(stream:owner,down:stream.initialSustain.isDown))
                for (index,state) in stream.sustainStates.enumerated() {
                    if index%256==0 {try Task.checkCancellation()}
                    append(try frame(state.seconds),.pedal(stream:owner,down:state.state.isDown))
                }
                // Last among this stream's same-frame controllers. Key-held voices
                // remain alive; only note-offs deferred by this pedal are released.
                append(try frame(stream.endSeconds),.pedal(stream:owner,down:false))
            }
        }
        // Preserve original fan-in note order, including equal-time voice allocation.
        var consumed:[NoteKey:Int]=[:]
        for (noteIndex,note) in notes.enumerated() {
            if noteIndex%256==0 {try Task.checkCancellation()}
            let key=NoteKey(note),index=consumed[key,default:0]
            if let matches=owners[key],index<matches.count {
                try addNote(note,stream:matches[index]);consumed[key]=index+1
            } else {try addNote(note,stream:1)}
        }
        events.sort {
            if $0.frame != $1.frame {return $0.frame<$1.frame}
            if $0.action.priority != $1.action.priority {return $0.action.priority<$1.action.priority}
            return $0.order<$1.order
        }
        let engine=try SynthEngine(patch)
        var result=PCM(frames:frames),cutoff=try SynthCutoffCursor(automation),resonance=try SynthResonanceCursor(automation)
        var cutoffSamples=[Double](repeating:patch.cutoff,count:blockSize)
        var resonanceSamples=[Double](repeating:patch.resonance,count:blockSize)
        var currentBend=[Double](repeating:0,count:performances.count+2)
        var currentPedal=[Bool](repeating:false,count:performances.count+2),cursor=0,index=0
        while cursor<frames {
            try Task.checkCancellation()
            while index<events.count && events[index].frame<=cursor {
                let action=events[index].action
                switch action {
                case .off(let stream,let voice,_):try engine.ownedNoteOffPedal(stream:stream,voice:voice,down:currentPedal[Int(stream)])
                case .bend(let stream,let semitones):
                    currentBend[Int(stream)]=semitones
                    try engine.ownedBend(stream:stream,semitones:semitones)
                case .pedal(let stream,let down):
                    currentPedal[Int(stream)]=down
                    if !down {try engine.ownedSustainRelease(stream:stream)}
                case .on(let stream,let voice,let pitch,let velocity):
                    try engine.ownedNote(stream:stream,voice:voice,pitch:pitch,velocity:velocity,on:true,bend:currentBend[Int(stream)])
                }
                index+=1
            }
            let next=index<events.count ? events[index].frame:frames
            let count=min(blockSize,frames-cursor,max(1,next-cursor))
            if cutoff.active || resonance.active {
                for i in 0..<count {
                    if cutoff.active {cutoffSamples[i]=cutoff.value(at:Double(cursor+i)/PCM.rate)}
                    if resonance.active {resonanceSamples[i]=resonance.value(at:Double(cursor+i)/PCM.rate)}
                }
                cutoffSamples.withUnsafeBufferPointer { values in resonanceSamples.withUnsafeBufferPointer { resonances in
                    result.left.withUnsafeMutableBufferPointer { l in result.right.withUnsafeMutableBufferPointer { r in
                        engine.render(left:l.baseAddress!+cursor,right:r.baseAddress!+cursor,cutoffHz:cutoff.active ? values.baseAddress:nil,resonance:resonance.active ? resonances.baseAddress:nil,frames:UInt32(count))
                    } }
                } }
            } else {
                result.left.withUnsafeMutableBufferPointer { l in result.right.withUnsafeMutableBufferPointer { r in
                    engine.render(left:l.baseAddress!+cursor,right:r.baseAddress!+cursor,frames:UInt32(count))
                } }
            }
            cursor+=count
        }
        return result
    }
}
