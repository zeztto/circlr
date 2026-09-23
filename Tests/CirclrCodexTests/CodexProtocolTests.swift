import Foundation
import XCTest
@testable import CirclrCodex

final class CodexProtocolTests: XCTestCase {
    private func packet(_ text: String) -> Data { Data((text + "\n").utf8) }

    private func dequeue(_ reducer: inout CodexEventReducer) -> Data? {
        let generation = reducer.generation
        return reducer.dequeueOutbound(generation: generation)
    }

    private func handshake(_ reducer: inout CodexEventReducer) throws -> UInt64 {
        let generation = try reducer.start(version: "0.80.0")
        let initialize = try XCTUnwrap(dequeue(&reducer))
        let request = try JSONDecoder().decode(CodexJSONValue.self, from: initialize)
        XCTAssertEqual(request["method"], .string("initialize"))
        XCTAssertNil(request["jsonrpc"])
        guard let id = request["id"] else { throw CodexProtocolError.malformedEnvelope }
        let wireID: String
        switch id {
        case .integer(let number): wireID = String(number)
        default: throw CodexProtocolError.malformedEnvelope
        }
        let events = try reducer.receive(packet("{\"id\":\(wireID),\"result\":{\"userAgent\":\"fixture\"}}"),
                                         generation: generation)
        XCTAssertEqual(events, [.protocolReady])
        XCTAssertEqual(reducer.connectionState, .protocolReady)
        let initialized = try XCTUnwrap(dequeue(&reducer))
        XCTAssertEqual(try CodexWire.decode(Data(initialized.dropLast())),
                       .notification(method: "initialized", params: .object([:])))
        return generation
    }

    func testFramerRestoresSplitUnicodeAndCoalescedMessages() throws {
        var framer = CodexJSONLFramer(maximumLineBytes: 100)
        let first = packet("{\"method\":\"warning\",\"params\":{\"message\":\"안녕\"}}")
        let second = packet("{\"method\":\"thread/started\",\"params\":{}}")
        let splitIndex = try XCTUnwrap(first.firstIndex(of: 0xEC)) + 1
        XCTAssertTrue(try framer.append(first.prefix(splitIndex)).isEmpty)
        let lines = try framer.append(first.suffix(from: splitIndex) + second)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(try CodexWire.decode(lines[0]), .notification(method: "warning", params: .object(["message": .string("안녕")])))
        XCTAssertEqual(try CodexWire.decode(lines[1]), .notification(method: "thread/started", params: .object([:])))
        try framer.finish()
    }

    func testFramerAndEnvelopeRejectInvalidInputWithoutSilentDrop() throws {
        var framer = CodexJSONLFramer(maximumLineBytes: 16, maximumMessagesPerRead: 2)
        XCTAssertThrowsError(try framer.append(Data(repeating: 0x61, count: 18))) { error in
            XCTAssertEqual(error as? CodexProtocolError, .lineTooLong)
        }
        var burst = CodexJSONLFramer(maximumLineBytes: 16, maximumMessagesPerRead: 2)
        XCTAssertThrowsError(try burst.append(Data("{}\n{}\n{}\n".utf8))) { error in
            XCTAssertEqual(error as? CodexProtocolError, .tooManyMessages)
        }
        XCTAssertThrowsError(try CodexWire.decode(Data([0x7B, 0xFF, 0x7D])))
        XCTAssertThrowsError(try CodexWire.decode(Data("{\"jsonrpc\":\"2.0\",\"method\":\"x\"}".utf8))) { error in
            XCTAssertEqual(error as? CodexProtocolError, .unsupportedJSONRPCHeader)
        }
        XCTAssertThrowsError(try CodexWire.decode(Data("{\"id\":1,\"result\":{},\"error\":{\"code\":1,\"message\":\"x\"}}".utf8)))
    }

    func testOutboundQueueHasPacketAndByteBackpressure() throws {
        var queue = CodexOutboundQueue(maximumPackets: 1, maximumBytes: 5)
        try queue.enqueue(Data("{}\n".utf8))
        XCTAssertThrowsError(try queue.enqueue(Data("{}\n".utf8)))
        XCTAssertEqual(queue.queuedBytes, 3)
        XCTAssertEqual(queue.dequeue(), Data("{}\n".utf8))
        XCTAssertEqual(queue.queuedBytes, 0)
        XCTAssertThrowsError(try queue.enqueue(Data("12345\n".utf8)))
    }

