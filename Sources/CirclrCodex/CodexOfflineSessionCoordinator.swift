import Foundation

public enum CodexOfflineSessionError: Error, Equatable {
    case invalidState
    case modelCatalogUnavailable
    case modelNotListed
    case modelCatalogInvalid
    case deliveryBackpressure
    case generationMismatch
    case host(CodexProcessHostError)
    case protocolFailure(CodexProtocolError)
    case childExited(CodexProcessExit)
}

public struct CodexOfflineSessionSnapshot: Equatable {
    public let generation: UInt64?
    public let connection: CodexConnectionState
    public let turn: CodexTurnState
    public let threadID: String?
    public let modelIDs: [String]
    public let modelCatalogComplete: Bool
    public let selectedModel: String?
    public let failure: CodexOfflineSessionError?
}

/// Internal, credential-free bridge for a fixed JSONL child fixture. This is
/// deliberately absent from the app target. It is not a production App Server
/// integration: G0 runtime, authentication, policy, MCP and packaging gates
/// remain open. All child callbacks and public mutations are serialized here.
public final class CodexOfflineSessionCoordinator: @unchecked Sendable {
    public typealias UpdateHandler = @Sendable (CodexOfflineSessionSnapshot, [CodexEvent]) -> Void

    private let host: CodexProcessHost
    private let authorizedCWD: String
    private let version: String
    private let onUpdate: UpdateHandler
    private let stateQueue = DispatchQueue(label: "circlr.codex.offline-session.state")
    private let deliveryQueue = DispatchQueue(label: "circlr.codex.offline-session.delivery")
    private var reducer: CodexEventReducer
    private var activeGeneration: UInt64?
    private var deliveryEpoch: UInt64 = 0
    private var pendingDeliveries = 0
    private var pendingDeliveryBytes = 0
    private var terminalUpdateQueued = false
    private var terminalSnapshot: CodexOfflineSessionSnapshot?
    private var terminalRevision: UInt64 = 0
    private var failure: CodexOfflineSessionError?
    private var catalog: [String: CodexModelSummary] = [:]
    private var catalogIDBytes = 0
    private var seenCursors: Set<String> = []
    private var collectingCatalog = false
    private var catalogComplete = false
    private var selectedModel: String?
    private var suppressTurnText = false
    private let maximumCatalogModels = 256
    private let maximumCatalogIDBytes = 262_144
    private let maximumCatalogPages = 32
    private let maximumPendingDeliveries = 32
    private let maximumPendingDeliveryBytes = 2_097_152
    private let terminalReservedBytes = 2_097_152

    public init(host: CodexProcessHost, authorizedThreadCWD: String,
                version: String, onUpdate: @escaping UpdateHandler) {
        precondition(!version.isEmpty)
        self.host = host
        self.authorizedCWD = authorizedThreadCWD
        self.version = version
        self.onUpdate = onUpdate
        self.reducer = CodexEventReducer(authorizedThreadCWD: authorizedThreadCWD)
    }

    deinit { try? host.stop() }

    public var snapshot: CodexOfflineSessionSnapshot {
        stateQueue.sync { snapshotLocked() }
    }

    #if DEBUG
    /// Simulates a callback already queued by a previous child after restart.
    func receiveForTesting(_ bytes: Data, generation: UInt64) {
        stateQueue.sync { receiveLocked(bytes, generation: generation) }
    }

    var pendingDeliveriesForTesting: Int {
        stateQueue.sync { pendingDeliveries }
    }

    func blockStateQueueForTesting(entered: DispatchSemaphore, gate: DispatchSemaphore) {
        stateQueue.async {
            entered.signal()
            gate.wait()
        }
    }

    var hostRunningForTesting: Bool { host.isRunning }
    #endif

