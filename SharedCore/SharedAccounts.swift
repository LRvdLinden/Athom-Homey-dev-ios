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

    /// Returns the keychain status, so the iPhone can tell the user why sharing failed.
    @discardableResult
    static func save(_ accounts: [SharedAccount]) -> OSStatus {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(accounts) else { return errSecParam }
        clear()
        if accounts.isEmpty { return errSecSuccess }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrLabel as String: "Homey Developer Tools – Apple TV",
            kSecValueData as String: data,
        ]
        return SecItemAdd(item as CFDictionary, nil)
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

/// Accounts that were added on the Apple TV itself (paired with the iPhone over the
/// local network, or entered as a Personal Access Token). Stored only on this device,
/// so they work without iCloud Keychain.
enum LinkedAccountsStore {
    private static let service = "nl.lrvdlinden.homeydevtools.linked-accounts"
    private static let account = "accounts"

    static func load() -> [SharedAccount] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([SharedAccount].self, from: data)) ?? []
    }

    static func save(_ accounts: [SharedAccount]) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(accounts) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !accounts.isEmpty else { return }
        var item = query
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    /// Adds or replaces accounts (matched by id).
    static func upsert(_ new: [SharedAccount]) {
        var all = load()
        for acc in new {
            if let i = all.firstIndex(where: { $0.id == acc.id }) { all[i] = acc } else { all.append(acc) }
        }
        save(all)
    }

    static func remove(_ id: String) {
        save(load().filter { $0.id != id })
    }
}

/// Builds a SharedAccount from `GET /user/me`, used to verify a Personal Access Token.
extension SharedAccount {
    init(me: JSON, pat: String) {
        let first = me["firstname"].string ?? ""
        let last = me["lastname"].string ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        let avatar: JSON = me["avatar"]
        let avatarURL: String = avatar.isContainer ? avatar.firstString("large", "medium", "small", "url") : (avatar.string ?? "")
        let id: String = me.firstString("_id", "id")
        self.init(
            id: id.isEmpty ? me.firstString("email") : id,
            name: full.isEmpty ? me.firstString("fullname", "name", "email") : full,
            email: me.firstString("email"),
            avatar: avatarURL,
            pat: pat,
            sharedAt: Date()
        )
    }
}
