import Foundation

public enum PlaybackFollowMode: String {
    case off, following, suspended
    public func interrupted(playing: Bool) -> Self { playing && self == .following ? .suspended : self }
    /// Only a MIDI grid/orbit or an audio waveform is a precision editor that
    /// should remain in view when ordinary playback begins.
    public static func isEditingMIDIOrAudio(_ content: MusicCircleContent?, audioClipReady: Bool) -> Bool {
        switch content {
        case .midi, .rhythmMIDI: return true
        case .audio, .rhythmAudio: return audioClipReady
        default: return false
        }
    }
    /// A visible precision editor is an intentional camera position. Ordinary playback
    /// leaves it in place; callers without one retain the existing follow-on-start policy.
    public func startingPlayback(visiblePrecisionEditor: Bool = false) -> Self {
        if visiblePrecisionEditor { return self == .following ? .suspended : self }
        return self == .suspended ? .following : self
    }
    public func toggled() -> Self { self == .following ? .off : .following }
}

/// All positions use the prepared plan's absolute seconds, including overlap and repeats.
public enum PlaybackPosition {
    public static func occurrence(in plan: ExecutionPlan, at seconds: Double) -> Occurrence? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return plan.occurrences.last { $0.start <= seconds && seconds < $0.end }
    }

    public static func followOccurrence(in plan: ExecutionPlan, at seconds: Double) -> Occurrence? {
        if let active = occurrence(in: plan, at: seconds) { return active }
        guard seconds.isFinite, seconds >= 0 else { return nil }
        if let transition = plan.transitions.first(where: { $0.start <= seconds && seconds < $0.start+$0.duration }) {
            return plan.occurrences.first { $0.id == transition.sourceOccurrenceID }
        }
        return seconds >= plan.duration ? plan.occurrences.last : nil
    }

    public static func localSeconds(for node: CircleSceneNode, at seconds: Double,
                                    plan: ExecutionPlan, album: AlbumExecutionPlan?, albumID: ID?) -> Double? {
        guard seconds.isFinite, seconds >= 0, let timeline = node.timeline, timeline.duration > 0 else { return nil }
        var local: Double?
        switch node.id {
        case .album:
            if plan.arrangementID == albumID, seconds < plan.duration { local = seconds }
        case .composition(let id):
            if plan.arrangementID == albumID, let album,
               let active = album.compositions.first(where: { $0.start <= seconds && seconds < $0.end && $0.path.contains(id) }),
               let depth = active.path.firstIndex(of: id) {
                let prefix = Array(active.path.prefix(depth+1)), iterations = Array(active.iterations.prefix(depth+1))
                let beginning = album.compositions.first { Array($0.path.prefix(depth+1)) == prefix && Array($0.iterations.prefix(depth+1)) == iterations }?.start ?? active.start
                local = seconds-beginning
            }
        case .section(_, let use), .music(_, let use, _):
            guard let active = plan.occurrences.last(where: { $0.use.id == use && $0.start <= seconds && seconds < $0.end }) else { return nil }
            local = seconds-active.start
            if let music = node.music, let clock = node.clock {
                local = sourceSeconds(music, node: node, clock: clock, occurrence: active, local: seconds-active.start)
            }
        default: break
        }
        guard let local, local.isFinite, local >= 0, local < timeline.duration else { return nil }
        return local
    }

    private static func sourceSeconds(_ music: MusicCircle, node: CircleSceneNode, clock: MusicClock,
                                      occurrence: Occurrence, local: Double) -> Double? {
        let start = occurrence.clock.seconds(at: music.startBeat)
        guard local >= start else { return nil }
        switch music.content {
        case .midi, .rhythmMIDI:
            let q = music.settings.tempo.source == .inherit ? occurrence.clock.beat(atSeconds: local)-music.startBeat : (local-start)*node.context.tempo/60
            let length = music.lengthBeats ?? occurrence.clock.beats
            guard length > 0, q >= 0, q < length*Double(music.repeatCount) else { return nil }
            return clock.seconds(at: q.truncatingRemainder(dividingBy: length))
        case .audio, .rhythmAudio:
            for clip in occurrence.signalPlan?.audio[music.id] ?? [] {
                let spans = OrbitTiming.intervals(node: music, context: node.context, clock: occurrence.clock, clips: [clip])
                if let span = spans.first(where: { $0.start <= local && local < $0.end }) {
                    return local-span.start+clock.seconds(at: clip.beat)
                }
            }
            return nil
        default: return nil
        }
    }
}
