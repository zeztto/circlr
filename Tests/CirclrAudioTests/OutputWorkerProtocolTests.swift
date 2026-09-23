import XCTest
@testable import CirclrAudio

final class OutputWorkerProtocolTests: XCTestCase {
    func testLoopWireHasDistinctBoundedClockAndCommandDirection() throws {
        let id=UUID()
        let prepare=OutputWorkerPacket(session:id,sequence:1,payload:.prepareLoop(frames:480,selection:.systemDefault))
        var command=OutputWorkerWire(session:id,receiving:.commands)
        XCTAssertEqual(try command.receive(OutputWorkerWire.encode(prepare)),[prepare])
        var events=OutputWorkerWire(session:id)
        XCTAssertThrowsError(try events.receive(OutputWorkerWire.encode(prepare)))
        let clock=OutputWorkerPacket(session:id,sequence:1,payload:.loopClock(run:id,seconds:20000))
        XCTAssertNoThrow(try OutputWorkerWire.encode(clock))
        XCTAssertThrowsError(try OutputWorkerWire.encode(.init(session:id,sequence:1,payload:.clock(run:id,seconds:20000))))
        XCTAssertThrowsError(try OutputWorkerWire.encode(.init(session:id,sequence:1,payload:.loopClock(run:id,seconds:.infinity))))
        XCTAssertThrowsError(try OutputWorkerWire.encode(.init(session:id,sequence:1,payload:.loopClock(run:id,seconds:9_000_000_001))))
    }
    func testSelectionWireBoundsAndLegacyDecoding() throws {
        let id = UUID()
        for uid in ["", "   ", "bad\nuid", String(repeating: "x", count: 1025), "bad\0uid"] {
            XCTAssertThrowsError(try OutputWorkerWire.encode(.init(session: id, sequence: 1,
                payload: .prepareOutput(frames: 100, selection: .deviceUID(uid)))))
        }
        for selection in [OutputDeviceSelection.systemDefault, .deviceUID("valid")] {
            let packet = OutputWorkerPacket(session: id, sequence: 1, payload: .prepareOutput(frames: 100, selection: selection))
            var commands = OutputWorkerWire(session: id, receiving: .commands)
            XCTAssertEqual(try commands.receive(OutputWorkerWire.encode(packet)), [packet])
        }
        var legacy = OutputWorkerWire(session: id)
        let hello = OutputWorkerPacket(session: id, sequence: 1, payload: .hello)
        XCTAssertEqual(try legacy.receive(OutputWorkerWire.encode(hello)), [hello])
        var sequence: UInt64 = 2
        for stage in OutputWorkerWire.legacyTraceStages {
            for phase in [PlaybackOutputTraceEvent.Phase.entered, .completed] {
                _ = try legacy.receive(OutputWorkerWire.encode(.init(session: id, sequence: sequence,
                    payload: .trace(stage: stage, phase: phase, elapsedSeconds: Double(sequence)))))
                sequence += 1
            }
        }
        XCTAssertEqual(PlaybackOutputTrace.maximumEvents, OutputWorkerWire.traceStages.count * 2 + 4)
    }
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
        XCTAssertThrowsError(try wire.receive(packet(OutputWorkerWire.traceStages.count * 2 + 1, .playerPlay, .completed, 10)))
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

