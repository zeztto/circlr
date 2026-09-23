import Foundation

public enum CodexConnectionState: Equatable {
    case stopped
    case initializing
    /// Handshake complete only; account, policy and circlr MCP are not verified.
    case protocolReady
    case failed(CodexProtocolError)
}

public enum CodexTurnState: Equatable {
    case idle, starting, running, cancelling, completed, interrupted, failed
}

public struct CodexPendingServerRequest: Equatable {
    public let id: CodexServerRequestID
    public let method: String
    public let threadID: String?
    public let turnID: String?
    public let params: CodexJSONValue
}

public enum CodexEvent: Equatable {
    case protocolReady
    case accountRead(CodexAccountSummary)
    case modelsListed(CodexModelPage)
    case threadOpened(threadID: String)
    case turnStarted(threadID: String, turnID: String)
    case turnCompleted(threadID: String, turnID: String, status: CodexTurnState, error: String?)
    case assistantDelta(itemID: String, text: String)
    case assistantFinal(itemID: String, text: String)
    case serverRequest(CodexPendingServerRequest)
    case serverRequestRejected(id: CodexServerRequestID, method: String)
    case serverRequestResolved(CodexServerRequestID)
    case rpcError(method: String, code: Int, message: String)
    case unknownNotification(String)
    case ignoredStaleGeneration
    case ignoredUnrelatedEvent(String)
}

/// Pure, Foundation-only app-server session reducer. The host owns Process/pipe IO
/// and passes its generation token with every read, preventing an old child's late
/// output from mutating a replacement connection. It does not confer DAW permissions.
public struct CodexEventReducer {
    private struct DeferredCompletion {
        let status: CodexTurnState
        let error: String?
    }

    private struct QueuedRejectedReply {
        let threadID: String?
    }

    private enum DeferredEvent {
        case delta(itemID: String, text: String)
        case final(itemID: String, text: String)
        case serverRequest(CodexPendingServerRequest)

        var byteCount: Int {
            switch self {
            case .delta(let id, let text), .final(let id, let text):
                return id.utf8.count + text.utf8.count
            case .serverRequest(let request):
                let paramsBytes = (try? JSONEncoder().encode(request.params).count) ?? Int.max
                let methodBytes = request.method.utf8.count
                guard paramsBytes <= Int.max - methodBytes else { return Int.max }
                return methodBytes + paramsBytes
            }
        }
    }

    private struct DeferredTurnEvents {
        var completion: DeferredCompletion?
        var events: [DeferredEvent] = []
    }

    private static let supportedServerRequestMethods: Set<String> = [
        "item/commandExecution/requestApproval",
        "item/fileChange/requestApproval",
        "item/permissions/requestApproval",
        "item/tool/requestUserInput",
        "mcpServer/elicitation/request"
    ]

    private enum PendingClientRequest {
        case initialize
        case accountRead
        case modelList
        case threadStart
        case turnStart(threadID: String, serial: UInt64)
        case interrupt(threadID: String, turnID: String, serial: UInt64)

        var method: String {
            switch self {
            case .initialize: return "initialize"
            case .accountRead: return "account/read"
            case .modelList: return "model/list"
            case .threadStart: return "thread/start"
            case .turnStart: return "turn/start"
            case .interrupt: return "turn/interrupt"
            }
        }
    }

    public private(set) var generation: UInt64 = 0
    public private(set) var connectionState: CodexConnectionState = .stopped
    public private(set) var turnState: CodexTurnState = .idle
    public private(set) var activeThreadID: String?
    public private(set) var activeTurnID: String?
    private var openedReadOnlyThreadID: String?
    private let requiresManagedThread: Bool
    private let authorizedThreadCWD: String?
    public private(set) var pendingServerRequests: [CodexServerRequestID: CodexPendingServerRequest] = [:]
    private var answeredServerRequests: Set<CodexServerRequestID> = []
    private var queuedRejectedReplies: [CodexServerRequestID: QueuedRejectedReply] = [:]
    public var outboundPacketCount: Int { outbound.packetCount }
    public var outboundQueuedBytes: Int { outbound.queuedBytes }

