import Foundation

/// Presentation only: projects and renderers continue to store a linear amplitude multiplier.
public enum GainScale {
    public static let maximum=4.0
    public static let minimumFaderDB = -72.0
    public static let maximumDB=20*log10(maximum)
    public static func decibels(_ gain:Double)->Double {gain>0 ? 20*log10(gain): -.infinity}
    public static func text(_ gain:Double)->String {
        guard gain != 0 else{return "−∞"}
        let db=decibels(gain)
        // Display precision does not change the raw baseline used by NumberEditSession.
        return String(format:"%.2f",locale:Locale(identifier:"en_US_POSIX"),abs(db)<0.005 ? 0:db)
    }
    public static func parse(_ text:String)->Double? {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"−",with:"-").lowercased()
        if ["-∞","-inf","-infinity"].contains(value){return 0}
        guard let db=Double(value),db.isFinite else{return nil}
        let gain=pow(10,db/20)
        return gain.isFinite && gain>0 ? gain:nil
    }
    public static func faderValue(_ gain:Double)->Double {min(maximumDB,max(minimumFaderDB,decibels(gain)))}
    public static func gain(atFader db:Double,preserving baseline:Double?=nil)->Double {
        if let baseline,abs(db-faderValue(baseline))<1e-9{return baseline}
        guard db>minimumFaderDB else{return 0}
        return min(maximum,pow(10,min(maximumDB,db)/20))
    }
}

public enum NumberEditPresentation:Hashable {
    case number,beatPosition,gainDecibels,panPercent,sourceSeconds,sourceMilliseconds
    case effectValue(unit:String)
    func text(_ value:Double)->String {
        switch self {
        case .beatPosition:return BeatPosition.text(value)
        case .gainDecibels:return GainScale.text(value)
        case .panPercent:return String(format:"%.2f",locale:Locale(identifier:"en_US_POSIX"),value*100)
        case .sourceSeconds:return String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),value)
        case .sourceMilliseconds:return String(format:"%.1f",locale:Locale(identifier:"en_US_POSIX"),value)
        case .effectValue:
            var text=String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),value)
            while text.last == "0" {text.removeLast()}
            if text.last == "." {text.removeLast()}
            return text == "-0" ? "0":text
        case .number:return String(format:"%.10g",locale:Locale(identifier:"en_US_POSIX"),value)
        }
    }
    func parse(_ text:String)->Double? {
        if self == .gainDecibels{return GainScale.parse(text)}
        let cleaned=text.trimmingCharacters(in:.whitespacesAndNewlines)
        let value=Double(self == .panPercent ? cleaned.replacingOccurrences(of:"−",with:"-"):cleaned)
        if self == .beatPosition {return value.map{BeatPosition.stored($0)}}
        return self == .panPercent ? value.map{$0/100}:value
    }
}
