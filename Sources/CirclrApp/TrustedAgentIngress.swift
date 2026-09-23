import Foundation
import Security
import CirclrCore

private struct TrustedCapabilityEnvelope: Decodable {
    let capability: String
}

/// Runs on AgentSocket's utility queue using only immutable credential data.
private func trustedCapabilityMatches(_ provided: String, _ expected: String) -> Bool {
    let bytes = Array(provided.utf8)
    let target = Array(expected.utf8)
    var difference = bytes.count ^ target.count
    for index in target.indices {
        difference |= Int(target[index] ^ (index < bytes.count ? bytes[index] : 0))
    }
    return difference == 0
}

/// App-owned IPC for exactly one trusted turn. This endpoint is never
/// published by AgentEndpointSelection and never uses the general MCP name.
@MainActor final class TrustedAgentIngress {
    private struct Envelope: Decodable {
        let capability: String
        let request: AgentRequest
    }

    private static var usedNames = Set<String>()
    private weak var store: AppStore?
    private let lease: AgentRunLease
    private let capability: String
    private var active = true
    private var socket: AgentSocket?
    let path: String

    /// Pass this only to the app-owned IPC client, outside model tool arguments.
    var clientCapability: String { capability }

    init(store: AppStore, lease: AgentRunLease, directory: URL) throws {
        guard store.trustedRun.active == lease,
              store.trustedRun.permitsCommit(lease, document: store.currentTrustedDocument),
              !store.trustedRun.turnCompleted else {
            throw CirclrError("trusted_run_stale: 활성 turn이 아닙니다")
        }
        self.store = store
        self.lease = lease
        capability = try Self.randomHex(byteCount: 32)

        // The basename has the same length as agent.sock, preserving the
        // existing sockaddr_un path budget. Never reuse a name in this process.
        var socketName: String?
        for _ in 0..<32 {
            let candidate = ".t" + (try Self.randomHex(byteCount: 4))
            if Self.usedNames.insert(candidate).inserted {
                socketName = candidate
                break
            }
        }
        guard let socketName else {
            throw CirclrError("trusted_run_ipc: endpoint를 만들 수 없습니다")
        }
        path = directory.appendingPathComponent(socketName).path
        let expectedCapability = capability
        socket = try AgentSocket(directory: directory, name: socketName,
                                 preflight: { data in
            guard let supplied = try? JSONDecoder().decode(TrustedCapabilityEnvelope.self,
                                                            from: data) else { return false }
            return trustedCapabilityMatches(supplied.capability, expectedCapability)
        }) { [weak self] data, reply in
            guard let self else {
                reply(Self.encode(error: "trusted_run_stale"))
                return
            }
            reply(self.handle(data))
        }
    }

    /// STOP first closes this turn's authority, then tears down its socket.
    /// Calling STOP on an old ingress cannot revoke a later turn.
    func stop() {
        closeSocket()
        if let store, store.trustedRun.active == lease {
            store.stopTrustedAgentTurn()
        }
    }

    private func closeSocket() {
        active = false
        socket = nil
    }

    private func handle(_ data: Data) -> Data {
        guard active, socket != nil, let store,
              store.trustedRun.active == lease,
              store.trustedRun.permitsCommit(lease, document: store.currentTrustedDocument),
              !store.trustedRun.turnCompleted else {
            // Completion closes request ingress but retains authority for a
            // job accepted before completion. Explicit STOP still revokes it.
            if active {
                if let store, store.trustedRun.active == lease,
                   store.trustedRun.turnCompleted,
                   store.trustedRun.permitsCommit(lease, document: store.currentTrustedDocument) {
                    closeSocket()
                } else {
                    stop()
                }
            }
            return Self.encode(error: "trusted_run_stale")
        }
        // The socket queue checked the capability before this callback could
        // reach MainActor. Verify it again with the typed request.
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              trustedCapabilityMatches(envelope.capability, capability) else {
            return Self.encode(error: "trusted_run_unauthorized")
        }
        do {
            let result = try store.executeTrustedAgent(envelope.request, lease: lease)
            return Self.encode(result: result)
        } catch {
            return Self.encode(error: AgentRunReplyProjection.safeFailure(error))
        }
    }

    private static func randomHex(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw CirclrError("trusted_run_ipc: 난수를 만들 수 없습니다")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func encode(result: [String: Any]) -> Data {
        let object: [String: Any] = ["ok": true, "result": result]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? encode(error: "trusted_run_encoding_failed")
    }

    private static func encode(error: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["ok": false, "error": error],
                                     options: [.sortedKeys]))
            ?? Data(#"{"ok":false,"error":"trusted_run_encoding_failed"}"#.utf8)
    }
}
