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
        case prepare(frames: Int)
        case prepared
        case play(run: UUID)
        case started(run: UUID)
        case clock(run: UUID, seconds: Double)
        case stop(run: UUID)
        case stopped(run: UUID)
        case finished(run: UUID)
        case failure(run: UUID?, message: String)
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
        case .prepare(let frames):
            guard frames > 0, frames <= OutputWorkerWire.maximumFrames else { throw OutputWorkerWireError.invalidPacket }
        case .clock(_, let seconds):
            guard seconds.isFinite, seconds >= 0,
                  seconds <= Double(OutputWorkerWire.maximumFrames) / 48_000 else { throw OutputWorkerWireError.invalidPacket }
        case .failure(_, let message):
            guard !message.isEmpty, message.utf8.count <= 1024 else { throw OutputWorkerWireError.invalidPacket }
        default: break
        }
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
    private let session: UUID
    private let direction: Direction
    private var lastSequence: UInt64 = 0
    private var pending = Data()
    private var closed = false

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
                case .prepare, .play, .stop: command = true
                default: command = false
                }
                guard command == (direction == .commands) else { throw OutputWorkerWireError.wrongDirection }
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
