import Foundation

/// Playback scope is independent of arrangement repeats and camera follow.
public enum PlaybackLoopMode:String,Codable,CaseIterable,Sendable {
    case off, song, section
}
