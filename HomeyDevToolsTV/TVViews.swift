import SwiftUI
import Charts

// MARK: - Style

enum TV {
    static let accent = Color(red: 0, green: 0.51, blue: 0.98)
    static let card = Color(red: 0.133, green: 0.137, blue: 0.161)
    static let background = Color(red: 0.071, green: 0.075, blue: 0.098)
    static func number(_ n: Int) -> String { n.formatted(.number) }
    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }
    static func relative(_ d: Date?) -> String { d?.formatted(.relative(presentation: .named)) ?? "—" }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

struct TVLogo: View {
    var size: CGFloat = 60
    var spinning = false
    var body: some View {
        if spinning {
            TimelineView(.animation) { ctx in
                Image("HomeyLogo").resizable().scaledToFit().frame(width: size, height: size)
                    .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.3) / 1.3 * 360))
            }
        } else {
            Image("HomeyLogo").resizable().scaledToFit().frame(width: size, height: size)
        }
    }
}

struct TVAppIcon: View {
    let app: DevApp
    var size: CGFloat = 80
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Color(hex: app.brandColor) ?? TV.accent.opacity(0.3))
            if let url = app.iconURL {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Text(app.name.prefix(1)).font(.title).bold() }
            } else {
                Text(app.name.prefix(1)).font(.title).bold()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

struct TVTile: View {
    let title: LocalizedStringKey
    let value: String
    let icon: String
    var tint: Color = TV.accent
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.5)
            if let detail { Text(detail).font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(TV.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .tvFocusCard()
    }
}

/// Lets a non-interactive card take focus, so the Siri Remote can move down
/// through the dashboard (tvOS only scrolls by moving focus).
struct TVFocusCard: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .scaleEffect(focused ? 1.03 : 1)
            .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 24, y: 12)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

extension View {
    func tvFocusCard() -> some View { modifier(TVFocusCard()) }
}

struct TVBadge: View {
    let state: String

