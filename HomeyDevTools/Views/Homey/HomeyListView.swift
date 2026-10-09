import SwiftUI

/// The Homeys linked to the active account — the same list Developer Tools uses
/// for its Homey picker (`user/me` → `homeys`), with a fallback to `/homey/{id}`
/// when the account only returns ids.
struct HomeyListView: View {
    @Environment(AuthManager.self) private var auth
    @State private var homeys: [HomeyRef] = []
    @State private var loading = false
    @State private var error: String?
    @AppStorage("activeHomeyId") private var activeHomeyId = ""

    var body: some View {
        List {
            if let error {
                ErrorBanner(message: error) { Task { await reload() } }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(homeys) { h in
                    NavigationLink(value: h) { HomeyRow(homey: h, isActive: h.id == activeHomeyId) }
                }
            } header: {
                if !homeys.isEmpty { Text("Gekoppelde Homeys (\(homeys.count))") }
            } footer: {
                if !homeys.isEmpty {
                    Text("Verbonden via Homey Cloud met een delegation token van je account, net als Developer Tools.")
                }
            }
            .cardRows()

            Section {
                ForEach(Config.webTools, id: \.path) { tool in
                    NavigationLink { WebToolsView(start: Config.devTools(tool.path)) } label: {
                        Label(tool.title, systemImage: tool.icon)
                    }
                }
            } header: {
                Text("Tools & Wireless (Developer Tools)")
            } footer: {
                Text("Zigbee, Z-Wave, RF, IR, BLE, Pairing en meer openen de officiële tools voor je actieve Homey.")
            }
            .cardRows()
        }
        .themedList()
        .overlay {
            if homeys.isEmpty {
                if loading { ProgressView() }
                else if error == nil {
                    ContentUnavailableView("Geen Homeys", systemImage: "circle.circle",
                                           description: Text("Er is geen Homey aan dit account gekoppeld."))
                }
            }
        }
        .navigationTitle("Homeys")
        .navigationDestination(for: HomeyRef.self) { h in
            HomeyDetailView(homey: h).onAppear { activeHomeyId = h.id }
        }
        .toolbar { AccountSwitcherButton() }
        .refreshable { await reload(force: true) }
        .task { await reload() }
        .onChange(of: auth.user) { _, _ in Task { await resolve() } }
    }

    private func reload(force: Bool = false) async {
        loading = true; defer { loading = false }
        if force || auth.user.isNull {
            do { try await auth.loadUser(); error = nil } catch { self.error = error.localizedDescription }
        }
        await resolve()
    }

    /// Parse `user.homeys`; entries that are only ids are fetched individually.
    private func resolve() async {
        let raw = auth.user["homeys"].items
        var out: [HomeyRef] = raw.compactMap(HomeyRef.init)
        let idsOnly = raw.compactMap { $0.string }.filter { id in !out.contains { $0.id == id } }
        for id in idsOnly {
            if let j = try? await auth.athom("/homey/\(id)"), let h = HomeyRef(j) { out.append(h) }
        }
        var seen = Set<String>()
        homeys = out.filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !auth.user.isNull && homeys.isEmpty && raw.isEmpty && error == nil {
            error = nil
        }
    }
}

struct HomeyRow: View {
    let homey: HomeyRef
    var isActive = false

    var body: some View {
        HStack(spacing: 12) {
            HomeyLogo(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(homey.name).font(.body.weight(.medium))
                    if isActive { StateBadge(state: "actief") }
                }
                Text(homey.subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct HomeyDetailView: View {
    let homey: HomeyRef
    @Environment(AuthManager.self) private var auth
    @State private var client: HomeyClient?

    var body: some View {
        Group {
            if let client {
                List {
                    Section {
                        HStack(spacing: 14) {
                            HomeyLogo(size: 54)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(homey.name).font(.title3.weight(.semibold))
                                Text(homey.subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)

                    Section {
                        NavigationLink { DevicesView(client: client) } label: { Label("Apparaten", systemImage: "lightbulb.2") }
                        NavigationLink { FlowsView(client: client) } label: { Label("Flows", systemImage: "arrow.triangle.branch") }
                        NavigationLink { HomeyAppsView(client: client) } label: { Label("Apps", systemImage: "square.stack.3d.up") }
                        NavigationLink { VariablesView(client: client) } label: { Label("Logic-variabelen", systemImage: "function") }
                        NavigationLink { NotificationsView(client: client) } label: { Label("Tijdlijn", systemImage: "bell") }
                    }
                    .cardRows()

                    Section("Developer") {
                        NavigationLink { SystemView(client: client) } label: { Label("Systeeminformatie", systemImage: "cpu") }
                        NavigationLink { APIPlaygroundView(target: .homey(client)) } label: { Label("Web API Playground", systemImage: "terminal") }
                        ForEach(Config.webTools.filter { $0.path != "/tools/system" && $0.path != "/tools/api-playground" }, id: \.path) { tool in
                            NavigationLink { WebToolsView(start: Config.devTools(tool.path)) } label: { Label(tool.title, systemImage: tool.icon) }
                        }
                    }
                    .cardRows()

                    Section("Homey") {
                        LabeledContent("ID", value: homey.id).textSelection(.enabled)
                        if !homey.model.isEmpty { LabeledContent("Model", value: homey.model) }
                        if !homey.platform.isEmpty { LabeledContent("Platform", value: homey.platform) }
                        if !homey.softwareVersion.isEmpty { LabeledContent("Versie", value: homey.softwareVersion) }
                        if !homey.role.isEmpty { LabeledContent("Rol", value: homey.role) }
                        LabeledContent("Remote URL", value: homey.remoteURL.host() ?? "").font(.caption)
                        NavigationLink("Ruwe data") { JSONInspectorView(title: homey.name, json: homey.raw) }
                    }
                    .cardRows()
                }
                .themedList()
            } else {
                HomeyLogo(size: 54, spinning: true)
            }
        }
        .navigationTitle(homey.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if client == nil { client = HomeyClient(homey: homey, auth: auth) } }
    }
}
