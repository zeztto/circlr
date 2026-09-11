import Foundation

/// Internal output-worker wire contract. No device calls or user paths belong here.
struct OutputWorkerPacket: Codable, Equatable {
    static let version = 1
    let version: Int
    let session: UUID
    let sequence: UInt64
    let payload: Payload

    enum Payload: Codable, Equatable {
        case hello
        case helloCapabilities(outputDeviceSelection: Bool)
        case helloLoopCapabilities(outputDeviceSelection: Bool)
        case helloBoundaryLoopCapabilities(outputDeviceSelection: Bool)
        case prepareLoop(frames: Int, selection: OutputDeviceSelection)
        case prepareLoopRange(frames:Int,cycleFrames:Int,startFrame:Int,selection:OutputDeviceSelection)
        case queueLoopChange(change:UUID,frames:Int,cycleFrames:Int)
        case exitLoop(change:UUID)
        case loopChangeScheduled(change:UUID,elapsedFrame:Int64,frames:Int,exiting:Bool)
        case loopChangeRejected(change:UUID,message:String)
        case loopClock(run: UUID, seconds: Double)
        case loopFinished(run:UUID,elapsedFrame:Int64)
        case prepareOutput(frames: Int, selection: OutputDeviceSelection)
        case outputDevice(descriptor: OutputDeviceDescriptor)
        case prepare(frames: Int)
        case prepared
        case play(run: UUID)
        case started(run: UUID)
        case clock(run: UUID, seconds: Double)
        case stop(run: UUID)
        case stopped(run: UUID)
        case finished(run: UUID)
        case failure(run: UUID?, message: String)
        case trace(stage: PlaybackOutputTraceEvent.Stage, phase: PlaybackOutputTraceEvent.Phase, elapsedSeconds: Double)
    }

    init(session: UUID, sequence: UInt64, payload: Payload) {
        version = Self.version
        self.session = session
        self.sequence = sequence
        self.payload = payload
    }

    func validate() throws {
        guard version == Self.version, sequence > 0 else { throw OutputWorkerWireError.invalidPacket }
        switch payload {
        case .prepareOutput(let frames, let selection), .prepareLoop(let frames, let selection):
            try Self.validateSelection(selection)
            guard frames > 0, frames <= OutputWorkerWire.maximumFrames else { throw OutputWorkerWireError.invalidPacket }
        case .prepareLoopRange(let frames,let cycleFrames,let startFrame,let selection):
            try Self.validateSelection(selection)
            guard frames>0,frames<=OutputWorkerWire.maximumFrames,cycleFrames>0,cycleFrames<=frames,startFrame>=0,startFrame<cycleFrames else{throw OutputWorkerWireError.invalidPacket}
        case .queueLoopChange(_,let frames,let cycleFrames):
            guard frames>0,frames<=OutputWorkerWire.maximumFrames,cycleFrames>0,cycleFrames<=frames else{throw OutputWorkerWireError.invalidPacket}
        case .loopChangeScheduled(_,let elapsed,let frames,_):
            guard elapsed>=0,elapsed<=432_000_000_000_000,frames>0,frames<=OutputWorkerWire.maximumFrames else{throw OutputWorkerWireError.invalidPacket}
        case .loopChangeRejected(_,let message):
            guard !message.isEmpty,message.utf8.count<=1024 else{throw OutputWorkerWireError.invalidPacket}
        case .outputDevice(let descriptor):
            try Self.validateSelection(.deviceUID(descriptor.uid))
            guard !descriptor.name.isEmpty, descriptor.name.utf8.count <= 1024, !descriptor.name.contains("\0") else { throw OutputWorkerWireError.invalidPacket }
        case .prepare(let frames):
            guard frames > 0, frames <= OutputWorkerWire.maximumFrames else { throw OutputWorkerWireError.invalidPacket }
        case .clock(_, let seconds):
            guard seconds.isFinite, seconds >= 0,
                  seconds <= Double(OutputWorkerWire.maximumFrames) / 48_000 else { throw OutputWorkerWireError.invalidPacket }
        case .loopFinished(_,let frame):
            guard frame>=0,frame<=432_000_000_000_000 else{throw OutputWorkerWireError.invalidPacket}
        case .loopClock(_, let seconds):
            // Roughly 285 years at sample-frame precision. Bounds numeric conversion,
            // not the finite source file; loop duration is independent of its length.
            guard seconds.isFinite, seconds >= 0, seconds <= 9_000_000_000 else { throw OutputWorkerWireError.invalidPacket }
        case .failure(_, let message):
            guard !message.isEmpty, message.utf8.count <= 1024 else { throw OutputWorkerWireError.invalidPacket }
        case .trace(let stage, _, let elapsed):
            guard OutputWorkerWire.traceStages.contains(stage), elapsed.isFinite, elapsed >= 0,
                  elapsed <= Double(OutputWorkerWire.maximumFrames) / 48_000 else { throw OutputWorkerWireError.invalidPacket }
        default: break
        }
    }
    static func validateSelection(_ selection: OutputDeviceSelection) throws {
        do { try selection.validate() }
        catch { throw OutputWorkerWireError.invalidPacket }
    }
}

