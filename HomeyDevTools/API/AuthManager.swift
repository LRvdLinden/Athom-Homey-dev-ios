import Foundation
import Observation
import WebKit

enum Credential: Codable, Equatable, Sendable {
    /// Logged in with email + password on the Developer Tools website.
    case web(WebSession)
    /// Personal Access Token (My Account → Personal Access Tokens).
    case pat(String)

    var accessToken: String {
        switch self {
        case .web(let s): return s.accessToken
        case .pat(let p): return p
        }
    }
}

/// One saved Athom/Homey account (like the account switcher in the Facebook app).
struct StoredAccount: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var email: String
    var avatar: String
    var credential: Credential
    var lastUsed: Date
    var needsLogin: Bool = false

    var avatarURL: URL? { URL(string: avatar) }
    var methodLabel: String {
        switch credential { case .web: return "Homey-account"; case .pat: return "Personal Access Token" }
    }
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? String(email.prefix(1)).uppercased() : s.uppercased()
    }
}

/// Owns all saved accounts, the active one, token refresh and delegation tokens
/// for the Apps API (`audience=apps`) and Homey (`audience=homey`).
@MainActor
@Observable
final class AuthManager {
    private(set) var accounts: [StoredAccount] = []
    private(set) var activeID: String?
    private(set) var user: JSON = .null
    private(set) var userError: String?

    @ObservationIgnored private var delegated: [String: (token: String, expires: Date?)] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Error>?

    private enum Keys {
        static let accounts = "accounts.v2"
        static let active = "activeAccountID"
    }

    init() {
        accounts = Keychain.load([StoredAccount].self, for: Keys.accounts) ?? []
        activeID = UserDefaults.standard.string(forKey: Keys.active)
        if active == nil { activeID = accounts.sorted { $0.lastUsed > $1.lastUsed }.first?.id }
    }

    var active: StoredAccount? { accounts.first { $0.id == activeID } }
    var isLoggedIn: Bool { active != nil }
    var otherAccounts: [StoredAccount] { accounts.filter { $0.id != activeID }.sorted { $0.lastUsed > $1.lastUsed } }
    var loginMethodLabel: String { active?.methodLabel ?? "Niet ingelogd" }

    /// Session to put into the in-app Developer Tools website for the active account.
    var activeWebSession: WebSession? {
        if case .web(let s) = active?.credential { return s }
        return nil
    }

    // MARK: Adding accounts

    func addWebAccount(_ session: WebSession) async throws {
        try await add(credential: .web(session))
    }

    func addPATAccount(_ raw: String) async throws {
        let pat = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pat.isEmpty else { throw APIError(status: 0, message: "Vul een Personal Access Token in.", url: "") }
        try await add(credential: .pat(pat))
    }

    private func add(credential: Credential) async throws {
        let me = try await HTTP.send(
            Config.athomAPI.appendingPathComponent("user/me"),
            headers: ["Authorization": "Bearer \(credential.accessToken)"]
        ).json
        let id = me.firstString("_id", "id").isEmpty ? me.firstString("email") : me.firstString("_id", "id")
        guard !id.isEmpty else { throw APIError(status: 0, message: "Kon het account niet herkennen.", url: "user/me") }
        let account = StoredAccount(
            id: id,
            name: Self.displayName(me),
            email: me.firstString("email"),
            avatar: Self.avatar(me),
            credential: credential,
            lastUsed: Date()
        )
        if let i = accounts.firstIndex(where: { $0.id == id }) { accounts[i] = account } else { accounts.append(account) }
        activate(id)
        user = me
        userError = nil
        save()
    }

    // MARK: Switching / signing out

    func switchTo(_ id: String) {
        guard id != activeID, accounts.contains(where: { $0.id == id }) else { return }
        activate(id)
        user = .null
        save()
        Task { try? await loadUser() }
    }

    private func activate(_ id: String) {
        activeID = id
        delegated.removeAll()
        refreshTask = nil
        if let i = accounts.firstIndex(where: { $0.id == id }) { accounts[i].lastUsed = Date() }
        UserDefaults.standard.set(id, forKey: Keys.active)
    }

    /// Removes the account from this device ("Afmelden").
    func signOut(_ id: String) {
        accounts.removeAll { $0.id == id }
        let storeID = WebDataStores.identifier(for: id)
        Task { try? await WKWebsiteDataStore.remove(forIdentifier: storeID) }
        if activeID == id {
            user = .null
            delegated.removeAll()
            activeID = nil
            if let next = accounts.sorted(by: { $0.lastUsed > $1.lastUsed }).first { activate(next.id); Task { try? await loadUser() } }
            else { UserDefaults.standard.removeObject(forKey: Keys.active) }
        }
        save()
    }