    private var nextClientID = 1
    private var turnSerial: UInt64 = 0
    private var framing: CodexJSONLFramer
    private var outbound: CodexOutboundQueue
    private var pendingClientRequests: [CodexClientRequestID: PendingClientRequest] = [:]
    private let maximumPendingClientRequests = 64
    private let maximumRetiredClientIDs = 128
    private var retiredClientIDs: [CodexClientRequestID] = []
    private var retiredClientIDSet: Set<CodexClientRequestID> = []
    private var deferredTurnEvents: [String: DeferredTurnEvents] = [:]
    private let maximumDeferredTurns = 64
    private let maximumDeferredEvents = 128
    private let maximumDeferredEventBytes = 1_048_576
    private var deferredEventCount = 0
    private var deferredEventBytes = 0
    private var deferredServerRequestIDs: Set<CodexServerRequestID> = []
    /// Only byte counts are retained; full text leaves through CodexEvent.
    private var assistantByteCountByItem: [String: Int] = [:]
    private var assistantTextBytes = 0
    private let maximumAssistantItems: Int
    private let maximumPendingServerRequests: Int
    private let maximumAssistantTextBytes: Int
    private var interruptSent = false

    public init(maximumLineBytes: Int = 1_048_576,
                maximumMessagesPerRead: Int = 128,
                maximumOutboundPackets: Int = 64,
                maximumOutboundBytes: Int = 1_048_576,
                maximumPendingServerRequests: Int = 64,
                maximumAssistantItems: Int = 256,
                maximumAssistantTextBytes: Int = 1_048_576,
                authorizedThreadCWD: String? = nil) {
        precondition(maximumPendingServerRequests > 0 && maximumAssistantItems > 0 && maximumAssistantTextBytes > 0)
        self.framing = CodexJSONLFramer(maximumLineBytes: maximumLineBytes,
                                       maximumMessagesPerRead: maximumMessagesPerRead)
        self.outbound = CodexOutboundQueue(maximumPackets: maximumOutboundPackets,
                                           maximumBytes: maximumOutboundBytes)
        self.maximumPendingServerRequests = maximumPendingServerRequests
        self.maximumAssistantItems = maximumAssistantItems
        self.maximumAssistantTextBytes = maximumAssistantTextBytes
        self.requiresManagedThread = authorizedThreadCWD != nil
        // The host must supply its approved workspace directory. A nil value
        // preserves legacy turn-only protocol use, but cannot open a thread.
        // An invalid supplied path remains managed and fails closed.
        self.authorizedThreadCWD = authorizedThreadCWD.flatMap(Self.canonicalDirectoryPath)
    }

    private static func canonicalDirectoryPath(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return canonical
    }

    /// Start a new *transport* generation. Call only after the previous child is
    /// stopped or being discarded; never reuse a generation for a new process.
    @discardableResult
    public mutating func start(clientName: String = "circlr", title: String = "circlr",
                               version: String) throws -> UInt64 {
        guard generation < UInt64.max, !clientName.isEmpty, !title.isEmpty, !version.isEmpty else {
            throw CodexProtocolError.invalidState
        }
        generation += 1
        framing.reset()
        outbound.clear()
        pendingClientRequests.removeAll()
        retiredClientIDs.removeAll()
        retiredClientIDSet.removeAll()
        clearDeferred()
        pendingServerRequests.removeAll()
        answeredServerRequests.removeAll()
        queuedRejectedReplies.removeAll()
        assistantByteCountByItem.removeAll()
        assistantTextBytes = 0
        activeThreadID = nil
        activeTurnID = nil
        openedReadOnlyThreadID = nil
        turnState = .idle
        turnSerial = 0
        interruptSent = false
        connectionState = .initializing
        do {
            _ = try send(method: "initialize", params: .object([
                "clientInfo": .object([
                    "name": .string(clientName), "title": .string(title), "version": .string(version)
                ])
            ]), pending: .initialize)
        } catch let error as CodexProtocolError {
            fail(error)
            throw error
        } catch {
            fail(.malformedEnvelope)
            throw CodexProtocolError.malformedEnvelope
        }
        return generation
    }

    public mutating func stop() {
        framing.reset()
        outbound.clear()
        pendingClientRequests.removeAll()
        retiredClientIDs.removeAll()
        retiredClientIDSet.removeAll()
        clearDeferred()
        pendingServerRequests.removeAll()
        answeredServerRequests.removeAll()
        queuedRejectedReplies.removeAll()
        assistantByteCountByItem.removeAll()
        assistantTextBytes = 0
        activeThreadID = nil
        activeTurnID = nil
        openedReadOnlyThreadID = nil
        turnState = .idle
        interruptSent = false
        connectionState = .stopped
    }

    public mutating func processEnded(generation observedGeneration: UInt64) {
        guard observedGeneration == generation, connectionState != .stopped else { return }
        fail(.invalidState)
    }

    /// A writer must present the generation of the child process it owns.
    /// A stale writer receives no packet and cannot drain a replacement child's
    /// initialize or turn request.
    public mutating func dequeueOutbound(generation observedGeneration: UInt64) -> Data? {
        guard observedGeneration == generation,
              connectionState == .initializing || connectionState == .protocolReady else {
            return nil
        }
        guard let packet = outbound.dequeuePacket() else { return nil }
        if let id = packet.serverRequestID { queuedRejectedReplies.removeValue(forKey: id) }
        return packet.data
    }

