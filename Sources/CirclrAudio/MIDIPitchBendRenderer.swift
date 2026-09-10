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
    private struct NoteKey:Hashable {
        let id:ID; let beat:Double; let length:Double; let pitch:Int; let velocity:Int
        init(_ note:Note) {id=note.id;beat=note.beat;length=note.length;pitch=note.pitch;velocity=note.velocity}
    }
    private enum Action {
        case off(stream:UInt64,voice:UInt64,pitch:Int)
        case bend(stream:UInt64,semitones:Double)
        case on(stream:UInt64,voice:UInt64,pitch:Int,velocity:Int)
        var priority:Int {switch self {case .off:return 0;case .bend:return 1;case .on:return 2}}
    }
    private struct Event {let frame:Int;let order:Int;let action:Action}

    static func render(_ notes:[Note],patch:SynthPatch,clock:MusicClock,tail:Double,
                       automation:[AutomationPlan],performances:[MIDIPerformanceStream],blockSize:Int) throws -> PCM {
        guard (1...65536).contains(blockSize),notes.count<=500000,performances.count<=1_000_000 else {
            throw CirclrError("신스 연주 event 수·렌더 block 크기를 확인하세요")
        }
        let frames=try ProductionInstrument.frameCount(clock:clock,tail:tail)
        var budget=notes.count*2, available:[NoteKey:Int]=[:]
        for note in notes {
            try ArrangementCompiler.validateNote(note)
            guard (note.beat+note.length).isFinite else {throw CirclrError("MIDI note 종료 위치를 확인하세요")}
            available[NoteKey(note),default:0]+=1
        }
        var identities=Set<ID>(),allCenter=true
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
                guard note.beat<clock.beats,onset+1e-9>=stream.startSeconds,(note.beat+note.length).isFinite,
                      let remaining=available[NoteKey(note)],remaining>0 else {
                    throw CirclrError("피치 벤드 연주의 MIDI note 출처·위치를 확인하세요")
                }
                available[NoteKey(note)]=remaining-1
                owners[NoteKey(note),default:[]].append(UInt64(streamIndex+2))
            }
        }
        // This exact old path preserves allocation/order/phase/limiter behavior.
        if allCenter {return try ProductionInstrument.synth(notes,patch:patch,clock:clock,tail:tail,automation:automation,blockSize:blockSize)}
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
            let owner=UInt64(index+2)
            append(try frame(stream.startSeconds),.bend(stream:owner,semitones:stream.initialPitchBend.semitones))
            for state in stream.pitchBendStates {append(try frame(state.seconds),.bend(stream:owner,semitones:state.state.semitones))}
        }
        // Preserve original fan-in note order, including equal-time voice allocation.
        var consumed:[NoteKey:Int]=[:]
        for note in notes {
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
        var result=PCM(frames:frames),cutoff=try SynthCutoffCursor(automation)
        var cutoffSamples=[Double](repeating:patch.cutoff,count:blockSize)
        var currentBend=[Double](repeating:0,count:performances.count+2),cursor=0,index=0
        while cursor<frames {
            try Task.checkCancellation()
            while index<events.count && events[index].frame<=cursor {
                let action=events[index].action
                switch action {
                case .off(let stream,let voice,let pitch):try engine.ownedNote(stream:stream,voice:voice,pitch:pitch,velocity:0,on:false,bend:0)
                case .bend(let stream,let semitones):
                    currentBend[Int(stream)]=semitones
                    try engine.ownedBend(stream:stream,semitones:semitones)
                case .on(let stream,let voice,let pitch,let velocity):
                    try engine.ownedNote(stream:stream,voice:voice,pitch:pitch,velocity:velocity,on:true,bend:currentBend[Int(stream)])
                }
                index+=1
            }
            let next=index<events.count ? events[index].frame:frames
            let count=min(blockSize,frames-cursor,max(1,next-cursor))
            if cutoff.active {
                for i in 0..<count {cutoffSamples[i]=cutoff.value(at:Double(cursor+i)/PCM.rate)}
                cutoffSamples.withUnsafeBufferPointer { values in
                    result.left.withUnsafeMutableBufferPointer { l in result.right.withUnsafeMutableBufferPointer { r in
                        engine.render(left:l.baseAddress!+cursor,right:r.baseAddress!+cursor,cutoffHz:values.baseAddress!,frames:UInt32(count))
                    } }
                }
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
