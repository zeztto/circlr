import Foundation

/// Presentation units for the existing NativeDSP parameters; serialized values stay unchanged.
public struct EffectParameter: Identifiable, Equatable {
    public enum Slot: String { case amount, secondary }
    public let kind: EffectKind
    public let id: Slot
    public let title: String
    public let unit: String
    public let range: ClosedRange<Double>
    public let hint: String

    public static func all(for kind: EffectKind) -> [EffectParameter] {
        func parameter(_ slot: Slot, _ title: String, _ unit: String, _ range: ClosedRange<Double>, _ hint: String = "") -> EffectParameter {
            EffectParameter(kind: kind, id: slot, title: title, unit: unit, range: range, hint: hint)
        }
        switch kind {
        case .gain: return [parameter(.amount, "게인", "배", 0...4, "1배는 원래 레벨 · 0배는 무음")]
        case .lowpass: return [parameter(.amount, "컷오프", "Hz", 40...20000, "이 주파수보다 높은 소리를 줄입니다")]
        case .delay: return [parameter(.amount, "지연 시간", "ms", 30...1000),
                            parameter(.secondary, "반복 레벨", "%", 0...95, "원음을 유지합니다 · 피드백도 같은 비율로 증가하며 최대 80%입니다")]
        case .reverb: return [parameter(.amount, "공간 크기", "%", 0...100), parameter(.secondary, "잔향 레벨", "%", 0...95)]
        case .drive: return [parameter(.amount, "드라이브", "배", 1...19)]
        case .pan: return [parameter(.amount, "팬", "%", -100...100, "−100 왼쪽 · 0 중앙 · 100 오른쪽")]
        case .compressor: return [parameter(.amount, "임계값", "dB", -36 ... -6), parameter(.secondary, "압축비", ":1", 2...11.5)]
        case .audioUnit: return []
        }
    }
    public func value(in effect: Effect) -> Double {
        let a = min(1, max(0, effect.amount)), b = min(0.95, max(0, effect.secondary))
        if id == .secondary {return kind == .compressor ? 2+b*10 : b*100}
        switch kind {
        case .gain: return effect.amount
        case .lowpass: return 40*pow(500,a)
        case .delay: return 30+a*970
        case .drive: return 1+a*18
        case .pan: return min(1,max(-1,effect.amount))*100
        case .compressor: return -36+a*30
        case .reverb: return a*100
        case .audioUnit: return 0
        }
    }
    public func applying(_ value: Double, to effect: Effect) throws -> Effect {
        guard effect.kind == kind, value.isFinite, range.contains(value) else {throw CirclrError("\(title) 범위: \(range.lowerBound.formatted())–\(range.upperBound.formatted()) \(unit)")}
        if value == self.value(in: effect) {return effect}
        var next = effect
        if id == .secondary {next.secondary = kind == .compressor ? (value-2)/10 : value/100}
        else {
            switch kind {
            case .gain: next.amount = value
            case .lowpass: next.amount = log(value/40)/log(500)
            case .delay: next.amount = (value-30)/970
            case .drive: next.amount = (value-1)/18
            case .pan, .reverb: next.amount = value/100
            case .compressor: next.amount = (value+36)/30
            case .audioUnit: break
            }
        }
        return next
    }
    /// Logarithmic travel for a frequency control, linear travel for the other units.
    public func sliderPosition(in effect: Effect) -> Double {
        let value = min(range.upperBound,max(range.lowerBound,self.value(in:effect)))
        return kind == .lowpass ? log(value/40)/log(500) : (value-range.lowerBound)/(range.upperBound-range.lowerBound)
    }
    public func value(at position: Double) -> Double {
        let p = min(1,max(0,position))
        return kind == .lowpass ? 40*pow(500,p) : range.lowerBound+p*(range.upperBound-range.lowerBound)
    }
}