    func testAudioQueueTraceHandshakeIsOrderedAndRequiresCompletedValidation() throws {
        let id = UUID()
        func packet(_ sequence: UInt64, _ payload: OutputWorkerPacket.Payload) throws -> Data {
            try OutputWorkerWire.encode(.init(session: id, sequence: sequence, payload: payload))
        }
        let hello = try packet(1, .helloCapabilities(outputDeviceSelection: true))
        let validationEntered = try packet(2, .trace(stage: .fileValidation, phase: .entered, elapsedSeconds: 0.1))
        let validationCompleted = try packet(3, .trace(stage: .fileValidation, phase: .completed, elapsedSeconds: 0.2))
        let backend = try packet(4, .audioQueueBackend)
        var wire = OutputWorkerWire(session: id)
        XCTAssertEqual(try wire.receive(hello + validationEntered + validationCompleted + backend).count, 4)
        var sequence: UInt64 = 5
        for stage in [PlaybackOutputTraceEvent.Stage.queueCreation, .queueAudible, .queueStart] {
            for phase in [PlaybackOutputTraceEvent.Phase.entered, .completed] {
                XCTAssertEqual(try wire.receive(packet(sequence, .trace(stage: stage, phase: phase,
                    elapsedSeconds: Double(sequence) / 10))).count, 1)
                sequence += 1
            }
        }
        try wire.finish()

        for prefix in [hello, hello + validationEntered] {
            var invalid = OutputWorkerWire(session: id)
            _ = try invalid.receive(prefix)
            XCTAssertThrowsError(try invalid.receive(try packet(prefix == hello ? 2 : 3, .audioQueueBackend))) {
                XCTAssertEqual($0 as? OutputWorkerWireError, .invalidPacket)
            }
        }
        var duplicate = OutputWorkerWire(session: id)
        _ = try duplicate.receive(hello + validationEntered + validationCompleted + backend)
        XCTAssertThrowsError(try duplicate.receive(try packet(5, .audioQueueBackend))) {
            XCTAssertEqual($0 as? OutputWorkerWireError, .invalidPacket)
        }
        var outOfOrder = OutputWorkerWire(session: id)
        _ = try outOfOrder.receive(hello + validationEntered + validationCompleted + backend)
        XCTAssertThrowsError(try outOfOrder.receive(try packet(5, .trace(stage: .queueStart, phase: .entered, elapsedSeconds: 0.5)))) {
            XCTAssertEqual($0 as? OutputWorkerWireError, .invalidPacket)
        }
        var command = OutputWorkerWire(session: id, receiving: .commands)
        XCTAssertThrowsError(try command.receive(try packet(1, .audioQueueBackend))) {
            XCTAssertEqual($0 as? OutputWorkerWireError, .wrongDirection)
        }
    }

    func testAudioQueueTraceAlsoAllowsLoopCommandsAndEvents() throws {
        let session = UUID(), run = UUID(), change = UUID()
        var events = OutputWorkerWire(session: session)
        var eventSequence: UInt64 = 0
        func receiveEvent(_ payload: OutputWorkerPacket.Payload) throws {
            eventSequence += 1
            let packet = OutputWorkerPacket(session: session, sequence: eventSequence, payload: payload)
            XCTAssertEqual(try events.receive(OutputWorkerWire.encode(packet)), [packet])
        }
        try receiveEvent(.helloBoundaryLoopCapabilities(outputDeviceSelection: true))
        for phase in [PlaybackOutputTraceEvent.Phase.entered, .completed] {
            try receiveEvent(.trace(stage: .fileValidation, phase: phase, elapsedSeconds: Double(eventSequence) / 10))
        }
        try receiveEvent(.prepared)
        try receiveEvent(.audioQueueBackend)
        for stage in [PlaybackOutputTraceEvent.Stage.queueCreation, .queueAudible, .queueStart] {
            for phase in [PlaybackOutputTraceEvent.Phase.entered, .completed] {
                try receiveEvent(.trace(stage: stage, phase: phase, elapsedSeconds: Double(eventSequence) / 10))
            }
        }
        try receiveEvent(.outputDevice(descriptor: .init(uid: "selected", name: "Output")))
        try receiveEvent(.started(run: run))
        try receiveEvent(.loopClock(run: run, seconds: 1))
        try receiveEvent(.loopChangeScheduled(change: change, elapsedFrame: 48_000, frames: 960, exiting: false))
        try receiveEvent(.loopFinished(run: run, elapsedFrame: 48_960))
        try events.finish()

        var commands = OutputWorkerWire(session: session, receiving: .commands)
        var commandSequence: UInt64 = 0
        func receiveCommand(_ payload: OutputWorkerPacket.Payload) throws {
            commandSequence += 1
            let packet = OutputWorkerPacket(session: session, sequence: commandSequence, payload: payload)
            XCTAssertEqual(try commands.receive(OutputWorkerWire.encode(packet)), [packet])
        }
        try receiveCommand(.prepareLoopRange(frames: 576, cycleFrames: 480, startFrame: 0, selection: .deviceUID("selected")))
        try receiveCommand(.play(run: run))
        try receiveCommand(.queueLoopChange(change: change, frames: 1008, cycleFrames: 960))
        try receiveCommand(.exitLoop(change: UUID()))
        try commands.finish()
    }

}
