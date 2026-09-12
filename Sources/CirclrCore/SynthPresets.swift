import Foundation

/// Factory values are copied only on explicit selection; no preset identifier is serialized.
public struct SynthPreset: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let detail: String
    public let patch: SynthPatch

    private init(_ id:String,_ name:String,_ detail:String,_ voice:SynthVoice,
                 cutoff:Double,attack:Double,decay:Double,sustain:Double,release:Double,
                 detune:Double,character:Double,motion:Double,resonance:Double,width:Double,envelope:Double) {
        self.id=id;self.name=name;self.detail=detail
        var p=SynthPatch(voice);p.engineVersion=3
        p.cutoff=cutoff;p.attack=attack;p.decay=decay;p.sustain=sustain;p.release=release
        p.detune=detune;p.character=character;p.motion=motion;p.resonance=resonance
        p.stereoWidth=width;p.filterEnvelope=envelope;self.patch=p
    }

    public static let factory:[SynthPreset] = [
        .init("warm-pad","따뜻한 패드","느린 어택 · 넓은 코드",.pad,
              cutoff:2800,attack:0.42,decay:1.1,sustain:0.72,release:1.5,detune:11,character:0.35,motion:0.3,resonance:0.1,width:0.85,envelope:0.2),
        .init("round-bass","둥근 베이스","짧은 저음 · 모노 중심",.bass,
              cutoff:520,attack:0.004,decay:0.2,sustain:0.5,release:0.08,detune:0,character:0.3,motion:0.08,resonance:0.13,width:0,envelope:1.2),
        .init("glass-keys","유리 건반","맑은 어택 · 짧은 잔향",.keys,
              cutoff:8200,attack:0.003,decay:1.1,sustain:0.12,release:0.24,detune:2,character:0.72,motion:0.12,resonance:0.06,width:0.25,envelope:0),
        .init("wide-chorus","넓은 후렴","밝은 화음 · 넓은 스테레오",.supersaw,
              cutoff:7600,attack:0.012,decay:0.26,sustain:0.7,release:0.22,detune:23,character:0.75,motion:0.32,resonance:0.12,width:0.95,envelope:0.25),
        .init("soft-saw","부드러운 소우","닫힌 필터 · 긴 화음",.supersaw,
              cutoff:2400,attack:0.16,decay:0.7,sustain:0.6,release:0.65,detune:13,character:0.25,motion:0.18,resonance:0.08,width:0.7,envelope:0.1),
        .init("crisp-pluck","또렷한 플럭","짧은 펄스 · 아르페지오",.pluck,
              cutoff:1600,attack:0.002,decay:0.16,sustain:0.04,release:0.12,detune:5,character:0.65,motion:0.16,resonance:0.18,width:0.45,envelope:2.3),
        .init("singing-lead","노래하는 리드","둥근 어택 · 선명한 멜로디",.lead,
              cutoff:3400,attack:0.02,decay:0.3,sustain:0.66,release:0.24,detune:6,character:0.5,motion:0.2,resonance:0.15,width:0.18,envelope:0.4),
        .init("velvet-ep","벨벳 전자피아노","어두운 배음 · 따뜻한 코드",.electricPiano,
              cutoff:6800,attack:0.004,decay:2.6,sustain:0.07,release:0.32,detune:0,character:0.23,motion:0.3,resonance:0.06,width:0.55,envelope:0),
        .init("bell-ep","벨 전자피아노","밝은 타격감 · 선명한 코드",.electricPiano,
              cutoff:12500,attack:0.002,decay:1.8,sustain:0.04,release:0.22,detune:0,character:0.85,motion:0.52,resonance:0.08,width:0.7,envelope:0),
        .init("rotary-organ","회전 오르간","지속 화음 · 움직이는 배음",.organ,
              cutoff:7400,attack:0.008,decay:0.18,sustain:0.88,release:0.08,detune:0,character:0.58,motion:0.65,resonance:0.05,width:0.65,envelope:0),
        .init("short-brass","짧은 브라스","필터 어택 · 리듬 화음",.brass,
              cutoff:1900,attack:0.025,decay:0.28,sustain:0.42,release:0.15,detune:8,character:0.62,motion:0.2,resonance:0.24,width:0.5,envelope:0.9),
        .init("silk-strings","실크 스트링","느린 전개 · 넓은 지속음",.strings,
              cutoff:4800,attack:0.48,decay:1.3,sustain:0.78,release:1.2,detune:17,character:0.4,motion:0.62,resonance:0.08,width:0.95,envelope:0.15)
    ]

    /// An edited or legacy patch remains custom, without silently upgrading its engine.
    public static func matching(_ patch:SynthPatch)->SynthPreset? {factory.first{$0.patch==patch}}
}
