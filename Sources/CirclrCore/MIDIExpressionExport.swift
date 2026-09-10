import Foundation

/// SMF has channel-scoped controllers, not circlr source/voice IDs. Expressive
/// exports reserve channel 9 and allocate every source its own melodic channel.
enum MIDIExpressionExport {
    private struct Event {let tick:Int;let priority:Int;let order:Int;let bytes:[UInt8]}
    static func encode(sources:[(String,Lane)],tempo:Double,meter:Meter,tempoChanges:[TempoChange])throws->Data {
        let expressive=sources.contains{$0.1.pitchBend != nil}
        guard sources.count<256,(!expressive || sources.count<=15),
              [1,2,4,8,16,32].contains(meter.denominator),(1...32).contains(meter.numerator),tempoChanges.count<4096 else {
            throw CirclrError("표현 MIDI는 드럼 채널을 제외한 독립 연주 15개까지 저장합니다. 트랙 수·박자·템포 변화 수를 확인하세요")
        }
        func micros(_ bpm:Double)throws->Int {
            guard bpm.isFinite,(1...999).contains(bpm) else{throw CirclrError("MIDI 템포는 유한한 1–999 BPM이어야 합니다")}
            let value=(60_000_000/bpm).rounded()
            guard (1...16_777_215).contains(value) else{throw CirclrError("MIDI 템포가 24-bit microsecond 범위를 넘습니다")}
            return Int(value)
        }
        func tick(_ beat:Double)throws->Int {
            guard beat.isFinite,(0...131072).contains(beat) else{throw CirclrError("MIDI 위치는 유한한 0–131072박이어야 합니다")}
            return Int((beat*960).rounded())
        }
        func bytes(_ n:Int,_ count:Int)->[UInt8] {(0..<count).reversed().map{UInt8(truncatingIfNeeded:n >> ($0*8))}}
        func variable(_ n:Int)->[UInt8] {var v=n,out=[UInt8(v&127)];v >>= 7;while v>0 {out.insert(UInt8(v&127)|128,at:0);v >>= 7};return out}
        func chunk(_ name:String,_ body:[UInt8])->[UInt8] {Array(name.utf8)+bytes(body.count,4)+body}
        var totalNotes=0,eventCount=0
        func charge(_ count:Int)throws {
            guard count<=1_000_000-eventCount else{throw CirclrError("MIDI 저장 이벤트가 1,000,000개를 넘습니다")}
            eventCount+=count
        }
        let melodic=(0...15).filter{$0 != 9}
        var assigned=[Int?](repeating:nil,count:sources.count),used=Set<Int>()
        if expressive {
            for (index,source) in sources.enumerated() {
                try source.1.pitchBend?.validate()
                if let preferred=source.1.pitchBend?.channel,preferred != 9,used.insert(preferred).inserted {assigned[index]=preferred}
            }
            for index in sources.indices where assigned[index]==nil {
                guard let channel=melodic.first(where:{!used.contains($0)}) else{throw CirclrError("독립 MIDI 채널이 부족합니다")}
                assigned[index]=channel;used.insert(channel)
            }
        }
        var conductor:[Event]=[]
        conductor.append(.init(tick:0,priority:1,order:0,bytes:[255,81,3]+bytes(try micros(tempo),3)))
        conductor.append(.init(tick:0,priority:1,order:1,bytes:[255,88,4,UInt8(meter.numerator),UInt8(log2(Double(meter.denominator))),24,8]))
        var previous=0.0
        for (index,change) in tempoChanges.enumerated() {
            guard change.beat>=previous else{throw CirclrError("MIDI 템포 변화는 시간순이어야 합니다")}
            conductor.append(.init(tick:try tick(change.beat),priority:1,order:index+2,bytes:[255,81,3]+bytes(try micros(change.bpm),3)))
            previous=change.beat
        }
        try charge(conductor.count+1)
        func body(_ events:[Event],name:String?=nil)->[UInt8] {
            let ordered=events.sorted {
                if $0.tick != $1.tick {return $0.tick<$1.tick}
                if $0.priority != $1.priority {return $0.priority<$1.priority}
                return $0.order<$1.order
            }
            var result:[UInt8]=[],last=0
            if let name {
                var title=[UInt8]()
                // Keep each Unicode scalar complete. Byte truncation can make
                // Korean UTF-8 invalid and discard the entire imported name.
                for scalar in name.unicodeScalars {
                    let encoded=Array(String(scalar).utf8)
                    guard title.count+encoded.count<=1024 else{break}
                    title+=encoded
                }
                result=[0,255,3]+variable(title.count)+title
            }
            for event in ordered {result+=variable(event.tick-last)+event.bytes;last=event.tick}
            result += [0,255,47,0]
            return result
        }
        var output=chunk("MThd",[0,1]+bytes(sources.count+1,2)+bytes(960,2))
        output+=chunk("MTrk",body(conductor))
        for (index,source) in sources.enumerated() {
            try Task.checkCancellation()
            let lane=source.1,channel=assigned[index] ?? 0
            guard lane.notes.count<=100000-totalNotes else{throw CirclrError("MIDI 저장 노트가 100,000개를 넘습니다")}
            totalNotes+=lane.notes.count
            var events:[Event]=[]
            func append(_ time:Int,_ priority:Int,_ data:[UInt8])throws {
                try charge(1);events.append(.init(tick:time,priority:priority,order:events.count,bytes:data))
            }
            func range(_ value:MIDIPitchBendRange,at time:Int)throws {
                for (controller,data) in [(101,0),(100,0),(6,value.semitones),(38,value.cents),(101,127),(100,127)] {
                    try append(time,1,[UInt8(0xb0|channel),UInt8(controller),UInt8(data)])
                }
            }
            func wheel(_ value:Int,at time:Int)throws {try append(time,1,[UInt8(0xe0|channel),UInt8(value&127),UInt8(value>>7)])}
            if expressive {
                let bend=lane.pitchBend ?? MIDIPitchBendSequence()
                let decodedCount=bend.events.reduce(3) {count,event in
                    switch event.kind {case .range:return count+2;case .value:return count+1}
                }
                guard decodedCount<=100000 else {throw CirclrError("RPN을 MIDI 메시지로 변환한 피치 벤드 상태가 채널당 100,000개를 넘습니다")}
                try range(bend.initialRange,at:0);try wheel(bend.initialValue,at:0)
                for event in bend.events {
                    let time=try tick(event.beat)
                    switch event.kind {case .value(let value):try wheel(value,at:time);case .range(let value):try range(value,at:time)}
                }
            }
            var noteEnds:[Int:(beat:Double,tick:Int)]=[:]
            let notes=expressive ? lane.notes.enumerated().sorted {
                if $0.element.beat != $1.element.beat {return $0.element.beat<$1.element.beat}
                return $0.offset<$1.offset
            }.map(\.element):lane.notes
            for note in notes {
                try ArrangementCompiler.validateNote(note)
                let first=try tick(note.beat),last=max(first+1,try tick(note.beat+note.length))
                guard last<=131072*960 else{throw CirclrError("MIDI note의 최소 tick 길이가 파일 시간 범위를 넘습니다")}
                if expressive,let prior=noteEnds[note.pitch],note.beat<prior.beat || first<prior.tick {
                    throw CirclrError("\(source.0): 같은 source의 겹치는 pitch \(note.pitch) 노트는 독립 voice ID를 MIDI에 보존할 수 없습니다. 겹침을 정리한 뒤 저장하세요")
                }
                noteEnds[note.pitch]=(note.beat+note.length,last)
                try append(first,2,[UInt8(0x90|channel),UInt8(note.pitch),UInt8(note.velocity)])
                try append(last,0,[UInt8(0x80|channel),UInt8(note.pitch),0])
            }
            try charge(2) // name and end-of-track metadata
            output+=chunk("MTrk",body(events,name:source.0))
            guard output.count<=16_777_216 else{throw CirclrError("MIDI 파일이 16 MiB를 넘습니다")}
        }
        return Data(output)
    }
}
