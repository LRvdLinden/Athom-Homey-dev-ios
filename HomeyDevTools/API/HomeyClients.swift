import Foundation

/// One HomeyClient per Homey and account, shared by every screen, so a Homey
/// session is made once instead of on every screen that opens.
@MainActor
enum HomeyClients {
    private static var cache: [String: HomeyClient] = [:]

    static func client(for homey: HomeyRef, auth: AuthManager) -> HomeyClient {
        let key = "\(auth.activeID ?? "-")|\(homey.id)"
        if let c = cache[key], c.homey.remoteURL == homey.remoteURL { return c }
        let c = HomeyClient(homey: homey, auth: auth)
        cache[key] = c
        return c
    }

    /// Forget the sessions of an account (sign-out).
    static func reset(accountID: String? = nil) {
        guard let accountID else { cache.removeAll(); return }
        cache = cache.filter { !$0.key.hasPrefix("\(accountID)|") }
    }
}