    @discardableResult
    public mutating func startTurn(threadID: String, text: String,
                                   model: String? = nil) throws -> CodexClientRequestID {
        guard connectionState == .protocolReady,
              turnState != .starting, turnState != .running, turnState != .cancelling,
              !pendingClientRequests.values.contains(where: { if case .threadStart = $0 { return true }; return false }),
              turnSerial < UInt64.max,
              !threadID.isEmpty, !text.isEmpty,
              !requiresManagedThread || openedReadOnlyThreadID == threadID,
              model.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true else {
            throw CodexProtocolError.invalidState
        }
        let input: CodexJSONValue = .array([.object(["type": .string("text"), "text": .string(text)])])
        let nextSerial = turnSerial + 1
        var params: [String: CodexJSONValue] = [
            "threadId": .string(threadID), "input": input
        ]
        if let model { params["model"] = .string(model) }
        let id = try send(method: "turn/start", params: .object(params),
                          pending: .turnStart(threadID: threadID, serial: nextSerial))
        turnSerial = nextSerial
        activeThreadID = threadID
        activeTurnID = nil
        turnState = .starting
        interruptSent = false
        assistantByteCountByItem.removeAll()
        assistantTextBytes = 0
        pendingServerRequests.removeAll()
        answeredServerRequests.removeAll()
        clearDeferred()
        return id
    }

    /// Read only the account's authentication mode and plan. The response's
    /// email and any future credential fields are discarded by the projection.
    @discardableResult
    public mutating func readAccount(refreshToken: Bool = false) throws -> CodexClientRequestID {
        guard connectionState == .protocolReady,
              !pendingClientRequests.values.contains(where: { if case .accountRead = $0 { return true }; return false }) else {
            throw CodexProtocolError.invalidState
        }
        return try send(method: "account/read", params: .object([
            "refreshToken": .bool(refreshToken)
        ]), pending: .accountRead)
    }

    /// Page through the current account's visible model catalog before choosing
    /// a model for `thread/start` and `turn/start`.
    @discardableResult
    public mutating func listModels(cursor: String? = nil) throws -> CodexClientRequestID {
        guard connectionState == .protocolReady,
              cursor.map({ !$0.isEmpty }) ?? true,
              !pendingClientRequests.values.contains(where: { if case .modelList = $0 { return true }; return false }) else {
            throw CodexProtocolError.invalidState
        }
        var params: [String: CodexJSONValue] = ["includeHidden": .bool(false)]
        if let cursor { params["cursor"] = .string(cursor) }
        return try send(method: "model/list", params: .object(params), pending: .modelList)
    }

    /// The caller must choose `model` from this app-server's `model/list` catalog
    /// and construct this reducer with a trusted, approved workspace directory.
    /// The app-server sandbox stays read-only; music writes use the separate
    /// TrustedAgentGateway lease and revision boundary.
    @discardableResult
    public mutating func startThread(model: String, cwd: String) throws -> CodexClientRequestID {
        guard connectionState == .protocolReady,
              turnState != .starting, turnState != .running, turnState != .cancelling,
              !pendingClientRequests.values.contains(where: { if case .threadStart = $0 { return true }; return false }),
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let authorizedThreadCWD,
              Self.canonicalDirectoryPath(cwd) == authorizedThreadCWD else {
            throw CodexProtocolError.invalidState
        }
        return try send(method: "thread/start", params: .object([
            "model": .string(model), "cwd": .string(authorizedThreadCWD),
            "sandbox": .string("read-only"), "approvalPolicy": .string("never")
        ]), pending: .threadStart)
    }

    /// Cancellation is a request. Only a matching `turn/completed` event confirms
    /// interruption; cancelling before the start response defers the RPC until
    /// the server supplies a turn ID.
    public mutating func interruptActiveTurn() throws {
        guard turnState == .starting || turnState == .running || turnState == .cancelling else {
            throw CodexProtocolError.invalidState
        }
        if turnState == .cancelling { return }
        if let threadID = activeThreadID, let turnID = activeTurnID {
            try sendInterrupt(threadID: threadID, turnID: turnID)
        }
        turnState = .cancelling
    }

