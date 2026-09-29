import XCTest
import CirclrCodex
@testable import CirclrApp

@MainActor
final class ChatGPTAccountTests: XCTestCase {
    @MainActor final class Listener: ChatGPTAccountCallbackListening {
        var validateCallback: ((URL) -> Bool)?
        var continuation: CheckedContinuation<URL, Error>?
        var started = false
        var cancelled = false
        func start() async throws -> URL { started = true; return URL(string: "http://127.0.0.1:32100/auth/callback")! }
        func callback() async throws -> URL { try await withCheckedThrowingContinuation { continuation = $0 } }
        func cancel() { cancelled = true; continuation?.resume(throwing: CancellationError()); continuation = nil }
        func deliver() { continuation?.resume(returning: URL(string: "http://127.0.0.1:32100/auth/callback?code=test")!); continuation = nil }
    }
    @MainActor final class Fixture {
        var saved: ChatGPTAccountRecord?
        var listener = Listener()
        var opened = false
        var openedURL: URL?
        var exchanged: CheckedContinuation<SIWCAuthCredential, Error>?
        var refreshed: CheckedContinuation<SIWCAuthCredential, Error>?
        var refreshCount = 0
        var revoked = 0
        var invalidations = 0
        var saveFails = false
        var deps: ChatGPTAccountDependencies {
            ChatGPTAccountDependencies(load: { self.saved }, save: { value in
                if self.saveFails { throw SIWCAuthError.server }; self.saved = value
            }, makeListener: { self.listener }, openBrowser: { url in
                self.openedURL = url
                XCTAssertTrue(self.listener.started); self.opened = true; return true
            }, exchange: { _, _ in try await withCheckedThrowingContinuation { self.exchanged = $0 } },
            refresh: { _ in self.refreshCount += 1; return try await withCheckedThrowingContinuation { self.refreshed = $0 } },
            revoke: { _ in self.revoked += 1 })
        }
    }
    static func credential(host: String, expires: Date = .distantFuture, token: String = "test-access", email: String = "test@example.invalid", subject: String = "test-sub", earliestRefreshAt: Date? = nil) throws -> SIWCAuthCredential {
        var value: [String: Any] = ["identity": ["issuer": "https://auth.openai.com", "subject": subject, "clientID": "oaiapp_test", "email": email], "hostID": host, "accessToken": token, "refreshToken": "test-refresh", "idToken": "test-id", "scopes": ["chatgpt.tokens.use.direct"], "expiresAt": expires.timeIntervalSinceReferenceDate, "savedAt": Date().timeIntervalSinceReferenceDate]
        if let earliestRefreshAt { value["earliestRefreshAt"] = earliestRefreshAt.timeIntervalSinceReferenceDate }
        return try JSONDecoder().decode(SIWCAuthCredential.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func spin(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<1000 { if predicate() { return }; await Task.yield() }
        XCTFail("Expected asynchronous state not reached")
    }
    func testHostIDUsesUUIDURIAndNormalizesOnlyUnregisteredLegacyHost() throws {
        let fresh = Fixture()
        _ = try ChatGPTAccountCoordinator(dependencies: fresh.deps)
        let host = try XCTUnwrap(fresh.saved?.hostID)
        XCTAssertTrue(host.hasPrefix("urn:uuid:"))
        XCTAssertNotNil(UUID(uuidString: String(host.dropFirst("urn:uuid:".count))))
        _ = try ChatGPTAccountCoordinator(dependencies: fresh.deps)
        XCTAssertEqual(fresh.saved?.hostID, host)

        let bare = UUID().uuidString
        let legacy = Fixture()
        legacy.saved = .init(hostID: bare)
        _ = try ChatGPTAccountCoordinator(dependencies: legacy.deps)
        XCTAssertEqual(legacy.saved?.hostID, "urn:uuid:" + bare)
        let registered = try Self.credential(host: bare)
        for credential in [registered, nil] as [SIWCAuthCredential?] {
            legacy.saved = .init(hostID: bare, identity: registered.identity, credential: credential)
            _ = try ChatGPTAccountCoordinator(dependencies: legacy.deps)
            XCTAssertEqual(legacy.saved?.hostID, bare)
            XCTAssertEqual(legacy.saved?.identity, registered.identity)
        }
    }
    func testTerminalRefreshClearsOnlyCredentialAndKeepsRegistration() async throws {
        let f = Fixture()
        let old = try Self.credential(host: "urn:uuid:" + UUID().uuidString, expires: .distantPast)
        f.saved = .init(hostID: old.hostID, identity: old.identity, credential: old)
        let account = try ChatGPTAccountCoordinator(dependencies: f.deps, onSessionInvalidated: { f.invalidations += 1 })
        let request = Task { try await account.accessToken() }
        await spin { f.refreshed != nil }
        f.refreshed?.resume(throwing: SIWCAuthError.invalidGrant)
        do { _ = try await request.value; XCTFail("Unusable refresh token accepted") }
        catch { XCTAssertEqual(error as? SIWCAuthError, .invalidGrant) }
        XCTAssertNil(f.saved?.credential)
        XCTAssertEqual(f.saved?.identity, old.identity)
        XCTAssertEqual(f.saved?.hostID, old.hostID)
        XCTAssertEqual(account.state, .signedOut)
        XCTAssertEqual(f.invalidations, 1)
    }
    func testCancelDuringExchangeRejectsLateCredentialAndRevokesIt() async throws {
        let f = Fixture()
        let account = try ChatGPTAccountCoordinator(dependencies: f.deps, onSessionInvalidated: { f.invalidations += 1 })
        account.startLogin()
        await spin { f.listener.continuation != nil }
        XCTAssertTrue(f.opened)
        f.listener.deliver()
        await spin { f.exchanged != nil }
        account.cancelLogin()
        f.exchanged?.resume(returning: try Self.credential(host: XCTUnwrap(f.saved).hostID))
        await spin { f.revoked == 1 }
        XCTAssertNil(f.saved?.credential)
        XCTAssertEqual(account.state, .signedOut)
        XCTAssertEqual(f.invalidations, 2)
    }
    func testMissingPlanPermissionDoesNotInstallCredentialAndExplainsRecovery() async throws {
        let f = Fixture()
        let account = try ChatGPTAccountCoordinator(dependencies: f.deps)
        account.startLogin()
        await spin { f.listener.continuation != nil }
        f.listener.deliver()
        await spin { f.exchanged != nil }
        f.exchanged?.resume(throwing: SIWCAuthError.insufficientScope)
        await spin { account.state == .signedOut }
        XCTAssertNil(f.saved?.credential)
        XCTAssertTrue(account.message?.contains("플랜 사용 권한") == true)
        XCTAssertTrue(account.message?.contains("다시 로그인") == true)
    }
    func testCredentialInstalledOnlyAfterExchangeAndAtomicSave() async throws {
        let f = Fixture()
        let account = try ChatGPTAccountCoordinator(dependencies: f.deps)
        account.startLogin()
        await spin { f.listener.continuation != nil }
        f.listener.deliver()
        await spin { f.exchanged != nil }
        XCTAssertEqual(account.state, .signingIn)
        XCTAssertNil(f.saved?.credential)
        f.exchanged?.resume(returning: try Self.credential(host: XCTUnwrap(f.saved).hostID))
        await spin { account.state == .signedIn }
        XCTAssertEqual(f.saved?.identity?.subject, "test-sub")
        let token = try await account.accessToken()
        XCTAssertEqual(token, "test-access")
    }
    func testConcurrentRefreshSharesRotationAndPersistsBeforeReturning() async throws {
        let f = Fixture()
        let old = try Self.credential(host: "test-host", expires: .distantPast)
        f.saved = .init(hostID: old.hostID, identity: old.identity, credential: old)
        let account = try ChatGPTAccountCoordinator(dependencies: f.deps)
        let first = Task { try await account.accessToken() }
        let second = Task { try await account.accessToken() }
        await spin { f.refreshCount == 1 }
        f.refreshed?.resume(returning: try Self.credential(host: old.hostID, token: "rotated"))
        let a = try await first.value; let b = try await second.value
        XCTAssertEqual(a, "rotated"); XCTAssertEqual(b, "rotated")
        XCTAssertEqual(f.refreshCount, 1)
        XCTAssertEqual(f.saved?.credential?.accessToken, "rotated")
    }
    func testCancelledRefreshWaiterDoesNotDiscardRotationForOtherCaller() async throws {
        let f = Fixture()
        let old = try Self.credential(host: "test-host", expires: .distantPast)
        f.saved = .init(hostID: old.hostID, identity: old.identity, credential: old)
        let account = try ChatGPTAccountCoordinator(dependencies: f.deps)
        let first = Task { try await account.accessToken() }
        await spin { f.refreshed != nil }
        let second = Task { try await account.accessToken() }
        first.cancel()
        f.refreshed?.resume(returning: try Self.credential(host: old.hostID, token: "rotated"))
        do { _ = try await first.value; XCTFail("Cancelled caller returned token") } catch {}
        let token = try await second.value
        XCTAssertEqual(token, "rotated")
        XCTAssertEqual(f.saved?.credential?.accessToken, "rotated")
        XCTAssertEqual(f.refreshCount, 1)
        XCTAssertEqual(f.revoked, 0)
    }
    func testLogoutInvalidatesImmediatelyAndRejectsLateRefresh() async throws {
        let f = Fixture()
        let old = try Self.credential(host: "test-host", expires: .distantPast)
        f.saved = .init(hostID: old.hostID, identity: old.identity, credential: old)
        let account = try ChatGPTAccountCoordinator(dependencies: f.deps, onSessionInvalidated: { f.invalidations += 1 })
        let request = Task { try await account.accessToken() }
        await spin { f.refreshed != nil }
        await account.logout()
        XCTAssertEqual(f.invalidations, 1)
        XCTAssertNil(f.saved?.credential)
        XCTAssertEqual(f.saved?.identity, old.identity)
        f.refreshed?.resume(returning: try Self.credential(host: old.hostID, token: "late"))
        do { _ = try await request.value; XCTFail("Late credential escaped") } catch {}
        XCTAssertEqual(account.state, .signedOut)
        XCTAssertNil(f.saved?.credential)
        XCTAssertEqual(f.revoked, 2)
    }
    func testOfflineRefreshRetainsCredential() async throws {
        let f = Fixture()
        let old = try Self.credential(host: "test-host", expires: .distantPast)
        f.saved = .init(hostID: old.hostID, identity: old.identity, credential: old)
        let account = try ChatGPTAccountCoordinator(dependencies: f.deps)
        let request = Task { try await account.accessToken() }
        await spin { f.refreshed != nil }
        f.refreshed?.resume(throwing: SIWCAuthError.network)
        do { _ = try await request.value; XCTFail() } catch {}
        XCTAssertEqual(f.saved?.credential?.accessToken, old.accessToken)
        XCTAssertEqual(account.state, .signedIn)
    }
    func testRefreshFloorUsesUnexpiredTokenAndPreservesExpiredCredential() async throws {
        for expired in [false, true] {
            let f = Fixture()
            let now = Date()
            let old = try Self.credential(host: "test-host", expires: now.addingTimeInterval(expired ? -5 : 30), earliestRefreshAt: now.addingTimeInterval(120))
            f.saved = .init(hostID: old.hostID, identity: old.identity, credential: old)
            let account = try ChatGPTAccountCoordinator(dependencies: f.deps)
            if expired {
                do { _ = try await account.accessToken(); XCTFail("Expired token returned") }
                catch { XCTAssertEqual(error as? SIWCAuthError, .notYetRefreshable) }
            } else {
                let token = try await account.accessToken()
                XCTAssertEqual(token, old.accessToken)
            }
            XCTAssertEqual(f.refreshCount, 0)
            XCTAssertNotNil(f.saved?.credential)
            XCTAssertEqual(account.state, .signedIn)
        }
    }

    func testExplicitAccountSwitchUsesFreshRegistrationAndKeepsOldUntilVerified() async throws {
        let f = Fixture()
        let old = try Self.credential(host: "test-host")
        f.saved = .init(hostID: old.hostID, identity: old.identity, credential: old)
        let account = try ChatGPTAccountCoordinator(dependencies: f.deps)
        account.startLogin(newAccount: true)
        await spin { f.listener.continuation != nil }
        let url = try XCTUnwrap(f.openedURL)
        let clientID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "client_id" }?.value
        XCTAssertEqual(clientID, "dynamic_agent_client")
        XCTAssertEqual(f.saved?.credential?.identity.subject, "test-sub")
        f.listener.deliver()
        await spin { f.exchanged != nil }
        f.exchanged?.resume(returning: try Self.credential(host: old.hostID, subject: "other"))
        await spin { account.state == .signedIn }
        XCTAssertEqual(f.saved?.credential?.identity.subject, "other")
    }

    func testRefreshAllowsProfileEmailChangeButRejectsSubjectChange() async throws {
        for changedSubject in [false, true] {
            let f = Fixture()
            let old = try Self.credential(host: "test-host", expires: .distantPast)
            f.saved = .init(hostID: old.hostID, identity: old.identity, credential: old)
            let account = try ChatGPTAccountCoordinator(dependencies: f.deps)
            let request = Task { try await account.accessToken() }
            await spin { f.refreshed != nil }
            f.refreshed?.resume(returning: try Self.credential(host: old.hostID, email: "updated@example.invalid", subject: changedSubject ? "other" : "test-sub"))
            if changedSubject {
                do { _ = try await request.value; XCTFail("Wrong subject accepted") } catch {}
                XCTAssertNil(f.saved?.credential)
                XCTAssertEqual(account.state, .signedOut)
            } else {
                _ = try await request.value
                XCTAssertEqual(f.saved?.identity?.email, "updated@example.invalid")
            }
        }
    }

    func testLoopbackTimeoutFinishesPendingCallback() async throws {
        let listener = ChatGPTAccountLoopbackListener(timeout: 0.05)
        _ = try await listener.start()
        do { _ = try await listener.callback(); XCTFail("Timeout expected") }
        catch { XCTAssertEqual(error as? ChatGPTAccountCallbackError, .timedOut) }
    }

    func testLoopbackParserRejectsHostBodyAndAbsoluteURI() {
        let redirect = URL(string: "http://127.0.0.1:32100/auth/callback")!
        func parse(_ target: String = "/auth/callback?state=x", headers: String = "Host: 127.0.0.1:32100", body: String = "") -> URL? {
            ChatGPTAccountLoopbackListener.parseRequest(Data("GET \(target) HTTP/1.1\r\n\(headers)\r\n\r\n\(body)".utf8), redirect: redirect)
        }
        XCTAssertNotNil(parse())
        XCTAssertNil(parse(headers: "Host: evil.invalid"))
        XCTAssertNil(parse(headers: "Host: 127.0.0.1:32100\r\nHost: 127.0.0.1:32100"))
        XCTAssertNil(parse(headers: "Host: 127.0.0.1:32100\r\nContent-Length: 1", body: "x"))
        XCTAssertNil(parse(body: "x"))
        XCTAssertNil(parse("http://127.0.0.1:32100/auth/callback?state=x"))
    }
    func testLiveLoopbackAcceptsMatchingStateAndClosesOnCancel() async throws {
        let listener = ChatGPTAccountLoopbackListener(timeout: 5)
        let redirect = try await listener.start()
        listener.validateCallback = { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "valid" }
        let bad = URL(string: redirect.absoluteString + "?state=wrong")!
        let (_, badResponse) = try await URLSession.shared.data(from: bad)
        XCTAssertEqual((badResponse as? HTTPURLResponse)?.statusCode, 400)
        let callback = Task { try await listener.callback() }
        let good = URL(string: redirect.absoluteString + "?state=valid")!
        let (body, response) = try await URLSession.shared.data(from: good)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("valid"))
        let received = try await callback.value
        XCTAssertEqual(received, good)
        listener.cancel()
        let cancelled = ChatGPTAccountLoopbackListener(timeout: 5)
        _ = try await cancelled.start()
        cancelled.cancel()
        do { _ = try await cancelled.callback(); XCTFail() } catch {}
    }
}
