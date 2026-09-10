import Foundation

public enum SynthVoice: Int, Codable, CaseIterable {
    case pad, bass, keys, supersaw, pluck, lead, electricPiano, organ, brass, strings
    public var label: String { ["오로라 패드", "펄스 베이스", "글라스 키", "와이드 소우", "아르페지오 플럭", "폴라 리드", "벨벳 EP", "드로바 오르간", "폴리 브라스", "앙상블 스트링"][rawValue] }
}
public struct SynthPatch: Codable, Equatable {
    public var engineVersion: Int = 3
    public var character: Double = 0.6
    public var motion: Double = 0.4
    public var resonance: Double = 0.12
    public var stereoWidth: Double = 0.75
    public var filterEnvelope: Double = 0
    public var voice: SynthVoice
    public var cutoff: Double
    public var attack: Double
    public var decay: Double
    public var sustain: Double
    public var release: Double
    public var detune: Double
    public init(_ voice: SynthVoice = .pad) {
        self.voice = voice; detune = 12; cutoff = 3800
        attack = 0.15; decay = 0.5; sustain = 0.65; release = 0.8
        switch voice {
        case .pad: break
        case .bass: stereoWidth=0; filterEnvelope=1.3; cutoff=650; attack=0.004; decay=0.18; sustain=0.5; release=0.08; detune=3
        case .keys: stereoWidth=0; cutoff=7500; attack=0.003; decay=1.2; sustain=0.16; release=0.25; detune=4
        case .supersaw: cutoff=7000; attack=0.008; decay=0.18; sustain=0.72; release=0.12; detune=21
        case .pluck: filterEnvelope=2.1; cutoff=1800; attack=0.002; decay=0.19; sustain=0.08; release=0.15; detune=7
        case .lead: stereoWidth=0.2; filterEnvelope=0.3; cutoff=3800; attack=0.014; decay=0.22; sustain=0.6; release=0.28; detune=8
        case .electricPiano: cutoff=10000; attack=0.003; decay=2.8; sustain=0.08; release=0.3; detune=0; stereoWidth=0.65; motion=0.55
        case .organ: cutoff=8000; attack=0.007; decay=0.25; sustain=0.85; release=0.09; detune=0; stereoWidth=0.65; motion=0.5
        case .brass: cutoff=2000; attack=0.035; decay=0.45; sustain=0.55; release=0.18; detune=9; resonance=0.22; filterEnvelope=0.5; stereoWidth=0.55
        case .strings: cutoff=5400; attack=0.35; decay=1.2; sustain=0.8; release=0.9; detune=16; stereoWidth=0.95; motion=0.7
        }
    }
    private enum CodingKeys:String,CodingKey {case voice,cutoff,attack,decay,sustain,release,detune,engineVersion,resonance,stereoWidth,filterEnvelope,character,motion}
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        voice=try c.decode(SynthVoice.self,forKey:.voice)
        cutoff=try c.decode(Double.self,forKey:.cutoff);attack=try c.decode(Double.self,forKey:.attack)
        decay=try c.decode(Double.self,forKey:.decay);sustain=try c.decode(Double.self,forKey:.sustain)
        release=try c.decode(Double.self,forKey:.release);detune=try c.decode(Double.self,forKey:.detune)
        engineVersion=try c.decodeIfPresent(Int.self,forKey:.engineVersion) ?? 1
        resonance=try c.decodeIfPresent(Double.self,forKey:.resonance) ?? 0.12
        stereoWidth=try c.decodeIfPresent(Double.self,forKey:.stereoWidth) ?? 0.75
        filterEnvelope=try c.decodeIfPresent(Double.self,forKey:.filterEnvelope) ?? 0
        character=try c.decodeIfPresent(Double.self,forKey:.character) ?? 0.6
        motion=try c.decodeIfPresent(Double.self,forKey:.motion) ?? 0.4
    }
    public func validate() throws {
        guard (1...3).contains(engineVersion),(voice.rawValue<6 || engineVersion==3),
              character.isFinite,(0...1).contains(character),motion.isFinite,(0...1).contains(motion),
              resonance.isFinite,(0...0.9).contains(resonance),
              stereoWidth.isFinite,(0...1).contains(stereoWidth),filterEnvelope.isFinite,(-4...4).contains(filterEnvelope),
              cutoff.isFinite,(40...20000).contains(cutoff), attack.isFinite,(0.001...5).contains(attack),
              decay.isFinite,(0.001...10).contains(decay), sustain.isFinite,(0...1).contains(sustain),
              release.isFinite,(0.005...10).contains(release),detune.isFinite,(0...60).contains(detune)
        else { throw CirclrError("신스의 필터·엔벌로프·디튠 범위를 확인하세요") }
    }
}
public struct SampleInstrument: Codable, Equatable {
    public var assetID: ID
    public var rootPitch: Int = 60
    public var oneShot: Bool = true
    public var zones: [SampleZone]?
    public init(assetID: ID, rootPitch: Int = 60, oneShot: Bool = true) { self.assetID=assetID; self.rootPitch=rootPitch; self.oneShot=oneShot }
}
public struct SampleZone: Codable, Equatable {
    public var pitch:Int
    public var assetID:ID
    public init(_ pitch:Int,assetID:ID){self.pitch=pitch;self.assetID=assetID}
}
public extension Instrument {
    static func synthesizer(_ voice: SynthVoice) -> Instrument {
        var result=Instrument();result.kind = .synthesizer;result.synth=SynthPatch(voice);return result
    }
    static func sampler(assetID: ID, rootPitch: Int = 60) -> Instrument {
        var result=Instrument();result.kind = .sampler;result.sample=SampleInstrument(assetID:assetID,rootPitch:rootPitch);return result
    }
}

