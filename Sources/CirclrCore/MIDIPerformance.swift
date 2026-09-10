import Foundation

/// Ordered hold state on the parent section's seconds clock. Equal-time entries
/// retain MIDI file order; a renderer consumes the final state before note-on.
public struct MIDITimedPitchBendState: Equatable, Sendable {
    public let seconds: Double
    public let state: MIDIPitchBendState
}

/// An independent controller/voice domain. A renderer must additionally scope
/// this ID by the enclosing arrangement occurrence, and retain its final state
/// for voices that release after endSeconds.
public struct MIDIPerformanceStream: Equatable {
    public let id: ID
    public let sourceNodeID: ID
    public let sourceChannel: Int
    public let notes: [Note]
    public let startSeconds: Double
    public let endSeconds: Double
    public let initialPitchBend: MIDIPitchBendState
    public let pitchBendStates: [MIDITimedPitchBendState]
}

extension SectionGraphCompiler {
    /// Pattern swing affects note placement only, never controller timestamps.
    static func performanceStreams(notes: [Note], sequence: MIDIPitchBendSequence,
                                   patternLength: Double? = nil, grid: BeatGrid,
                                   node: MusicCircle, context: MusicContext,
                                   parentClock: MusicClock) throws -> [MIDIPerformanceStream] {
        try sequence.validate()
        if node.muted { return [] }
        let length = node.lengthBeats ?? parentClock.beats
        guard length.isFinite, length > 0, (1...256).contains(node.repeatCount) else {
            throw CirclrError("MIDI 서클의 길이·반복을 확인하세요")
        }
        let cycle = patternLength ?? length
        guard cycle.isFinite, cycle > 0 else { throw CirclrError("MIDI 연주 반복 길이를 확인하세요") }
        let repeatEstimate = patternLength == nil ? 1 : ceil(parentClock.beats / cycle)
        guard repeatEstimate.isFinite, repeatEstimate * Double(node.repeatCount) <= 1_000_000 else { throw CirclrError("MIDI 연주 stream이 너무 많습니다") }
        let patternCount = Int(repeatEstimate)
        let ownTempo = node.settings.tempo.source != .inherit
        let offset = parentClock.seconds(at: node.startBeat)
        func seconds(_ beat: Double) -> Double {
            ownTempo ? offset + beat * 60 / context.tempo : parentClock.seconds(at: node.startBeat + beat)
        }
        var output: [MIDIPerformanceStream] = [], count = 0
        let step = 1 / Double(max(1, grid.subdivisions))
        for iteration in 0..<node.repeatCount {
            for patternIteration in 0..<patternCount {
                let patternOffset = Double(patternIteration) * cycle
                guard patternOffset < length, patternOffset < parentClock.beats - 0.000001 || patternLength == nil else { break }
                let base = Double(iteration) * length
                let start = seconds(base + patternOffset)
                let controllerEnd = min(length, patternOffset + cycle, patternLength == nil ? length : parentClock.beats)
                let end = min(parentClock.seconds, seconds(base + controllerEnd))
                guard start < end else { continue }
                var scheduled: [Note] = []
                for note in notes {
                    try ArrangementCompiler.validateNote(note)
                    var q = note.beat + patternOffset
                    if patternLength != nil {
                        let stepIndex = Int((note.beat / step).rounded())
                        q = note.beat + (patternOffset + (stepIndex % 2 == 1 ? grid.swing * step : 0))
                    }
                    guard q < length, patternLength == nil || q < parentClock.beats else { continue }
                    let expandedLength = patternLength == nil ? note.length : min(note.length, parentClock.beats - q)
                    let noteEnd = q + expandedLength
                    let onset = seconds(base + q)
                    let stop = min(parentClock.seconds, seconds(base + min(length, noteEnd)))
                    guard onset < stop else { continue }
                    var copy = note
                    copy.id = "\(node.id):\(note.id):\(iteration)"
                    copy.beat = parentClock.beat(atSeconds: onset)
                    copy.length = parentClock.beat(atSeconds: stop) - copy.beat
                    scheduled.append(copy)
                    count += 1
                    guard count <= 1_000_000 else { throw CirclrError("MIDI 연주 event가 너무 많습니다") }
                }
                var raw = sequence.initialValue, range = sequence.initialRange
                let initial = MIDIPitchBendState(rawValue: raw, range: range)
                var states: [MIDITimedPitchBendState] = []
                for event in sequence.events {
                    let time = seconds(base + patternOffset + event.beat)
                    // End-exclusive: the next repeat starts from its own initial
                    // state; the preceding repeat keeps its last active state.
                    guard event.beat < cycle, time < end else { break }
                    switch event.kind { case .value(let value): raw = value; case .range(let value): range = value }
                    states.append(.init(seconds: time, state: .init(rawValue: raw, range: range)))
                    count += 1
                    guard count <= 1_000_000 else { throw CirclrError("MIDI 연주 event가 너무 많습니다") }
                }
                count += 1 // initial controller state is an event too
                guard count <= 1_000_000 else { throw CirclrError("MIDI 연주 event가 너무 많습니다") }
                output.append(.init(id: "\(node.id.utf8.count):\(node.id):\(iteration):\(patternIteration)",
                                    sourceNodeID: node.id, sourceChannel: sequence.channel,
                                    notes: scheduled, startSeconds: start, endSeconds: end,
                                    initialPitchBend: initial, pitchBendStates: states))
            }
        }
        return output
    }
}
