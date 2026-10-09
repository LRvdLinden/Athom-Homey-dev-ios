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

            AppleTVSection()

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


/// Share saved accounts with the Apple TV app through iCloud Keychain.
struct AppleTVSection: View {
    @Environment(AuthManager.self) private var auth
    @AppStorage(AppleTVSharing.enabledKey) private var enabled = false
    @State private var busy = false
    @State private var status: String?
    @State private var error: String?

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { enabled }, set: { on in enabled = on; Task { await apply(on) } })) {
                Label("Delen met Apple TV", systemImage: "appletv")
            }
            .disabled(busy)
            NavigationLink { TVLinkView() } label: {
                Label("Koppel via wifi", systemImage: "wifi")
            }
            if enabled {
                Button { Task { await apply(true) } } label: {
                    HStack { Label("Nu bijwerken", systemImage: "arrow.triangle.2.circlepath"); if busy { Spacer(); ProgressView() } }
                }
                .disabled(busy)
            }
            if let status { Text(status).font(.footnote).foregroundStyle(.green) }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Apple TV")
        } footer: {
            Text("‘Koppel via wifi’ stuurt je accounts direct naar een Apple TV in hetzelfde netwerk, met de code die de Apple TV toont. ‘Delen met Apple TV’ gaat via je iCloud-sleutelhanger en kan even duren. Beide gebruiken per account je Personal Access Token (zoals ‘Reveal’ in Developer Tools → My Account).")
        }
        .cardRows()
    }

    private func apply(_ on: Bool) async {
        busy = true; error = nil; status = nil
        defer { busy = false }
        guard on else { AppleTVSharing.stop(); status = L("Niet meer gedeeld met Apple TV"); return }
        do {
            let n = try await AppleTVSharing.publish(auth: auth)
            status = L("\(n) account(s) gedeeld met Apple TV")
        } catch {
            self.error = error.localizedDescription
        }
    }
}


/// Sends the saved accounts to an Apple TV on the same network, using the code it shows.
struct TVLinkView: View {
    @Environment(AuthManager.self) private var auth
    @State private var sender = TVLinkSender()
    @State private var selected: TVLinkSender.FoundTV?
    @State private var code = ""
    @State private var preparing = false
    @State private var prepareError: String?

    var body: some View {
        List {
            Section {
                Label("Open Homey Dev op je Apple TV. Daar staat een code van 4 cijfers.", systemImage: "appletv")
                Label("Kies hieronder je Apple TV en voer die code in.", systemImage: "number")
            }
            .cardRows()

            Section {
                if sender.found.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Apple TV zoeken…").foregroundStyle(Theme.textSecondary)
                    }
                }
                ForEach(sender.found) { (tv: TVLinkSender.FoundTV) in
                    Button { code = ""; selected = tv } label: {
                        Label(tv.name, systemImage: "appletv.fill")
                    }
                    .disabled(busy)
                }
            } header: {
                Text("Apple TV in dit netwerk")
            } footer: {
                Text("iPhone en Apple TV moeten op hetzelfde wifi-netwerk zitten. Sta ‘Lokaal netwerk’ toe als iOS daarom vraagt.")
            }
            .cardRows()

            statusSection
        }
        .themedList()
        .navigationTitle("Koppel via wifi")
        .onAppear { sender.start() }
        .onDisappear { sender.stop() }
        .alert("Code van je Apple TV", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            TextField("0000", text: $code)
                .keyboardType(.numberPad)
            Button("Annuleer", role: .cancel) { selected = nil }
            Button("Koppel") {
                if let tv = selected { Task { await link(tv) } }
                selected = nil
            }
        } message: {
            Text("Voer de 4 cijfers in die op je Apple TV staan.")
        }
    }

    private var busy: Bool { preparing || sender.status == .sending }

    @ViewBuilder
    private var statusSection: some View {
        if preparing {
            Section { HStack(spacing: 12) { ProgressView(); Text("Accounts voorbereiden…") } }.cardRows()
        } else if let prepareError {
            Section { Label(prepareError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }.cardRows()
        } else {
            switch sender.status {
            case .searching:
                EmptyView()
            case .sending:
                Section { HStack(spacing: 12) { ProgressView(); Text("Versturen naar Apple TV…") } }.cardRows()
            case .done(let n):
                Section { Label(L("\(n) account(s) staan nu op je Apple TV"), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }.cardRows()
            case .failed(let message):
                Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }.cardRows()
            }
        }
    }

    private func link(_ tv: TVLinkSender.FoundTV) async {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 4 else { prepareError = L("Voer de 4 cijfers van je Apple TV in."); return }
        prepareError = nil
        preparing = true
        defer { preparing = false }
        do {
            let accounts = try await AppleTVSharing.sharedAccounts(auth: auth)
            sender.reset()
            sender.send(accounts, to: tv, code: trimmed)
        } catch {
            prepareError = error.localizedDescription
        }
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
            Text("Statusmeldingen: de app controleert zelf bij elke verversing en op de achtergrond (iOS bepaalt hoe vaak). Direct via push: een server controleert elke paar minuten en stuurt een pushmelding via OneSignal, ook als de app dicht is. Met push aan stuurt de app zelf geen dubbele meldingen.")
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