    func testHandshakeTurnStreamingFinalItemAndInterruptAcknowledgement() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let turnRequestID = try reducer.startTurn(threadID: "thread-1", text: "Chorus 분석")
        let outbound = try XCTUnwrap(dequeue(&reducer))
        let request = try JSONDecoder().decode(CodexJSONValue.self, from: outbound)
        XCTAssertEqual(request["method"], .string("turn/start"))
        XCTAssertEqual(request["params"]?["input"]?[0]?["text"], .string("Chorus 분석"))
        XCTAssertEqual(try reducer.receive(packet("{\"id\":\(idNumber(turnRequestID)),\"result\":{\"turn\":{\"id\":\"turn-1\",\"status\":\"inProgress\"}}}"), generation: generation),
                       [.turnStarted(threadID: "thread-1", turnID: "turn-1")])
        let stream = packet("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"item-1\",\"delta\":\"안녕\"}}")
        XCTAssertEqual(try reducer.receive(stream, generation: generation), [.assistantDelta(itemID: "item-1", text: "안녕")])
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"item/completed\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"item\":{\"type\":\"agentMessage\",\"id\":\"item-1\",\"text\":\"완료\"}}}"), generation: generation),
                       [.assistantFinal(itemID: "item-1", text: "완료")])
        try reducer.interruptActiveTurn()
        XCTAssertEqual(reducer.turnState, .cancelling)
        let interrupt = try XCTUnwrap(dequeue(&reducer))
        let interruptJSON = try JSONDecoder().decode(CodexJSONValue.self, from: interrupt)
        XCTAssertEqual(interruptJSON["method"], .string("turn/interrupt"))
        XCTAssertEqual(reducer.turnState, .cancelling)
        let ackID = try XCTUnwrap(interruptJSON["id"])
        guard case .integer(let ackNumber) = ackID else { return XCTFail("missing interrupt id") }
        XCTAssertTrue(try reducer.receive(packet("{\"id\":\(ackNumber),\"result\":{}}"), generation: generation).isEmpty)
        XCTAssertEqual(reducer.turnState, .cancelling)
        let finish = packet("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"thread-1\",\"turn\":{\"id\":\"turn-1\",\"status\":\"interrupted\"}}}")
        XCTAssertEqual(try reducer.receive(finish, generation: generation),
                       [.turnCompleted(threadID: "thread-1", turnID: "turn-1", status: .interrupted, error: nil)])
        XCTAssertEqual(reducer.turnState, .interrupted)
    }

    func testCancelBeforeStartResponseQueuesInterruptWhenTurnIDArrives() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let id = try reducer.startTurn(threadID: "thread-a", text: "start")
        _ = dequeue(&reducer)
        try reducer.interruptActiveTurn()
        XCTAssertEqual(reducer.outboundPacketCount, 0)
        XCTAssertEqual(try reducer.receive(packet("{\"id\":\(idNumber(id)),\"result\":{\"turn\":{\"id\":\"turn-a\"}}}"), generation: generation),
                       [.turnStarted(threadID: "thread-a", turnID: "turn-a")])
        XCTAssertEqual(reducer.turnState, .cancelling)
        XCTAssertEqual(reducer.outboundPacketCount, 1)
        try reducer.interruptActiveTurn()
        XCTAssertEqual(reducer.outboundPacketCount, 1)
    }

    func testServerRequestIDsRemainDistinctFromClientIDsAndResolveOnce() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "test")
        _ = dequeue(&reducer)
        _ = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation)
        let event = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"method\":\"item/fileChange/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"item-1\"}}"), generation: generation)
        guard case .serverRequest(let request) = try XCTUnwrap(event.first) else { return XCTFail("expected server request") }
        XCTAssertEqual(request.id.value, startID.value)
        try reducer.respondToServerRequest(request.id, result: .object(["decision": .string("decline")]), generation: generation)
        let reply = try XCTUnwrap(dequeue(&reducer))
        let replyJSON = try JSONDecoder().decode(CodexJSONValue.self, from: reply)
        XCTAssertEqual(replyJSON["id"], startID.value.json)
        XCTAssertNil(replyJSON["method"])
        XCTAssertThrowsError(try reducer.respondToServerRequest(request.id, result: .object([:]), generation: generation))
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"serverRequest/resolved\",\"params\":{\"threadId\":\"thread-1\",\"requestId\":\(idNumber(startID))}}"), generation: generation), [.serverRequestResolved(request.id)])
    }

    func testOldGenerationAndUnrelatedTurnCannotMutateCurrentTurn() throws {
        var reducer = CodexEventReducer()
        let old = try handshake(&reducer)
        let current = try reducer.start(version: "0.80.0")
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"turn/completed\",\"params\":{}}"), generation: old), [.ignoredStaleGeneration])
        XCTAssertEqual(reducer.connectionState, .initializing)
        let packet = try XCTUnwrap(dequeue(&reducer))
        let initJSON = try JSONDecoder().decode(CodexJSONValue.self, from: packet)
        guard case .integer(let initID)? = initJSON["id"] else { return XCTFail("missing id") }
        _ = try reducer.receive(self.packet("{\"id\":\(initID),\"result\":{}}"), generation: current)
        _ = dequeue(&reducer)
        let id = try reducer.startTurn(threadID: "new-thread", text: "new")
        _ = dequeue(&reducer)
        _ = try reducer.receive(self.packet("{\"id\":\(idNumber(id)),\"result\":{\"turn\":{\"id\":\"new-turn\"}}}"), generation: current)
        XCTAssertEqual(try reducer.receive(self.packet("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"new-thread\",\"turn\":{\"id\":\"old-turn\",\"status\":\"completed\"}}}"), generation: current), [.ignoredUnrelatedEvent("turn/completed")])
        XCTAssertEqual(reducer.turnState, .running)
    }

    func testOldWriterCannotDrainNewGenerationOutboundPackets() throws {
        var reducer = CodexEventReducer()
        let oldGeneration = try reducer.start(version: "0.80.0")
        let currentGeneration = try reducer.start(version: "0.80.0")
        XCTAssertEqual(reducer.outboundPacketCount, 1)
        XCTAssertNil(reducer.dequeueOutbound(generation: oldGeneration))
        XCTAssertEqual(reducer.outboundPacketCount, 1)
        let currentPacket = try XCTUnwrap(reducer.dequeueOutbound(generation: currentGeneration))
        let value = try JSONDecoder().decode(CodexJSONValue.self, from: currentPacket)
        XCTAssertEqual(value["method"], .string("initialize"))
        XCTAssertEqual(reducer.outboundPacketCount, 0)
    }

    func testMissingInterruptAcknowledgementsDoNotAccumulateAcrossTurns() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        var latestInterruptID = 0
        for index in 0..<140 {
            let startID = try reducer.startTurn(threadID: "thread-1", text: "turn \(index)")
            _ = dequeue(&reducer)
            let turnID = "turn-\(index)"
            _ = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"\(turnID)\"}}}"), generation: generation)
            try reducer.interruptActiveTurn()
            let interrupt = try XCTUnwrap(dequeue(&reducer))
            let json = try JSONDecoder().decode(CodexJSONValue.self, from: interrupt)
            guard case .integer(let interruptID)? = json["id"] else {
                return XCTFail("interrupt request id missing")
            }
            latestInterruptID = interruptID
            _ = try reducer.receive(packet("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"thread-1\",\"turn\":{\"id\":\"\(turnID)\",\"status\":\"interrupted\"}}}"), generation: generation)
        }
        XCTAssertEqual(reducer.connectionState, .protocolReady)
        XCTAssertEqual(try reducer.receive(packet("{\"id\":\(latestInterruptID),\"result\":{}}"), generation: generation),
                       [.ignoredUnrelatedEvent("retiredResponse")])
        XCTAssertEqual(reducer.connectionState, .protocolReady)
    }

    func testMandatoryMalformedEventFailsClosedAndUnknownNotificationSurvives() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"future/event\",\"params\":{}}"), generation: generation), [.unknownNotification("future/event")])
        XCTAssertThrowsError(try reducer.receive(packet("{\"method\":\"turn/completed\",\"params\":{}}"), generation: generation))
        XCTAssertEqual(reducer.connectionState, .failed(.requiredField("turn/completed.threadId/turn")))
        XCTAssertEqual(reducer.outboundPacketCount, 0)
    }

    func testInitializeEnqueueFailureIsTerminalAndLeavesNoPhantomConnection() {
        var reducer = CodexEventReducer(maximumOutboundBytes: 8)
        XCTAssertThrowsError(try reducer.start(version: "0.80.0")) { error in
            XCTAssertEqual(error as? CodexProtocolError, .outboundQueueFull)
        }
        XCTAssertEqual(reducer.connectionState, .failed(.outboundQueueFull))
        XCTAssertEqual(reducer.outboundPacketCount, 0)
        XCTAssertThrowsError(try reducer.startTurn(threadID: "thread", text: "text"))
    }

    func testNotificationBeforeStartResponseDoesNotDuplicateTurnOrInterrupt() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let id = try reducer.startTurn(threadID: "thread-1", text: "draft")
        _ = dequeue(&reducer)
        try reducer.interruptActiveTurn()
        let started = packet("{\"method\":\"turn/started\",\"params\":{\"threadId\":\"thread-1\",\"turn\":{\"id\":\"turn-1\",\"status\":\"inProgress\"}}}")
        XCTAssertEqual(try reducer.receive(started, generation: generation), [])
        XCTAssertEqual(reducer.outboundPacketCount, 0)
        XCTAssertEqual(try reducer.receive(packet("{\"id\":\(idNumber(id)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation),
                       [.turnStarted(threadID: "thread-1", turnID: "turn-1")])
        XCTAssertEqual(reducer.outboundPacketCount, 1)
        XCTAssertEqual(try reducer.receive(started, generation: generation), [])
        XCTAssertEqual(reducer.outboundPacketCount, 1)
        XCTAssertEqual(reducer.turnState, .cancelling)
    }

    func testTerminalTurnRejectsLateDeltasAndServerApprovalsWithoutHang() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "test")
        _ = dequeue(&reducer)
        _ = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation)
        let completion = packet("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"thread-1\",\"turn\":{\"id\":\"turn-1\",\"status\":\"completed\"}}}")
        _ = try reducer.receive(completion, generation: generation)
        XCTAssertEqual(reducer.turnState, .completed)
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"late\",\"delta\":\"must not appear\"}}"), generation: generation),
                       [.ignoredUnrelatedEvent("item/agentMessage/delta")])
        XCTAssertEqual(try reducer.receive(completion, generation: generation), [.ignoredUnrelatedEvent("turn/completed")])
        let approval = packet("{\"id\":77,\"method\":\"item/fileChange/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"late\"}}")
        XCTAssertEqual(try reducer.receive(approval, generation: generation),
                       [.serverRequestRejected(id: CodexServerRequestID(.integer(77)), method: "item/fileChange/requestApproval")])
        XCTAssertTrue(reducer.pendingServerRequests.isEmpty)
        let reply = try XCTUnwrap(dequeue(&reducer))
        let json = try JSONDecoder().decode(CodexJSONValue.self, from: reply)
        XCTAssertEqual(json["id"], .integer(77))
        XCTAssertEqual(json["error"]?["code"], .integer(-32602))
        XCTAssertNil(json["result"])
        XCTAssertThrowsError(try reducer.respondToServerRequest(CodexServerRequestID(.integer(77)),
                                                                 result: .object(["decision": .string("accept")]),
                                                                 generation: generation))
    }

    func testCompletionBeforeStartResponseRemainsTerminal() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "text")
        _ = dequeue(&reducer)
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"item-1\",\"delta\":\"partial\"}}"), generation: generation), [])
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"item/completed\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"item\":{\"type\":\"agentMessage\",\"id\":\"item-1\",\"text\":\"final\"}}}"), generation: generation), [])
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"thread-1\",\"turn\":{\"id\":\"turn-1\",\"status\":\"failed\",\"error\":{\"message\":\"offline\"}}}}"), generation: generation), [])
        XCTAssertEqual(reducer.turnState, .starting)
        XCTAssertEqual(try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation),
                       [.turnStarted(threadID: "thread-1", turnID: "turn-1"),
                        .assistantDelta(itemID: "item-1", text: "partial"),
                        .assistantFinal(itemID: "item-1", text: "final"),
                        .turnCompleted(threadID: "thread-1", turnID: "turn-1", status: .failed, error: "offline")])
        XCTAssertEqual(reducer.turnState, .failed)
    }

    func testOldCompletionDuringNextStartCannotCompleteNewTurnOnSameThread() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let firstID = try reducer.startTurn(threadID: "thread-1", text: "first")
        _ = dequeue(&reducer)
        _ = try reducer.receive(packet("{\"id\":\(idNumber(firstID)),\"result\":{\"turn\":{\"id\":\"turn-old\"}}}"), generation: generation)
        let oldCompletion = packet("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"thread-1\",\"turn\":{\"id\":\"turn-old\",\"status\":\"completed\"}}}")
        _ = try reducer.receive(oldCompletion, generation: generation)
        let nextID = try reducer.startTurn(threadID: "thread-1", text: "second")
        _ = dequeue(&reducer)
        let oldStarted = packet("{\"method\":\"turn/started\",\"params\":{\"threadId\":\"thread-1\",\"turn\":{\"id\":\"turn-old\",\"status\":\"inProgress\"}}}")
        XCTAssertEqual(try reducer.receive(oldStarted, generation: generation), [])
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-old\",\"itemId\":\"old-item\",\"delta\":\"stale first\"}}"), generation: generation), [])
        XCTAssertEqual(try reducer.receive(oldCompletion, generation: generation), [])
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-old\",\"itemId\":\"old-item\",\"delta\":\"stale\"}}"), generation: generation), [])
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"item/completed\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-old\",\"item\":{\"type\":\"agentMessage\",\"id\":\"old-item\",\"text\":\"stale final\"}}}"), generation: generation), [])
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-new\",\"itemId\":\"new-item\",\"delta\":\"new\"}}"), generation: generation), [])
        XCTAssertEqual(try reducer.receive(packet("{\"method\":\"item/completed\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-new\",\"item\":{\"type\":\"agentMessage\",\"id\":\"new-item\",\"text\":\"new final\"}}}"), generation: generation), [])
        XCTAssertEqual(reducer.turnState, .starting)
        XCTAssertNil(reducer.activeTurnID)
        XCTAssertEqual(try reducer.receive(packet("{\"id\":\(idNumber(nextID)),\"result\":{\"turn\":{\"id\":\"turn-new\"}}}"), generation: generation),
                       [.turnStarted(threadID: "thread-1", turnID: "turn-new"),
                        .assistantDelta(itemID: "new-item", text: "new"),
                        .assistantFinal(itemID: "new-item", text: "new final")])
        XCTAssertEqual(reducer.turnState, .running)
        XCTAssertEqual(reducer.activeTurnID, "turn-new")
        XCTAssertEqual(try reducer.receive(oldStarted, generation: generation), [.ignoredUnrelatedEvent("turn/started")])
        XCTAssertEqual(try reducer.receive(oldCompletion, generation: generation), [.ignoredUnrelatedEvent("turn/completed")])
        XCTAssertEqual(reducer.turnState, .running)
    }

    func testAssistantTextTotalBoundAcrossItemsFailsConnection() throws {
        var reducer = CodexEventReducer(maximumAssistantTextBytes: 5)
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "text")
        _ = dequeue(&reducer)
        _ = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation)
        _ = try reducer.receive(packet("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"item-1\",\"delta\":\"abc\"}}"), generation: generation)
        XCTAssertThrowsError(try reducer.receive(packet("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"item-2\",\"delta\":\"def\"}}"), generation: generation)) { error in
            XCTAssertEqual(error as? CodexProtocolError, .accumulatedTextTooLong)
        }
        XCTAssertEqual(reducer.connectionState, .failed(.accumulatedTextTooLong))
    }

    func testManyTinyAssistantDeltasKeepBoundedByteAccounting() throws {
        var reducer = CodexEventReducer(maximumAssistantTextBytes: 2_000)
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "text")
        _ = dequeue(&reducer)
        _ = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation)
        let delta = packet("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"item-1\",\"delta\":\"a\"}}")
        for _ in 0..<2_000 {
            XCTAssertEqual(try reducer.receive(delta, generation: generation),
                           [.assistantDelta(itemID: "item-1", text: "a")])
        }
        XCTAssertThrowsError(try reducer.receive(delta, generation: generation)) { error in
            XCTAssertEqual(error as? CodexProtocolError, .accumulatedTextTooLong)
        }
    }

    func testUnsupportedAndUnscopedServerRequestsReceiveErrors() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let unsupported = try reducer.receive(packet("{\"id\":\"ask-1\",\"method\":\"attestation/generate\",\"params\":{}}"), generation: generation)
        XCTAssertEqual(unsupported, [.serverRequestRejected(id: CodexServerRequestID(.string("ask-1")), method: "attestation/generate")])
        let firstReply = try XCTUnwrap(dequeue(&reducer))
        let firstJSON = try JSONDecoder().decode(CodexJSONValue.self, from: firstReply)
        XCTAssertEqual(firstJSON["error"]?["code"], .integer(-32601))

        let unscoped = try reducer.receive(packet("{\"id\":\"ask-2\",\"method\":\"item/fileChange/requestApproval\",\"params\":{}}"), generation: generation)
        XCTAssertEqual(unscoped, [.serverRequestRejected(id: CodexServerRequestID(.string("ask-2")), method: "item/fileChange/requestApproval")])
        let secondReply = try XCTUnwrap(dequeue(&reducer))
        let secondJSON = try JSONDecoder().decode(CodexJSONValue.self, from: secondReply)
        XCTAssertEqual(secondJSON["error"]?["code"], .integer(-32602))
        XCTAssertTrue(reducer.pendingServerRequests.isEmpty)
    }

    func testResolvedRequestDropsQueuedReplyBeforeHostCanFlushIt() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "test")
        _ = dequeue(&reducer)
        _ = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation)
        let incoming = packet("{\"id\":42,\"method\":\"item/fileChange/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"item-1\"}}")
        let event = try reducer.receive(incoming, generation: generation)
        guard case .serverRequest(let request) = try XCTUnwrap(event.first) else { return XCTFail("request missing") }
        try reducer.respondToServerRequest(request.id, result: .object(["decision": .string("decline")]), generation: generation)
        XCTAssertEqual(reducer.outboundPacketCount, 1)
        let resolved = packet("{\"method\":\"serverRequest/resolved\",\"params\":{\"threadId\":\"thread-1\",\"requestId\":42}}")
        XCTAssertEqual(try reducer.receive(resolved, generation: generation), [.serverRequestResolved(request.id)])
        XCTAssertNil(dequeue(&reducer))
        XCTAssertTrue(reducer.pendingServerRequests.isEmpty)
        XCTAssertThrowsError(try reducer.respondToServerRequest(request.id, result: .object([:]), generation: generation))
    }

    func testResolvedFromWrongThreadCannotClearCurrentApprovalOrQueuedReply() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "edit")
        _ = dequeue(&reducer)
        _ = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation)
        let approval = packet("{\"id\":42,\"method\":\"item/fileChange/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"item-1\"}}")
        let events = try reducer.receive(approval, generation: generation)
        guard case .serverRequest(let request) = try XCTUnwrap(events.first) else { return XCTFail("request missing") }
        try reducer.respondToServerRequest(request.id, result: .object(["decision": .string("decline")]), generation: generation)
        let wrong = packet("{\"method\":\"serverRequest/resolved\",\"params\":{\"threadId\":\"thread-other\",\"requestId\":42}}")
        XCTAssertEqual(try reducer.receive(wrong, generation: generation), [.ignoredUnrelatedEvent("serverRequest/resolved")])
        XCTAssertNotNil(reducer.pendingServerRequests[request.id])
        XCTAssertEqual(reducer.outboundPacketCount, 1)
        let correct = packet("{\"method\":\"serverRequest/resolved\",\"params\":{\"threadId\":\"thread-1\",\"requestId\":42}}")
        XCTAssertEqual(try reducer.receive(correct, generation: generation), [.serverRequestResolved(request.id)])
        XCTAssertNil(reducer.pendingServerRequests[request.id])
        XCTAssertNil(dequeue(&reducer))
    }

    func testResolvedFromWrongThreadCannotClearDeferredApproval() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "edit")
        _ = dequeue(&reducer)
        let approval = packet("{\"id\":43,\"method\":\"item/fileChange/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"item-1\"}}")
        XCTAssertEqual(try reducer.receive(approval, generation: generation), [])
        let wrong = packet("{\"method\":\"serverRequest/resolved\",\"params\":{\"threadId\":\"thread-other\",\"requestId\":43}}")
        XCTAssertEqual(try reducer.receive(wrong, generation: generation), [.ignoredUnrelatedEvent("serverRequest/resolved")])
        let events = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation)
        XCTAssertEqual(events.count, 2)
        XCTAssertNotNil(reducer.pendingServerRequests[CodexServerRequestID(.integer(43))])
    }

    func testResolvedRejectedRequestOnlyDropsSameThreadQueuedError() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let rejected = packet("{\"id\":90,\"method\":\"item/fileChange/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-old\"}}")
        let requestID = CodexServerRequestID(.integer(90))
        XCTAssertEqual(try reducer.receive(rejected, generation: generation),
                       [.serverRequestRejected(id: requestID, method: "item/fileChange/requestApproval")])
        XCTAssertEqual(reducer.outboundPacketCount, 1)

        let wrong = packet("{\"method\":\"serverRequest/resolved\",\"params\":{\"threadId\":\"thread-other\",\"requestId\":90}}")
        XCTAssertEqual(try reducer.receive(wrong, generation: generation),
                       [.ignoredUnrelatedEvent("serverRequest/resolved")])
        XCTAssertEqual(reducer.outboundPacketCount, 1)

        let correct = packet("{\"method\":\"serverRequest/resolved\",\"params\":{\"threadId\":\"thread-1\",\"requestId\":90}}")
        XCTAssertEqual(try reducer.receive(correct, generation: generation), [.serverRequestResolved(requestID)])
        XCTAssertEqual(reducer.outboundPacketCount, 0)
        XCTAssertNil(dequeue(&reducer))
    }

    func testQueuedRejectedReplyOwnsWireIDUntilWritten() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let rejected = packet("{\"id\":91,\"method\":\"item/fileChange/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-old\"}}")
        XCTAssertEqual(try reducer.receive(rejected, generation: generation),
                       [.serverRequestRejected(id: CodexServerRequestID(.integer(91)), method: "item/fileChange/requestApproval")])
        XCTAssertThrowsError(try reducer.receive(rejected, generation: generation)) { error in
            XCTAssertEqual(error as? CodexProtocolError, .tooManyPendingServerRequests)
        }
        XCTAssertEqual(reducer.connectionState, .failed(.tooManyPendingServerRequests))
        XCTAssertNil(dequeue(&reducer))
    }

    func testErrorNotificationMustMatchActiveThreadAndTurn() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "edit")
        _ = dequeue(&reducer)
        _ = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation)
        func error(_ thread: String, _ turn: String) -> Data {
            packet("{\"method\":\"error\",\"params\":{\"threadId\":\"\(thread)\",\"turnId\":\"\(turn)\",\"error\":{\"message\":\"offline\"}}}")
        }
        XCTAssertEqual(try reducer.receive(error("thread-other", "turn-1"), generation: generation), [.ignoredUnrelatedEvent("error")])
        XCTAssertEqual(try reducer.receive(error("thread-1", "turn-old"), generation: generation), [.ignoredUnrelatedEvent("error")])
        XCTAssertEqual(try reducer.receive(error("thread-1", "turn-1"), generation: generation), [.rpcError(method: "turn", code: 0, message: "offline")])
        _ = try reducer.receive(packet("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"thread-1\",\"turn\":{\"id\":\"turn-1\",\"status\":\"failed\"}}}"), generation: generation)
        XCTAssertEqual(try reducer.receive(error("thread-1", "turn-1"), generation: generation), [.ignoredUnrelatedEvent("error")])
    }

    func testDeferredItemFloodFailsClosedAtBound() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        _ = try reducer.startTurn(threadID: "thread-1", text: "test")
        _ = dequeue(&reducer)
        let delta = packet("{\"method\":\"item/agentMessage/delta\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-1\",\"itemId\":\"item-1\",\"delta\":\"a\"}}")
        for _ in 0..<128 {
            XCTAssertEqual(try reducer.receive(delta, generation: generation), [])
        }
        XCTAssertThrowsError(try reducer.receive(delta, generation: generation)) { error in
            XCTAssertEqual(error as? CodexProtocolError, .tooManyDeferredItems)
        }
        XCTAssertEqual(reducer.connectionState, .failed(.tooManyDeferredItems))
    }

    func testEarlyApprovalWaitsForMatchingTurnResponseWithoutAutoDecision() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "edit")
        _ = dequeue(&reducer)
        let approval = packet("{\"id\":42,\"method\":\"item/fileChange/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-new\",\"itemId\":\"item-1\"}}")
        XCTAssertEqual(try reducer.receive(approval, generation: generation), [])
        XCTAssertTrue(reducer.pendingServerRequests.isEmpty)
        XCTAssertEqual(reducer.outboundPacketCount, 0)
        let events = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-new\"}}}"), generation: generation)
        XCTAssertEqual(events.first, .turnStarted(threadID: "thread-1", turnID: "turn-new"))
        guard events.count == 2, case .serverRequest(let request) = events[1] else {
            return XCTFail("matching approval was not delivered")
        }
        XCTAssertEqual(request.id, CodexServerRequestID(.integer(42)))
        XCTAssertNotNil(reducer.pendingServerRequests[request.id])
        XCTAssertEqual(reducer.outboundPacketCount, 0)
    }

    func testOldApprovalIsRejectedAndUnscopedElicitationFailsClosed() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let firstID = try reducer.startTurn(threadID: "thread-1", text: "first")
        _ = dequeue(&reducer)
        _ = try reducer.receive(packet("{\"id\":\(idNumber(firstID)),\"result\":{\"turn\":{\"id\":\"turn-old\"}}}"), generation: generation)
        _ = try reducer.receive(packet("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"thread-1\",\"turn\":{\"id\":\"turn-old\",\"status\":\"completed\"}}}"), generation: generation)
        let nextID = try reducer.startTurn(threadID: "thread-1", text: "next")
        _ = dequeue(&reducer)
        let oldApproval = packet("{\"id\":43,\"method\":\"item/commandExecution/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-old\",\"itemId\":\"old-item\"}}")
        XCTAssertEqual(try reducer.receive(oldApproval, generation: generation), [])
        let unscoped = packet("{\"id\":44,\"method\":\"mcpServer/elicitation/request\",\"params\":{\"threadId\":\"thread-1\",\"serverName\":\"circlr\"}}")
        XCTAssertEqual(try reducer.receive(unscoped, generation: generation),
                       [.serverRequestRejected(id: CodexServerRequestID(.integer(44)), method: "mcpServer/elicitation/request")])
        let unscopedReply = try XCTUnwrap(dequeue(&reducer))
        let unscopedJSON = try JSONDecoder().decode(CodexJSONValue.self, from: unscopedReply)
        XCTAssertEqual(unscopedJSON["id"], .integer(44))
        XCTAssertEqual(unscopedJSON["error"]?["code"], .integer(-32602))
        let events = try reducer.receive(packet("{\"id\":\(idNumber(nextID)),\"result\":{\"turn\":{\"id\":\"turn-new\"}}}"), generation: generation)
        XCTAssertEqual(events, [.turnStarted(threadID: "thread-1", turnID: "turn-new"),
                                .serverRequestRejected(id: CodexServerRequestID(.integer(43)), method: "item/commandExecution/requestApproval")])
        let oldReply = try XCTUnwrap(dequeue(&reducer))
        let oldJSON = try JSONDecoder().decode(CodexJSONValue.self, from: oldReply)
        XCTAssertEqual(oldJSON["id"], .integer(43))
        XCTAssertEqual(oldJSON["error"]?["code"], .integer(-32602))
        XCTAssertTrue(reducer.pendingServerRequests.isEmpty)
    }

    func testUnscopedMCPRequestIsRejectedEvenAfterTurnStart() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "edit")
        _ = dequeue(&reducer)
        _ = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-1\"}}}"), generation: generation)
        let unscoped = packet("{\"id\":81,\"method\":\"mcpServer/elicitation/request\",\"params\":{\"threadId\":\"thread-1\",\"serverName\":\"circlr\"}}")
        XCTAssertEqual(try reducer.receive(unscoped, generation: generation),
                       [.serverRequestRejected(id: CodexServerRequestID(.integer(81)), method: "mcpServer/elicitation/request")])
        XCTAssertTrue(reducer.pendingServerRequests.isEmpty)
        let reply = try XCTUnwrap(dequeue(&reducer))
        let json = try JSONDecoder().decode(CodexJSONValue.self, from: reply)
        XCTAssertEqual(json["error"]?["code"], .integer(-32602))
    }

    func testDeferredApprovalBoundAndResolutionBeforeStartResponse() throws {
        var reducer = CodexEventReducer(maximumPendingServerRequests: 2)
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "edit")
        _ = dequeue(&reducer)
        func approval(_ id: Int) -> Data {
            packet("{\"id\":\(id),\"method\":\"item/fileChange/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-new\",\"itemId\":\"item-\(id)\"}}")
        }
        XCTAssertEqual(try reducer.receive(approval(51), generation: generation), [])
        XCTAssertEqual(try reducer.receive(approval(52), generation: generation), [])
        let resolved = packet("{\"method\":\"serverRequest/resolved\",\"params\":{\"threadId\":\"thread-1\",\"requestId\":51}}")
        XCTAssertEqual(try reducer.receive(resolved, generation: generation),
                       [.serverRequestResolved(CodexServerRequestID(.integer(51)))])
        let events = try reducer.receive(packet("{\"id\":\(idNumber(startID)),\"result\":{\"turn\":{\"id\":\"turn-new\"}}}"), generation: generation)
        XCTAssertEqual(events.count, 2)
        XCTAssertNil(reducer.pendingServerRequests[CodexServerRequestID(.integer(51))])
        XCTAssertNotNil(reducer.pendingServerRequests[CodexServerRequestID(.integer(52))])

        var bounded = CodexEventReducer(maximumPendingServerRequests: 2)
        let boundedGeneration = try handshake(&bounded)
        _ = try bounded.startTurn(threadID: "thread-1", text: "edit")
        _ = dequeue(&bounded)
        XCTAssertEqual(try bounded.receive(approval(61), generation: boundedGeneration), [])
        XCTAssertEqual(try bounded.receive(approval(62), generation: boundedGeneration), [])
        XCTAssertThrowsError(try bounded.receive(approval(63), generation: boundedGeneration)) { error in
            XCTAssertEqual(error as? CodexProtocolError, .tooManyPendingServerRequests)
        }
        XCTAssertEqual(bounded.connectionState, .failed(.tooManyPendingServerRequests))
    }

    func testTurnStartRPCErrorRejectsDeferredApproval() throws {
        var reducer = CodexEventReducer()
        let generation = try handshake(&reducer)
        let startID = try reducer.startTurn(threadID: "thread-1", text: "edit")
        _ = dequeue(&reducer)
        let approval = packet("{\"id\":71,\"method\":\"item/fileChange/requestApproval\",\"params\":{\"threadId\":\"thread-1\",\"turnId\":\"turn-unknown\",\"itemId\":\"item-1\"}}")
        XCTAssertEqual(try reducer.receive(approval, generation: generation), [])
        let error = packet("{\"id\":\(idNumber(startID)),\"error\":{\"code\":-32001,\"message\":\"overloaded\"}}")
        XCTAssertEqual(try reducer.receive(error, generation: generation),
                       [.rpcError(method: "turn/start", code: -32001, message: "overloaded"),
                        .serverRequestRejected(id: CodexServerRequestID(.integer(71)), method: "item/fileChange/requestApproval")])
        XCTAssertEqual(reducer.turnState, .failed)
        let reply = try XCTUnwrap(dequeue(&reducer))
        let replyJSON = try JSONDecoder().decode(CodexJSONValue.self, from: reply)
        XCTAssertEqual(replyJSON["id"], .integer(71))
        XCTAssertEqual(replyJSON["error"]?["code"], .integer(-32602))
        XCTAssertTrue(reducer.pendingServerRequests.isEmpty)
    }

    private func idNumber(_ id: CodexClientRequestID) -> Int {
        guard case .integer(let value) = id.value else { return -1 }
        return value
    }
}

private extension CodexJSONValue {
    subscript(_ index: Int) -> CodexJSONValue? {
        guard case .array(let values) = self, values.indices.contains(index) else { return nil }
        return values[index]
    }
}