    @discardableResult
    public func start() throws -> UInt64 {
        try stateQueue.sync {
            guard activeGeneration == nil else { throw CodexOfflineSessionError.invalidState }
            let generation: UInt64
            do {
                generation = try host.start(onOutput: { [weak self] generation, bytes in
                    // Do not enqueue unbounded raw pipe chunks. Holding this
                    // callback applies the host's byte/chunk backpressure.
                    guard let self else { return }
                    self.stateQueue.sync { self.receiveLocked(bytes, generation: generation) }
                }, onExit: { [weak self] generation, exit in
                    guard let self else { return }
                    self.stateQueue.sync { self.endedLocked(exit, generation: generation) }
                })
            } catch let error as CodexProcessHostError {
                throw CodexOfflineSessionError.host(error)
            }
            do {
                let reducerGeneration = try reducer.start(version: version)
                guard reducerGeneration == generation else {
                    reducer.stop()
                    try? host.stop()
                    throw CodexOfflineSessionError.generationMismatch
                }
                activeGeneration = generation
                deliveryEpoch &+= 1
                terminalSnapshot = nil
                terminalRevision &+= 1
                failure = nil
                catalog.removeAll()
                catalogIDBytes = 0
                seenCursors.removeAll()
                collectingCatalog = false
                catalogComplete = false
                selectedModel = nil
                suppressTurnText = false
                try drainLocked(generation: generation)
                publishLocked([], generation: generation)
                guard activeGeneration == generation else {
                    throw CodexOfflineSessionError.deliveryBackpressure
                }
                return generation
            } catch {
                if activeGeneration == nil { try? host.stop() }
                throw error
            }
        }
    }

    public func stop() throws {
        try stateQueue.sync {
            activeGeneration = nil
            deliveryEpoch &+= 1
            terminalSnapshot = nil
            terminalRevision &+= 1
            reducer.stop()
            catalog.removeAll()
            catalogIDBytes = 0
            seenCursors.removeAll()
            collectingCatalog = false
            catalogComplete = false
            selectedModel = nil
            suppressTurnText = false
            failure = nil
            do { try host.stop() }
            catch let error as CodexProcessHostError { throw CodexOfflineSessionError.host(error) }
        }
    }

    @discardableResult
    public func readAccount() throws -> CodexClientRequestID {
        try mutateLocked { try $0.readAccount() }
    }

    /// Refresh every page. The previous catalog is unavailable until the new
    /// traversal completes; a removed model is never silently replaced.
    @discardableResult
    public func refreshModelCatalog() throws -> CodexClientRequestID {
        try stateQueue.sync {
            guard let generation = activeGeneration, !collectingCatalog else {
                throw CodexOfflineSessionError.invalidState
            }
            catalog.removeAll()
            catalogIDBytes = 0
            seenCursors.removeAll()
            catalogComplete = false
            collectingCatalog = true
            do {
                let id = try reducer.listModels()
                try drainLocked(generation: generation)
                return id
            } catch {
                collectingCatalog = false
                throw error
            }
        }
    }

    @discardableResult
    public func startThread(model: String) throws -> CodexClientRequestID {
        try stateQueue.sync {
            guard catalogComplete else { throw CodexOfflineSessionError.modelCatalogUnavailable }
            guard catalog[model] != nil else { throw CodexOfflineSessionError.modelNotListed }
            guard let generation = activeGeneration else { throw CodexOfflineSessionError.invalidState }
            let id = try reducer.startThread(model: model, cwd: authorizedCWD)
            selectedModel = model
            try drainLocked(generation: generation)
            return id
        }
    }

    @discardableResult
    public func startTurn(threadID: String, text: String) throws -> CodexClientRequestID {
        try stateQueue.sync {
            guard catalogComplete, let selectedModel else {
                throw CodexOfflineSessionError.modelCatalogUnavailable
            }
            guard catalog[selectedModel] != nil else { throw CodexOfflineSessionError.modelNotListed }
            guard let generation = activeGeneration else { throw CodexOfflineSessionError.invalidState }
            let id = try reducer.startTurn(threadID: threadID, text: text, model: selectedModel)
            suppressTurnText = false
            try drainLocked(generation: generation)
            return id
        }
    }

    /// A cancel request fences approvals immediately. It does not claim that
    /// the turn ended; only the matching turn/completed event does that.
    public func cancelTurn() throws {
        try stateQueue.sync {
            guard let generation = activeGeneration else { throw CodexOfflineSessionError.invalidState }
            do { try reducer.interruptActiveTurn() }
            catch {
                failLocked(.invalidState, generation: generation)
                throw error
            }
            suppressTurnText = true
            // Invalidate text already queued for a slow observer. In-flight
            // callbacks may finish, but a queued callback cannot start later.
            deliveryEpoch &+= 1
            var events: [CodexEvent] = []
            for id in Array(reducer.pendingServerRequests.keys) {
                events.append(try reducer.declineServerRequest(id, generation: generation))
            }
            try drainLocked(generation: generation)
            publishLocked(events, generation: generation)
        }
    }

