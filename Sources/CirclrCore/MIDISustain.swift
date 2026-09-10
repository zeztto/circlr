import Foundation

/// Raw CC64 state. Half-pedal values are preserved; this contract uses the MIDI switch threshold.
public struct MIDISustainState: Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public var isDown: Bool { rawValue >= 64 }
}

public struct MIDISustainEvent: Codable, Equatable, Sendable {
    public var beat: Double
    public var rawValue: Int
    public init(beat: Double, rawValue: Int) { self.beat = beat; self.rawValue = rawValue }
    public func validate() throws {
        guard beat.isFinite, (0...131072).contains(beat), (0...127).contains(rawValue) else {
            throw CirclrError("Sustain 위치는 유한한 0–131072박, CC64 raw 값은 0–127이어야 합니다")
        }
    }
}

/// Standalone source data only; Project storage, import, editing UI and rendering are not connected.
/// Equal-beat events retain their original order, including pedal-up/down transitions.
public struct MIDISustainSequence: Codable, Equatable, Sendable {
    public var channel: Int
    public var initialValue: Int
    public var events: [MIDISustainEvent]
    public init(channel: Int = 0, initialValue: Int = 0, events: [MIDISustainEvent] = []) {
        self.channel = channel; self.initialValue = initialValue; self.events = events
    }
    public func validate() throws {
        guard (0...15).contains(channel), (0...127).contains(initialValue), events.count <= 100000 else {
            throw CirclrError("Sustain 채널·초기 CC64 값·이벤트 수를 확인하세요")
        }
        var previous = 0.0
        for event in events {
            try event.validate()
            guard event.beat >= previous else { throw CirclrError("Sustain 이벤트는 시간순이어야 합니다") }
            previous = event.beat
        }
    }
    /// Checked O(event count) query, including validation of events after the query position.
    /// Returns the final hold state only: renderers must consume the ordered events themselves,
    /// never coalesce pedal release transitions through this convenience API or call it per sample.
    public func state(atBeat beat: Double) throws -> MIDISustainState {
        guard beat.isFinite, (0...131072).contains(beat) else {
            throw CirclrError("Sustain 조회 위치는 유한한 0–131072박이어야 합니다")
        }
        try validate()
        var value = initialValue
        for event in events {
            guard event.beat <= beat else { break }
            value = event.rawValue
        }
        return MIDISustainState(rawValue: value)
    }
}
