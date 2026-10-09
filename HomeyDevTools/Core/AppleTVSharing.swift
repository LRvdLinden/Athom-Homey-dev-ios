import Foundation

extension AuthManager: TokenProvider {}

/// iPhone side of the Apple TV link: publishes every saved account (as PAT) to iCloud Keychain.
@MainActor
enum AppleTVSharing {
    static let enabledKey = "appleTVSharingEnabled"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Fetches (or reveals) each account's Personal Access Token and shares it.
    static func publish(auth: AuthManager) async throws -> Int {
        var shared: [SharedAccount] = []
        var lastError: Error?
        for acc in auth.accounts {
            do {
                let pat = try await personalAccessToken(for: acc, auth: auth)
                shared.append(SharedAccount(id: acc.id, name: acc.name, email: acc.email, avatar: acc.avatar, pat: pat, sharedAt: Date()))
            } catch { lastError = error }
        }
        if shared.isEmpty, let lastError { throw lastError }
        SharedAccountsStore.save(shared)
        return shared.count
    }

    static func stop() { SharedAccountsStore.clear() }

    /// PAT accounts already have one; web accounts ask Athom for theirs
    /// (`GET /user/me/pat/apps`, the "Reveal" button in Developer Tools → My Account).
    private static func personalAccessToken(for acc: StoredAccount, auth: AuthManager) async throws -> String {
        switch acc.credential {
        case .pat(let p): return p
        case .web(let session):
            // The active account goes through AuthManager so an expired session is refreshed first.
            let resp: JSON = acc.id == auth.activeID
                ? try await auth.athom("/user/me/pat/apps")
                : try await HTTP.send(Config.athomAPI.appendingPathComponent("user/me/pat/apps"),
                                      headers: ["Authorization": "Bearer \(session.accessToken)"]).json
            let token: String
            switch resp {
            case .string(let s): token = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
            default: token = resp.firstString("token", "pat", "accessToken", "access_token")
            }
            guard !token.isEmpty else { throw APIError(status: 0, message: L("Geen Personal Access Token ontvangen."), url: "user/me/pat/apps") }
            return token
        }
    }
}