    private var label: String {
        switch state {
        case "in_review": L("In review")
        case "live", "reviewed_approved", "approved": L("Live")
        case "test": L("Test")
        case "reviewed_rejected", "rejected": L("Afgewezen")
        default: state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var color: Color {
        switch state {
        case "in_review": .orange
        case "live", "reviewed_approved", "approved": .green
        case "test": .blue
        case "reviewed_rejected", "rejected": .red
        default: .gray
        }
    }

    var body: some View {
        if !state.isEmpty {
            Text(label).font(.caption.weight(.bold))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(color.opacity(0.2), in: Capsule()).foregroundStyle(color)
        }
    }
}

struct TVInstallChart: View {
    let points: [StatPoint]
    var height: CGFloat = 320

    var body: some View {
        let data = Array(points.suffix(60))
        if data.count > 1 {
            Chart(data) { p in
                AreaMark(x: .value("Datum", p.date), y: .value("Installaties", p.value))
                    .foregroundStyle(LinearGradient(colors: [TV.accent.opacity(0.45), TV.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Datum", p.date), y: .value("Installaties", p.value))
                    .foregroundStyle(TV.accent)
                    .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: height)
        } else {
            Text("Nog geen geschiedenis").foregroundStyle(.secondary).frame(height: height)
        }
    }
}

// MARK: - Root

struct TVRootView: View {
    @Environment(TVStore.self) private var store
    @State private var splash = true

    var body: some View {
        ZStack {
            if store.active == nil {
                TVWelcomeView()
            } else {
                TabView {
                    NavigationStack { TVDashboardView() }.tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
                    NavigationStack { TVAppsView() }.tabItem { Label("My Apps", systemImage: "square.stack.3d.up.fill") }
                    NavigationStack { TVOrganizationsView() }.tabItem { Label("Organisaties", systemImage: "building.2.fill") }
                    NavigationStack { TVSettingsView() }.tabItem { Label("Account", systemImage: "person.crop.circle.fill") }
                }
                .id(store.activeID)
            }
            if splash {
                ZStack {
                    TV.background.ignoresSafeArea()
                    VStack(spacing: 30) {
                        TVLogo(size: 180, spinning: true)
                        Text("Homey Developer Tools").font(.title2.bold())
                    }
                }
                .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeInOut(duration: 0.5)) { splash = false }
        }
    }
}

struct TVWelcomeView: View {
    @Environment(TVStore.self) private var store

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 70) {
                VStack(spacing: 30) {
                    TVLogo(size: 220)
                    Text("Homey Developer Tools").font(.title2.bold()).multilineTextAlignment(.center)
                }
                .frame(width: 420)
                .padding(.top, 40)
                TVAddAccountPanel()
            }
            .padding(70)
        }
        .task {
            // Accounts shared through iCloud Keychain can arrive later; keep looking.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                store.reloadAccounts()
            }
        }
    }
}

/// The three ways to get an account onto the Apple TV.
struct TVAddAccountPanel: View {
    @Environment(TVStore.self) private var store
    @State private var receiver = TVLinkReceiver()

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Koppelen met je iPhone", systemImage: "iphone.radiowaves.left.and.right").font(.title3.bold())
                Text("Open de app op je iPhone → Account → Apple TV → Koppel via wifi, kies deze Apple TV en voer deze code in:")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    ForEach(0..<4, id: \.self) { (i: Int) in
                        Text(digit(at: i))
                            .font(.system(size: 76, weight: .bold, design: .rounded).monospacedDigit())
                            .frame(width: 104, height: 128)
                            .background(TV.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                statusView
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("Of voer een Personal Access Token in", systemImage: "key.fill").font(.title3.bold())
                NavigationLink { TVPATLoginView() } label: {
                    Label("Token invoeren", systemImage: "keyboard")
                }
                Text("Tip: je iPhone toont een melding om met het toetsenbord van je iPhone te typen of te plakken.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text("Je kunt accounts ook delen via de iCloud-sleutelhanger (iPhone-app → Account → Apple TV → Delen met Apple TV). Dat kan een paar minuten duren.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 1000, alignment: .leading)
        .onAppear {
            receiver.onAccounts = { accounts in store.addLinked(accounts) }
            receiver.start()
        }
        .onDisappear { receiver.stop() }
    }

    private func digit(at index: Int) -> String {
        let chars: [Character] = Array(receiver.code)
        return index < chars.count ? String(chars[index]) : ""
    }

    @ViewBuilder
    private var statusView: some View {
        switch receiver.status {
        case .idle:
            EmptyView()
        case .waiting:
            Label("Wacht op je iPhone…", systemImage: "wifi").font(.callout).foregroundStyle(.secondary)
        case .connecting:
            HStack(spacing: 14) { ProgressView(); Text("Verbinden…").font(.callout) }
        case .received(let n):
            Label(L("\(n) account(s) toegevoegd"), systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
        }
    }
}

/// Log in on the Apple TV with a Personal Access Token.
struct TVPATLoginView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("Personal Access Token").font(.title2.bold())
            Text("Maak of toon je token in Developer Tools onder My Account → Personal Access Tokens (Reveal). Plak het via je iPhone-toetsenbord.")
                .font(.callout).foregroundStyle(.secondary)
            SecureField("Personal Access Token", text: $token)
                .textContentType(.password)
                .frame(maxWidth: 1000)
            HStack(spacing: 24) {
                Button { Task { await submit() } } label: {
                    if busy { ProgressView() } else { Label("Toevoegen", systemImage: "checkmark") }
                }
                .disabled(busy || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Annuleer") { dismiss() }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func submit() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await store.addPAT(token)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Dashboard

struct TVDashboardView: View {
    @Environment(TVStore.self) private var store
    @Environment(TVPortfolio.self) private var portfolio

    var body: some View {
        let apps = portfolio.allApps
        let installs = apps.reduce(0) { $0 + $1.installs }
        let cloud = apps.reduce(0) { $0 + $1.installsCloud }
        let local = apps.reduce(0) { $0 + $1.installsLocal }
        let review = apps.filter(\.inReview)
        let crashes = apps.reduce(0) { $0 + $1.liveCrashes }
        let rated = apps.compactMap(\.rating).filter { $0 > 0 }
        let rating = rated.isEmpty ? nil : rated.reduce(0, +) / Double(rated.count)
        let hist = portfolio.totalHistory
        let delta7: Int? = {
            guard let last = hist.last, let cut = Calendar.current.date(byAdding: .day, value: -7, to: last.date),
                  let base = hist.last(where: { $0.date <= cut }) else { return nil }
            return Int(last.value - base.value)
        }()

        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HStack(spacing: 20) {
                    TVLogo(size: 64)
                    VStack(alignment: .leading) {
                        Text(store.active?.name ?? "").font(.title2.bold())
                        Text("Bijgewerkt \(TV.relative(portfolio.lastLoaded))").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if portfolio.loading { ProgressView() }
                }
                if let e = portfolio.error { Text(e).foregroundStyle(.orange) }

                HStack(spacing: 24) {
                    TVTile(title: "Installaties", value: TV.number(installs), icon: "arrow.down.circle.fill",
                           detail: delta7.map { "\($0 >= 0 ? "+" : "")\(TV.number($0)) · 7d" })
                    TVTile(title: "Cloud / Local", value: "\(TV.compact(cloud)) / \(TV.compact(local))", icon: "cloud.fill", tint: .cyan)
                    TVTile(title: "In review", value: "\(review.count)", icon: "hourglass", tint: review.isEmpty ? .secondary : .orange)
                    TVTile(title: "Live crashes", value: "\(crashes)", icon: "ladybug.fill", tint: crashes > 0 ? .red : .green)
                    TVTile(title: "Gem. rating", value: rating.map { String(format: "%.1f ★", $0) } ?? "—", icon: "star.fill", tint: .yellow)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Installatietrend (60 dagen)").font(.headline)
                    TVInstallChart(points: hist)
                }
                .padding(28)
                .background(TV.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .tvFocusCard()

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top apps").font(.headline)
                        ForEach(apps.prefix(6)) { app in
                            NavigationLink { TVAppDetailView(app: app) } label: { TVAppRow(app: app) }.buttonStyle(.card)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Wacht op certificering").font(.headline)
                        if review.isEmpty {
                            Label("Niets in review", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(TV.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .tvFocusCard()
                        }
                        ForEach(review) { app in
                            NavigationLink {
                                TVAppDetailView(app: app)
                            } label: {
                                HStack { TVAppIcon(app: app, size: 56); Text(app.name); Spacer(); Text("v\(app.testVersion)").foregroundStyle(.orange) }
                                    .padding(16)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .frame(width: 620, alignment: .leading)
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 30)
        }
        .scrollClipDisabled()
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            await portfolio.load(store)
            // Status board: refresh every 5 minutes while visible.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await portfolio.load(store, force: true)
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

struct TVAppRow: View {
    let app: DevApp
    var body: some View {
        HStack(spacing: 20) {
            TVAppIcon(app: app, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(app.name).font(.headline); if app.inReview { TVBadge(state: "in_review") } }
                Text("live \(app.liveVersion)").font(.caption).foregroundStyle(.green)
            }
            Spacer()
            if let r = app.rating, r > 0 { Text(String(format: "★ %.1f", r)).foregroundStyle(.yellow) }
            Text(TV.number(app.installs)).font(.title3.bold().monospacedDigit())
        }
        .padding(16)
    }
}

// MARK: - Apps

struct TVAppsView: View {
    @Environment(TVStore.self) private var store
    @Environment(TVPortfolio.self) private var portfolio

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 400), spacing: 40)], spacing: 40) {
                ForEach(portfolio.allApps) { app in
                    NavigationLink {
                        TVAppDetailView(app: app)
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 18) {
                                TVAppIcon(app: app, size: 90)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.name).font(.headline).lineLimit(1)
                                    Text(app.id).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            HStack {
                                Text(TV.number(app.installs)).font(.title2.bold().monospacedDigit())
                                Spacer()
                                if app.inReview { TVBadge(state: "in_review") } else { TVBadge(state: app.liveState) }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(60)
        }
        .overlay { if portfolio.allApps.isEmpty && portfolio.loading { ProgressView() } }
        .task { await portfolio.load(store) }
    }
}

struct TVAppDetailView: View {
    let app: DevApp
    @Environment(TVStore.self) private var store
    @State private var detail: AppDetail?

    var body: some View {
        let a = detail?.app ?? app
        // A plain scroll view with focusable cards: tvOS scrolls by moving focus,
        // and the Menu button on the remote goes back to the list.
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header(a)
                HStack(spacing: 24) {
                    TVTile(title: "Installaties", value: TV.number(a.installs), icon: "arrow.down.circle.fill")
                    TVTile(title: "Cloud / Local", value: "\(TV.compact(a.installsCloud)) / \(TV.compact(a.installsLocal))", icon: "cloud.fill", tint: .cyan)
                    TVTile(title: "Apparaten", value: detail.map { TV.compact($0.deviceCount) } ?? "…", icon: "sensor.fill", tint: .teal)
                    TVTile(title: "Rating", value: a.rating.map { String(format: "%.1f ★", $0) } ?? "—", icon: "star.fill", tint: .yellow)
                }
                if let d = detail {
                    content(d)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 30)
        }
        .scrollClipDisabled()
        .task { detail = await AppsAPI(auth: store).detail(for: app) }
    }

    private func header(_ a: DevApp) -> some View {
        HStack(spacing: 30) {
            TVAppIcon(app: a, size: 140)
            VStack(alignment: .leading, spacing: 8) {
                Text(a.name).font(.largeTitle.bold())
                Text(a.id).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    if !a.liveVersion.isEmpty { Text("Live \(a.liveVersion)").foregroundStyle(.green) }
                    if !a.testVersion.isEmpty { Text("Test \(a.testVersion)").foregroundStyle(.blue) }
                    if a.inReview { TVBadge(state: "in_review") }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func content(_ d: AppDetail) -> some View {
        if !d.installStats.isEmpty {
            card("Installatietrend") { TVInstallChart(points: d.installStats, height: 300) }
        }
        if !d.builds.isEmpty {
            card("Builds") {
                ForEach(d.builds.prefix(8)) { b in
                    HStack {
                        Text("v\(b.version)").font(.headline.monospacedDigit())
                        TVBadge(state: b.state)
                        Spacer()
                        Text(TV.relative(b.createdAt)).foregroundStyle(.secondary)
                        Text(TV.compact(b.installs)).monospacedDigit().frame(width: 120, alignment: .trailing)
                        if b.crashes > 0 { Label("\(b.crashes)", systemImage: "ladybug.fill").foregroundStyle(.red) }
                    }
                }
            }
        }
        if !d.liveCrashes.isEmpty {
            card("Crashes in live build") {
                ForEach(d.liveCrashes.prefix(8)) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.firstLine).font(.callout.monospaced()).lineLimit(2)
                        Text("\(c.count)× · Homey \(c.homeyVersion) · \(TV.relative(c.updatedAt ?? c.createdAt))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !d.suggestions.isEmpty {
            card("Suggesties") {
                ForEach(d.suggestions.prefix(10)) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.text)
                        Text(TV.relative(s.createdAt)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func card<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .background(TV.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .tvFocusCard()
    }
}

// MARK: - Organisations

struct TVOrganizationsView: View {
    @Environment(TVStore.self) private var store
    @Environment(TVPortfolio.self) private var portfolio

    var body: some View {
        List {
            ForEach(portfolio.organizations) { org in
                NavigationLink {
                    TVOrganizationDetailView(org: org)
                } label: {
                    HStack {
                        Image(systemName: "building.2.fill").foregroundStyle(TV.accent)
                        Text(org.name).font(.headline)
                        Spacer()
                        Text("\(portfolio.orgApps[org.id]?.count ?? org.appRefs.count) apps").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if portfolio.organizations.isEmpty && !portfolio.loading {
                ContentUnavailableView("Geen organisaties", systemImage: "building.2")
            }
        }
        .task { await portfolio.load(store) }
    }
}

struct TVOrganizationDetailView: View {
    let org: DevOrganization
    @Environment(TVPortfolio.self) private var portfolio

    var body: some View {
        let apps = portfolio.orgApps[org.id] ?? []
        let members = org.members.enumerated().map { OrgMember($1, index: $0) }
        List {
            Section("Apps (\(apps.count))") {
                ForEach(apps) { app in NavigationLink { TVAppDetailView(app: app) } label: { TVAppRow(app: app) } }
            }
            Section("Leden (\(members.count))") {
                ForEach(members) { m in
                    HStack(spacing: 20) {
                        AsyncImage(url: m.avatarURL) { $0.resizable().scaledToFill() } placeholder: {
                            Text(m.initials).font(.headline).frame(maxWidth: .infinity, maxHeight: .infinity).background(TV.accent.opacity(0.3))
                        }
                        .frame(width: 60, height: 60).clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text(m.name)
                            Text(m.email).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(m.role.capitalized).foregroundStyle(.secondary)
                    }
                    .focusable()
                }
            }
        }
        .navigationTitle(org.name)
    }
}

// MARK: - Settings

struct TVSettingsView: View {
    @Environment(TVStore.self) private var store
    @Environment(TVPortfolio.self) private var portfolio

    var body: some View {
        List {
            Section("Accounts") {
                ForEach(store.accounts) { acc in
                    Button { store.switchTo(acc.id) } label: {
                        HStack(spacing: 20) {
                            AsyncImage(url: acc.avatarURL) { $0.resizable().scaledToFill() } placeholder: {
                                Text(acc.initials).font(.headline).frame(maxWidth: .infinity, maxHeight: .infinity).background(TV.accent.opacity(0.3))
                            }
                            .frame(width: 70, height: 70).clipShape(Circle())
                            VStack(alignment: .leading) {
                                Text(acc.name).font(.headline)
                                Text(acc.email).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if acc.id == store.activeID { Image(systemName: "checkmark.circle.fill").foregroundStyle(TV.accent) }
                        }
                    }
                    .contextMenu {
                        if store.isLinkedHere(acc.id) {
                            Button("Verwijder van deze Apple TV", role: .destructive) { store.removeLinked(acc.id) }
                        }
                    }
                }
                NavigationLink {
                    ScrollView { TVAddAccountPanel().padding(80) }
                } label: {
                    Label("Account toevoegen", systemImage: "plus.circle.fill")
                }
            }
            Section {
                Button { store.reloadAccounts(); Task { await portfolio.load(store, force: true) } } label: {
                    Label("Gegevens verversen", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text("Houd een account ingedrukt om het van deze Apple TV te verwijderen. Accounts uit je iCloud-sleutelhanger beheer je in de iPhone-app onder Account → Apple TV.")
            }
            Section {
                NavigationLink { TVLegalView(document: .privacy) } label: {
                    Label("Privacy & voorwaarden", systemImage: "lock.shield")
                }
                NavigationLink { TVLegalView(document: .disclaimer) } label: {
                    Label("Disclaimer", systemImage: "hand.raised")
                }
            } footer: {
                VStack(spacing: 10) {
                    TVLogo(size: 56)
                    Text(AppInfo.versionLine).font(.headline)
                    Text(AppInfo.copyright).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            }
        }
    }
}

/// Privacy / disclaimer on the Apple TV: focusable cards so the remote can scroll.
struct TVLegalView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 30) {
                    Image(systemName: document.icon)
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 120, height: 120)
                        .background(TV.accent.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(document.title).font(.largeTitle.bold())
                        Text(document.intro).font(.title3).foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 30), GridItem(.flexible(), spacing: 30)], spacing: 30) {
                    ForEach(document.parts) { (part: LegalDocument.Part) in
                        HStack(alignment: .top, spacing: 24) {
                            Image(systemName: part.icon)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(TV.accent)
                                .frame(width: 60, height: 60)
                                .background(TV.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(part.title).font(.headline)
                                Text(part.text).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(30)
                        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
                        .background(TV.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .tvFocusCard()
                    }
                }
                VStack(spacing: 8) {
                    Text(document.updated).font(.caption).foregroundStyle(.secondary)
                    Text(AppInfo.versionLine).font(.callout)
                    Text(AppInfo.copyright).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
    }
}
