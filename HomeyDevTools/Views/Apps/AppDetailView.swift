import SwiftUI
import Charts

struct AppDetailView: View {
    let app: DevApp
    @Environment(AuthManager.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var detail: AppDetail?
    @State private var loading = false
    @State private var range: TrendRange = .month

    enum TrendRange: String, CaseIterable, Identifiable {
        case week = "7d", month = "30d", quarter = "90d", year = "1j", all = "Alles"
        var id: String { rawValue }
        var days: Int? {
            switch self { case .week: 7; case .month: 30; case .quarter: 90; case .year: 365; case .all: nil }
        }
    }

    var body: some View {
        let d = detail
        let a = d?.app ?? app
        List {
            Section { header(a) }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(title: "Installaties", value: Fmt.number(a.installs), systemImage: "arrow.down.circle")
                    StatTile(title: "Rating", value: a.rating.map { String(format: "%.1f ★", $0) } ?? "—", systemImage: "star", tint: .yellow)
                    StatTile(title: "Cloud", value: Fmt.number(a.installsCloud), systemImage: "cloud", tint: .cyan)
                    StatTile(title: "Local", value: Fmt.number(a.installsLocal), systemImage: "house", tint: .indigo)
                    StatTile(title: "Apparaten", value: d.map { Fmt.number($0.deviceCount) } ?? "…", systemImage: "sensor", tint: .teal)
                    StatTile(title: "Crashes (live)", value: Fmt.number(a.liveCrashes), systemImage: "ladybug", tint: a.liveCrashes > 0 ? .red : .secondary)
                    StatTile(title: "Suggesties", value: d.map { "\($0.suggestions.count)" } ?? "…", systemImage: "lightbulb", tint: .orange)
                    StatTile(title: "Builds", value: d.map { "\($0.builds.count)" } ?? "…", systemImage: "hammer", tint: .purple)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let d, !d.errors.isEmpty {
                Section { ForEach(d.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) } }
            }

            if let d, !d.installStats.isEmpty { trendSection(d.installStats) }

            if let live = d?.liveBuild {
                Section("Live build") {
                    LabeledContent("Versie", value: live.version)
                    LabeledContent("Status") { StateBadge(state: live.state) }
                    LabeledContent("Installaties", value: Fmt.number(live.installs))
                    LabeledContent("Gepubliceerd", value: Fmt.date(live.createdAt))
                    if !live.platforms.isEmpty { LabeledContent("Platforms", value: live.platforms.joined(separator: ", ")) }
                    if !live.changelog.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Changelog").font(.caption).foregroundStyle(.secondary)
                            Text(live.changelog).font(.callout)
                        }
                    }
                    let perms = live.raw["permissions"].array.compactMap(\.string)
                    if !perms.isEmpty {
                        DisclosureGroup("Permissies (\(perms.count))") {
                            ForEach(perms, id: \.self) { Text($0).font(.caption.monospaced()) }
                        }
                    }
                }
            }

            if let d {
                Section {
                    ForEach(d.builds.prefix(6)) { b in
                        NavigationLink { BuildDetailView(appId: a.id, build: b) } label: { BuildRow(build: b, app: a) }
                    }
                    if d.builds.count > 6 {
                        NavigationLink("Alle \(d.builds.count) builds") { BuildsListView(app: a, builds: d.builds) }
                    }
                } header: { Text("Builds") }

                if !d.liveCrashes.isEmpty {
                    Section("Crashes in live build") {
                        ForEach(d.liveCrashes.prefix(10)) { c in
                            NavigationLink { CrashDetailView(crash: c) } label: { CrashRow(crash: c) }
                        }
                    }
                }

                if !d.suggestions.isEmpty {
                    Section("Suggesties (\(d.suggestions.count))") {
                        ForEach(d.suggestions.prefix(20)) { s in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.text.isEmpty ? L("(leeg)") : s.text).font(.callout)
                                Text(Fmt.relative(s.createdAt)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !d.drivers.isEmpty {
                    Section("Gekoppelde apparaten per driver") {
                        ForEach(d.drivers) { drv in
                            LabeledContent(drv.driverId, value: Fmt.number(drv.count))
                                .font(.callout)
                        }
                    }
                }
            } else if loading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            }

            if let tid = a.testBuildId, !a.testState.isEmpty {
                BuildActionsSection(appId: a.id, buildId: tid, version: a.testVersion, state: a.testState) { await load() }
            }

            Section("Beheer") {
                NavigationLink { ReviewsView(appId: a.id) } label: {
                    LabeledContent { Text(a.rating.map { String(format: "%.1f ★", $0) } ?? "") } label: { Label("Reviews", systemImage: "star.bubble") }
                }
                NavigationLink { AppNotificationSettingsView(appId: a.id) } label: { Label("Meldingen", systemImage: "bell.badge") }
                NavigationLink { TransferAppView(app: a) } label: { Label("Overdragen naar organisatie", systemImage: "arrow.right.arrow.left") }
            }
            .cardRows()

            Section("Links") {
                if let url = Config.devToolsAppPage(a.id) {
                    NavigationLink { WebToolsView(start: url).navigationBarTitleDisplayMode(.inline) } label: {
                        Label("Openen in Developer Tools", systemImage: "hammer.circle")
                    }
                }
                if let url = Config.appStorePage(a.id) {
                    Button { openURL(url) } label: { Label("Bekijk in Homey App Store", systemImage: "bag") }
                }
                Button { UIPasteboard.general.string = a.id } label: { Label("Kopieer app-id", systemImage: "doc.on.doc") }
                NavigationLink { JSONInspectorView(title: a.id, json: a.raw) } label: { Label("Ruwe API-data", systemImage: "curlybraces") }
            }
        }
        .themedList()
        .navigationTitle(a.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if detail == nil { await load() } }
    }

