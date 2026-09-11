import Foundation

/// Local bar positions extend the final meter without allocating every future bar.
public enum AutomationRuler {
    public struct Tick:Equatable {
        public let bar:Int
        public let beat:Double
    }
    public struct Position:Equatable {
        public let bar:Int
        /// One-based position in the meter's denominator, not quarter-note offset.
        public let beat:Double
    }
    public static func ticks(clock:MusicClock?,end:Double,capacity:Int)->[Tick] {
        guard let clock,end.isFinite,end>0,end<=1_048_576,!clock.meters.isEmpty else{return []}
        let known=clock.barStarts.dropLast().prefix(while:{$0<end}).count
        let period=clock.meters.last!.quarters
        let extra=end>clock.barContinuationBeat ? Int(ceil((end-clock.barContinuationBeat)/period)):0
        let count=known+extra,limit=max(1,min(64,capacity))
        var step=1
        while Double(count)/Double(step)>Double(limit) {step*=2}
        return stride(from:0,to:count,by:step).map { index in
            let beat=index<clock.meters.count ? clock.barStarts[index]:clock.barContinuationBeat+Double(index-clock.meters.count)*period
            return Tick(bar:index+1,beat:beat)
        }
    }
    public static func position(at beat:Double,clock:MusicClock?)->Position? {
        guard let clock,beat.isFinite,(0...1_048_576).contains(beat),!clock.meters.isEmpty else{return nil}
        let index:Int,start:Double,meter:Meter
        if beat>=clock.barContinuationBeat {
            meter=clock.meters.last!
            let extra=Int(floor((beat-clock.barContinuationBeat)/meter.quarters))
            index=clock.meters.count+extra;start=clock.barContinuationBeat+Double(extra)*meter.quarters
        } else {
            index=clock.bar(at:beat);start=clock.barStarts[index];meter=clock.meters[index]
        }
        return Position(bar:index+1,beat:1+(beat-start)*Double(meter.denominator)/4)
    }
    public static func text(at beat:Double,clock:MusicClock?)->String? {
        guard let position=position(at:beat,clock:clock) else{return nil}
        return "\(position.bar)마디 · "+String(format:"%.2f박",locale:Locale(identifier:"en_US_POSIX"),position.beat)
    }
}
