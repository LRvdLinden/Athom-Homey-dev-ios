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
    }
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
                    NavigationStack { TVHomeysView() }.tabItem { Label("Homeys", systemImage: "circle.circle") }
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
        HStack(spacing: 80) {
            TVLogo(size: 280)
            VStack(alignment: .leading, spacing: 28) {
                Text("Homey Developer Tools").font(.largeTitle.bold())
                Text("Deel je account vanaf je iPhone:").font(.title3)
                VStack(alignment: .leading, spacing: 14) {
                    Label("Open Developer Tools op je iPhone", systemImage: "1.circle.fill")
                    Label("Ga naar Account → Apple TV", systemImage: "2.circle.fill")
                    Label("Zet ‘Delen met Apple TV’ aan", systemImage: "3.circle.fill")
                }
                .font(.title3)
                Text("Je accounts komen via je iCloud-sleutelhanger binnen. Zorg dat iPhone en Apple TV met hetzelfde Apple-account zijn ingelogd.")
                    .font(.callout).foregroundStyle(.secondary)
                Button { store.reloadAccounts() } label: { Label("Opnieuw zoeken", systemImage: "arrow.clockwise") }
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
        .padding(80)
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

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top apps").font(.headline)
                        ForEach(apps.prefix(6)) { app in
                            NavigationLink(value: app) { TVAppRow(app: app) }.buttonStyle(.card)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Wacht op certificering").font(.headline)
                        if review.isEmpty { Label("Niets in review", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                        ForEach(review) { app in
                            NavigationLink(value: app) {
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
        .navigationDestination(for: DevApp.self) { TVAppDetailView(app: $0) }
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
                    NavigationLink(value: app) {
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
        .navigationDestination(for: DevApp.self) { TVAppDetailView(app: $0) }
        .task { await portfolio.load(store) }
    }
}

struct TVAppDetailView: View {
    let app: DevApp
    @Environment(TVStore.self) private var store
    @State private var detail: AppDetail?

    var body: some View {
        let a = detail?.app ?? app
        List {
            Section {
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
                }
                .padding(.vertical, 10)
            }
            Section {
                HStack(spacing: 24) {
                    TVTile(title: "Installaties", value: TV.number(a.installs), icon: "arrow.down.circle.fill")
                    TVTile(title: "Cloud / Local", value: "\(TV.compact(a.installsCloud)) / \(TV.compact(a.installsLocal))", icon: "cloud.fill", tint: .cyan)
                    TVTile(title: "Apparaten", value: detail.map { TV.compact($0.deviceCount) } ?? "…", icon: "sensor.fill", tint: .teal)
                    TVTile(title: "Rating", value: a.rating.map { String(format: "%.1f ★", $0) } ?? "—", icon: "star.fill", tint: .yellow)
                }
            }
            if let d = detail, !d.installStats.isEmpty {
                Section("Installatietrend") { TVInstallChart(points: d.installStats, height: 300) }
            }
            if let d = detail {
                Section("Builds") {
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
                if !d.liveCrashes.isEmpty {
                    Section("Crashes in live build") {
                        ForEach(d.liveCrashes.prefix(8)) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.firstLine).font(.callout.monospaced()).lineLimit(2)
                                Text("\(c.count)× · Homey \(c.homeyVersion) · \(TV.relative(c.updatedAt ?? c.createdAt))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !d.suggestions.isEmpty {
                    Section("Suggesties") {
                        ForEach(d.suggestions.prefix(10)) { s in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.text)
                                Text(TV.relative(s.createdAt)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section { ProgressView() }
            }
        }
        .task { detail = await AppsAPI(auth: store).detail(for: app) }
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
                ForEach(apps) { app in NavigationLink(value: app) { TVAppRow(app: app) } }
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
                }
            }
        }
        .navigationTitle(org.name)
        .navigationDestination(for: DevApp.self) { TVAppDetailView(app: $0) }
    }
}

// MARK: - Homeys

struct TVHomeysView: View {
    @Environment(TVStore.self) private var store

    var body: some View {
        List {
            ForEach(store.homeys) { h in
                NavigationLink { TVHomeyDetailView(client: HomeyClient(homey: h, auth: store)) } label: {
                    HStack(spacing: 20) {
                        TVLogo(size: 50)
                        VStack(alignment: .leading) {
                            Text(h.name).font(.headline)
                            Text(h.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay { if store.homeys.isEmpty { ContentUnavailableView("Geen Homeys", systemImage: "circle.circle") } }
        .task { if store.user.isNull { try? await store.loadUser() } }
    }
}

struct TVHomeyDetailView: View {
    let client: HomeyClient
    @State private var devices: [HomeyDevice] = []
    @State private var zones: [String: String] = [:]
    @State private var system: JSON = .null
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.orange) }
            Section("Systeem") {
                LabeledContent("Model", value: system.firstString("homeyModelName", "modelName").isEmpty ? client.homey.subtitle : system.firstString("homeyModelName", "modelName"))
                LabeledContent("Versie", value: system.firstString("homeyVersion", "softwareVersion"))
                NavigationLink { TVInsightsView(client: client) } label: { Label("Insights", systemImage: "chart.xyaxis.line") }
            }
            let grouped = Dictionary(grouping: devices) { zones[$0.zoneId] ?? L("Overig") }
            ForEach(grouped.keys.sorted(), id: \.self) { zone in
                Section(zone) {
                    ForEach(grouped[zone] ?? []) { d in
                        HStack {
                            Image(systemName: d.systemImage).foregroundStyle(d.available ? TV.accent : .secondary).frame(width: 50)
                            Text(d.name)
                            Spacer()
                            Text(d.capabilities.filter { !$0.value.isNull }.prefix(3).map(\.formattedValue).joined(separator: " · "))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(client.homey.name)
        .task {
            do {
                async let z = client.zones()
                async let d = client.devices()
                let (zs, ds) = try await (z, d)
                zones = Dictionary(zs.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
                devices = ds
                error = nil
            } catch { self.error = error.localizedDescription }
            system = (try? await client.system()) ?? .null
        }
    }
}

struct TVInsightsView: View {
    let client: HomeyClient
    @State private var logs: [JSON] = []

    var body: some View {
        List {
            ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                NavigationLink { TVInsightsLogView(client: client, log: log) } label: {
                    HStack {
                        Text(log["title"].localized.isEmpty ? log.firstString("id") : log["title"].localized)
                        Spacer()
                        Text(log.firstString("ownerName", "uri")).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Insights")
        .task { logs = (try? await client.request("/api/manager/insights/log"))?.items ?? [] }
    }
}

struct TVInsightsLogView: View {
    let client: HomeyClient
    let log: JSON
    @State private var resolution = "last24Hours"
    @State private var points: [StatPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Picker("Periode", selection: $resolution) {
                Text("24u").tag("last24Hours")
                Text("7d").tag("last7Days")
                Text("31d").tag("last31Days")
                Text("1j").tag("last1Year")
            }
            .pickerStyle(.segmented)
            if points.count > 1 {
                Chart(points) { p in
                    AreaMark(x: .value("Tijd", p.date), y: .value("Waarde", p.value))
                        .foregroundStyle(LinearGradient(colors: [TV.accent.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Tijd", p.date), y: .value("Waarde", p.value))
                        .lineStyle(StrokeStyle(lineWidth: 4))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: .automatic(includesZero: false))
            } else {
                Text("Geen waarden in deze periode.").foregroundStyle(.secondary)
            }
        }
        .padding(60)
        .navigationTitle(log["title"].localized)
        .task(id: resolution) {
            let uri = log.firstString("uri", "ownerUri")
            let path = "/api/manager/insights/log/\(uri.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uri)/\(log.firstString("id"))/entry?resolution=\(resolution)"
            let j = (try? await client.request(path)) ?? .null
            let values = j["values"].isNull ? j.array : j["values"].array
            points = values.compactMap { v in
                guard let t = v["t"].date, let val = v["v"].double else { return nil }
                return StatPoint(date: t, value: val)
            }
        }
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
                }
            }
            Section {
                Button { store.reloadAccounts(); Task { await portfolio.load(store, force: true) } } label: {
                    Label("Gegevens verversen", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text("Accounts beheer je in de iPhone-app onder Account → Apple TV. Ze komen via je iCloud-sleutelhanger binnen.")
            }
        }
    }
}
