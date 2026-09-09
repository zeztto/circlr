import Foundation

/// User-facing ordinal only. Durations, commands and document beats remain zero-based.
public enum BeatPosition {
    public static func displayed(_ beat:Double)->Double {beat+1}
    public static func stored(_ position:Double)->Double {position-1}
    public static func text(_ beat:Double)->String {
        String(format:"%.10g",locale:Locale(identifier:"en_US_POSIX"),displayed(beat))
    }
}
