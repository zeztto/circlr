import Foundation

public enum NameEditResolution:Equatable {
    case unchanged
    case composing
    case apply(String)
}

/// A name draft never changes the project until the original target and value are checked.
public struct NameEditSession<Context:Equatable> {
    public private(set) var text=""
    private var baseline:String?
    private var context:Context?
    public init() {}
    public var isDirty:Bool {baseline.map{$0 != text} ?? false}
    public var hasBaseline:Bool {baseline != nil}
    public mutating func begin(value:String,context:Context) {baseline=value;self.context=context;text=value}
    public mutating func type(_ text:String,value:String,context:Context) {
        if !hasBaseline {begin(value:value,context:context)}
        self.text=text
    }
    public mutating func reset(value:String) {baseline=nil;context=nil;text=value}
    public mutating func refresh(value:String,context:Context,editing:Bool) {
        guard !editing || !isDirty else{return}
        if editing {begin(value:value,context:context)} else {reset(value:value)}
    }
    public func resolve(value:String,context:Context,isComposing:Bool=false)throws->NameEditResolution {
        guard !isComposing else{return .composing}
        guard let baseline,isDirty else{return .unchanged}
        guard self.context==context,baseline==value else {throw CirclrError("편집 대상이나 이름이 변경되었습니다. Esc로 취소한 뒤 다시 입력하세요")}
        let name=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else{throw CirclrError("이름을 입력하세요")}
        guard name.rangeOfCharacter(from:.newlines)==nil else{throw CirclrError("이름은 한 줄로 입력하세요")}
        guard name.count<=256 else{throw CirclrError("이름은 256자 이내로 입력하세요")}
        return name==baseline ? .unchanged:.apply(name)
    }
}
