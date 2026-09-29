import XCTest
import Security
import CryptoKit
@testable import CirclrCodex

final class SIWCAuthTests: XCTestCase {
    func testAttemptUsesPKCEAndRejectsCallbackSubstitutionAndReplayState() throws {
        let a = try attempt()
        let b = try attempt()
        XCTAssertNotEqual(a.state, b.state); XCTAssertNotEqual(a.nonce, b.nonce)
        let params = URLComponents(url: a.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(params.first { $0.name == "code_challenge" }?.value, Data(SHA256.hash(data: Data(a.verifier.utf8))).url64)
        XCTAssertEqual(params.first { $0.name == "agent_name_hint" }?.value, "circlr")
        XCTAssertEqual(try a.callback(callback(a), now: Date()).client, "oaiapp_test")
        for url in [callback(a, state: b.state), callback(a, host: "localhost"), callback(a, path: "/callback"),
                    URL(string: callback(a).absoluteString + "&state=extra")!, callback(a, client: "dynamic_agent_client")] {
            XCTAssertThrowsError(try a.callback(url, now: Date()))
        }
        XCTAssertThrowsError(try a.callback(callback(a), now: a.createdAt.addingTimeInterval(601)))
        XCTAssertThrowsError(try SIWCAuthAttempt.make(hostID: "host", redirectURI: URL(string: "http://localhost:123/auth/callback")!))
        XCTAssertFalse(String(reflecting: a).contains(a.verifier))
    }
    func testReturningClientCannotBeReplaced() throws {
        let a = try SIWCAuthAttempt.make(hostID: "host", redirectURI: URL(string: "http://127.0.0.1:4567/auth/callback")!, registeredClientID: "oaiapp_test", expectedSubject: "sub")
        XCTAssertFalse(a.authorizationURL.absoluteString.contains("agent_name_hint"))
        XCTAssertThrowsError(try a.callback(callback(a, client: "oaiapp_other"), now: Date()))
        let noClient = URL(string: "http://127.0.0.1:4567/auth/callback?code=code&state=\(a.state)")!
        XCTAssertEqual(try a.callback(noClient, now: Date()).client, "oaiapp_test")
    }
    func testActualRS256SignatureAndClaimsAreRequired() throws {
        let fixture = try RSAFixture()
        let claims: [String: Any] = ["iss": "https://auth.openai.com", "sub": "user", "aud": "oaiapp_test", "exp": 2000, "nonce": "nonce"]
        let token = try fixture.sign(claims)
        let identity = try SIWCAuthJWT.validate(token, jwks: fixture.jwks, clientID: "oaiapp_test", nonce: "nonce", now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(identity.subject, "user")
        for (field, value) in [("iss", "https://evil.test" as Any), ("aud", "oaiapp_other" as Any), ("exp", 1000 as Any), ("nonce", "wrong" as Any), ("exp", true as Any), ("nbf", 2000 as Any)] {
            var bad = claims; bad[field] = value
            XCTAssertThrowsError(try SIWCAuthJWT.validate(fixture.sign(bad), jwks: fixture.jwks, clientID: "oaiapp_test", nonce: "nonce", now: Date(timeIntervalSince1970: 1000)))
        }
        var components = token.split(separator: ".").map(String.init)
        var tampered = claims; tampered["sub"] = "attacker"
        components[1] = try JSONSerialization.data(withJSONObject: tampered).url64
        XCTAssertThrowsError(try SIWCAuthJWT.validate(components.joined(separator: "."), jwks: fixture.jwks, clientID: "oaiapp_test", nonce: "nonce", now: Date(timeIntervalSince1970: 1000)))
        XCTAssertThrowsError(try SIWCAuthJWT.validate(token, jwks: fixture.jwks, clientID: "oaiapp_test", nonce: "nonce", expectedSubject: "other", now: Date(timeIntervalSince1970: 1000)))
        XCTAssertThrowsError(try SIWCAuthJWT.validate(fixture.sign(claims, algorithm: "none"), jwks: fixture.jwks, clientID: "oaiapp_test", nonce: "nonce", now: Date(timeIntervalSince1970: 1000)))
    }
    func testExchangeRefreshScopesAndRedaction() async throws {
        let fixture = try RSAFixture(), a = try attempt()
        let id = try fixture.sign(["iss": "https://auth.openai.com", "sub": "user", "aud": "oaiapp_test", "exp": Date().timeIntervalSince1970 + 3600, "nonce": a.nonce])
        AuthURLProtocol.handler = { request in
            if request.url!.path.contains("jwks") { return (200, fixture.jwks) }
            var bytes = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; bytes.append(contentsOf: buffer.prefix(n)) }
            }
            let body = String(data: bytes, encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("client_id=oaiapp_test")); XCTAssertFalse(body.contains("dynamic_agent_client"))
            return (200, try JSONSerialization.data(withJSONObject: ["access_token": "secret-access", "refresh_token": "secret-refresh", "id_token": id, "token_type": "Bearer", "expires_in": 3600, "scope": "openid offline_access resource.invoke chatgpt.tokens.use.direct", "earliest_refresh_at": 1000]))
        }
        let client = client()
        let credential = try await client.exchange(callbackURL: callback(a), attempt: a)
        XCTAssertEqual(credential.identity.subject, "user")
        XCTAssertEqual(credential.earliestRefreshAt, Date(timeIntervalSince1970: 1000))
        XCTAssertFalse(String(reflecting: credential).contains("secret"))
        _ = try await client.refresh(credential: credential)
        do { _ = try await client.exchange(callbackURL: callback(a), attempt: a); XCTFail("replayed") } catch { XCTAssertEqual(error as? SIWCAuthError, .invalidCallback) }
        AuthURLProtocol.handler = { request in
            if request.url!.path.contains("jwks") { return (200, fixture.jwks) }
            return (200, try JSONSerialization.data(withJSONObject: ["access_token": "secret", "refresh_token": "secret", "token_type": "Bearer", "expires_in": 3600, "scope": "openid offline_access"]))
        }
        do { _ = try await client.refresh(credential: credential); XCTFail("missing scope") } catch { XCTAssertEqual(error as? SIWCAuthError, .insufficientScope) }
        AuthURLProtocol.handler = { _ in (500, Data("secret response".utf8)) }
        do { _ = try await client.refresh(credential: credential); XCTFail("server") } catch { XCTAssertFalse(error.localizedDescription.contains("secret")) }
    }
    func testDocumentedTerminalRefreshErrorsAreSanitizedAndTemporaryFailuresRemainRetryable() async throws {
        let now = Date()
        let credential = SIWCAuthCredential(identity: .init(issuer: "https://auth.openai.com", subject: "user", clientID: "oaiapp_test", email: nil), hostID: "urn:uuid:" + UUID().uuidString, accessToken: "synthetic", refreshToken: "synthetic", idToken: "synthetic", scopes: [], expiresAt: now, savedAt: now, earliestRefreshAt: nil)
        let terminal = ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"]
        for code in terminal + ["invalid_client", "unknown_error"] {
            for status in [400, 401, 503] {
                AuthURLProtocol.handler = { _ in
                    (status, try JSONSerialization.data(withJSONObject: ["error": code, "error_description": "secret-token-do-not-log"]))
                }
                do { _ = try await client().refresh(credential: credential); XCTFail("Error accepted") }
                catch {
                    XCTAssertEqual(error as? SIWCAuthError, status < 500 && terminal.contains(code) ? .invalidGrant : .server)
                    XCTAssertFalse(String(reflecting: error).contains("secret-token"))
                }
            }
        }
    }
    func testRefreshFloorWireFormatsAndLegacyPersistence() throws {
        // Synthetic wire fixtures: actual provider field representation remains a live gate.
        let decode: (String) throws -> Date = {
            try JSONDecoder().decode(SIWCAuthRefreshDate.self, from: Data($0.utf8)).date
        }
        XCTAssertEqual(try decode("1790726400"), try decode("\"2026-09-30T00:00:00Z\""))
        XCTAssertEqual(try decode("1790726400.5"), try decode("\"2026-09-30T00:00:00.500Z\""))
        for value in ["true", "-1", "1790726400000", "\"tomorrow\"", "{}", "null"] {
            XCTAssertThrowsError(try decode(value))
        }
        let identity = SIWCAuthIdentity(issuer: "https://auth.openai.com", subject: "user", clientID: "oaiapp_test", email: nil)
        let now = Date(timeIntervalSince1970: 1790726400)
        let credential = SIWCAuthCredential(identity: identity, hostID: "host", accessToken: "synthetic", refreshToken: "synthetic", idToken: "synthetic", scopes: [], expiresAt: now, savedAt: now, earliestRefreshAt: now.addingTimeInterval(30))
        XCTAssertFalse(credential.canRefresh(now: now)); XCTAssertTrue(credential.canRefresh(now: now.addingTimeInterval(30)))
        let encoded = try JSONEncoder().encode(credential)
        XCTAssertEqual(try JSONDecoder().decode(SIWCAuthCredential.self, from: encoded).earliestRefreshAt, credential.earliestRefreshAt)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "earliestRefreshAt")
        let legacy = try JSONDecoder().decode(SIWCAuthCredential.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.earliestRefreshAt); XCTAssertTrue(legacy.canRefresh(now: now))
    }
    func testRefreshBeforeFloorDoesNotSendRequest() async throws {
        AuthURLProtocol.handler = { _ in XCTFail("early refresh sent HTTP"); return (500, Data()) }
        let now = Date()
        let credential = SIWCAuthCredential(identity: .init(issuer: "https://auth.openai.com", subject: "user", clientID: "oaiapp_test", email: nil), hostID: "host", accessToken: "synthetic", refreshToken: "synthetic", idToken: "synthetic", scopes: [], expiresAt: now.addingTimeInterval(10), savedAt: now, earliestRefreshAt: now.addingTimeInterval(30))
        do { _ = try await client().refresh(credential: credential); XCTFail("early refresh accepted") }
        catch { XCTAssertEqual(error as? SIWCAuthError, .notYetRefreshable) }
    }
    private func attempt() throws -> SIWCAuthAttempt { try .make(hostID: "host", redirectURI: URL(string: "http://127.0.0.1:4567/auth/callback")!) }
    private func callback(_ a: SIWCAuthAttempt, state: String? = nil, host: String = "127.0.0.1", path: String = "/auth/callback", client: String = "oaiapp_test") -> URL {
        URL(string: "http://\(host):4567\(path)?code=code&state=\(state ?? a.state)&client_id=\(client)")!
    }
    private func client() -> SIWCAuthClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthURLProtocol.self]
        return SIWCAuthClient(session: URLSession(configuration: config))
    }
}