    func logout() { if let activeID { signOut(activeID) } }

    private func save() { Keychain.save(accounts, for: Keys.accounts) }

    private func updateActive(_ change: (inout StoredAccount) -> Void) {
        guard let i = accounts.firstIndex(where: { $0.id == activeID }) else { return }
        change(&accounts[i])
        save()
    }

    /// Called by the in-app website when it rotated tokens for the active account.
    func adoptWebSession(_ session: WebSession) {
        guard session.hasToken, case .web(let current) = active?.credential, current != session else { return }
        if !session.userId.isEmpty, session.userId != activeID { return }
        updateActive { $0.credential = .web(session); $0.needsLogin = false }
        delegated.removeAll()
    }

    // MARK: Tokens

    func accessToken() throws -> String {
        guard let active else { throw APIError(status: 401, message: "Niet ingelogd.", url: "") }
        return active.credential.accessToken
    }

    private func refreshActive() async throws {
        if let refreshTask { return try await refreshTask.value }
        guard case .web(let session) = active?.credential else {
            throw APIError(status: 401, message: "Token ongeldig of ingetrokken. Voeg het account opnieuw toe.", url: "")
        }
        let id = activeID
        let task = Task { () throws -> Void in
            do {
                let new = try await WebSessionBridge.refresh(session)
                guard self.activeID == id else { return }
                self.updateActive { $0.credential = .web(new); $0.needsLogin = false }
                self.delegated.removeAll()
            } catch {
                if self.activeID == id { self.updateActive { $0.needsLogin = true } }
                throw error
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    /// Request against api.athom.com with the account token; refreshes once on 401.
    func athom(_ path: String, method: String = "GET", json body: JSON? = nil) async throws -> JSON {
        guard let url = URL(string: path, relativeTo: Config.athomAPI)?.absoluteURL else {
            throw APIError(status: 0, message: "Ongeldig pad", url: path)
        }
        func run() async throws -> JSON {
            let token = try accessToken()
            let data = body.map { $0.data() } ?? (method == "POST" ? Data("{}".utf8) : nil)
            return try await HTTP.send(url, method: method, headers: ["Authorization": "Bearer \(token)"], body: data).json
        }
        do { return try await run() } catch let e as APIError where e.isUnauthorized {
            try await refreshActive()
            return try await run()
        }
    }

    func loadUser() async throws {
        do {
            let me = try await athom("/user/me")
            user = me
            userError = nil
            updateActive {
                $0.name = Self.displayName(me)
                $0.email = me.firstString("email")
                $0.avatar = Self.avatar(me)
            }
        } catch {
            userError = error.localizedDescription
            throw error
        }
    }

    func delegationToken(audience: String) async throws -> String {
        if let cached = delegated[audience], (cached.expires ?? .distantFuture) > Date() { return cached.token }
        let resp = try await athom("/delegation/token?audience=\(audience)", method: "POST", json: .object([:]))
        let token: String
        switch resp {
        case .string(let s): token = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        default: token = resp.firstString("token", "access_token")
        }
        guard !token.isEmpty else { throw APIError(status: 0, message: "Geen delegation token ontvangen (\(audience)).", url: "delegation/token") }
        delegated[audience] = (token, JWT.expiry(token))
        return token
    }

    func invalidateDelegation(_ audience: String) { delegated[audience] = nil }

    // MARK: User helpers

    private static func displayName(_ me: JSON) -> String {
        let full = "\(me["firstname"].string ?? "") \(me["lastname"].string ?? "")".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? me.firstString("fullname", "name", "email") : full
    }

    private static func avatar(_ me: JSON) -> String {
        let a = me["avatar"]
        return a.isContainer ? a.firstString("large", "medium", "small", "url") : (a.string ?? "")
    }

    var displayName: String { user.isNull ? (active?.name ?? "") : Self.displayName(user) }
    var email: String { user.isNull ? (active?.email ?? "") : user.firstString("email") }
    var avatarURL: URL? { URL(string: user.isNull ? (active?.avatar ?? "") : Self.avatar(user)) }
    var firstName: String { user["firstname"].string ?? displayName.split(separator: " ").first.map(String.init) ?? "" }

    /// Homeys linked to the account (same source as Developer Tools: `user.homeys`).
    var homeys: [HomeyRef] {
        var seen = Set<String>()
        return user["homeys"].items.compactMap(HomeyRef.init)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
