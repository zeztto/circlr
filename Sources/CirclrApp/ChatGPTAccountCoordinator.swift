import AppKit
import Combine
import CirclrCodex

struct ChatGPTAccountRecord: Codable {
    var hostID: String
    var identity: SIWCAuthIdentity?
    var credential: SIWCAuthCredential?
}

@MainActor
struct ChatGPTAccountDependencies {
    var load: () throws -> ChatGPTAccountRecord?
    var save: (ChatGPTAccountRecord) throws -> Void
    var makeListener: () -> any ChatGPTAccountCallbackListening
    var openBrowser: (URL) -> Bool
    var exchange: (URL, SIWCAuthAttempt) async throws -> SIWCAuthCredential
    var refresh: (SIWCAuthCredential) async throws -> SIWCAuthCredential
    var revoke: (SIWCAuthCredential) async throws -> Void
    var now: () -> Date = Date.init

    static func live(service: String) -> Self {
        let store = ChatGPTAccountKeychain(service: service)
        let client = SIWCAuthClient()
        return Self(load: { try store.load() }, save: { try store.save($0) },
                    makeListener: { ChatGPTAccountLoopbackListener() },
                    openBrowser: { NSWorkspace.shared.open($0) },
                    exchange: { try await client.exchange(callbackURL: $0, attempt: $1) },
                    refresh: { try await client.refresh(credential: $0) },
                    revoke: { try await client.revoke(credential: $0) })
    }
}

/// Credentials stay outside documents, recovery snapshots, console history and Codex's auth files.
@MainActor
final class ChatGPTAccountCoordinator: ObservableObject {
    enum State: Equatable { case signedOut, signingIn, signedIn, refreshing, failed }
    @Published private(set) var state: State = .signedOut
    @Published private(set) var message: String?
    var identity: SIWCAuthIdentity? { record.credential?.identity }
    private let dependencies: ChatGPTAccountDependencies
    private var record: ChatGPTAccountRecord
    private var generation: UInt64 = 0
    private var listener: (any ChatGPTAccountCallbackListening)?
    private var loginTask: Task<Void, Never>?
    private var refreshTask: Task<SIWCAuthCredential, Error>?
    /// Must synchronously invalidate music permissions and cancel model work before any await.
    private let onSessionInvalidated: () -> Void

    init(dependencies: ChatGPTAccountDependencies, onSessionInvalidated: @escaping () -> Void = {}) throws {
        self.dependencies = dependencies
        self.onSessionInvalidated = onSessionInvalidated
        if let saved = try dependencies.load() {
            guard !saved.hostID.isEmpty,
                  saved.credential.map({ $0.hostID == saved.hostID && $0.identity == saved.identity }) ?? true else {
                throw SIWCAuthError.invalidConfiguration
            }
            record = saved
        } else {
            record = ChatGPTAccountRecord(hostID: UUID().uuidString)
            try dependencies.save(record)
        }
        if record.credential != nil { state = .signedIn }
    }

