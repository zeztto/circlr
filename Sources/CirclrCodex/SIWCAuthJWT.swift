import Foundation
import Security

/// Only RS256 keys fetched from the fixed OpenAI JWKS endpoint are accepted.
public enum SIWCAuthJWT {
    public static func validate(_ token: String, jwks: Data, clientID: String, nonce: String?,
                                expectedSubject: String? = nil, now: Date = Date()) throws -> SIWCAuthIdentity {
        guard token.utf8.count <= 65536, jwks.count <= 1048576 else { throw SIWCAuthError.invalidToken }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let headerData = Data(url64: parts[0]), let body = Data(url64: parts[1]),
              let signature = Data(url64: parts[2]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "RS256", header["crit"] == nil,
              let kid = header["kid"] as? String, !kid.isEmpty,
              let keys = (try? JSONSerialization.jsonObject(with: jwks) as? [String: Any])?["keys"] as? [[String: Any]] else { throw SIWCAuthError.invalidToken }
        let matching = keys.filter { $0["kid"] as? String == kid }
        guard matching.count == 1, let key = matching.first, key["kty"] as? String == "RSA",
              key["alg"] == nil || key["alg"] as? String == "RS256",
              key["use"] == nil || key["use"] as? String == "sig",
              key["key_ops"] == nil || (key["key_ops"] as? [String])?.contains("verify") == true,
              let n = key["n"] as? String, let e = key["e"] as? String,
              let modulus = Data(url64: n), let exponent = Data(url64: e),
              modulus.count >= 256, modulus.count <= 1024, exponent.count <= 8,
              let rsa = SecKeyCreateWithData(der(0x30, integer(modulus) + integer(exponent)) as CFData,
                [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
              SecKeyVerifySignature(rsa, .rsaSignatureMessagePKCS1v15SHA256,
                Data("\(parts[0]).\(parts[1])".utf8) as CFData, signature as CFData, nil),
              let claims = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              claims["iss"] as? String == "https://auth.openai.com",
              let sub = claims["sub"] as? String, !sub.isEmpty,
              let exp = number(claims["exp"]), exp > now.timeIntervalSince1970 else { throw SIWCAuthError.invalidToken }
        let audiences = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard audiences.contains(clientID), audiences.count == 1 || claims["azp"] as? String == clientID,
              claims["azp"] == nil || claims["azp"] as? String == clientID,
              nonce == nil || claims["nonce"] as? String == nonce else { throw SIWCAuthError.invalidToken }
        for field in ["iat", "nbf"] where claims[field] != nil {
            guard let time = number(claims[field]), time <= now.timeIntervalSince1970 + 30 else { throw SIWCAuthError.invalidToken }
        }
        guard expectedSubject == nil || sub == expectedSubject else { throw SIWCAuthError.accountMismatch }
        return SIWCAuthIdentity(issuer: "https://auth.openai.com", subject: sub, clientID: clientID, email: claims["email"] as? String)
    }
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    private static func integer(_ data: Data) -> Data { der(0x02, (data.first.map { $0 & 0x80 != 0 } ?? false) ? Data([0]) + data : data) }
    private static func der(_ tag: UInt8, _ data: Data) -> Data {
        var size = data.count, length: [UInt8] = []
        repeat { length.insert(UInt8(size & 255), at: 0); size >>= 8 } while size > 0
        return Data([tag] + (data.count < 128 ? [UInt8(data.count)] : [0x80 | UInt8(length.count)] + length)) + data
    }
}
