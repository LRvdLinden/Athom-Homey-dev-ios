import Foundation
import Security

/// An account shared from the iPhone to the Apple TV through iCloud Keychain.
/// Uses the account's Personal Access Token (the same one Developer Tools reveals
/// under My Account), because it doesn't expire like a web session does.
struct SharedAccount: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var email: String
    var avatar: String
    var pat: String
    var sharedAt: Date

    var avatarURL: URL? { URL(string: avatar) }
    var initials: String {
        let s = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? String(email.prefix(1)).uppercased() : s.uppercased()
    }
}

/// Synchronizable keychain item in the shared access group
/// (`$(AppIdentifierPrefix)nl.lrvdlinden.homeydevtools.shared`, first in both apps' entitlements).
enum SharedAccountsStore {
    private static let service = "nl.lrvdlinden.homeydevtools.shared-accounts"
    private static let account = "accounts"

    static func load() -> [SharedAccount] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([SharedAccount].self, from: data)) ?? []
    }

    @discardableResult
    static func save(_ accounts: [SharedAccount]) -> Bool {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(accounts) else { return false }
        clear()
        if accounts.isEmpty { return true }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrLabel as String: "Homey Developer Tools – Apple TV",
            kSecValueData as String: data,
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
