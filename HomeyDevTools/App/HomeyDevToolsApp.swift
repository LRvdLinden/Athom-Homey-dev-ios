import SwiftUI

@main
struct HomeyDevToolsApp: App {
    @State private var auth = AuthManager()
    @State private var portfolio = PortfolioStore()
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(portfolio)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var portfolio
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                if auth.isLoggedIn {
                    MainTabView()
                        .id(auth.activeID)          // fresh view tree per account
                } else {
                    LoginView()
                }
            }
            .animation(.default, value: auth.isLoggedIn)

            if showSplash {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(1)
            }
        }
        .task {
            let start = Date()
            if auth.isLoggedIn {
                let auth = auth, portfolio = portfolio
                async let user: Void? = try? auth.loadUser()
                async let apps: Void = portfolio.load(auth: auth, force: true)
                _ = await (user, apps)
            }
            let remaining = 1.6 - Date().timeIntervalSince(start)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
        }
        .onChange(of: auth.activeID) { _, _ in
            portfolio.reset()
            Task { await portfolio.load(auth: auth, force: true) }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { AppsListView() }
                .tabItem { Label("My Apps", systemImage: "square.stack.3d.up.fill") }
            NavigationStack { OrganizationsView() }
                .tabItem { Label("Organisaties", systemImage: "building.2.fill") }
            NavigationStack { HomeyListView() }
                .tabItem { Label("Homeys", systemImage: "circle.circle") }
            NavigationStack { AccountView() }
                .tabItem { Label("Account", systemImage: "person.crop.circle.fill") }
        }
    }
}

/// Shared cache of the developer portfolio (own apps + organisations) for the active account.
@MainActor
@Observable
final class PortfolioStore {
    enum Source: Hashable, Identifiable {
        case mine
        case org(String)
        var id: String { switch self { case .mine: return "me"; case .org(let id): return id } }
    }

    var myApps: [DevApp] = []
    var organizations: [DevOrganization] = []
    var orgApps: [String: [DevApp]] = [:]
    var isLoading = false
    var error: String?
    var orgError: String?
    var lastLoaded: Date?
    @ObservationIgnored private var generation = 0

    func reset() {
        generation += 1
        myApps = []; organizations = []; orgApps = [:]; error = nil; orgError = nil; lastLoaded = nil; isLoading = false
    }

    var allApps: [DevApp] {
        var seen = Set<String>(), out: [DevApp] = []
        for a in myApps + orgApps.values.flatMap({ $0 }) where seen.insert(a.id).inserted { out.append(a) }
        return out.sorted { $0.installs > $1.installs }
    }

    func apps(for source: Source) -> [DevApp] {
        switch source {
        case .mine: return myApps
        case .org(let id): return orgApps[id] ?? []
        }
    }

    func load(auth: AuthManager, force: Bool = false) async {
        if isLoading { return }
        if !force, let lastLoaded, Date().timeIntervalSince(lastLoaded) < 120 { return }
        let gen = generation
        isLoading = true
        defer { if gen == generation { isLoading = false } }
        let api = AppsAPI(auth: auth)
        do {
            let mine = try await api.myApps()
            guard gen == generation else { return }
            myApps = mine
            error = nil
        } catch {
            guard gen == generation else { return }
            self.error = error.localizedDescription
        }
        do {
            let orgs = try await api.organizations()
            guard gen == generation else { return }
            organizations = orgs
            orgError = nil
            for org in orgs {
                let full = (try? await api.organization(org.id)) ?? org
                guard gen == generation else { return }
                if let i = organizations.firstIndex(where: { $0.id == org.id }) { organizations[i] = full }
                if let apps = try? await api.apps(of: full) { orgApps[org.id] = apps }
            }
        } catch {
            guard gen == generation else { return }
            orgError = error.localizedDescription
        }
        lastLoaded = Date()
        await WidgetSync.update(apps: allApps, accountName: auth.displayName)
    }
}
