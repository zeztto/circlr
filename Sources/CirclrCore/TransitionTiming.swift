import Foundation

/// Relative to the end of the source's last repetition, using the same clocks as playback.
public struct TransitionTiming: Equatable {
    public let duration: Double
    public let startOffset: Double
    public let targetOffset: Double

    public init(_ transition: Transition, source: MusicClock, target: MusicClock) throws {
        let length=transition.length
        guard length.isFinite, length>=0 else {throw CirclrError("전환 길이를 확인하세요")}
        switch transition.anchor {
        case .seconds: duration=length
        case .sourceBars:
            guard length<=Double(source.meters.count) else {throw CirclrError("전환 길이가 출발 섹션보다 깁니다")}
            duration=source.seconds-source.seconds(at:source.beatAtBar(Double(source.meters.count)-length))
        case .targetBars:
            guard length<=Double(target.meters.count) else {throw CirclrError("전환 길이가 도착 섹션보다 깁니다")}
            duration=target.seconds(at:target.beatAtBar(length))
        }
        guard duration.isFinite else {throw CirclrError("전환 시간을 계산할 수 없습니다")}
        switch transition.mode {
        case .within:
            guard duration<=source.seconds else {throw CirclrError("전환이 출발 섹션 범위를 넘습니다")}
            startOffset = -duration; targetOffset=0
        case .insert: startOffset=0; targetOffset=duration
        case .overlap:
            guard duration<min(source.seconds,target.seconds) else {throw CirclrError("겹침은 두 섹션보다 짧아야 합니다")}
            startOffset = -duration; targetOffset = -duration
        }
    }
}
