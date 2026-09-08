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
    public var beats:Double {tracks.flatMap(\.notes).map{$0.beat+$0.length}.max() ?? 0}
}

public enum MIDIImport {
    /// AudioToolbox pairs SMF note-on/off events without opening an audio device.
    /// Only note performances are imported; controller/program/SysEx data is counted for the UI.
    public static func read(_ data:Data)throws->ImportedMIDI {
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
        return result
    }
}