    /// The P1 layer has no approval authority. P3's gateway must gate any accepted
    /// result before calling this, and only a request from this generation may be
    /// answered. Clearing on completion/resolution prevents a late duplicate reply.
    public mutating func respondToServerRequest(_ id: CodexServerRequestID,
                                                result: CodexJSONValue,
                                                generation observedGeneration: UInt64) throws {
        guard observedGeneration == generation else { throw CodexProtocolError.staleGeneration }
        guard connectionState == .protocolReady,
              pendingServerRequests[id] != nil,
              !answeredServerRequests.contains(id) else { throw CodexProtocolError.invalidState }
        let packet = try CodexWire.serverReply(id: id, result: result)
        try outbound.enqueue(packet, serverRequestID: id)
        answeredServerRequests.insert(id)
    }

    /// Decline a pending server request without granting a capability. The
    /// offline coordinator uses this until a separate, trusted approval owner
    /// exists. A resolved, answered, or previous-generation request cannot be
    /// revived by a late UI action.
    public mutating func declineServerRequest(_ id: CodexServerRequestID,
                                              generation observedGeneration: UInt64) throws -> CodexEvent {
        guard observedGeneration == generation else { throw CodexProtocolError.staleGeneration }
        guard connectionState == .protocolReady,
              let request = pendingServerRequests[id],
              !answeredServerRequests.contains(id) else { throw CodexProtocolError.invalidState }
        let events = try rejectServerRequest(id: id, method: request.method,
                                             threadID: request.threadID,
                                             message: "circlr approval is unavailable")
        pendingServerRequests.removeValue(forKey: id)
        return events[0]
    }

    public mutating func receive(_ bytes: Data, generation observedGeneration: UInt64) throws -> [CodexEvent] {
        guard observedGeneration == generation else { return [.ignoredStaleGeneration] }
        guard connectionState == .initializing || connectionState == .protocolReady else {
            throw CodexProtocolError.invalidState
        }
        do {
            let lines = try framing.append(bytes)
            var events: [CodexEvent] = []
            for line in lines { events += try reduce(CodexWire.decode(line)) }
            return events
        } catch let error as CodexProtocolError {
            fail(error)
            throw error
        } catch {
            fail(.malformedEnvelope)
            throw CodexProtocolError.malformedEnvelope
        }
    }

    private mutating func send(method: String, params: CodexJSONValue,
                               pending: PendingClientRequest) throws -> CodexClientRequestID {
        guard nextClientID < Int.max else { throw CodexProtocolError.invalidState }
        guard pendingClientRequests.count < maximumPendingClientRequests else {
            fail(.tooManyPendingClientRequests)
            throw CodexProtocolError.tooManyPendingClientRequests
        }
        let id = CodexClientRequestID(nextClientID)
        try outbound.enqueue(CodexWire.request(id: id, method: method, params: params))
        nextClientID += 1
        pendingClientRequests[id] = pending
        return id
    }

    private mutating func sendInterrupt(threadID: String, turnID: String) throws {
        guard !interruptSent else { return }
        _ = try send(method: "turn/interrupt", params: .object([
            "threadId": .string(threadID), "turnId": .string(turnID)
        ]), pending: .interrupt(threadID: threadID, turnID: turnID, serial: turnSerial))
        interruptSent = true
    }

    private mutating func fail(_ error: CodexProtocolError) {
        connectionState = .failed(error)
        turnState = .failed
        framing.reset()
        outbound.clear()
        pendingClientRequests.removeAll()
        retiredClientIDs.removeAll()
        retiredClientIDSet.removeAll()
        clearDeferred()
        pendingServerRequests.removeAll()
        answeredServerRequests.removeAll()
        queuedRejectedReplies.removeAll()
        assistantByteCountByItem.removeAll()
        assistantTextBytes = 0
    }

