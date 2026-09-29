import Foundation
import Security

/// Single Keychain value makes rotating credentials and their registration index atomic.
struct ChatGPTAccountKeychain {
    let service: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "chatgpt-direct-session-v1"]
    }
    func load() throws -> ChatGPTAccountRecord? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw Failure(status: status) }
        return try JSONDecoder().decode(ChatGPTAccountRecord.self, from: data)
    }
    func save(_ record: ChatGPTAccountRecord) throws {
        let data = try JSONEncoder().encode(record)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if status != errSecSuccess { throw Failure(status: status) }
    }
    struct Failure: Error { let status: OSStatus }
}
