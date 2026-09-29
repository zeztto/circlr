import Foundation

/// A portable phrase contains musical values only: no source IDs, paths or project state.
public struct MIDIClipboard: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public let relativeBeat: Double
        public let length: Double
        public let pitch: Int
        public let velocity: Int
    }
    public static let maximumNotes = 4096
    public static let maximumBytes = 1_048_576
    public let version: Int
    public let sourceStartBeat: Double
    public let notes: [Entry]

    public init(notes source: [Note]) throws {
        guard !source.isEmpty, source.count <= Self.maximumNotes else { throw CirclrError("복사할 노트는 1–4096개여야 합니다") }
        for note in source { try ArrangementCompiler.validateNote(note) }
        version = 1
        let start = source.map(\.beat).min()!
        sourceStartBeat = start
        notes = source.sorted { $0.beat == $1.beat ? $0.pitch < $1.pitch : $0.beat < $1.beat }.map {
            Entry(relativeBeat: $0.beat - start, length: $0.length, pitch: $0.pitch, velocity: $0.velocity)
        }
        try validate()
    }
    public func validate() throws {
        guard version == 1, sourceStartBeat.isFinite, sourceStartBeat >= 0, sourceStartBeat <= 131072,
              !notes.isEmpty, notes.count <= Self.maximumNotes, notes.contains(where: { $0.relativeBeat == 0 }) else {
            throw CirclrError("지원하는 MIDI 구절 형식과 노트 수를 확인하세요")
        }
        for entry in notes {
            guard entry.relativeBeat.isFinite, entry.relativeBeat >= 0, entry.length.isFinite, entry.length > 0,
                  sourceStartBeat + entry.relativeBeat + entry.length <= 131072,
                  (0...127).contains(entry.pitch), (1...127).contains(entry.velocity) else {
                throw CirclrError("MIDI 구절의 박·길이·음높이·세기가 유효하지 않습니다")
            }
        }
    }
    public func encoded() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumBytes else { throw CirclrError("MIDI 클립보드가 1MiB를 넘습니다") }
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumBytes else { throw CirclrError("MIDI 클립보드 크기를 확인하세요") }
        let phrase = try JSONDecoder().decode(Self.self, from: data)
        try phrase.validate()
        return phrase
    }
    /// All notes must fit. Never crop, quantize, transpose, or replace target notes implicitly.
    public func pasting(into lane: Lane, at beat: Double, beats: Double) throws -> Lane {
        try validate()
        guard beat.isFinite, beat >= 0, beats.isFinite, beats > 0, beats <= 131072,
              lane.notes.count + notes.count <= 100000,
              notes.allSatisfy({ beat + $0.relativeBeat < beats && beat + $0.relativeBeat + $0.length <= beats + 1e-8 }) else {
            throw CirclrError("붙여넣을 구절이 서클 길이를 넘습니다. 커서를 앞쪽으로 옮기거나 서클 길이를 늘리세요")
        }
        var result = lane
        result.notes += notes.map { Note(beat: beat + $0.relativeBeat, length: $0.length, pitch: $0.pitch, velocity: $0.velocity) }
        return result
    }
}