    private mutating func reduce(_ message: CodexWireMessage) throws -> [CodexEvent] {
        switch message {
        case .response(let id, let result, let error):
            guard let pending = pendingClientRequests.removeValue(forKey: id) else {
                if retiredClientIDSet.contains(id) {
                    return [.ignoredUnrelatedEvent("retiredResponse")]
                }
                throw CodexProtocolError.unexpectedResponse
            }
            if let error {
                // Account and catalog RPC errors are server-controlled text. Do
                // not forward an address or credential embedded in that text.
                let publicMessage = pending.method == "account/read" || pending.method == "model/list"
                    ? "Codex request failed" : error.message
                if pending.method == "initialize" { fail(.invalidState) }
                else if case .turnStart(_, let serial) = pending,
                        serial == turnSerial, isTurnActive {
                    turnState = .failed
                    let rejections = try rejectAllDeferredServerRequests()
                    return [.rpcError(method: pending.method, code: error.code,
                                      message: publicMessage)] + rejections
                }
                else if case .interrupt(let threadID, let turnID, let serial) = pending,
                        serial == turnSerial,
                        activeThreadID == threadID, activeTurnID == turnID,
                        turnState == .cancelling {
                    turnState = .running
                    interruptSent = false
                }
                return [.rpcError(method: pending.method, code: error.code, message: publicMessage)]
            }
            guard let result else { throw CodexProtocolError.malformedEnvelope }
            switch pending {
            case .initialize:
                guard connectionState == .initializing, result.object != nil else {
                    throw CodexProtocolError.malformedEnvelope
                }
                try outbound.enqueue(CodexWire.notification(method: "initialized"))
                connectionState = .protocolReady
                return [.protocolReady]
            case .accountRead:
                guard connectionState == .protocolReady else { throw CodexProtocolError.invalidState }
                return [.accountRead(try CodexAccountSummary(json: result))]
            case .modelList:
                guard connectionState == .protocolReady else { throw CodexProtocolError.invalidState }
                return [.modelsListed(try CodexModelPage(json: result))]
            case .threadStart:
                guard connectionState == .protocolReady else { throw CodexProtocolError.invalidState }
                guard let threadID = result["thread"]?["id"]?.string, !threadID.isEmpty else {
                    throw CodexProtocolError.requiredField("thread.id")
                }
                activeThreadID = threadID
                openedReadOnlyThreadID = threadID
                activeTurnID = nil
                turnState = .idle
                return [.threadOpened(threadID: threadID)]
            case .turnStart(let threadID, let serial):
                guard serial == turnSerial else { return [.ignoredUnrelatedEvent("turn/start")] }
                guard let turnID = result["turn"]?["id"]?.string, !turnID.isEmpty else {
                    throw CodexProtocolError.requiredField("turn.id")
                }
                let deferred = deferredTurnEvents[turnID]
                let mismatchedRequests = deferredTurnEvents
                    .filter { $0.key != turnID }
                    .values.flatMap { entry in entry.events.compactMap { event -> CodexPendingServerRequest? in
                        if case .serverRequest(let request) = event { return request }
                        return nil
                    } }
                clearDeferred()
                var events = try adoptTurn(threadID: threadID, turnID: turnID,
                                           sendPendingInterrupt: deferred?.completion == nil)
                for request in mismatchedRequests {
                    events += try rejectServerRequest(id: request.id, method: request.method,
                                                      threadID: request.threadID)
                }
                for event in deferred?.events ?? [] {
                    switch event {
                    case .delta(let itemID, let text):
                        events += try appendAssistantDelta(itemID: itemID, text: text)
                    case .final(let itemID, let text):
                        events += try finalizeAssistantItem(itemID: itemID, text: text)
                    case .serverRequest(let request):
                        if deferred?.completion != nil {
                            events += try rejectServerRequest(id: request.id, method: request.method,
                                                              threadID: request.threadID)
                        } else {
                            guard pendingServerRequests.count < maximumPendingServerRequests else {
                                throw CodexProtocolError.tooManyPendingServerRequests
                            }
                            pendingServerRequests[request.id] = request
                            events.append(.serverRequest(request))
                        }
                    }
                }
                if let completion = deferred?.completion {
                    events += finishTurn(threadID: threadID, turnID: turnID,
                                         status: completion.status, error: completion.error)
                }
                return events
            case .interrupt:
                // The empty RPC result acknowledges receipt, not completion.
                guard result.object != nil else { throw CodexProtocolError.malformedEnvelope }
                return []
            }

        case .notification(let method, let params):
            return try reduceNotification(method: method, params: params)

        case .serverRequest(let id, let method, let params):
            guard connectionState == .protocolReady else { throw CodexProtocolError.invalidState }
            // Pending approvals and queued declines own their wire IDs until
            // resolved or written, regardless of the incoming method.
            guard queuedRejectedReplies[id] == nil,
                  pendingServerRequests[id] == nil,
                  !deferredServerRequestIDs.contains(id),
                  pendingServerRequests.count < maximumPendingServerRequests else {
                throw CodexProtocolError.tooManyPendingServerRequests
            }
            guard Self.supportedServerRequestMethods.contains(method) else {
                return try rejectServerRequest(id: id, method: method,
                                               threadID: params["threadId"]?.string,
                                               code: -32601, message: "Unsupported server request")
            }
            let threadID = params["threadId"]?.string
            let turnID = params["turnId"]?.string
            guard threadID != nil else {
                return try rejectServerRequest(id: id, method: method, threadID: nil)
            }
            if let threadID, threadID != activeThreadID {
                return try rejectServerRequest(id: id, method: method, threadID: threadID)
            }
            guard isTurnActive else {
                return try rejectServerRequest(id: id, method: method, threadID: threadID)
            }
            if activeTurnID == nil {
                // An optional-turnId elicitation cannot be scoped while start is
                // pending. Requests with IDs wait for the authoritative response.
                guard let turnID else {
                    return try rejectServerRequest(id: id, method: method, threadID: threadID)
                }
                if deferredTurnEvents[turnID]?.completion != nil {
                    return try rejectServerRequest(id: id, method: method, threadID: threadID)
                }
                let request = CodexPendingServerRequest(id: id, method: method,
                                                        threadID: threadID, turnID: turnID,
                                                        params: params)
                try deferEvent(.serverRequest(request), turnID: turnID)
                return []
            }
            if let turnID, turnID != activeTurnID {
                return try rejectServerRequest(id: id, method: method, threadID: threadID)
            }
            // MCP elicitation may omit turnId on the wire. This P1 layer cannot
            // prove that such a request belongs to the current turn, even when
            // its threadId matches, so a later gateway must handle that case.
            if turnID == nil {
                return try rejectServerRequest(id: id, method: method, threadID: threadID)
            }
            let request = CodexPendingServerRequest(id: id, method: method,
                                                    threadID: threadID, turnID: turnID,
                                                    params: params)
            pendingServerRequests[id] = request
            return [.serverRequest(request)]
        }
    }

