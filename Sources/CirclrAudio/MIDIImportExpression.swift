import Foundation
import CirclrCore

public struct MIDIImportExpressionIssue:Codable,Equatable {
    public var channel:Int?
    public var beat:Double?
    public var code:String
    public var message:String
    public init(channel:Int?=nil,beat:Double?=nil,code:String,message:String) {
        self.channel=channel;self.beat=beat;self.code=code;self.message=message
    }
}

extension ImportedMIDI {
    public func issues(selectedIDs:Set<String>)->[MIDIImportExpressionIssue] {
        let selected=tracks.filter{selectedIDs.contains($0.id)},channels=Set(selected.map(\.channel))
        var result=expressionIssues.filter{$0.channel == nil || channels.contains($0.channel!)}
        if selected.contains(where:{$0.channel==9 && ($0.pitchBend != nil || $0.sustain != nil)}) {
            result.append(.init(channel:9,code:"drum_backend_unsupported",message:"드럼 채널의 피치 벤드·sustain 연주는 아직 지원하지 않습니다. 표현 제외를 선택하면 노트만 가져옵니다"))
        }
        return result
    }
    public func importParts(selectedIDs:Set<String>,expressionPolicy:MIDIImportExpressionPolicy = .preserve)throws->[MIDIImportPart] {
        guard !selectedIDs.isEmpty,selectedIDs.isSubset(of:Set(tracks.map(\.id))) else {throw CirclrError("가져올 MIDI 트랙을 다시 선택하세요")}
        if expressionPolicy == .preserve,let issue=issues(selectedIDs:selectedIDs).first {throw CirclrError(issue.message)}
        return tracks.filter{selectedIDs.contains($0.id)}.map {
            MIDIImportPart(name:$0.name,notes:$0.notes,drums:$0.channel==9,pitchBend:expressionPolicy == .preserve ? $0.pitchBend:nil,sustain:expressionPolicy == .preserve ? $0.sustain:nil)
        }
    }
}