enum OutputWorkerWireError: Error, Equatable {
    case invalidPacket, oversizedFrame, oversizedChunk, malformedFrame, truncatedFrame, stalePacket, wrongDirection, closed
}

/// A receive stream belongs to exactly one child session and one direction.
/// Any protocol error permanently closes it; callers must discard that child.
struct OutputWorkerWire {
    enum Direction { case commands, events }
    static let maximumChunkBytes = 64 * 1024
    static let maximumFrameBytes = 16 * 1024
    static let maximumFrames = 48_000 * 60 * 60 * 4
    static let legacyTraceStages: [PlaybackOutputTraceEvent.Stage] = [.fileValidation, .engineCreation, .mixerAcquisition, .routing, .scheduling, .engineStart, .playerPlay]
    static let traceStages: [PlaybackOutputTraceEvent.Stage] = [.fileValidation, .engineCreation, .outputNodeAcquisition, .deviceSelection, .mixerAcquisition, .routing, .scheduling, .engineStart, .playerPlay]
    private let session: UUID
    private let direction: Direction
    private var lastSequence: UInt64 = 0
    private var pending = Data()
    private var closed = false
    private var traceIndex = 0
    private var traceElapsed = 0.0
    private var selectedTraceStages = Self.traceStages

    init(session: UUID, receiving direction: Direction = .events) {
        self.session = session
        self.direction = direction
    }

    static func encode(_ packet: OutputWorkerPacket) throws -> Data {
        try packet.validate()
        var data = try JSONEncoder().encode(packet)
        guard data.count <= maximumFrameBytes else { throw OutputWorkerWireError.oversizedFrame }
        data.append(10)
        return data
    }

    mutating func receive(_ chunk: Data) throws -> [OutputWorkerPacket] {
        guard !closed else { throw OutputWorkerWireError.closed }
        // Commit only after the complete chunk has passed validation.
        var staged = self
        do {
            guard chunk.count <= Self.maximumChunkBytes else { throw OutputWorkerWireError.oversizedChunk }
            let packets = try staged.consume(chunk)
            self = staged
            return packets
        } catch {
            closed = true
            pending.removeAll()
            throw error
        }
    }

    private mutating func consume(_ chunk: Data) throws -> [OutputWorkerPacket] {
        var result: [OutputWorkerPacket] = []
        for byte in chunk {
            if byte == 10 {
                guard !pending.isEmpty else { throw OutputWorkerWireError.malformedFrame }
                let packet: OutputWorkerPacket
                do { packet = try JSONDecoder().decode(OutputWorkerPacket.self, from: pending) }
                catch { throw OutputWorkerWireError.malformedFrame }
                try packet.validate()
                guard packet.session == session, lastSequence < UInt64.max, packet.sequence == lastSequence + 1 else { throw OutputWorkerWireError.stalePacket }
                let command: Bool
                switch packet.payload {
                case .prepare, .prepareOutput, .prepareLoop, .prepareLoopRange, .queueLoopChange, .exitLoop, .play, .stop: command = true
                default: command = false
                }
                guard command == (direction == .commands) else { throw OutputWorkerWireError.wrongDirection }
                if case .hello = packet.payload { selectedTraceStages = Self.legacyTraceStages }
                if case .helloCapabilities(let supported) = packet.payload { selectedTraceStages = supported ? Self.traceStages : Self.legacyTraceStages }
                if case .helloBoundaryLoopCapabilities(let supported) = packet.payload { selectedTraceStages = supported ? Self.traceStages : Self.legacyTraceStages }
                if case .helloLoopCapabilities(let supported) = packet.payload { selectedTraceStages = supported ? Self.traceStages : Self.legacyTraceStages }
                if case .trace(let stage, let phase, let elapsed) = packet.payload {
                    guard traceIndex < selectedTraceStages.count * 2, stage == selectedTraceStages[traceIndex / 2],
                          phase == (traceIndex % 2 == 0 ? .entered : .completed), elapsed >= traceElapsed else {
                        throw OutputWorkerWireError.invalidPacket
                    }
                    traceIndex += 1; traceElapsed = elapsed
                }
                lastSequence = packet.sequence
                result.append(packet)
                pending.removeAll(keepingCapacity: true)
            } else {
                guard pending.count < Self.maximumFrameBytes else { throw OutputWorkerWireError.oversizedFrame }
                pending.append(byte)
            }
        }
        return result
    }

    mutating func finish() throws {
        guard !closed else { throw OutputWorkerWireError.closed }
        closed = true
        guard pending.isEmpty else { pending.removeAll(); throw OutputWorkerWireError.truncatedFrame }
    }
}