    private mutating func rejectServerRequest(id: CodexServerRequestID,
                                              method: String,
                                              threadID: String?,
                                              code: Int = -32602,
                                              message: String = "Request is outside the active circlr turn") throws -> [CodexEvent] {
        // A JSON-RPC error unblocks the server without granting an unrelated or
        // already-finished turn any permission. The host must flush this packet.
        try outbound.enqueue(CodexWire.serverErrorReply(
            id: id, code: code, message: message
        ), serverRequestID: id)
        queuedRejectedReplies[id] = QueuedRejectedReply(threadID: threadID)
        return [.serverRequestRejected(id: id, method: method)]
    }

    private mutating func adoptTurn(threadID: String, turnID: String,
                                    sendPendingInterrupt: Bool = true) throws -> [CodexEvent] {
        guard activeThreadID == threadID else { return [.ignoredUnrelatedEvent("turn/start")] }
        if let activeTurnID, activeTurnID != turnID { throw CodexProtocolError.malformedEnvelope }
        if activeTurnID == turnID { return [] }
        guard isTurnActive else { return [.ignoredUnrelatedEvent("turn/started")] }
        self.activeTurnID = turnID
        if turnState == .starting { turnState = .running }
        else if turnState == .cancelling && sendPendingInterrupt {
            try sendInterrupt(threadID: threadID, turnID: turnID)
        }
        return [.turnStarted(threadID: threadID, turnID: turnID)]
    }

    private mutating func deferTurn(_ turnID: String,
                                     completion: DeferredCompletion? = nil) throws {
        guard deferredTurnEvents[turnID] != nil || deferredTurnEvents.count < maximumDeferredTurns else {
            throw CodexProtocolError.tooManyDeferredTurns
        }
        var pending = deferredTurnEvents[turnID] ?? DeferredTurnEvents()
        if pending.completion == nil, let completion { pending.completion = completion }
        deferredTurnEvents[turnID] = pending
    }

    private mutating func deferEvent(_ event: DeferredEvent, turnID: String) throws {
        try deferTurn(turnID)
        guard var pending = deferredTurnEvents[turnID] else {
            throw CodexProtocolError.malformedEnvelope
        }
        guard pending.completion == nil else { return }
        guard deferredEventCount < maximumDeferredEvents,
              event.byteCount <= maximumDeferredEventBytes - deferredEventBytes else {
            throw CodexProtocolError.tooManyDeferredItems
        }
        if case .serverRequest(let request) = event {
            guard deferredServerRequestIDs.count < maximumPendingServerRequests,
                  deferredServerRequestIDs.insert(request.id).inserted else {
                throw CodexProtocolError.tooManyPendingServerRequests
            }
        }
        pending.events.append(event)
        deferredTurnEvents[turnID] = pending
        deferredEventCount += 1
        deferredEventBytes += event.byteCount
    }

    private mutating func clearDeferred() {
        deferredTurnEvents.removeAll()
        deferredEventCount = 0
        deferredEventBytes = 0
        deferredServerRequestIDs.removeAll()
    }

    private mutating func rejectAllDeferredServerRequests() throws -> [CodexEvent] {
        let requests = deferredTurnEvents.values.flatMap { entry in
            entry.events.compactMap { event -> CodexPendingServerRequest? in
                if case .serverRequest(let request) = event { return request }
                return nil
            }
        }
        clearDeferred()
        var events: [CodexEvent] = []
        for request in requests {
            events += try rejectServerRequest(id: request.id, method: request.method,
                                              threadID: request.threadID)
        }
        return events
    }