    private func load() async {
        loading = true
        detail = await AppsAPI(auth: auth).detail(for: detail?.app ?? app)
        loading = false
    }

    @ViewBuilder
    private func header(_ a: DevApp) -> some View {
        VStack(spacing: 12) {
            if let img = a.imageURL {
                AsyncImage(url: img) { i in i.resizable().scaledToFill() } placeholder: { Color(hex: a.brandColor) ?? Color.accentColor.opacity(0.2) }
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            HStack(spacing: 12) {
                AppIconView(url: a.iconURL, brand: a.brandColor, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.name).font(.title3.weight(.semibold))
                    Text(a.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack(spacing: 6) {
                        if !a.liveVersion.isEmpty { versionPill("Live", a.liveVersion, .green) }
                        if !a.testVersion.isEmpty { versionPill("Test", a.testVersion, .blue) }
                        if a.inReview { StateBadge(state: "in_review") }
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func versionPill(_ label: String, _ v: String, _ c: Color) -> some View {
        Text("\(label) \(v)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(c.opacity(0.15), in: Capsule())
            .foregroundStyle(c)
    }

    @ViewBuilder
    private func trendSection(_ all: [StatPoint]) -> some View {
        let pts: [StatPoint] = {
            guard let days = range.days, let last = all.last?.date else { return all }
            let from = Calendar.current.date(byAdding: .day, value: -days, to: last) ?? last
            return all.filter { $0.date >= from }
        }()
        let delta = (pts.last?.value ?? 0) - (pts.first?.value ?? 0)
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Installatietrend").font(.headline)
                        Text("\(delta >= 0 ? "+" : "")\(Int(delta)) in deze periode")
                            .font(.caption).foregroundStyle(delta >= 0 ? Color.green : Color.red)
                    }
                    Spacer()
                }
                Picker("Periode", selection: $range) {
                    ForEach(TrendRange.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                Chart(pts) { p in
                    AreaMark(x: .value("Datum", p.date), y: .value("Installaties", p.value))
                        .foregroundStyle(.linearGradient(colors: [Color.accentColor.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Datum", p.date), y: .value("Installaties", p.value))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
            }
            .padding(.vertical, 6)
        }
    }
}

struct BuildRow: View {
    let build: DevBuild
    var app: DevApp?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("v\(build.version)").font(.body.weight(.medium).monospacedDigit())
                    StateBadge(state: build.state)
                    if app?.liveBuildId == build.id { StateBadge(state: "live") }
                    else if app?.testBuildId == build.id { StateBadge(state: "test") }
                }
                Text("#\(build.id) · \(Fmt.relative(build.createdAt))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.compact(build.installs)).font(.callout.monospacedDigit())
                if build.crashes > 0 {
                    Label("\(build.crashes)", systemImage: "ladybug.fill").font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }
}

struct BuildsListView: View {
    let app: DevApp
    let builds: [DevBuild]

    var body: some View {
        List(builds) { b in
            NavigationLink { BuildDetailView(appId: app.id, build: b) } label: { BuildRow(build: b, app: app) }
        }
        .navigationTitle("Builds")
    }
}

struct CrashRow: View {
    let crash: DevCrash
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(crash.firstLine).font(.callout.monospaced()).lineLimit(2)
            HStack {
                Label("\(crash.count)×", systemImage: "ladybug").foregroundStyle(.red)
                if !crash.homeyVersion.isEmpty { Text("Homey \(crash.homeyVersion)") }
                Spacer()
                Text(Fmt.relative(crash.updatedAt ?? crash.createdAt))
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct CrashDetailView: View {
    let crash: DevCrash
    var body: some View {
        List {
            Section {
                LabeledContent("Aantal", value: "\(crash.count)")
                LabeledContent("Homey-versie", value: crash.homeyVersion.isEmpty ? "—" : crash.homeyVersion)
                LabeledContent("Eerst gezien", value: Fmt.date(crash.createdAt))
                LabeledContent("Laatst gezien", value: Fmt.date(crash.updatedAt))
            }
            Section("Stacktrace") {
                ScrollView(.horizontal) {
                    Text(crash.stack.isEmpty ? L("(geen stack)") : crash.stack)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
            }
            Section { NavigationLink("Ruwe API-data") { JSONInspectorView(title: L("Crash"), json: crash.raw) } }
        }
        .navigationTitle("Crash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: crash.stack) { Image(systemName: "square.and.arrow.up") }
        }
    }
}