    private func mutateLocked(_ operation: (inout CodexEventReducer) throws -> CodexClientRequestID) throws -> CodexClientRequestID {
        try stateQueue.sync {
            guard let generation = activeGeneration else { throw CodexOfflineSessionError.invalidState }
            let id = try operation(&reducer)
            try drainLocked(generation: generation)
            return id
        }
    }

    private func receiveLocked(_ bytes: Data, generation: UInt64) {
        guard activeGeneration == generation else { return }
        do {
            let incoming = try reducer.receive(bytes, generation: generation)
            var outgoing: [CodexEvent] = []
            for event in incoming {
                switch event {
                case .serverRequest(let request):
                    // A later line in this same pipe read may have completed
                    // the turn or resolved the request before delivery here.
                    if reducer.pendingServerRequests[request.id] != nil {
                        outgoing.append(try reducer.declineServerRequest(request.id, generation: generation))
                    }
                case .modelsListed(let page):
                    try acceptPageLocked(page)
                    outgoing.append(event)
                case .rpcError(let method, _, _) where method == "model/list":
                    catalog.removeAll()
                    catalogIDBytes = 0
                    collectingCatalog = false
                    catalogComplete = false
                    outgoing.append(event)
                case .assistantDelta, .assistantFinal:
                    // The reducer still validates the wire. A cancelled turn's
                    // late text must never reach a new UI or document owner.
                    if !suppressTurnText { outgoing.append(event) }
                default:
                    outgoing.append(event)
                }
            }
            try drainLocked(generation: generation)
            publishLocked(outgoing, generation: generation)
        } catch let error as CodexProtocolError {
            failLocked(.protocolFailure(error), generation: generation)
        } catch let error as CodexOfflineSessionError {
            failLocked(error, generation: generation)
        } catch let error as CodexProcessHostError {
            failLocked(.host(error), generation: generation)
        } catch {
            failLocked(.invalidState, generation: generation)
        }
    }

    private func acceptPageLocked(_ page: CodexModelPage) throws {
        guard collectingCatalog,
              page.models.count <= maximumCatalogModels - catalog.count else {
            throw CodexOfflineSessionError.modelCatalogInvalid
        }
        for model in page.models {
            guard catalog[model.id] == nil,
                  model.id.utf8.count <= maximumCatalogIDBytes - catalogIDBytes else {
                throw CodexOfflineSessionError.modelCatalogInvalid
            }
            catalog[model.id] = model
            catalogIDBytes += model.id.utf8.count
        }
        if let cursor = page.nextCursor {
            guard seenCursors.count < maximumCatalogPages,
                  seenCursors.insert(cursor).inserted else {
                throw CodexOfflineSessionError.modelCatalogInvalid
            }
            _ = try reducer.listModels(cursor: cursor)
        } else {
            collectingCatalog = false
            catalogComplete = true
        }
    }

    private func drainLocked(generation: UInt64) throws {
        while let packet = reducer.dequeueOutbound(generation: generation) {
            do { try host.write(packet, generation: generation) }
            catch let error as CodexProcessHostError {
                failLocked(.host(error), generation: generation)
                throw error
            }
        }
    }

    private func endedLocked(_ exit: CodexProcessExit, generation: UInt64) {
        guard activeGeneration == generation else { return }
        activeGeneration = nil
        reducer.processEnded(generation: generation)
        catalogComplete = false
        collectingCatalog = false
        failure = .childExited(exit)
        enqueueTerminalLocked()
    }

    private func failLocked(_ error: CodexOfflineSessionError, generation: UInt64) {
        guard activeGeneration == generation else { return }
        activeGeneration = nil
        deliveryEpoch &+= 1
        reducer.processEnded(generation: generation)
        catalogComplete = false
        collectingCatalog = false
        failure = error
        try? host.stop()
        // At most one coalesced terminal slot exists across all generations.
        // Its snapshot contains no assistant text or raw server request.
        enqueueTerminalLocked()
    }

