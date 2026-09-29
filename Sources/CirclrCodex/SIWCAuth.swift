import Foundation
import CryptoKit
import Security

public enum SIWCAuthError: String, Error, LocalizedError, Sendable {
    case invalidConfiguration, invalidCallback, stateMismatch, denied, incompleteRegistration
    case accountMismatch, invalidToken, insufficientScope, network, invalidGrant, server, busy, notYetRefreshable
    public var errorDescription: String? { "ChatGPT authentication: \(rawValue)" }
}

public struct SIWCAuthIdentity: Codable, Equatable, Sendable {
    public let issuer: String
    public let subject: String
    public let clientID: String
    public let email: String?
}

public struct SIWCAuthCredential: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let identity: SIWCAuthIdentity
    public let hostID: String
    public let accessToken: String
    public let refreshToken: String
    public let idToken: String
    public let scopes: Set<String>
    public let expiresAt: Date
    public let savedAt: Date
    public let earliestRefreshAt: Date?
    public func canRefresh(now: Date = Date()) -> Bool {
        earliestRefreshAt.map { now >= $0 } ?? true
    }
    public var description: String { "SIWCAuthCredential([REDACTED])" }
    public var debugDescription: String { description }
}

public struct SIWCAuthAttempt: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let hostID: String
    public let redirectURI: URL
    public let registeredClientID: String?
    public let expectedSubject: String?
    public let state: String
    public let nonce: String
    let verifier: String
    public let createdAt: Date
    public var description: String { "SIWCAuthAttempt([REDACTED])" }
    public var debugDescription: String { description }
    public static func make(hostID: String, redirectURI: URL, registeredClientID: String? = nil,
                            expectedSubject: String? = nil) throws -> Self {
        guard !hostID.isEmpty, hostID.count <= 256, validRedirect(redirectURI),
              registeredClientID.map(validClient) ?? true,
              (registeredClientID == nil) == (expectedSubject == nil) else { throw SIWCAuthError.invalidConfiguration }
        return try Self(hostID: hostID, redirectURI: redirectURI, registeredClientID: registeredClientID,
                        expectedSubject: expectedSubject, state: random(), nonce: random(), verifier: random(), createdAt: Date())
    }
    public var authorizationURL: URL {
        var url = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        var items = ["client_id": registeredClientID ?? "dynamic_agent_client", "ext_agent_host_id": hostID,
                     "response_type": "code", "redirect_uri": redirectURI.absoluteString,
                     "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
                     "resource": "https://api.openai.com/v1", "state": state, "nonce": nonce,
                     "code_challenge_method": "S256", "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).url64]
        if registeredClientID == nil { items["agent_name_hint"] = "circlr" }
        url.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!
    }
    func callback(_ url: URL, now: Date) throws -> (code: String, client: String) {
        guard now.timeIntervalSince(createdAt) >= 0, now.timeIntervalSince(createdAt) < 600,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == redirectURI.scheme, c.host == "127.0.0.1", c.port == redirectURI.port,
              c.percentEncodedPath == "/auth/callback", c.user == nil, c.password == nil, c.fragment == nil else { throw SIWCAuthError.invalidCallback }
        var values: [String: String] = [:]
        for item in c.queryItems ?? [] {
            guard values[item.name] == nil, let value = item.value else { throw SIWCAuthError.invalidCallback }
            values[item.name] = value
        }
        guard values["state"] == state else { throw SIWCAuthError.stateMismatch }
        if values["error"] != nil { throw SIWCAuthError.denied }
        guard let code = values["code"], !code.isEmpty, code.count <= 8192 else { throw SIWCAuthError.invalidCallback }
        if let saved = registeredClientID {
            guard values["client_id"] == nil || values["client_id"] == saved else { throw SIWCAuthError.accountMismatch }
            return (code, saved)
        }
        guard let issued = values["client_id"], Self.validClient(issued) else { throw SIWCAuthError.incompleteRegistration }
        return (code, issued)
    }
    static func validClient(_ value: String) -> Bool {
        !value.isEmpty && value != "dynamic_agent_client" && value.count <= 256 && value.utf8.allSatisfy { $0 == 45 || (48...57).contains($0) || (65...90).contains($0) || $0 == 95 || (97...122).contains($0) }
    }
    private static func validRedirect(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return c.scheme == "http" && c.host == "127.0.0.1" && (1...65535).contains(c.port ?? 0) && c.percentEncodedPath == "/auth/callback" && c.user == nil && c.password == nil && c.query == nil && c.fragment == nil
    }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SIWCAuthError.invalidConfiguration }
        return Data(bytes).url64
    }
}

extension Data {
    var url64: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(url64: String) {
        guard !url64.isEmpty, url64.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        let s = url64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: s + String(repeating: "=", count: (4 - s.count % 4) % 4))
    }
}
