import Foundation

/// Editor units only. AutomationLane interpolation and stored values are unchanged.
public enum AutomationDisplay {
    public static func normalized(_ value:Double,parameter:AutomationParameter)->Double {
        let range=parameter.range,clamped=max(range.lowerBound,min(range.upperBound,value))
        if parameter == .synthCutoff {return log(clamped/40)/log(500)}
        return (clamped-range.lowerBound)/(range.upperBound-range.lowerBound)
    }
    public static func value(atNormalized position:Double,parameter:AutomationParameter)->Double {
        let position=max(0,min(1,position))
        if parameter == .synthCutoff {return 40*pow(500,position)}
        return parameter.range.lowerBound+position*(parameter.range.upperBound-parameter.range.lowerBound)
    }
    public static func hit(in ids:[ID],selected:ID?,cycle:Bool)->ID? {
        guard !ids.isEmpty else{return nil}
        guard let selected,let index=ids.firstIndex(of:selected) else{return ids.first}
        return cycle ? ids[(index+1)%ids.count]:selected
    }
    public static func value(_ value:Double,parameter:AutomationParameter)->String {
        if parameter == .gain{return GainScale.text(value)+" dB"}
        if parameter == .synthCutoff{return String(format:"%.2f Hz",locale:Locale(identifier:"en_US_POSIX"),value)}
        if parameter == .synthResonance{return String(format:"%.2f%%",locale:Locale(identifier:"en_US_POSIX"),value*100)}
        if value==0{return "중앙"}
        return (value<0 ? "L ":"R ")+String(format:"%.2f%%",locale:Locale(identifier:"en_US_POSIX"),abs(value)*100)
    }
    public static func nudge(_ value:Double,parameter:AutomationParameter,direction:Int,fine:Bool=false,coarse:Bool=false)->Double {
        let sign=direction<0 ? -1.0:direction>0 ? 1.0:0
        guard sign != 0 else{return value}
        if parameter == .synthCutoff {
            let step=fine ? 1.0:coarse ? 1000.0:100.0
            return max(40,min(20000,value+sign*step))
        }
        if parameter == .synthResonance {
            let step=fine ? 0.001:coarse ? 0.1:0.01
            return max(0,min(0.9,value+sign*step))
        }
        if parameter == .gain {
            let step=fine ? 0.1:coarse ? 3.0:0.5
            return GainScale.gain(atFader:GainScale.faderValue(value)+sign*step,preserving:value)
        }
        let step=fine ? 0.01:coarse ? 0.25:0.05
        return max(-1,min(1,value+sign*step))
    }
    public static func time(_ beat:Double,clock:MusicClock?)->String {
        let position=BeatPosition.text(beat)+"박"
        guard let clock else{return position}
        return position+String(format:" · %.2f초",locale:Locale(identifier:"en_US_POSIX"),clock.seconds(at:beat))
    }
}
