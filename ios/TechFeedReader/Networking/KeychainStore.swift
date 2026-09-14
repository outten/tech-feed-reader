import Foundation
import Security

/// Minimal Keychain wrapper for the one thing this app stores: the
/// bearer token issued by /api/auth/*/verify + /api/auth/recovery.
/// Never store it in UserDefaults — a Keychain item survives app
/// deletion/reinstall in the same way a real login should be able to,
/// and isn't readable by other apps.
enum KeychainStore {
    private static let service = "com.techfeedreader.ios.apitoken"
    private static let account = "current"

    static func saveToken(_ token: String) {
        let data = Data(token.utf8)
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
