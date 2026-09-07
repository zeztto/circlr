import Foundation

/// Each concentric outline represents one complete play of a section.
public struct SectionRings:Equatable {
    public let count:Int
    public let baseRadius:Double
    public let spacing:Double
    public init(repeats:Int,baseRadius:Double = 80) {
        count=max(1,min(256,repeats));self.baseRadius=baseRadius
        spacing=count>1 ? min(8,56/Double(count-1)):0
    }
    public var radii:[Double] {(0..<count).map{baseRadius+Double($0)*spacing}}
    public var outerRadius:Double {baseRadius+Double(count-1)*spacing}
    public var portRadius:Double {outerRadius+14}
    public var lineWidth:Double {count>1 ? min(1.4,spacing*0.45):1.4}
}

public enum AudioClipGeometry {
    /// Uses the same rate rule as the renderer, including the section end boundary.
    public static func visibleBeats(_ clip:AudioClip,clock:MusicClock)->Double {
        guard clip.beat.isFinite,clip.duration.isFinite,clip.duration>0,clip.sourceBPM>0 else{return 0}
        let start=clock.seconds(at:clip.beat)
        let rate=clip.followsTempo ? clock.bpm(at:clip.beat)/clip.sourceBPM:1
        let end=min(clock.seconds,start+clip.duration/rate)
        return max(0,clock.beat(atSeconds:end)-clip.beat)
    }
}