    private mutating func removeDeferredServerRequest(_ id: CodexServerRequestID) -> Bool {
        guard deferredServerRequestIDs.contains(id) else { return false }
        for turnID in Array(deferredTurnEvents.keys) {
            guard var pending = deferredTurnEvents[turnID] else { continue }
            var retained: [DeferredEvent] = []
            for event in pending.events {
                if case .serverRequest(let request) = event, request.id == id {
                    deferredEventCount -= 1
                    deferredEventBytes -= event.byteCount
                } else {
                    retained.append(event)
                }
            }
            pending.events = retained
            deferredTurnEvents[turnID] = pending
        }
        deferredServerRequestIDs.remove(id)
        return true
    }

    private func deferredServerRequest(_ id: CodexServerRequestID) -> CodexPendingServerRequest? {
        guard deferredServerRequestIDs.contains(id) else { return nil }
        for entry in deferredTurnEvents.values {
            for event in entry.events {
                if case .serverRequest(let request) = event, request.id == id {
                    return request
                }
            }
        }
        return nil
    }

    private mutating func appendAssistantDelta(itemID: String, text: String) throws -> [CodexEvent] {
        let priorBytes = assistantByteCountByItem[itemID] ?? 0
        let deltaBytes = text.utf8.count
        guard assistantByteCountByItem[itemID] != nil || assistantByteCountByItem.count < maximumAssistantItems,
              deltaBytes <= maximumAssistantTextBytes - assistantTextBytes else {
            throw CodexProtocolError.accumulatedTextTooLong
        }
        assistantByteCountByItem[itemID] = priorBytes + deltaBytes
        assistantTextBytes += deltaBytes
        return [.assistantDelta(itemID: itemID, text: text)]
    }

    private mutating func finalizeAssistantItem(itemID: String, text: String) throws -> [CodexEvent] {
        let priorBytes = assistantByteCountByItem[itemID] ?? 0
        let finalBytes = text.utf8.count
        guard assistantByteCountByItem[itemID] != nil || assistantByteCountByItem.count < maximumAssistantItems,
              finalBytes <= maximumAssistantTextBytes - (assistantTextBytes - priorBytes) else {
            throw CodexProtocolError.accumulatedTextTooLong
        }
        assistantByteCountByItem[itemID] = finalBytes
        assistantTextBytes = assistantTextBytes - priorBytes + finalBytes
        return [.assistantFinal(itemID: itemID, text: text)]
    }

    private mutating func finishTurn(threadID: String, turnID: String,
                                     status: CodexTurnState, error: String?) -> [CodexEvent] {
        turnState = status
        let finishedInterruptIDs = pendingClientRequests.compactMap { id, request -> CodexClientRequestID? in
            if case .interrupt(let requestThreadID, let requestTurnID, let serial) = request,
               requestThreadID == threadID, requestTurnID == turnID, serial == turnSerial {
                return id
            }
            return nil
        }
        for id in finishedInterruptIDs {
            pendingClientRequests.removeValue(forKey: id)
            retireClientID(id)
        }
        for id in pendingServerRequests.keys { outbound.removeServerReply(id) }
        pendingServerRequests.removeAll()
        answeredServerRequests.removeAll()
        assistantByteCountByItem.removeAll()
        assistantTextBytes = 0
        return [.turnCompleted(threadID: threadID, turnID: turnID,
                               status: status, error: error)]
    }

    private mutating func retireClientID(_ id: CodexClientRequestID) {
        guard retiredClientIDSet.insert(id).inserted else { return }
        retiredClientIDs.append(id)
        if retiredClientIDs.count > maximumRetiredClientIDs {
            let oldest = retiredClientIDs.removeFirst()
            retiredClientIDSet.remove(oldest)
        }
    }

