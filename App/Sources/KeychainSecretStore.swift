import Foundation
import PlayerCore
import Security

/// Task 2.2 (SEC-14): API keys and sync logins in the Keychain. Generic passwords, service `<bundle id>.secrets`,
/// account `<profile UUID>/<name>`, readable after the first unlock, never leaves the device (no iCloud, no backup).
struct KeychainSecretStore: SecretStore {
    struct KeychainError: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String { "Schlüsselbund-Fehler \(status)" }
    }

    let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "player") + ".secrets") { self.service = service }

    private func account(_ name: String, _ profile: UUID) -> String { profile.uuidString + "/" + name }

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func get(_ name: String, profile: UUID) -> String? {
        var q = base(account(name, profile))
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s = String(decoding: d, as: UTF8.self)
        return s.isEmpty ? nil : s
    }

    func set(_ value: String?, name: String, profile: UUID) throws {
        let q = base(account(name, profile))
        guard let value, !value.isEmpty else {
            let st = SecItemDelete(q as CFDictionary)
            if st != errSecSuccess && st != errSecItemNotFound { throw KeychainError(status: st) }
            return
        }
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var st = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if st == errSecItemNotFound {
            st = SecItemAdd(q.merging(attrs) { _, new in new } as CFDictionary, nil)
        }
        if st != errSecSuccess { throw KeychainError(status: st) }
    }

    /// Deletes all entries of a profile: lists the accounts of this service and removes those with the profile prefix.
    func removeAll(profile: UUID) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecReturnAttributes as String: true,
                                kSecMatchLimit as String: kSecMatchLimitAll]
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecItemNotFound { return }
        guard st == errSecSuccess, let items = out as? [[String: Any]] else { throw KeychainError(status: st) }
        let prefix = profile.uuidString + "/"
        for item in items {
            guard let acc = item[kSecAttrAccount as String] as? String, acc.hasPrefix(prefix) else { continue }
            let d = SecItemDelete(base(acc) as CFDictionary)
            if d != errSecSuccess && d != errSecItemNotFound { throw KeychainError(status: d) }
        }
    }
}
