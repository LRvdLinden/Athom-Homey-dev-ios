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
        .commands {
            SidebarCommands()
            CommandGroup(after: .toolbar) {
                Button("Gegevens verversen") {
                    Task {
                        try? await auth.loadUser()
                        await portfolio.load(auth: auth, force: true)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Link("Homey Developer Tools", destination: Config.developerToolsWeb)
                Link("Apps SDK-documentatie", destination: URL(string: "https://apps.developer.homey.app")!)
                Link("Web API-documentatie", destination: URL(string: "https://api.developer.homey.app")!)
            }
        }
    }
}

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var portfolio
    @State private var showSplash = true
    /// The account whose view tree is on screen. When the active account changes,
    /// the old tree is removed first (one short loading frame) before the new one
    /// is built. Swapping both in one step made the Mac app crash on sign-in,
    /// because the window toolbar still held items of the old tree.
    @State private var shownID: String?

    var body: some View {
        ZStack {
            Group {
                if let id = auth.activeID, auth.isLoggedIn {
                    if shownID == id {
                        MainTabView()
                            .id(id)                 // fresh view tree per account
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.background.ignoresSafeArea())
                    }
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
        .onChange(of: auth.accounts.map(\.id)) { _, _ in
            guard AppleTVSharing.isEnabled else { return }
            Task { _ = try? await AppleTVSharing.publish(auth: auth) }
        }
        .onAppear { shownID = auth.activeID }
        .onChange(of: auth.activeID) { _, newID in
            shownID = nil
            portfolio.reset()
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                if auth.activeID == newID { shownID = newID }
                await portfolio.load(auth: auth, force: true)
            }
        }
    }
}

/// iPhone: tab bar. iPad (regular width): sidebar like tools.developer.homey.app.
struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            SidebarRootView()
        } else {
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
}

enum SidebarItem: Hashable {
    case home, apps, organizations, homeys, account, apiClients, webhooks, website
    case tool(HomeyTool)
}

/// iPad layout: Developer Tools-style sidebar with sections and the web tools.
struct SidebarRootView: View {
    @Environment(AuthManager.self) private var auth
    @State private var selection: SidebarItem? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var path = NavigationPath()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section {
                    HStack(spacing: 10) {
                        Image("HomeyLogo").resizable().scaledToFit().frame(width: 28, height: 28)
                        Text("Developer Tools").font(.title3.weight(.bold))
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }
                Section {
                    Label("Home", systemImage: "house.fill").tag(SidebarItem.home)
                    Label("My Apps", systemImage: "square.stack.3d.up.fill").tag(SidebarItem.apps)
                    Label("My Organizations", systemImage: "building.2.fill").tag(SidebarItem.organizations)
                    Label("My API Clients", systemImage: "person.badge.key.fill").tag(SidebarItem.apiClients)
                    Label("My Webhooks", systemImage: "link").tag(SidebarItem.webhooks)
                }
                Section("Homey") {
                    Label("Homeys", systemImage: "circle.circle").tag(SidebarItem.homeys)
                    ForEach(HomeyTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.icon).tag(SidebarItem.tool(tool))
                    }
                }
                Section {
                    Label("Developer Tools (volledige website)", systemImage: "safari").tag(SidebarItem.website)
                    Label {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(auth.displayName.isEmpty ? L("Account") : auth.displayName).lineLimit(1)
                            if !auth.email.isEmpty { Text(auth.email).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    } icon: {
                        AccountAvatar(url: auth.avatarURL, initials: auth.active?.initials ?? "", size: 26)
                    }
                    .tag(SidebarItem.account)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Homey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        } detail: {
            // One stack for the whole app; it is reset when another section is
            // chosen instead of being rebuilt with `.id`, which on the Mac left
            // duplicate items in the window toolbar.
            NavigationStack(path: $path) {
                detail(for: selection ?? .home)
            }
        }
        .onChange(of: selection) { _, _ in path = NavigationPath() }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .home: DashboardView()
        case .apps: AppsListView()
        case .organizations: OrganizationsView()
        case .homeys: HomeyListView()
        case .account: AccountView()
        case .apiClients: APIClientsView()
        case .webhooks: WebToolsView(start: Config.webhooksPage)
        case .website: WebToolsView()
        case .tool(let tool): NativeToolHost(tool: tool)
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
        await WidgetSync.update(apps: allApps, accountName: auth.displayName, auth: auth)
    }
}
