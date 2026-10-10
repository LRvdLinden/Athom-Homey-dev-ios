import SwiftUI
import Charts

enum Watch {
    static let accent = Color(red: 0.10, green: 0.55, blue: 1.0)

    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }
    static func number(_ n: Int) -> String { n.formatted(.number) }
    static func signed(_ n: Int) -> String { n > 0 ? "+\(compact(n))" : n < 0 ? "−\(compact(-n))" : "±0" }

    static func color(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return accent }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func stateLabel(_ state: String) -> (text: String, color: Color)? {
        switch state {
        case "draft": (text: String(localized: "Draft"), color: Color.gray)
        case "test": (text: String(localized: "Test"), color: Color.blue)
        case "in_review": (text: String(localized: "In review"), color: Color.orange)
        case "reviewed_approved", "approved": (text: String(localized: "Goedgekeurd"), color: Color.green)
        case "reviewed_rejected", "rejected": (text: String(localized: "Afgekeurd"), color: Color.red)
        default: nil
        }
    }
}

/// Vertical pages: overview, apps, review & crashes.
struct WatchRootView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let snapshot = store.snapshot {
            TabView {
                WatchOverviewView(snapshot: snapshot)
                WatchAppsView(snapshot: snapshot)
                WatchAttentionView(snapshot: snapshot)
            }
            .tabViewStyle(.verticalPage)
        } else {
            WatchEmptyView()
        }
    }
}

struct WatchEmptyView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image("HomeyLogo").resizable().scaledToFit().frame(width: 52, height: 52)
                Text("Homey Dev").font(.headline)
                Text("Open de app op je iPhone. Je gegevens komen dan vanzelf naar je Apple Watch.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { store.refresh() } label: {
                    if store.refreshing { ProgressView() } else { Label("Ophalen", systemImage: "arrow.clockwise") }
                }
                if let message = store.message {
                    Text(message).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct WatchOverviewView: View {
    let snapshot: WidgetSnapshot
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Installaties").font(.caption2).foregroundStyle(.secondary)
                    Text(Watch.number(snapshot.totalInstalls))
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let d7 = snapshot.totalDelta7d {
                        Text("\(Watch.signed(d7)) · 7d")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(d7 >= 0 ? .green : .red)
                    }
                }

                if snapshot.totalHistory.count > 1 {
                    Chart(snapshot.totalHistory.suffix(30), id: \.date) { (p: HistoryPoint) in
                        AreaMark(x: .value("Dag", p.date), y: .value("Installaties", p.value))
                            .foregroundStyle(Watch.accent.opacity(0.25).gradient)
                        LineMark(x: .value("Dag", p.date), y: .value("Installaties", p.value))
                            .foregroundStyle(Watch.accent)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 44)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    WatchStat(title: "Cloud", value: Watch.compact(snapshot.totalCloud), icon: "cloud.fill", tint: .cyan)
                    WatchStat(title: "Local", value: Watch.compact(snapshot.totalLocal), icon: "house.fill", tint: Watch.accent)
                    WatchStat(title: "In review", value: "\(snapshot.inReview.count)", icon: "hourglass",
                              tint: snapshot.inReview.isEmpty ? .secondary : .orange)
                    WatchStat(title: "Crashes", value: "\(snapshot.totalLiveCrashes)", icon: "ladybug.fill",
                              tint: snapshot.totalLiveCrashes > 0 ? .red : .green)
                }

                Text("\(snapshot.accountName) · \(snapshot.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .navigationTitle("Homey Dev")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }
}

struct WatchStat: View {
    let title: LocalizedStringKey
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon).font(.system(size: 11)).foregroundStyle(tint).lineLimit(1)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct WatchAppsView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        List(snapshot.apps) { (app: WidgetApp) in
            NavigationLink { WatchAppDetailView(app: app) } label: { WatchAppRow(app: app) }
        }
        .navigationTitle("My Apps")
    }
}

struct WatchAppRow: View {
    let app: WidgetApp

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Watch.color(app.brandColor)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.footnote.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(Watch.compact(app.installs)).monospacedDigit()
                    if let d7 = app.delta7d, d7 != 0 {
                        Text(Watch.signed(d7)).foregroundStyle(d7 > 0 ? .green : .red)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let state = Watch.stateLabel(app.testState), app.testState != "test" {
                Circle().fill(state.color).frame(width: 7, height: 7)
            }
        }
    }
}

struct WatchAppDetailView: View {
    let app: WidgetApp

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(Watch.number(app.installs))
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Watch.color(app.brandColor))
                HStack {
                    if let d7 = app.delta7d { Text("\(Watch.signed(d7)) 7d").foregroundStyle(d7 >= 0 ? .green : .red) }
                    if let d30 = app.delta30d { Text("\(Watch.signed(d30)) 30d").foregroundStyle(.secondary) }
                }
                .font(.caption.monospacedDigit())

                if app.history.count > 1 {
                    Chart(app.history.suffix(30), id: \.date) { (p: HistoryPoint) in
                        LineMark(x: .value("Dag", p.date), y: .value("Installaties", p.value))
                            .foregroundStyle(Watch.color(app.brandColor))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 50)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if !app.liveVersion.isEmpty { row("Live", "v\(app.liveVersion)", .green) }
                    if !app.testVersion.isEmpty {
                        let state = Watch.stateLabel(app.testState)
                        row("Test", "v\(app.testVersion)\(state.map { " · \($0.text)" } ?? "")", state?.color ?? .blue)
                    }
                    row("Cloud / Local", "\(Watch.compact(app.cloud)) / \(Watch.compact(app.local))", .cyan)
                    if app.devices > 0 { row("Apparaten", Watch.compact(app.devices), .teal) }
                    if let r = app.rating, r > 0 { row("Rating", String(format: "%.1f ★", r), .yellow) }
                    row("Crashes", "\(app.liveCrashes)", app.liveCrashes > 0 ? .red : .green)
                    if app.suggestions > 0 { row("Suggesties", "\(app.suggestions)", .purple) }
                }
            }
        }
        .navigationTitle(app.name)
    }

    private func row(_ title: LocalizedStringKey, _ value: String, _ tint: Color) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(.caption)
    }
}

struct WatchAttentionView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        List {
            Section("In review") {
                if snapshot.inReview.isEmpty {
                    Label("Niets in review", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.footnote)
                }
                ForEach(snapshot.inReview) { (app: WidgetApp) in
                    NavigationLink { WatchAppDetailView(app: app) } label: {
                        VStack(alignment: .leading) {
                            Text(app.name).font(.footnote.weight(.semibold))
                            Text("v\(app.testVersion)").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
            }
            Section("Crashes") {
                if snapshot.crashingApps.isEmpty {
                    Label("Geen crashes", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.footnote)
                }
                ForEach(snapshot.crashingApps.prefix(8)) { (app: WidgetApp) in
                    NavigationLink { WatchAppDetailView(app: app) } label: {
                        HStack {
                            Text(app.name).font(.footnote).lineLimit(1)
                            Spacer()
                            Text("\(app.liveCrashes)").font(.footnote.monospacedDigit()).foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("Aandacht")
    }
}
