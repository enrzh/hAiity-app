import Foundation
import Security

/// Aufbewahrungsort für das GitHub-Token. Produktion: Keychain. Tests: ein
/// In-Memory-Fake — unsignierte Test-Hosts dürfen nicht in den Schlüsselbund.
protocol TokenVault: Sendable {
    func get() -> String?
    func set(_ value: String)
    func delete()
}

struct KeychainVault: TokenVault {
    let account: String
    func get() -> String? { Keychain.get(account: account) }
    func set(_ value: String) { Keychain.set(value, account: account) }
    func delete() { Keychain.delete(account: account) }
}

/// Minimaler Keychain-Wrapper für das GitHub-Token. Bewusst
/// `AfterFirstUnlockThisDeviceOnly`: das Token verlässt dieses Gerät nie —
/// kein iCloud-Schlüsselbund, kein Backup-Transfer (Familienregel aus aiity).
enum Keychain {
    private static let service = "com.aiity.haiity"

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
