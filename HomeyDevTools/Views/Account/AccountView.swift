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
                        Text(auth.displayName.isEmpty ? L("Homey-account") : auth.displayName).font(.title3.weight(.semibold))
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

            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    LabeledContent {
                        Text(Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "") ?? "")
                    } label: {
                        Label("Taal", systemImage: "globe")
                    }
                }
            } footer: {
                Text("De app volgt de taal van je toestel. Kies in Instellingen een andere taal alleen voor deze app.")
            }
            .cardRows()

            NotificationsSection()

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
            }
            .cardRows()

            Section {
                NavigationLink { LegalDocumentView(document: .privacy) } label: {
                    Label("Privacy & voorwaarden", systemImage: "lock.shield")
                }
                NavigationLink { LegalDocumentView(document: .disclaimer) } label: {
                    Label("Disclaimer", systemImage: "hand.raised")
                }
            } footer: {
                AppFooter()
                    .padding(.top, 28)
                    .padding(.bottom, 12)
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


/// Account → Meldingen: notifications for every status change of your apps.
struct NotificationsSection: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.openURL) private var openURL
    @AppStorage(StatusNotifier.enabledKey) private var enabled = false
    @AppStorage(PushNotifications.enabledKey) private var pushEnabled = false
    @State private var busy = false
    @State private var pushBusy = false
    @State private var error: String?

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { enabled }, set: { on in Task { await apply(on) } })) {
                HStack {
                    Label("Statusmeldingen", systemImage: "bell.badge")
                    if busy { Spacer(); ProgressView() }
                }
            }
            .disabled(busy)

            Toggle(isOn: Binding(get: { pushEnabled }, set: { on in Task { await applyPush(on) } })) {
                HStack {
                    Label("Direct via push (OneSignal)", systemImage: "bolt.badge.clock")
                    if pushBusy { Spacer(); ProgressView() }
                }
            }
            .disabled(pushBusy)

            if enabled || pushEnabled {
                ForEach(StatusNotifier.Kind.allCases) { (kind: StatusNotifier.Kind) in
                    KindToggle(kind: kind)
                }
                Button { StatusNotifier.sendTest() } label: {
                    Label("Testmelding sturen", systemImage: "paperplane")
                }
            }
            if pushEnabled && !enabled {
                Label("Alleen push: draait de GitHub-taak niet, dan krijg je niets. Zet ook Statusmeldingen aan als reserve.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(enabled ? .orange : .red)
                if !enabled {
                    Button("Open Instellingen") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote)
                }
            }
        } header: {
            Text("Meldingen")
        } footer: {
            Text("Statusmeldingen: de app controleert zelf bij elke verversing en op de achtergrond (iOS bepaalt hoe vaak). Direct via push: een GitHub Actions-taak controleert elk half uur en stuurt een pushmelding via OneSignal, ook als de app dicht is. Zet je beide aan, dan vangt de app het op als de push-server stilvalt; dezelfde wijziging verschijnt maar één keer.")
        }
        .cardRows()
    }

    private func applyPush(_ on: Bool) async {
        error = nil
        guard on else { PushNotifications.disable(); pushEnabled = false; return }
        pushBusy = true
        defer { pushBusy = false }
        do {
            try await PushNotifications.enable(auth: auth)
            pushEnabled = true
        } catch {
            pushEnabled = false
            self.error = error.localizedDescription
        }
    }

    private func apply(_ on: Bool) async {
        error = nil
        guard on else { StatusNotifier.disable(); enabled = false; return }
        busy = true
        defer { busy = false }
        do {
            if let warning = try await StatusNotifier.enable(auth: auth) { self.error = warning }
            enabled = true
        } catch {
            enabled = false
            self.error = error.localizedDescription
        }
    }
}

private struct KindToggle: View {
    let kind: StatusNotifier.Kind
    @Environment(AuthManager.self) private var auth
    @AppStorage private var isOn: Bool

    init(kind: StatusNotifier.Kind) {
        self.kind = kind
        _isOn = AppStorage(wrappedValue: true, kind.key)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(kind.title, systemImage: kind.icon)
        }
        .onChange(of: isOn) { _, _ in PushNotifications.sync(auth: auth) }
    }
}


/// Version, build and copyright at the bottom of the Account page.
struct AppFooter: View {
    var body: some View {
        VStack(spacing: 6) {
            HomeyLogo(size: 30)
                .opacity(0.9)
            Text(AppInfo.versionLine)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text(AppInfo.copyright)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

/// Privacy / disclaimer page in the app's card style.
struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 14) {
                    Image(systemName: document.icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Theme.buttonGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 6)
                    Text(document.title).font(.title2.weight(.bold))
                    Text(document.intro)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                ForEach(document.parts) { (part: LegalDocument.Part) in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: part.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 34, height: 34)
                            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(part.title).font(.headline)
                            Text(part.text)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .homeyCard()
                }

                Text(document.updated)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                AppFooter().padding(.vertical, 20)
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