public enum MIDIPattern: String, Codable, CaseIterable { case chords, arpeggio, bass, pulse
    public var label:String { switch self {case .chords:return "7th 코드";case .arpeggio:return "아르페지오";case .bass:return "베이스";case .pulse:return "리듬 펄스"} }
}
public enum MIDIGenerator {
    /// A deterministic, scale-aware starting point. Always creates ordinary editable notes.
    public static func notes(pattern: MIDIPattern, context: MusicContext, beats: Double) throws -> [Note] {
        try ContextResolver.validate(context)
        guard beats.isFinite, beats>0,beats<=4096 else {throw CirclrError("MIDI 생성 길이는 1–4096박 안에서 지정하세요")}
        let intervals=context.scale.intervals.sorted(), bar=context.meter.quarters
        guard !intervals.isEmpty else {throw CirclrError("스케일 음이 없습니다")}
        func pitch(_ degree:Int,_ octave:Int)->Int {octave*12+context.scale.root+intervals[degree%intervals.count]+12*(degree/intervals.count)}
        var result:[Note]=[]
        var start=0.0,index=0
        while start<beats {
            let degree=[0,5,3,4][index%4] % intervals.count, length=min(bar,beats-start)
            switch pattern {
            case .chords:
                for offset in [0,2,4,6] {result.append(Note(beat:start,length:length*0.92,pitch:pitch(degree+offset,4),velocity:78))}
            case .arpeggio:
                for step in 0..<Int(ceil(length*2)) {let beat=start+Double(step)*0.5;result.append(Note(beat:beat,length:min(0.34,beats-beat),pitch:pitch(degree+[0,2,4,6,4,2,6,4][step%8],4),velocity:step%4==0 ? 90:72))}
            case .bass:
                for step in 0..<Int(ceil(length)) {let beat=start+Double(step);result.append(Note(beat:beat,length:min(0.72,beats-beat),pitch:pitch(degree,2),velocity:step%2==0 ? 96:82))}
            case .pulse:
                for step in 0..<Int(ceil(length)) {let beat=start+Double(step);result.append(Note(beat:beat,length:min(0.2,beats-beat),pitch:60,velocity:step==0 ? 110:90))}
            }
            start+=bar;index+=1
        }
        return result
    }
}

public enum MIDIFile {
    /// Preserves source expression with independent melodic MIDI channels.
    public static func encode(sources:[(String,Lane)],tempo:Double,meter:Meter,tempoChanges:[TempoChange]=[])throws->Data {
        guard !sources.contains(where:{$0.1.sustain != nil}) else {throw CirclrError("서스테인 MIDI 파일 저장은 아직 지원하지 않습니다. 페달 표현을 보존할 수 없습니다")}
        if tempoChanges.isEmpty && !sources.contains(where:{$0.1.pitchBend != nil}) {
            return try encode(lanes:sources.map{($0.0,$0.1.notes)},tempo:tempo,meter:meter)
        }
        return try MIDIExpressionExport.encode(sources:sources,tempo:tempo,meter:meter,tempoChanges:tempoChanges)
    }
    /// SMF format 1, 960 PPQN. Off events sort before on events at the same tick.
    public static func encode(lanes: [(String,[Note])], tempo: Double, meter: Meter) throws -> Data {
        guard tempo.isFinite,(60_000_000.0/16_777_215...999).contains(tempo),[1,2,4,8,16,32].contains(meter.denominator),(1...32).contains(meter.numerator),lanes.count<256 else {throw CirclrError("MIDI tempo·박자·트랙 수를 확인하세요")}
        func bytes(_ n:Int,_ count:Int)->[UInt8] {(0..<count).reversed().map{UInt8(truncatingIfNeeded:n >> ($0*8))}}
        func variable(_ n:Int)->[UInt8] {var v=n,out=[UInt8(v&127)];v >>= 7;while v>0 {out.insert(UInt8(v&127)|128,at:0);v >>= 7};return out}
        func chunk(_ name:String,_ body:[UInt8])->[UInt8] {Array(name.utf8)+bytes(body.count,4)+body}
        let microseconds=Int((60_000_000/tempo).rounded())
        var data=chunk("MThd",[0,1]+bytes(lanes.count+1,2)+bytes(960,2))
        data+=chunk("MTrk",[0,255,81,3]+bytes(microseconds,3)+[0,255,88,4,UInt8(meter.numerator),UInt8(log2(Double(meter.denominator))),24,8,0,255,47,0])
        for (name,notes) in lanes {
            var events:[(Int,Bool,[UInt8])]=[]
            for note in notes {
                try ArrangementCompiler.validateNote(note)
                guard note.beat+note.length<200000 else {throw CirclrError("MIDI 길이 한도를 넘습니다")}
                events.append((Int((note.beat*960).rounded()),true,[144,UInt8(note.pitch),UInt8(note.velocity)]))
                events.append((max(Int((note.beat*960).rounded())+1,Int(((note.beat+note.length)*960).rounded())),false,[128,UInt8(note.pitch),0]))
            }
            events.sort { $0.0 == $1.0 ? (!$0.1 && $1.1) : $0.0<$1.0 }
            let title=Array(name.utf8.prefix(1024)); var body:[UInt8]=[0,255,3]+variable(title.count)+title,last=0
            for event in events {body+=variable(event.0-last)+event.2;last=event.0}
            body += [0,255,47,0];data+=chunk("MTrk",body)
        }
        return Data(data)
    }
}