/// Controller state is merged across all raw tracks by (tick, track, ordinal).
/// AudioToolbox's track numbering is irrelevant: its notes retain MIDI channel.
struct MIDIExpressionScan {
    var sequences:[Int:MIDIPitchBendSequence]=[:]
    var sustains:[Int:MIDISustainSequence]=[:]
    var issues:[MIDIImportExpressionIssue]=[]
    var ignoredEvents=0
    private struct Raw {let tick:Int;let order:Int;let status:UInt8;let a:Int;let b:Int}
    private struct Channel {
        var rpnMSB=127,rpnLSB=127,nrpn=false
        var range=MIDIPitchBendRange()
        var hasExplicitExpression=false
        var hasExplicitSustain=false
        var sustainEvents:[MIDISustainEvent]=[]
        var events:[MIDIPitchBendEvent]=[]
        var selectors:[Int]=[]
    }
    static func read(_ data:Data)throws->MIDIExpressionScan {
        try Task.checkCancellation()
        let bytes=[UInt8](data)
        func invalid()->CirclrError {CirclrError("MIDI 표현 데이터의 길이·상태를 확인할 수 없습니다. 표현 제외를 선택하면 노트만 가져옵니다")}
        func integer(_ offset:Int,_ count:Int)throws->Int {
            guard offset>=0,count<=4,offset<=bytes.count-count else{throw invalid()}
            return bytes[offset..<offset+count].reduce(0){($0<<8)|Int($1)}
        }
        guard bytes.count>=14 else{throw invalid()}
        let header=try integer(4,4),tracks=try integer(10,2),division=try integer(12,2)
        guard header>=6,header<=bytes.count-8,(1...256).contains(tracks),division>0,division<0x8000 else{throw invalid()}
        var cursor=header+8,found=0,count=0,raw:[Raw]=[],result=MIDIExpressionScan()
        while cursor<bytes.count && found<tracks {
            guard cursor<=bytes.count-8 else{throw invalid()}
            let tag=Array(bytes[cursor..<cursor+4]),length=try integer(cursor+4,4);cursor+=8
            guard length<=bytes.count-cursor else{throw invalid()}
            let end=cursor+length
            guard tag==Array("MTrk".utf8) else{cursor=end;continue}
            found+=1
            var tick=0,running:UInt8?=nil
            func variable()throws->Int {
                var value=0
                for _ in 0..<4 {
                    guard cursor<end else{throw invalid()}
                    let byte=bytes[cursor];cursor+=1;value=(value<<7)|Int(byte&127)
                    if byte&128==0{return value}
                }
                throw invalid()
            }
            while cursor<end {
                if count%256==0 {try Task.checkCancellation()}
                count+=1;guard count<=1_000_000 else{throw invalid()}
                let delta=try variable(),next=tick.addingReportingOverflow(delta)
                guard !next.overflow,cursor<end else{throw invalid()};tick=next.partialValue
                let status:UInt8
                if bytes[cursor]>=128 {status=bytes[cursor];cursor+=1} else {guard let prior=running else{throw invalid()};status=prior}
                if status==0xff {
                    running=nil
                    guard cursor<end else{throw invalid()}
                    let kind=bytes[cursor];cursor+=1
                    let length=try variable();guard length<=end-cursor else{throw invalid()};cursor+=length
                    if kind==0x2f {guard length==0,cursor==end else{throw invalid()};break}
                } else if status==0xf0 || status==0xf7 {
                    running=nil
                    let length=try variable();guard length<=end-cursor else{throw invalid()};cursor+=length
                    raw.append(.init(tick:tick,order:count,status:status,a:0,b:0))
                } else {
                    guard status>=0x80,status<=0xef else{throw invalid()};running=status
                    let length=(status&0xf0==0xc0 || status&0xf0==0xd0) ? 1:2
                    guard length<=end-cursor,bytes[cursor..<cursor+length].allSatisfy({$0<128}) else{throw invalid()}
                    let a=Int(bytes[cursor]),b=length==2 ? Int(bytes[cursor+1]):0;cursor+=length
                    if status&0xf0 != 0x80 && status&0xf0 != 0x90 {raw.append(.init(tick:tick,order:count,status:status,a:a,b:b))}
                }
            }
        }
        guard found==tracks else{throw invalid()}
        raw.sort{$0.tick == $1.tick ? $0.order<$1.order:$0.tick<$1.tick}
        var channels=[Channel](repeating:Channel(),count:16),consumed=Set<Int>(),issueKeys=Set<String>()
        func issue(_ event:Raw,_ channel:Int?,_ code:String,_ message:String) {
            // One actionable diagnostic per channel/type avoids huge preview payloads.
            let key="\(channel ?? -1):\(code)"
            if issueKeys.insert(key).inserted {result.issues.append(.init(channel:channel,beat:Double(event.tick)/Double(division),code:code,message:message))}
        }
        for (index,event) in raw.enumerated() {
            if index%256==0 {try Task.checkCancellation()}
            let beat=Double(event.tick)/Double(division)
            if event.status>=0xf0 {
                issue(event,nil,"sysex_unsupported","SysEx가 음정·초기 상태를 변경할 수 있어 표현을 보존할 수 없습니다. 표현 제외를 선택하세요")
                continue
            }
            let ch=Int(event.status&15),kind=event.status&0xf0
            if kind==0xe0 {
                guard beat<=131072,channels[ch].events.count<100000 else{throw invalid()}
                channels[ch].events.append(.init(beat:beat,kind:.value(event.a|(event.b<<7))))
                channels[ch].hasExplicitExpression=true
                consumed.insert(event.order)
            } else if kind==0xb0 {
                switch event.a {
                case 64:
                    guard beat<=131072,channels[ch].sustainEvents.count<100000 else{throw invalid()}
                    channels[ch].sustainEvents.append(.init(beat:beat,rawValue:event.b))
                    channels[ch].hasExplicitSustain=true
                    consumed.insert(event.order)
                case 101,100:
                    channels[ch].nrpn=false
                    if event.a==101 {channels[ch].rpnMSB=event.b} else{channels[ch].rpnLSB=event.b}
                    channels[ch].selectors.append(event.order)
                    if channels[ch].rpnMSB==127 && channels[ch].rpnLSB==127 {
                        consumed.formUnion(channels[ch].selectors);channels[ch].selectors=[]
                    }
                case 99,98:
                    channels[ch].nrpn=true;channels[ch].selectors=[]
                case 6,38,96,97:
                    let state=channels[ch]
                    if state.nrpn {
                        issue(event,ch,"nrpn_unsupported","NRPN 연주 설정은 아직 보존할 수 없습니다. 표현 제외를 선택하세요")
                    } else if state.rpnMSB==127 && state.rpnLSB==127 {
                        // Null RPN selection: data entry has no selected parameter.
                        consumed.insert(event.order)
                    } else if event.a==96 || event.a==97 {
                        issue(event,state.rpnMSB==0 && state.rpnLSB==6 ? nil:ch,"rpn_increment_unsupported","RPN 증감 연주 설정은 아직 보존할 수 없습니다. 표현 제외를 선택하세요")
                    } else if state.rpnMSB==0 && state.rpnLSB==0 {
                        guard beat<=131072,channels[ch].events.count<100000 else{throw invalid()}
                        if event.a==6 {channels[ch].range.semitones=event.b} else{channels[ch].range.cents=event.b}
                        channels[ch].events.append(.init(beat:beat,kind:.range(channels[ch].range)))
                        channels[ch].hasExplicitExpression=true
                        consumed.insert(event.order);consumed.formUnion(channels[ch].selectors);channels[ch].selectors=[]
                    } else {
                        let mpe=state.rpnMSB==0 && state.rpnLSB==6
                        issue(event,mpe ? nil:ch,mpe ? "mpe_unsupported":"rpn_unsupported",mpe ? "MPE 연주는 아직 보존할 수 없습니다. 표현 제외를 선택하세요":"이 RPN 연주 설정은 아직 보존할 수 없습니다. 표현 제외를 선택하세요")
                    }
                case 121:
                    if event.b==0 {
                        guard beat<=131072,channels[ch].events.count<100000,channels[ch].sustainEvents.count<100000 else{throw invalid()}
                        channels[ch].sustainEvents.append(.init(beat:beat,rawValue:0))
                        // Reset wheel and parameter selection, retaining sensitivity.
                        channels[ch].events.append(.init(beat:beat,kind:.value(8192)))
                        channels[ch].rpnMSB=127;channels[ch].rpnLSB=127;channels[ch].nrpn=false
                        channels[ch].selectors=[]
                        consumed.insert(event.order)
                    } else {
                        issue(event,ch,"controller_reset_unsupported","이 Controller 초기화 값의 연주 상태를 보존할 수 없습니다. 표현 제외를 선택하세요")
                    }
                default:break
                }
            }
        }
        // A reset-only file has no pitch expression to import. This keeps ordinary
        // drum reset messages on the existing notes-only path. If an explicit
        // bend/range exists anywhere, earlier resets remain in the full sequence.
        for ch in channels.indices where channels[ch].hasExplicitExpression {
            let sequence=MIDIPitchBendSequence(channel:ch,events:channels[ch].events)
            try sequence.validate();result.sequences[ch]=sequence
        }
        for ch in channels.indices where channels[ch].hasExplicitSustain {
            let sequence=MIDISustainSequence(channel:ch,events:channels[ch].sustainEvents)
            try sequence.validate();result.sustains[ch]=sequence
        }
        result.ignoredEvents=raw.count-consumed.count
        return result
    }
}
