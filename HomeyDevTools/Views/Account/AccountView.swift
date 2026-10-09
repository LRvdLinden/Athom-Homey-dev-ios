import SwiftUI

struct AccountView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(PortfolioStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system

    @State private var addAccount = false
    @State private var confirmSignOut: StoredAccount?

    var body: some View {
        List {
            // Active account
            Section {
                HStack(spacing: 14) {
                    AccountAvatar(url: auth.avatarURL, initials: auth.active?.initials ?? "", size: 62)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(auth.displayName.isEmpty ? "Homey-account" : auth.displayName).font(.title3.weight(.semibold))
                        if !auth.email.isEmpty { Text(auth.email).font(.subheadline).foregroundStyle(Theme.textSecondary) }
                        Text(auth.loginMethodLabel).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 6)
                if auth.active?.needsLogin == true {
                    Button { addAccount = true } label: {
                        Label("Sessie verlopen – opnieuw inloggen", systemImage: "exclamationmark.arrow.circlepath")
                    }
                    .foregroundStyle(.orange)
                }
            }
            .cardRows()

            // Facebook-style account switching
            Section {
                ForEach(auth.otherAccounts) { acc in
                    Button { auth.switchTo(acc.id) } label: { AccountRow(account: acc) }
                        .buttonStyle(.plain)
                        .swipeActions { Button("Afmelden", role: .destructive) { confirmSignOut = acc } }
                }
                Button { addAccount = true } label: { Label("Account toevoegen", systemImage: "person.crop.circle.badge.plus") }
            } header: {
                Text("Wisselen van account")
            } footer: {
                Text("Ingelogde accounts blijven veilig bewaard in de iOS-sleutelhanger. Tik om te wisselen, veeg om af te melden.")
            }
            .cardRows()

            Section("Weergave") {
                Picker(selection: $appearance) {
                    ForEach(AppearanceSetting.allCases) { s in
                        Label(s.label, systemImage: s.icon).tag(s)
                    }
                } label: {
                    Label("Thema", systemImage: "paintbrush")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .cardRows()

            if !store.organizations.isEmpty {
                Section("My Organizations") {
                    ForEach(store.organizations) { org in
                        NavigationLink { OrganizationDetailView(org: org) } label: {
                            HStack(spacing: 10) {
                                OrgAvatar(org: org, size: 30)
                                Text(org.name)
                                Spacer()
                                Text("\(store.orgApps[org.id]?.count ?? org.appRefs.count) apps").foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .cardRows()
            }

            Section("Developer") {
                NavigationLink { APIClientsView() } label: { Label("My API Clients", systemImage: "person.badge.key") }
                NavigationLink { WebToolsView(start: Config.webhooksPage) } label: { Label("My Webhooks", systemImage: "link") }
                NavigationLink { WebToolsView(start: Config.accountPage) } label: { Label("My Account & Personal Access Tokens", systemImage: "key") }
                NavigationLink { APIPlaygroundView(target: .apps) } label: { Label("Apps API Playground", systemImage: "terminal") }
                NavigationLink { APIPlaygroundView(target: .athom) } label: { Label("Athom API Playground", systemImage: "terminal.fill") }
                NavigationLink { WebToolsView() } label: { Label("Developer Tools (volledige website)", systemImage: "safari") }
                NavigationLink { JSONInspectorView(title: "user/me", json: auth.user) } label: { Label("Accountgegevens (ruw)", systemImage: "curlybraces") }
            }
            .cardRows()

            Section("Documentatie") {
                Button { openURL(URL(string: "https://apps.developer.homey.app")!) } label: { Label("Apps SDK", systemImage: "book") }
                Button { openURL(URL(string: "https://apps-sdk-v3.developer.homey.app/")!) } label: { Label("JavaScript Reference", systemImage: "curlybraces.square") }
                Button { openURL(URL(string: "https://api.developer.homey.app")!) } label: { Label("Web API", systemImage: "book.closed") }
            }
            .cardRows()

            Section {
                if let active = auth.active {
                    Button("Afmelden bij \(active.name.isEmpty ? active.email : active.name)", role: .destructive) { confirmSignOut = active }
                }
            } footer: {
                Text("Developer Tools voor Homey · v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Account")
        .navigationDestination(for: DevApp.self) { AppDetailView(app: $0) }
        .toolbar { AccountSwitcherButton() }
        .refreshable { try? await auth.loadUser(); await store.load(auth: auth, force: true) }
        .fullScreenCover(isPresented: $addAccount) { LoginView(isAddingAccount: true) }
        .confirmationDialog(
            "Afmelden?",
            isPresented: Binding(get: { confirmSignOut != nil }, set: { if !$0 { confirmSignOut = nil } }),
            titleVisibility: .visible,
            presenting: confirmSignOut
        ) { acc in
            Button("Afmelden bij \(acc.name.isEmpty ? acc.email : acc.name)", role: .destructive) { auth.signOut(acc.id) }
        } message: { _ in
            Text("Het account wordt van dit toestel verwijderd. Je kunt het later opnieuw toevoegen.")
        }
    }
}

/// My API Clients (api.athom.com/user/me/client).
struct APIClientsView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Loader(load: { () async throws -> [JSON] in try await auth.athom("/user/me/client").items }) { (clients: [JSON], reload) in
            List {
                ForEach(Array(clients.enumerated()), id: \.offset) { _, c in
                    NavigationLink { JSONInspectorView(title: c.firstString("name", "id"), json: c) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.firstString("name", "title", "_id", "id")).font(.body.weight(.medium))
                            Text(c.firstString("_id", "id")).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
                            let uris = c["redirectUri"].array.compactMap(\.string)
                            if !uris.isEmpty { Text(uris.joined(separator: ", ")).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(2) }
                        }
                    }
                    .cardRows()
                }
                Section {
                    NavigationLink { WebToolsView(start: Config.apiClientsPage) } label: { Label("Beheren / nieuwe client", systemImage: "plus") }
                }
                .cardRows()
            }
            .themedList()
            .overlay { if clients.isEmpty { ContentUnavailableView("Geen API clients", systemImage: "person.badge.key") } }
            .refreshable { await reload() }
        }
        .navigationTitle("My API Clients")
    }
}
