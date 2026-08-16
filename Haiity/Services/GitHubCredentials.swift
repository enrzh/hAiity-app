import Foundation
import Security

enum GitHubAppConfig {
    static let placeholderClientID = "REPLACE_ME_CLIENT_ID"

    static var clientID: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isConfigured: Bool {
        let id = clientID
        return !id.isEmpty && id != placeholderClientID
    }
}

protocol GitHubCredentialVault: Sendable {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

enum GitHubCredentialError: Error, Equatable, Sendable {
    case keychain(OSStatus)
}

struct KeychainGitHubCredentialVault: GitHubCredentialVault, Sendable {
    var service: String = "com.aiity.haiity.github"
    var account: String = "oauth-token"

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GitHubCredentialError.keychain(status) }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            return nil
        }
        return token
    }

    func save(_ token: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8)
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw GitHubCredentialError.keychain(status) }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubCredentialError.keychain(status)
        }
    }
}
