import SwiftUI

@main
struct HomeyDevToolsTVApp: App {
    @State private var store = TVStore()
    @State private var portfolio = TVPortfolio()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environment(store)
                .environment(portfolio)
                .tint(TV.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.reloadAccounts() }
                }
        }
    }
}

/// Accounts shared from the iPhone (iCloud Keychain) + token handling for the Apple TV.
@MainActor
@Observable
final class TVStore: TokenProvider {
    private(set) var accounts: [SharedAccount] = []
    private(set) var activeID: String?
    private(set) var user: JSON = .null
    @ObservationIgnored private var delegated: [String: (token: String, expires: Date?)] = [:]

    init() { reloadAccounts() }

    var active: SharedAccount? { accounts.first { $0.id == activeID } }

    /// Accounts from iCloud Keychain (shared by the iPhone) plus the ones added on
    /// this Apple TV (paired over the local network or entered as a token).
    func reloadAccounts() {
        var merged: [SharedAccount] = []
        for acc in LinkedAccountsStore.load() + SharedAccountsStore.load() {
            if let i = merged.firstIndex(where: { $0.id == acc.id }) {
                if acc.sharedAt > merged[i].sharedAt { merged[i] = acc }
            } else {
                merged.append(acc)
            }
        }
        let loaded = merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if loaded != accounts { accounts = loaded }
        if active == nil {
            let saved = UserDefaults.standard.string(forKey: "tvActiveAccount")
            activeID = accounts.first { $0.id == saved }?.id ?? accounts.first?.id
            delegated.removeAll()
            user = .null
        }
    }

    /// True when the account was added on this Apple TV (and can be removed here).
    func isLinkedHere(_ id: String) -> Bool {
        LinkedAccountsStore.load().contains { $0.id == id }
    }

    /// Saves accounts received from the iPhone over the local network.
    func addLinked(_ new: [SharedAccount]) {
        guard !new.isEmpty else { return }
        LinkedAccountsStore.upsert(new)
        reloadAccounts()
        if active == nil, let first = new.first { switchTo(first.id) }
    }

    /// Verifies a Personal Access Token with `GET /user/me` and saves the account.
    func addPAT(_ raw: String) async throws {
        let pat = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pat.isEmpty else { throw APIError(status: 0, message: L("Vul een Personal Access Token in."), url: "") }
        let me = try await HTTP.send(Config.athomAPI.appendingPathComponent("user/me"),
                                     headers: ["Authorization": "Bearer \(pat)"]).json
        let account = SharedAccount(me: me, pat: pat)
        guard !account.id.isEmpty else { throw APIError(status: 0, message: L("Kon het account niet herkennen."), url: "user/me") }
        LinkedAccountsStore.upsert([account])
        reloadAccounts()
        switchTo(account.id)
    }

    /// Removes an account that was added on this Apple TV.
    func removeLinked(_ id: String) {
        LinkedAccountsStore.remove(id)
        if activeID == id { activeID = nil }
        reloadAccounts()
    }

    func switchTo(_ id: String) {
        guard id != activeID else { return }
        activeID = id
        UserDefaults.standard.set(id, forKey: "tvActiveAccount")
        delegated.removeAll()
        user = .null
    }

    func athom(_ path: String, method: String = "GET", json body: JSON? = nil) async throws -> JSON {
        guard let pat = active?.pat else { throw APIError(status: 401, message: L("Niet ingelogd."), url: "") }
        guard let url = URL(string: path, relativeTo: Config.athomAPI)?.absoluteURL else { throw APIError(status: 0, message: L("Ongeldig pad"), url: path) }
        let data = body.map { $0.data() } ?? (method == "POST" ? Data("{}".utf8) : nil)
        return try await HTTP.send(url, method: method, headers: ["Authorization": "Bearer \(pat)"], body: data).json
    }

    func loadUser() async throws { user = try await athom("/user/me") }

    func delegationToken(audience: String) async throws -> String {
        if let c = delegated[audience], (c.expires ?? .distantFuture) > Date() { return c.token }
        let resp = try await athom("/delegation/token?audience=\(audience)", method: "POST", json: .object([:]))
        let token: String
        switch resp {
        case .string(let s): token = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        default: token = resp.firstString("token", "access_token")
        }
        guard !token.isEmpty else { throw APIError(status: 0, message: L("Geen delegation token ontvangen (\(audience))."), url: "delegation/token") }
        delegated[audience] = (token, JWT.expiry(token))
        return token
    }

    func invalidateDelegation(_ audience: String) { delegated[audience] = nil }

    var homeys: [HomeyRef] {
        var seen = Set<String>()
        return user["homeys"].items.compactMap(HomeyRef.init).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Developer portfolio of the active account, incl. combined install history for the dashboard.
@MainActor
@Observable
final class TVPortfolio {
    var myApps: [DevApp] = []
    var organizations: [DevOrganization] = []
    var orgApps: [String: [DevApp]] = [:]
    var history: [String: [StatPoint]] = [:]
    var loading = false
    var error: String?
    var lastLoaded: Date?
    @ObservationIgnored private var accountID: String?

    var allApps: [DevApp] {
        var seen = Set<String>(), out: [DevApp] = []
        for a in myApps + orgApps.values.flatMap({ $0 }) where seen.insert(a.id).inserted { out.append(a) }
        return out.sorted { $0.installs > $1.installs }
    }

    /// Daily total installs over the apps we have history for.
    var totalHistory: [StatPoint] {
        let cal = Calendar.current
        var perApp: [[Date: Double]] = []
        for (_, pts) in history {
            var d: [Date: Double] = [:]
            for p in pts { d[cal.startOfDay(for: p.date)] = p.value }
            perApp.append(d)
        }
        let days = Set(perApp.flatMap(\.keys)).sorted().suffix(60)
        return days.map { day in
            StatPoint(date: day, value: perApp.reduce(0) { acc, d in
                acc + (d.filter { $0.key <= day }.max { $0.key < $1.key }?.value ?? 0)
            })
        }
    }

    func load(_ store: TVStore, force: Bool = false) async {
        if store.activeID != accountID { reset(); accountID = store.activeID }
        guard store.active != nil, !loading else { return }
        if !force, let lastLoaded, Date().timeIntervalSince(lastLoaded) < 120 { return }
        loading = true; defer { loading = false }
        if store.user.isNull { try? await store.loadUser() }
        let api = AppsAPI(auth: store)
        do { myApps = try await api.myApps(); error = nil } catch { self.error = error.localizedDescription }
        if let orgs = try? await api.organizations() {
            organizations = orgs
            for org in orgs {
                let full = (try? await api.organization(org.id)) ?? org
                if let i = organizations.firstIndex(where: { $0.id == org.id }) { organizations[i] = full }
                if let apps = try? await api.apps(of: full) { orgApps[org.id] = apps }
            }
        }
        for app in allApps.prefix(10) {
            if let pts = try? await api.installStats(app.id) { history[app.id] = pts }
        }
        lastLoaded = Date()
    }

    func reset() {
        myApps = []; organizations = []; orgApps = [:]; history = [:]; error = nil; lastLoaded = nil
    }
}
