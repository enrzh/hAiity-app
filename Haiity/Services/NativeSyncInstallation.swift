import Foundation
import Security

/// Detects a new app install while retaining an identity across deletion and
/// reinstall. The sandbox marker is device-local; the Keychain value is the
/// durable side of the comparison.
enum NativeSyncInstallation {
    static let localIDKey = "nativeSyncInstallationID"
    static let pendingRecoveryKey = "nativeSyncRecoveryPending"

    private static let keychainService = "com.aiity.haiity.native-sync"
    private static let keychainAccount = "installation-id"

    static func needsCleanup(localID: String?, persistentID: String?) -> Bool {
        guard let persistentID, !persistentID.isEmpty else { return false }
        return localID != persistentID
    }

    /// Records the current install and leaves recovery pending until both
    /// native stores have been inspected successfully.
    static func prepare(defaults: UserDefaults = sharedDefaults) -> Bool {
        guard let persistentID = persistentID() else { return false }
        let localID = defaults.string(forKey: localIDKey)
        let detected = needsCleanup(localID: localID, persistentID: persistentID)
        let pending = defaults.bool(forKey: pendingRecoveryKey)
        defaults.set(persistentID, forKey: localIDKey)
        if detected || pending {
            defaults.set(true, forKey: pendingRecoveryKey)
        }
        return detected || pending
    }

    static func completeRecovery(defaults: UserDefaults = sharedDefaults) {
        defaults.removeObject(forKey: pendingRecoveryKey)
    }

    private static var sharedDefaults: UserDefaults {
        // The app sandbox is removed on uninstall. App Group containers can
        // outlive the main app because the widget shares them, so they cannot
        // reliably distinguish an update from a reinstall.
        .standard
    }

    private static func persistentID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let id = String(data: data, encoding: .utf8),
           !id.isEmpty {
            return id
        }
        guard status == errSecItemNotFound else { return nil }

        let id = UUID().uuidString
        var add = query
        add[kSecReturnData as String] = nil
        add[kSecMatchLimit as String] = nil
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecValueData as String] = Data(id.utf8)
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
        return id
    }
}

/// One cleanup operation for both EventKit stores. The two stores have
/// different fetch APIs, so keeping the coordination here avoids every caller
/// inventing its own partial-cleanup behavior.
@MainActor
enum NativeSyncCleanup {
    struct Result: Equatable, Sendable {
        let calendar: Bool
        let reminders: Bool

        var succeeded: Bool { calendar && reminders }
        var needsRetry: Bool { !succeeded }
    }

    static func run() async -> Result {
        let calendar = CalendarSync.removeAllOwnedItems()
        let reminders = await ReminderSync.removeAllOwnedItems()
        return Result(calendar: calendar, reminders: reminders)
    }
}
