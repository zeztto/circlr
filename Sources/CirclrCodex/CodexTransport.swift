import Foundation

/// Stateful JSONL framing for a pipe. UTF-8 validation happens only after a complete
/// newline, so a code point can straddle any number of reads without corruption.
public struct CodexJSONLFramer {
    public let maximumLineBytes: Int
    public let maximumMessagesPerRead: Int
    private var pending = Data()

    public init(maximumLineBytes: Int = 1_048_576, maximumMessagesPerRead: Int = 128) {
        precondition(maximumLineBytes > 0 && maximumMessagesPerRead > 0)
        self.maximumLineBytes = maximumLineBytes
        self.maximumMessagesPerRead = maximumMessagesPerRead
    }

    public var bufferedBytes: Int { pending.count }

    public mutating func append(_ bytes: Data) throws -> [Data] {
        var lines: [Data] = []
        for byte in bytes {
            if byte == 0x0A {
                var line = pending
                pending.removeAll(keepingCapacity: true)
                if line.last == 0x0D { line.removeLast() }
                guard !line.isEmpty else { throw CodexProtocolError.malformedEnvelope }
                guard line.count <= maximumLineBytes else { throw CodexProtocolError.lineTooLong }
                guard lines.count < maximumMessagesPerRead else { throw CodexProtocolError.tooManyMessages }
                lines.append(line)
            } else {
                guard pending.count < maximumLineBytes + 1 else { throw CodexProtocolError.lineTooLong }
                pending.append(byte)
            }
        }
        return lines
    }

    public mutating func finish() throws {
        guard pending.isEmpty else { throw CodexProtocolError.malformedEnvelope }
    }

    public mutating func reset() { pending.removeAll() }
}

/// A bounded packet queue; the owner must drain it into a child process's stdin.
/// It never silently discards a request or a server-request response.
public struct CodexOutboundQueue {
    private struct Packet {
        let data: Data
        let serverRequestID: CodexServerRequestID?
    }

    public let maximumPackets: Int
    public let maximumBytes: Int
    private var packets: [Packet] = []
    public private(set) var queuedBytes = 0

    public init(maximumPackets: Int = 64, maximumBytes: Int = 1_048_576) {
        precondition(maximumPackets > 0 && maximumBytes > 0)
        self.maximumPackets = maximumPackets
        self.maximumBytes = maximumBytes
    }

    public var packetCount: Int { packets.count }

    public mutating func enqueue(_ packet: Data,
                                 serverRequestID: CodexServerRequestID? = nil) throws {
        guard packet.last == 0x0A, !packet.isEmpty,
              packets.count < maximumPackets,
              packet.count <= maximumBytes - queuedBytes else {
            throw CodexProtocolError.outboundQueueFull
        }
        packets.append(Packet(data: packet, serverRequestID: serverRequestID))
        queuedBytes += packet.count
    }

    public mutating func dequeue() -> Data? {
        dequeuePacket()?.data
    }

    mutating func dequeuePacket() -> (data: Data, serverRequestID: CodexServerRequestID?)? {
        guard !packets.isEmpty else { return nil }
        let packet = packets.removeFirst()
        queuedBytes -= packet.data.count
        return (packet.data, packet.serverRequestID)
    }

    /// Drop a reply which the server has already resolved before the host wrote it.
    public mutating func removeServerReply(_ id: CodexServerRequestID) {
        var retained: [Packet] = []
        for packet in packets {
            if packet.serverRequestID == id { queuedBytes -= packet.data.count }
            else { retained.append(packet) }
        }
        packets = retained
    }

    public mutating func clear() {
        packets.removeAll()
        queuedBytes = 0
    }
}