private final class AuthURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
private struct RSAFixture {
    let key: SecKey
    let jwks: Data
    init() throws {
        key = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil))
        let pub = SecKeyCopyPublicKey(key)!
        let raw = SecKeyCopyExternalRepresentation(pub, nil)! as Data
        let bytes = Array(raw); var offset = 1
        func length() -> Int {
            let first = Int(bytes[offset]); offset += 1
            if first < 128 { return first }
            var result = 0
            for _ in 0..<(first & 127) { result = result * 256 + Int(bytes[offset]); offset += 1 }
            return result
        }
        _ = length(); offset += 1
        let nLength = length(); var n = Data(bytes[offset..<(offset+nLength)]); offset += nLength + 1
        let eLength = length(); let e = Data(bytes[offset..<(offset+eLength)])
        if n.first == 0 { n.removeFirst() }
        jwks = try JSONSerialization.data(withJSONObject: ["keys": [["kid": "fixture", "kty": "RSA", "alg": "RS256", "n": n.url64, "e": e.url64]]])
    }
    func sign(_ claims: [String: Any], algorithm: String = "RS256") throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": algorithm, "kid": "fixture"]).url64
        let body = try JSONSerialization.data(withJSONObject: claims).url64
        let input = "\(header).\(body)"
        let signature = try XCTUnwrap(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(input.utf8) as CFData, nil)) as Data
        return input + "." + signature.url64
    }
}
