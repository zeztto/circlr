import XCTest
@testable import CirclrAudio

final class OutputWorkerProtocolTests: XCTestCase {
    func testFragmentedAndCoalescedPackets() throws {
        let session = UUID(), run = UUID()
        let packets = [OutputWorkerPacket(session: session, sequence: 1, payload: .started(run: run)),
                       OutputWorkerPacket(session: session, sequence: 2, payload: .clock(run: run, seconds: 0.25))]
        let bytes = try packets.reduce(into: Data()) { $0.append(try OutputWorkerWire.encode($1)) }
        for split in 0...bytes.count {
            var stream = OutputWorkerWire(session: session)
            let first = try stream.receive(bytes.prefix(split))
            let second = try stream.receive(bytes.suffix(bytes.count - split))
            XCTAssertEqual(first + second, packets)
            try stream.finish()
        }
    }

    func testWrongSessionAndDuplicateSequenceCloseStream() throws {
        let session = UUID()
        for bad in [OutputWorkerPacket(session: UUID(), sequence: 2, payload: .hello),
                    OutputWorkerPacket(session: session, sequence: 1, payload: .hello)] {
            var stream = OutputWorkerWire(session: session)
            _ = try stream.receive(OutputWorkerWire.encode(.init(session: session, sequence: 1, payload: .hello)))
            XCTAssertThrowsError(try stream.receive(OutputWorkerWire.encode(bad))) { XCTAssertEqual($0 as? OutputWorkerWireError, .stalePacket) }
            XCTAssertThrowsError(try stream.receive(Data())) { XCTAssertEqual($0 as? OutputWorkerWireError, .closed) }
        }
    }

    func testMalformedChunkDoesNotReturnEarlierValidPackets() throws {
        let session = UUID()
        var bytes = try OutputWorkerWire.encode(.init(session: session, sequence: 1, payload: .hello))
        bytes.append(contentsOf: [123, 10])
        var stream = OutputWorkerWire(session: session)
        XCTAssertThrowsError(try stream.receive(bytes)) { XCTAssertEqual($0 as? OutputWorkerWireError, .malformedFrame) }
        XCTAssertThrowsError(try stream.finish()) { XCTAssertEqual($0 as? OutputWorkerWireError, .closed) }
    }

    func testOversizedPartialFrameIsRejectedBeforeNewline() throws {
        var stream = OutputWorkerWire(session: UUID())
        _ = try stream.receive(Data(repeating: 32, count: OutputWorkerWire.maximumFrameBytes))
        XCTAssertThrowsError(try stream.receive(Data([32]))) { XCTAssertEqual($0 as? OutputWorkerWireError, .oversizedFrame) }
    }

    func testEOFRejectsPartialFrameAndAcceptsEmptyStream() throws {
        var partial = OutputWorkerWire(session: UUID())
        _ = try partial.receive(Data("{".utf8))
        XCTAssertThrowsError(try partial.finish()) { XCTAssertEqual($0 as? OutputWorkerWireError, .truncatedFrame) }
        var empty = OutputWorkerWire(session: UUID())
        try empty.finish()
        XCTAssertThrowsError(try empty.receive(Data())) { XCTAssertEqual($0 as? OutputWorkerWireError, .closed) }
    }

    func testDirectionGapsAndChunkLimit() throws {
        let session = UUID()
        var events = OutputWorkerWire(session: session)
        XCTAssertThrowsError(try events.receive(OutputWorkerWire.encode(.init(session: session, sequence: 1, payload: .prepare(frames: 48000))))) {
            XCTAssertEqual($0 as? OutputWorkerWireError, .wrongDirection)
        }
        var commands = OutputWorkerWire(session: session, receiving: .commands)
        XCTAssertThrowsError(try commands.receive(OutputWorkerWire.encode(.init(session: session, sequence: 1, payload: .hello)))) {
            XCTAssertEqual($0 as? OutputWorkerWireError, .wrongDirection)
        }
        var gap = OutputWorkerWire(session: session)
        XCTAssertThrowsError(try gap.receive(OutputWorkerWire.encode(.init(session: session, sequence: 2, payload: .hello)))) {
            XCTAssertEqual($0 as? OutputWorkerWireError, .stalePacket)
        }
        var huge = OutputWorkerWire(session: session)
        XCTAssertThrowsError(try huge.receive(Data(repeating: 10, count: OutputWorkerWire.maximumChunkBytes + 1))) {
            XCTAssertEqual($0 as? OutputWorkerWireError, .oversizedChunk)
        }
    }

    func testInvalidVersionNumbersAndMessageBounds() throws {
        let session = UUID()
        for payload in [OutputWorkerPacket.Payload.prepare(frames: 0), .prepare(frames: OutputWorkerWire.maximumFrames + 1),
                        .clock(run: UUID(), seconds: -.infinity), .clock(run: UUID(), seconds: -1),
                        .failure(run: nil, message: String(repeating: "가", count: 342))] {
            XCTAssertThrowsError(try OutputWorkerWire.encode(.init(session: session, sequence: 1, payload: payload)))
        }
        XCTAssertThrowsError(try OutputWorkerWire.encode(.init(session: session, sequence: 0, payload: .hello)))
        let valid = try OutputWorkerWire.encode(.init(session: session, sequence: 1, payload: .hello))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["version"] = 2
        var changed = try JSONSerialization.data(withJSONObject: object); changed.append(10)
        var stream = OutputWorkerWire(session: session)
        XCTAssertThrowsError(try stream.receive(changed)) { XCTAssertEqual($0 as? OutputWorkerWireError, .invalidPacket) }
    }
    func testTraceOrderTimingBoundsAndEventLimit() throws {
        let id = UUID()
        func packet(_ n: Int, _ stage: PlaybackOutputTraceEvent.Stage, _ phase: PlaybackOutputTraceEvent.Phase, _ time: Double) throws -> Data {
            try OutputWorkerWire.encode(.init(session: id, sequence: UInt64(n), payload: .trace(stage: stage, phase: phase, elapsedSeconds: time)))
        }
        var wire = OutputWorkerWire(session: id)
        for (index, stage) in OutputWorkerWire.traceStages.enumerated() {
            let bytes = try packet(index * 2 + 1, stage, .entered, Double(index)) + packet(index * 2 + 2, stage, .completed, Double(index) + 0.1)
            XCTAssertTrue(try wire.receive(bytes.prefix(7)).isEmpty)
            XCTAssertEqual(try wire.receive(bytes.dropFirst(7)).count, 2)
        }
        XCTAssertThrowsError(try wire.receive(packet(15, .playerPlay, .completed, 8)))
        for (stage, phase, time) in [(PlaybackOutputTraceEvent.Stage.fileValidation, PlaybackOutputTraceEvent.Phase.entered, 1.0), (.fileValidation, .completed, 0.5), (.engineCreation, .entered, 2)] {
            var invalid = OutputWorkerWire(session: id)
            _ = try invalid.receive(packet(1, .fileValidation, .entered, 1))
            XCTAssertThrowsError(try invalid.receive(packet(2, stage, phase, time)))
        }
        for time in [-1.0, Double.nan, Double.infinity, 14401] {
            XCTAssertThrowsError(try packet(1, .fileValidation, .entered, time))
        }
        XCTAssertThrowsError(try packet(1, .cafWrite, .entered, 0))
        var commands = OutputWorkerWire(session: id, receiving: .commands)
        XCTAssertThrowsError(try commands.receive(packet(1, .fileValidation, .entered, 0)))
    }

}
