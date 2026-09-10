import Foundation
import AudioToolbox
import CirclrCore

public struct ImportedMIDITrack:Identifiable {
    public var id:String
    public var name:String
    public var channel:Int
    public var notes:[Note]
}
public struct ImportedMIDI {
    public var tracks:[ImportedMIDITrack]
    public var tempo:Double?
    public var ignoredPerformanceEvents:Int
    public var tempoChanges:[TempoChange]=[]
    public var tempoImportIssue:String?=nil
    public init(tracks:[ImportedMIDITrack],tempo:Double?,ignoredPerformanceEvents:Int,
                tempoChanges:[TempoChange]=[],tempoImportIssue:String?=nil) {
        self.tracks=tracks;self.tempo=tempo;self.ignoredPerformanceEvents=ignoredPerformanceEvents
        self.tempoChanges=tempoChanges;self.tempoImportIssue=tempoImportIssue
    }
    public var beats:Double {tracks.flatMap(\.notes).map{$0.beat+$0.length}.max() ?? 0}
}

public enum MIDIImport {
    /// AudioToolbox pairs SMF note-on/off events without opening an audio device.
    /// Only note performances are imported; controller/program/SysEx data is counted for the UI.
    public static func read(_ data:Data)throws->ImportedMIDI {
        try Task.checkCancellation()
        guard (14...16_777_216).contains(data.count),data.prefix(4)==Data("MThd".utf8) else {throw CirclrError("16 MiB 이하의 표준 MIDI 파일을 선택하세요")}
        let h=[UInt8](data.prefix(14)),format=Int(h[8])*256+Int(h[9]),trackCount=Int(h[10])*256+Int(h[11]),division=Int(h[12])*256+Int(h[13])
        guard format==0 || format==1,(1...256).contains(trackCount),division>0,division<0x8000 else {throw CirclrError("현재는 beat 기반 MIDI format 0/1을 지원합니다. SMPTE·format 2는 beat 기반 파일로 저장하세요")}
        func check(_ status:OSStatus)throws {if status != noErr {throw CirclrError("MIDI 파일을 읽지 못했습니다 · \(status)")}}
        var sequence:MusicSequence?
        try check(NewMusicSequence(&sequence));guard let sequence else {throw CirclrError("MIDI sequence 생성 실패")}
        defer {DisposeMusicSequence(sequence)}
        try check(MusicSequenceFileLoadData(sequence,data as CFData,.midiType,MusicSequenceLoadFlags(rawValue:0)))
        var count:UInt32=0;try check(MusicSequenceGetTrackCount(sequence,&count))
        guard count<=256 else {throw CirclrError("MIDI 트랙 수 한도를 넘습니다")}
        var result=ImportedMIDI(tracks:[],tempo:nil,ignoredPerformanceEvents:0),total=0,eventCount=0
        func events(_ track:MusicTrack,_ visit:(MusicTimeStamp,MusicEventType,UnsafeRawPointer,UInt32)throws->Void)throws {
            var iterator:MusicEventIterator?;try check(NewMusicEventIterator(track,&iterator));guard let iterator else{return}
            defer {DisposeMusicEventIterator(iterator)}
            var has=DarwinBoolean(false);try check(MusicEventIteratorHasCurrentEvent(iterator,&has))
            while has.boolValue {
                if eventCount%256==0 {try Task.checkCancellation()}
                eventCount+=1;guard eventCount<=1_000_000 else {throw CirclrError("MIDI 이벤트 수 한도를 넘습니다")}
                var time:MusicTimeStamp=0,type:MusicEventType=0,bytes:UInt32=0;var pointer:UnsafeRawPointer?
                try check(MusicEventIteratorGetEventInfo(iterator,&time,&type,&pointer,&bytes))
                if let pointer {try visit(time,type,pointer,bytes)}
                try check(MusicEventIteratorNextEvent(iterator));try check(MusicEventIteratorHasCurrentEvent(iterator,&has))
            }
        }
        var tempoTrack:MusicTrack?
        try check(MusicSequenceGetTempoTrack(sequence,&tempoTrack))
        if let tempoTrack {try events(tempoTrack){time,type,pointer,bytes in
            if type==kMusicEventType_ExtendedTempo,bytes>=MemoryLayout<ExtendedTempoEvent>.size,time==0 {result.tempo=pointer.loadUnaligned(as:ExtendedTempoEvent.self).bpm}
        }}
        for index in 0..<count {
            var track:MusicTrack?;try check(MusicSequenceGetIndTrack(sequence,index,&track));guard let track else {continue}
            var name="MIDI \(index+1)",channels:[Int:[Note]]=[:]
            try events(track){time,type,pointer,bytes in
                switch type {
                case kMusicEventType_MIDINoteMessage:
                    guard bytes>=MemoryLayout<MIDINoteMessage>.size else {throw CirclrError("MIDI 노트 데이터가 잘렸습니다")}
                    let event=pointer.loadUnaligned(as:MIDINoteMessage.self)
                    let note=Note(beat:time,length:Double(event.duration),pitch:Int(event.note),velocity:Int(event.velocity))
                    try ArrangementCompiler.validateNote(note)
                    guard event.channel<16,note.beat+note.length<=131072 else {throw CirclrError("MIDI 채널 또는 길이 한도를 넘습니다")}
                    total+=1;guard total<=100000 else {throw CirclrError("MIDI 노트 수 한도를 넘습니다")}
                    channels[Int(event.channel),default:[]].append(note)
                case kMusicEventType_Meta:
                    guard bytes>=8 else {throw CirclrError("MIDI metadata가 잘렸습니다")}
                    let kind=pointer.load(as:UInt8.self),length=pointer.advanced(by:4).loadUnaligned(as:UInt32.self)
                    guard length<=bytes-8 else {throw CirclrError("MIDI metadata 길이가 유효하지 않습니다")}
                    if kind==3 {let text=Data(bytes:pointer.advanced(by:8),count:Int(min(1024,length)));if let value=String(data:text,encoding:.utf8),!value.isEmpty {name=value}}
                case kMusicEventType_MIDIChannelMessage,kMusicEventType_MIDIRawData:result.ignoredPerformanceEvents+=1
                default:break
                }
            }
            for channel in channels.keys.sorted() {
                let notes=channels[channel]!.sorted{$0.beat==$1.beat ? $0.pitch<$1.pitch:$0.beat<$1.beat}
                result.tracks.append(ImportedMIDITrack(id:"\(index):\(channel)",name:channels.count>1 ? "\(name) · 채널 \(channel+1)":name,channel:channel,notes:notes))
            }
        }
        guard !result.tracks.isEmpty else {throw CirclrError("가져올 MIDI 노트가 없습니다")}
        do {result.tempoChanges=try readTempoChanges(data)}
        catch is CancellationError {throw CancellationError()}
        catch {result.tempoImportIssue=error.localizedDescription}
        return result
    }
    /// Stable order is track-chunk order, then event order; the last event at a beat wins.
    /// Failure here disables file-tempo application, not otherwise valid note-only import.
    static func readTempoChanges(_ data:Data)throws->[TempoChange] {
        try Task.checkCancellation()
        let bytes=[UInt8](data)
        func failure()->CirclrError {CirclrError("파일 템포 정보를 읽을 수 없습니다. 현재 템포 유지로 노트만 가져올 수 있습니다")}
        func integer(_ offset:Int,_ count:Int)throws->Int {
            guard offset>=0,count<=4,offset<=bytes.count-count else{throw failure()}
            return bytes[offset..<offset+count].reduce(0){($0<<8)|Int($1)}
        }
        guard bytes.count>=14,Array(bytes[0..<4])==Array("MThd".utf8) else{throw failure()}
        let header=try integer(4,4),format=try integer(8,2),trackCount=try integer(10,2),division=try integer(12,2)
        guard header>=6,header<=bytes.count-8,(0...1).contains(format),(1...256).contains(trackCount),division>0,division<0x8000 else{throw failure()}
        var position=8+header,tracks=0,eventCount=0,tempoCount=0
        var tempos:[(tick:Int,bpm:Double,order:Int)]=[]
        while position<bytes.count && tracks<trackCount {
            guard position<=bytes.count-8 else{throw failure()}
            let length=try integer(position+4,4),tag=Array(bytes[position..<position+4]);position+=8
            guard length<=bytes.count-position else{throw failure()}
            let end=position+length
            guard tag==Array("MTrk".utf8) else{position=end;continue}
            tracks+=1
            var tick=0,running:UInt8?=nil
            func variable()throws->Int {
                var value=0
                for _ in 0..<4 {
                    guard position<end else{throw failure()}
                    let byte=bytes[position];position+=1;value=(value<<7)|Int(byte&0x7f)
                    if byte&0x80==0 {return value}
                }
                throw failure()
            }
            while position<end {
                if eventCount%256==0 {try Task.checkCancellation()}
                eventCount+=1;guard eventCount<=1_000_000 else{throw failure()}
                let delta=try variable();let sum=tick.addingReportingOverflow(delta)
                guard !sum.overflow,position<end else{throw failure()};tick=sum.partialValue
                let status:UInt8
                if bytes[position]>=0x80 {status=bytes[position];position+=1}
                else {guard let prior=running else{throw failure()};status=prior}
                if status==0xff {
                    running=nil
                    guard position<end else{throw failure()}
                    let kind=bytes[position];position+=1;let count=try variable()
                    guard count<=end-position else{throw failure()}
                    if kind==0x51 {
                        tempoCount+=1
                        guard tempoCount<=4096,count==3 else{throw failure()}
                        let micros=try integer(position,3)
                        guard micros>0 else{throw failure()}
                        let bpm=60_000_000/Double(micros)
                        guard bpm.isFinite,(1...999).contains(bpm) else {
                            throw CirclrError("파일 템포 적용은 1–999 BPM을 지원합니다. 현재 템포 유지로 노트만 가져올 수 있습니다")
                        }
                        tempos.append((tick,bpm,tempoCount))
                    }
                    position+=count
                    if kind==0x2f {guard count==0,position==end else{throw failure()};break}
                } else if status==0xf0 || status==0xf7 {
                    running=nil;let count=try variable();guard count<=end-position else{throw failure()};position+=count
                } else {
                    guard status>=0x80,status<=0xef else{throw failure()}
                    running=status;let count=(status&0xf0==0xc0 || status&0xf0==0xd0) ? 1:2
                    guard count<=end-position,bytes[position..<position+count].allSatisfy({$0<0x80}) else{throw failure()}
                    position+=count
                }
            }
        }
        guard tracks==trackCount else{throw failure()}
        tempos.sort{$0.tick==$1.tick ? $0.order<$1.order:$0.tick<$1.tick}
        var result:[TempoChange]=[TempoChange(beat:0,bpm:120)]
        for event in tempos {
            let beat=Double(event.tick)/Double(division)
            if result.last?.beat==beat {result[result.count-1]=TempoChange(beat:beat,bpm:event.bpm)}
            else {result.append(TempoChange(beat:beat,bpm:event.bpm))}
        }
        guard result.count<=4096 else{throw failure()}
        return result
    }

}