    private mutating func reduceNotification(method: String,
                                             params: CodexJSONValue) throws -> [CodexEvent] {
        switch method {
        case "turn/started":
            guard let threadID = params["threadId"]?.string,
                  let turnID = params["turn"]?["id"]?.string,
                  !threadID.isEmpty, !turnID.isEmpty else {
                throw CodexProtocolError.requiredField("turn/started.threadId/turn.id")
            }
            guard threadID == activeThreadID, isTurnActive else {
                return [.ignoredUnrelatedEvent(method)]
            }
            if activeTurnID == nil {
                try deferTurn(turnID)
                return []
            }
            guard activeTurnID == turnID else { return [.ignoredUnrelatedEvent(method)] }
            return try adoptTurn(threadID: threadID, turnID: turnID)

        case "turn/completed":
            guard let threadID = params["threadId"]?.string,
                  let turnID = params["turn"]?["id"]?.string,
                  let statusValue = params["turn"]?["status"]?.string else {
                throw CodexProtocolError.requiredField("turn/completed.threadId/turn")
            }
            guard threadID == activeThreadID, isTurnActive else {
                return [.ignoredUnrelatedEvent(method)]
            }
            let status: CodexTurnState
            switch statusValue {
            case "completed": status = .completed
            case "interrupted": status = .interrupted
            case "failed": status = .failed
            default: throw CodexProtocolError.malformedEnvelope
            }
            let errorMessage = params["turn"]?["error"]?["message"]?.string
            if activeTurnID == nil {
                // The response is the authority for the new ID. Old completions
                // from this same thread may arrive while turn/start is pending.
                try deferTurn(turnID, completion: DeferredCompletion(status: status, error: errorMessage))
                return []
            }
            guard turnID == activeTurnID else { return [.ignoredUnrelatedEvent(method)] }
            return finishTurn(threadID: threadID, turnID: turnID,
                              status: status, error: errorMessage)

        case "item/agentMessage/delta":
            guard let threadID = params["threadId"]?.string,
                  let turnID = params["turnId"]?.string,
                  let itemID = params["itemId"]?.string,
                  let delta = params["delta"]?.string else {
                throw CodexProtocolError.requiredField("item/agentMessage/delta")
            }
            guard threadID == activeThreadID, isTurnActive else {
                return [.ignoredUnrelatedEvent(method)]
            }
            if activeTurnID == nil {
                try deferEvent(.delta(itemID: itemID, text: delta), turnID: turnID)
                return []
            }
            guard turnID == activeTurnID else { return [.ignoredUnrelatedEvent(method)] }
            return try appendAssistantDelta(itemID: itemID, text: delta)

        case "item/completed":
            guard let threadID = params["threadId"]?.string,
                  let turnID = params["turnId"]?.string else {
                throw CodexProtocolError.requiredField("item/completed.threadId/turnId")
            }
            guard threadID == activeThreadID, isTurnActive else {
                return [.ignoredUnrelatedEvent(method)]
            }
            guard params["item"]?["type"]?.string == "agentMessage",
                  let itemID = params["item"]?["id"]?.string,
                  let final = params["item"]?["text"]?.string else { return [] }
            if activeTurnID == nil {
                try deferEvent(.final(itemID: itemID, text: final), turnID: turnID)
                return []
            }
            guard turnID == activeTurnID else { return [.ignoredUnrelatedEvent(method)] }
            return try finalizeAssistantItem(itemID: itemID, text: final)

        case "serverRequest/resolved":
            guard let threadID = params["threadId"]?.string, !threadID.isEmpty,
                  let rawID = params["requestId"], let value = CodexRPCID(rawID) else {
                throw CodexProtocolError.requiredField("serverRequest/resolved.threadId/requestId")
            }
            let id = CodexServerRequestID(value)
            if let request = pendingServerRequests[id] {
                guard request.threadID == threadID else { return [.ignoredUnrelatedEvent(method)] }
                outbound.removeServerReply(id)
                answeredServerRequests.remove(id)
                pendingServerRequests.removeValue(forKey: id)
                return [.serverRequestResolved(id)]
            }
            if let request = deferredServerRequest(id) {
                guard request.threadID == threadID else { return [.ignoredUnrelatedEvent(method)] }
                _ = removeDeferredServerRequest(id)
                return [.serverRequestResolved(id)]
            }
            if let reply = queuedRejectedReplies[id] {
                guard reply.threadID == threadID else { return [.ignoredUnrelatedEvent(method)] }
                outbound.removeServerReply(id)
                queuedRejectedReplies.removeValue(forKey: id)
                return [.serverRequestResolved(id)]
            }
            return [.ignoredUnrelatedEvent(method)]

        case "error":
            guard let threadID = params["threadId"]?.string,
                  let turnID = params["turnId"]?.string,
                  let message = params["error"]?["message"]?.string else {
                throw CodexProtocolError.requiredField("error.threadId/turnId/message")
            }
            guard threadID == activeThreadID, turnID == activeTurnID, isTurnActive else {
                return [.ignoredUnrelatedEvent(method)]
            }
            // A turn-level error is informational until `turn/completed` supplies
            // the authoritative failed terminal status.
            return [.rpcError(method: "turn", code: 0, message: message)]

        default:
            return [.unknownNotification(method)]
        }
    }

    private var isTurnActive: Bool {
        turnState == .starting || turnState == .running || turnState == .cancelling
    }
}
