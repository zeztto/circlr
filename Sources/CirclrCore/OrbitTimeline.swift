import Foundation

public enum CircleLayout: String, Codable, Equatable { case orbit, freeform }

/// Seconds are the common coordinate across tempo maps and nested musical clocks.
public struct OrbitTimeline: Codable, Equatable {
    public struct Tick: Codable, Equatable {
        public var seconds: Double
        public var label: String
        public init(_ seconds: Double, _ label: String) { self.seconds=seconds; self.label=label }
    }
    public var duration: Double
    public var ticks: [Tick]
    public init(duration: Double, ticks: [Tick] = []) { self.duration=duration; self.ticks=ticks }
    public init(clock: MusicClock) {
        duration=clock.seconds
        ticks=clock.barStarts.dropLast().enumerated().map { Tick(clock.seconds(at:$0.element), String($0.offset+1)) }
    }
    public func angle(at seconds: Double) -> Double { -Double.pi/2 + min(1,max(0,seconds/max(1e-9,duration)))*2*Double.pi }
    public func seconds(at point: Point) -> Double { Self.phase(point)*duration }
    public static func phase(_ point: Point) -> Double {
        let turns=(atan2(point.y,point.x)+Double.pi/2)/(2*Double.pi)
        return turns-floor(turns)
    }
    public func point(at seconds: Double, radius: Double) -> Point {
        let a=angle(at:seconds); return Point(cos(a)*radius,sin(a)*radius)
    }
    /// Accumulated turns avoid a discontinuity when dragging across twelve o'clock.
    public static func phaseDelta(from: Double, to: Double) -> Double {
        var delta=to-from
        if delta>0.5 {delta-=1}; if delta < -0.5 {delta+=1}
        return delta
    }
}

public struct OrbitInterval: Codable, Equatable {
    public var start: Double
    public var end: Double
    public init(_ start: Double, _ end: Double) { self.start=start; self.end=end }
}
public struct OrbitPlacement: Codable, Equatable {
    public var owner: CircleAddress
    public var timeline: OrbitTimeline
    public var anchor: Double
    public var intervals: [OrbitInterval]
    /// Owner time-ring radius in world units after scene flattening. The visual
    /// satellite can sit outside this ring; its position never changes the anchor.
    /// Legacy freeform scenes retain their historical placement radius.
    public var radius: Double = 0
    public init(owner: CircleAddress, timeline: OrbitTimeline, anchor: Double, intervals: [OrbitInterval]) {
        self.owner=owner; self.timeline=timeline; self.anchor=anchor; self.intervals=intervals
    }
}

public enum OrbitTiming {
    /// Matches the existing MIDI scheduler and audio renderer, including natural audio repeats.
    public static func intervals(node: MusicCircle, context: MusicContext, clock: MusicClock, clips: [AudioClip] = []) -> [OrbitInterval] {
        guard node.content.input == nil else {return []}
        let own=node.settings.tempo.source != .inherit
        func time(_ beat: Double) -> Double { own ? clock.seconds(at:node.startBeat)+beat*60/context.tempo : clock.seconds(at:node.startBeat+beat) }
        var spans: [OrbitInterval]=[]
        func append(_ start: Double, _ end: Double) {
            let last=min(clock.seconds,end)
            if start<last {spans.append(OrbitInterval(max(0,start),last))}
        }
        switch node.content {
        case .audio, .rhythmAudio:
            for clip in clips {
                let rate=clip.followsTempo ? (own ? context.tempo : clock.bpm(at:node.startBeat+clip.beat))/clip.sourceBPM : 1
                guard rate.isFinite, rate>0 else {continue}
                let duration=clip.duration/rate
                let timing=AudioClipTiming(node:node,context:context,clock:clock)
                for i in 0..<node.repeatCount {
                    if let length=node.lengthBeats {
                        guard clip.beat<length else {break}
                        let start=timing.position(clip,iteration:i)
                        append(start,min(start+duration,time(Double(i+1)*length)))
                    } else {
                        let start=time(clip.beat)+Double(i)*clip.loopSourceDuration/rate
                        append(start,start+duration)
                    }
                }
            }
        default:
            let length=node.lengthBeats ?? clock.beats
            for i in 0..<node.repeatCount {append(time(Double(i)*length),time(Double(i+1)*length))}
        }
        return spans.sorted {$0.start < $1.start}
    }
}
