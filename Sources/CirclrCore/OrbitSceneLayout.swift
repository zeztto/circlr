import Foundation

/// Shared outward-layout dimensions. Music time and manual offsets are independent.
public enum OrbitSceneLayout {
    public static let gap: Double = 100
    public static func radius(role: CircleRole, music: MusicCircle? = nil, signal: SignalNode? = nil) -> Double {
        switch role {
        case .album: return 340
        case .song: return 280
        case .movement: return 230
        case .section: return 200
        case .sound: return 230
        case .group: return 160
        case .music:
            if let signal {
                switch signal.kind {
                case .source: return 72
                case .effect: return 54
                case .bus: return 54
                case .master: return 42
                }
            }
            switch music?.content {
            case .audio, .rhythmAudio: return 100
            case .midi, .rhythmMIDI: return 88
            case .instrument: return 72
            case .effect: return 54
            case .mix, .router: return 54
            case .output: return 42
            case nil: return 80
            }
        }
    }
}
