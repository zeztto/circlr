import Foundation

private final class SIWCNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor SIWCAuthClient {
    private let session: URLSession
    private var consumedAttempts = Set<String>()
    private var refreshing = Set<String>()
    public init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        self.session = session ?? URLSession(configuration: config, delegate: SIWCNoRedirect(), delegateQueue: nil)
    }
    public func exchange(callbackURL: URL, attempt: SIWCAuthAttempt) async throws -> SIWCAuthCredential {
        let result = try attempt.callback(callbackURL, now: Date())
        guard consumedAttempts.insert(attempt.state).inserted else { throw SIWCAuthError.invalidCallback }
        let response = try await token(["grant_type": "authorization_code", "client_id": result.client,
            "code": result.code, "code_verifier": attempt.verifier, "redirect_uri": attempt.redirectURI.absoluteString])
        guard let id = response.id_token else { throw SIWCAuthError.invalidToken }
        let identity = try SIWCAuthJWT.validate(id, jwks: await keys(), clientID: result.client,
            nonce: attempt.nonce, expectedSubject: attempt.expectedSubject)
        return try credential(response, identity: identity, hostID: attempt.hostID, idToken: id)
    }
    public func refresh(credential old: SIWCAuthCredential) async throws -> SIWCAuthCredential {
        guard old.canRefresh() else { throw SIWCAuthError.notYetRefreshable }
        let key = old.identity.clientID + ":" + old.identity.subject
        guard refreshing.insert(key).inserted else { throw SIWCAuthError.busy }
        defer { refreshing.remove(key) }
        let response = try await token(["grant_type": "refresh_token", "client_id": old.identity.clientID, "refresh_token": old.refreshToken])
        var identity = old.identity
        if let id = response.id_token {
            identity = try SIWCAuthJWT.validate(id, jwks: await keys(), clientID: old.identity.clientID,
                                               nonce: nil, expectedSubject: old.identity.subject)
        }
        return try credential(response, identity: identity, hostID: old.hostID, idToken: response.id_token ?? old.idToken)
    }
    /// Caller must clear local tokens even when remote revocation cannot be confirmed.
    public func revoke(credential: SIWCAuthCredential) async throws {
        let data = try await request(URLRequest(url: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!))
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["issuer"] as? String == "https://auth.openai.com",
              let raw = object["revocation_endpoint"] as? String, let endpoint = URL(string: raw),
              endpoint.scheme == "https", endpoint.host == "auth.openai.com", endpoint.port == nil,
              endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil else { throw SIWCAuthError.invalidConfiguration }
        _ = try await request(form(endpoint, ["token": credential.refreshToken, "token_type_hint": "refresh_token", "client_id": credential.identity.clientID]))
    }
    private struct Response: Decodable {
        let access_token: String
        let refresh_token: String
        let id_token: String?
        let token_type: String
        let expires_in: Double
        let scope: String
        let earliest_refresh_at: SIWCAuthRefreshDate?
    }
    private func token(_ parameters: [String: String]) async throws -> Response {
        var fields = parameters; fields["resource"] = "https://api.openai.com/v1"
        let data = try await request(form(URL(string: "https://auth.openai.com/api/accounts/oauth/token")!, fields))
        guard let value = try? JSONDecoder().decode(Response.self, from: data) else { throw SIWCAuthError.invalidToken }
        return value
    }
    private func keys() async throws -> Data {
        try await request(URLRequest(url: URL(string: "https://auth.openai.com/.well-known/jwks.json")!))
    }
    private func credential(_ value: Response, identity: SIWCAuthIdentity, hostID: String, idToken: String) throws -> SIWCAuthCredential {
        guard value.token_type.lowercased() == "bearer", !value.access_token.isEmpty, !value.refresh_token.isEmpty,
              value.access_token.utf8.count <= 65536, value.refresh_token.utf8.count <= 65536,
              value.expires_in.isFinite, value.expires_in > 0, value.expires_in <= 86400 else { throw SIWCAuthError.invalidToken }
        let scopes = Set(value.scope.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        guard scopes.isSuperset(of: ["openid", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct"]) else { throw SIWCAuthError.insufficientScope }
        let now = Date()
        return SIWCAuthCredential(identity: identity, hostID: hostID, accessToken: value.access_token,
            refreshToken: value.refresh_token, idToken: idToken, scopes: scopes, expiresAt: now.addingTimeInterval(value.expires_in), savedAt: now, earliestRefreshAt: value.earliest_refresh_at?.date)
    }
    private func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").utf8)
        return request
    }
    private func request(_ request: URLRequest) async throws -> Data {
        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.url == request.url, data.count <= 1048576 else { throw SIWCAuthError.server }
            if http.statusCode == 400,
               (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String == "invalid_grant" { throw SIWCAuthError.invalidGrant }
            guard http.statusCode == 200 else { throw SIWCAuthError.server }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as SIWCAuthError { throw error }
        catch { throw SIWCAuthError.network }
    }
}

/// Compatibility parser: the published token reference names this field but does not
/// specify its wire type. Support Unix seconds and RFC3339, never infer milliseconds.
struct SIWCAuthRefreshDate: Decodable {
    let date: Date
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let seconds = try? value.decode(Double.self), seconds.isFinite,
           seconds >= 0, seconds <= 253402300799 {
            date = Date(timeIntervalSince1970: seconds)
            return
        }
        if let text = try? value.decode(String.self), text.count <= 64 {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fractional = formatter.date(from: text)
            formatter.formatOptions = [.withInternetDateTime]
            if let parsed = fractional ?? formatter.date(from: text),
               parsed.timeIntervalSince1970 >= 0, parsed.timeIntervalSince1970 <= 253402300799 {
                date = parsed
                return
            }
        }
        throw SIWCAuthError.invalidToken
    }
}