    func startLogin(newAccount: Bool = false) {
        invalidate()
        state = .signingIn; message = nil
        let epoch = generation
        let callback = dependencies.makeListener()
        listener = callback
        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let redirect = try await callback.start()
                try self.check(epoch)
                let attempt = try SIWCAuthAttempt.make(hostID: self.record.hostID, redirectURI: redirect,
                    registeredClientID: newAccount ? nil : self.record.identity?.clientID,
                    expectedSubject: newAccount ? nil : self.record.identity?.subject)
                callback.validateCallback = { url in
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    let states = items.filter { $0.name == "state" }
                    return states.count == 1 && states[0].value == attempt.state
                }
                guard self.dependencies.openBrowser(attempt.authorizationURL) else { throw ChatGPTAccountCallbackError.unavailable }
                let response = try await callback.callback()
                try self.check(epoch)
                let credential = try await self.dependencies.exchange(response, attempt)
                if self.generation != epoch || Task.isCancelled {
                    try? await self.dependencies.revoke(credential)
                    throw CancellationError()
                }
                try self.install(credential)
                self.state = .signedIn
            } catch {
                guard self.generation == epoch else { return }
                self.state = self.record.credential == nil ? .signedOut : .signedIn
                self.message = "ChatGPT 로그인에 실패했습니다. 다시 시도해 주세요."
            }
            callback.cancel()
            if self.generation == epoch { self.listener = nil; self.loginTask = nil }
        }
    }

    func cancelLogin() {
        invalidate()
        state = record.credential == nil ? .signedOut : .signedIn
        message = nil
    }

    /// One refresh per session; all concurrent callers await the same rotation.
    func accessToken() async throws -> String {
        guard state != .signingIn, let credential = record.credential else { throw SIWCAuthError.invalidGrant }
        let epoch = generation
        let now = dependencies.now()
        if credential.expiresAt.timeIntervalSince(now) > 60 { return credential.accessToken }
        if !credential.canRefresh(now: now) {
            if credential.expiresAt > now { return credential.accessToken }
            message = "계정 연결을 아직 갱신할 수 없습니다. 잠시 후 다시 시도해 주세요."
            throw SIWCAuthError.notYetRefreshable
        }
        let task: Task<SIWCAuthCredential, Error>
        if let refreshTask { task = refreshTask }
        else {
            state = .refreshing
            task = Task { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.performRefresh(credential, epoch: epoch)
            }
            refreshTask = task
        }
        let refreshed = try await task.value
        try check(epoch)
        return refreshed.accessToken
    }

    /// Installation belongs to the shared task, never to an individual waiter.
    private func performRefresh(_ credential: SIWCAuthCredential, epoch: UInt64) async throws -> SIWCAuthCredential {
        do {
            let refreshed = try await dependencies.refresh(credential)
            if generation != epoch || Task.isCancelled {
                try? await dependencies.revoke(refreshed)
                throw CancellationError()
            }
            guard refreshed.identity.issuer == credential.identity.issuer,
                  refreshed.identity.subject == credential.identity.subject,
                  refreshed.identity.clientID == credential.identity.clientID else { throw SIWCAuthError.accountMismatch }
            try install(refreshed)
            refreshTask = nil
            state = .signedIn; message = nil
            return refreshed
        } catch {
            guard generation == epoch else { throw CancellationError() }
            refreshTask = nil
            if let authError = error as? SIWCAuthError,
               [.invalidGrant, .accountMismatch, .invalidToken, .insufficientScope].contains(authError) {
                invalidate()
                record.credential = nil
                do { try dependencies.save(record) }
                catch { message = "계정 정보를 안전하게 지우지 못했습니다. 다시 로그아웃해 주세요."; state = .failed; throw error }
                state = .signedOut
                message = "ChatGPT에 다시 로그인해 주세요."
            } else {
                state = .signedIn
                message = "계정 연결을 갱신하지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요."
            }
            throw error
        }
    }

    func logout() async {
        let credential = record.credential
        invalidate()
        let epoch = generation
        record.credential = nil
        state = .signedOut; message = nil
        do { try dependencies.save(record) }
        catch { state = .failed; message = "계정 정보를 안전하게 지우지 못했습니다. 다시 로그아웃해 주세요." }
        if let credential {
            do { try await dependencies.revoke(credential) }
            catch {
                guard generation == epoch else { return }
                if state != .failed { message = "로컬 계정은 로그아웃되었습니다. 서버의 연결 해제는 확인하지 못했습니다." }
            }
        }
    }

    private func install(_ credential: SIWCAuthCredential) throws {
        guard credential.hostID == record.hostID else { throw SIWCAuthError.accountMismatch }
        let next = ChatGPTAccountRecord(hostID: record.hostID, identity: credential.identity, credential: credential)
        try dependencies.save(next)
        record = next
    }

    private func check(_ epoch: UInt64) throws {
        guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
    }

    private func invalidate() {
        generation &+= 1
        onSessionInvalidated()
        listener?.cancel(); listener = nil
        loginTask?.cancel(); loginTask = nil
        refreshTask?.cancel(); refreshTask = nil
    }
}
