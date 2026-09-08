import Foundation

/// A draft is independent of the model until it is resolved against its original target.
public struct NumberEditSession<Context: Equatable> {
    public var text = ""
    private var baseline: Double?
    private var context: Context?
    public let presentation:NumberEditPresentation
    public init(presentation:NumberEditPresentation = .number) {self.presentation=presentation}

    public static func format(_ value: Double) -> String {
        // Keep small envelope/time values legible; entering and leaving never rounds the model.
        String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    public var isDirty: Bool {baseline.map {text != presentation.text($0)} ?? false}
    public var hasBaseline: Bool {baseline != nil}
    public mutating func type(_ text: String, value: Double, context: Context) {
        // The first text event may arrive before the framework's focus callback.
        if !hasBaseline {begin(value:value,context:context)}
        self.text=text
    }
    public mutating func begin(value: Double, context: Context) {
        baseline=value; self.context=context; text=presentation.text(value)
    }
    public mutating func reset(value: Double) {
        baseline=nil; context=nil; text=presentation.text(value)
    }
    public mutating func refresh(value: Double, context: Context, editing: Bool) {
        guard !editing || !isDirty else {return}
        if editing {begin(value:value,context:context)} else {reset(value:value)}
    }
    /// Nil means no mutation. The caller consumes the draft before invoking a synchronous setter.
    public func resolve(value: Double, context: Context, range: ClosedRange<Double>, integerOnly: Bool = false) throws -> Double? {
        guard let baseline,isDirty else {return nil}
        guard self.context == context,baseline == value else {
            throw CirclrError("편집 대상이 변경되었습니다. Esc로 취소한 뒤 다시 입력하세요")
        }
        guard let number=presentation.parse(text),number.isFinite else {
            throw CirclrError(presentation == .gainDecibels ? "dB 값 또는 무음을 뜻하는 −∞를 입력하세요":"유한한 숫자를 입력하세요")
        }
        guard range.contains(number) else {
            let min=range.lowerBound,max=range.upperBound,unlimited=Double.greatestFiniteMagnitude
            let description = min == -unlimited ? "\(Self.format(max)) 이하" : max == unlimited ? "\(Self.format(min)) 이상" : "\(Self.format(min))–\(Self.format(max))"
            let unit=presentation == .gainDecibels ? "dB":"%"
            throw CirclrError(presentation == .number ? "입력 범위: \(description)":"입력 범위: \(presentation.text(min))–\(presentation.text(max)) \(unit)")
        }
        guard !integerOnly || number.rounded() == number else {throw CirclrError("정수를 입력하세요")}
        return number == baseline ? nil:number
    }
}
