import Foundation
import Security

enum KeyStore {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pinmoir.Cast.openai", kSecAttrAccount as String: "personal-api-key"] }
    static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { SecItemDelete(query as CFDictionary); return }
        let values: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if result == errSecItemNotFound {
            let status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        } else if result != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
    }
}