    private func enqueueTerminalLocked() {
        terminalSnapshot = snapshotLocked()
        terminalRevision &+= 1
        guard !terminalUpdateQueued else { return }
        terminalUpdateQueued = true
        pendingDeliveries += 1
        pendingDeliveryBytes += terminalReservedBytes
        scheduleTerminalDelivery()
    }

    private func scheduleTerminalDelivery() {
        deliveryQueue.async { [weak self] in
            guard let self else { return }
            let (snapshot, revision) = self.stateQueue.sync {
                (self.terminalSnapshot, self.terminalRevision)
            }
            if let snapshot { self.onUpdate(snapshot, []) }
            let changed = self.stateQueue.sync {
                if self.terminalRevision != revision && self.terminalSnapshot != nil {
                    return true
                }
                self.terminalUpdateQueued = false
                self.terminalSnapshot = nil
                self.pendingDeliveries -= 1
                self.pendingDeliveryBytes -= self.terminalReservedBytes
                return false
            }
            if changed { self.scheduleTerminalDelivery() }
        }
    }

    private func snapshotLocked() -> CodexOfflineSessionSnapshot {
        CodexOfflineSessionSnapshot(
            generation: activeGeneration, connection: reducer.connectionState,
            turn: reducer.turnState, threadID: reducer.activeThreadID,
            modelIDs: catalog.keys.sorted(), modelCatalogComplete: catalogComplete,
            selectedModel: selectedModel, failure: failure
        )
    }

    private func publishLocked(_ events: [CodexEvent], generation: UInt64) {
        let snapshot = snapshotLocked()
        let epoch = deliveryEpoch
        let bytes = Self.deliveryBytes(snapshot: snapshot, events: events)
        guard pendingDeliveries < maximumPendingDeliveries,
              bytes <= maximumPendingDeliveryBytes - pendingDeliveryBytes else {
            // A slow observer cannot cause unbounded retained snapshots/text.
            // The one terminal update is scheduled separately by failLocked.
            if activeGeneration == generation {
                failLocked(.deliveryBackpressure, generation: generation)
            }
            return
        }
        pendingDeliveries += 1
        pendingDeliveryBytes += bytes
        enqueueDeliveryLocked(snapshot, events: events, epoch: epoch, bytes: bytes)
    }

    private func enqueueDeliveryLocked(_ snapshot: CodexOfflineSessionSnapshot,
                                       events: [CodexEvent], epoch: UInt64, bytes: Int) {
        deliveryQueue.async { [weak self] in
            guard let self else { return }
            let current = self.stateQueue.sync { self.deliveryEpoch == epoch }
            if current { self.onUpdate(snapshot, events) }
            self.stateQueue.async { [weak self] in
                guard let self else { return }
                self.pendingDeliveries -= 1
                self.pendingDeliveryBytes -= bytes
            }
        }
    }

    private static func deliveryBytes(snapshot: CodexOfflineSessionSnapshot,
                                      events: [CodexEvent]) -> Int {
        var bytes = 128 + snapshot.modelIDs.reduce(0) { $0 + $1.utf8.count }
        bytes += snapshot.threadID?.utf8.count ?? 0
        bytes += snapshot.selectedModel?.utf8.count ?? 0
        for event in events {
            bytes += 64
            switch event {
            case .assistantDelta(let id, let text), .assistantFinal(let id, let text):
                bytes += id.utf8.count + text.utf8.count
            case .threadOpened(let id), .unknownNotification(let id), .ignoredUnrelatedEvent(let id):
                bytes += id.utf8.count
            case .turnStarted(let thread, let turn):
                bytes += thread.utf8.count + turn.utf8.count
            case .turnCompleted(let thread, let turn, _, let error):
                bytes += thread.utf8.count + turn.utf8.count + (error?.utf8.count ?? 0)
            case .rpcError(let method, _, let message):
                bytes += method.utf8.count + message.utf8.count
            case .serverRequestRejected(_, let method):
                bytes += method.utf8.count
            case .modelsListed(let page):
                bytes += page.models.reduce(0) { $0 + $1.id.utf8.count + 8 }
                bytes += page.nextCursor?.utf8.count ?? 0
            case .serverRequest(let request):
                // Not emitted by this coordinator; retain a conservative bound
                // if that policy is changed in a later slice.
                bytes += (try? JSONEncoder().encode(request.params).count) ?? 1_048_576
            default:
                break
            }
        }
        return bytes
    }
}
