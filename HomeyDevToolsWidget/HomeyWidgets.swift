import WidgetKit
import SwiftUI
import Charts
import AppIntents

// MARK: - Bundle

@main
struct HomeyWidgetBundle: WidgetBundle {
    var body: some Widget {
        InstallsWidget()
        TopAppsWidget()
        ReviewStatusWidget()
    }
}

// MARK: - App picker (widget configuration)

struct AppChoice: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Homey-app"
    static var defaultQuery = AppChoiceQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AppChoiceQuery: EntityQuery {
    func entities(for identifiers: [AppChoice.ID]) async throws -> [AppChoice] {
        let apps = (WidgetSnapshot.load() ?? .placeholder).apps
        return identifiers.compactMap { id in apps.first { $0.id == id }.map { AppChoice(id: $0.id, name: $0.name) } }
    }

    func suggestedEntities() async throws -> [AppChoice] {
        (WidgetSnapshot.load() ?? .placeholder).apps.map { AppChoice(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> AppChoice? { nil }
}

struct SelectAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Kies een app"
    static var description = IntentDescription("Toon de installaties van één app, of laat leeg voor al je apps.")

    @Parameter(title: "App")
    var app: AppChoice?
}

// MARK: - Timelines

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var appId: String? = nil
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load() ?? WidgetSnapshot.placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct AppIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .placeholder) }

    func snapshot(for configuration: SelectAppIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .placeholder, appId: configuration.app?.id)
    }

    func timeline(for configuration: SelectAppIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load(), appId: configuration.app?.id)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60)))
    }
}

// MARK: - Shared styling

enum W {
    static let accent = Color(red: 0, green: 0.51, blue: 0.98)
    static let cloud = Color.cyan
    static let local = Color.indigo

    static func number(_ n: Int) -> String { n.formatted(.number) }
    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }
    static func signed(_ n: Int) -> String { n > 0 ? "+\(compact(n))" : n < 0 ? "−\(compact(-n))" : "±0" }
    static func rating(_ r: Double?) -> String { r.map { String(format: "%.1f", $0) } ?? "—" }
}

struct WidgetHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            Image("HomeyLogo").resizable().scaledToFit().frame(width: 14, height: 14)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            if let trailing { Text(trailing).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary) }
        }
    }
}

struct AppIcon: View {
    let app: WidgetApp
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let url = AppGroup.iconURL(for: app.id), let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    (Color(hex: app.brandColor) ?? W.accent)
                    Text(app.name.prefix(1)).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct DeltaLabel: View {
    let delta: Int?
    var suffix: String? = nil
    var body: some View {
        if let delta {
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "equal")
                Text(W.signed(delta))
                if let suffix { Text(suffix).foregroundStyle(.secondary).fontWeight(.regular) }
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(delta > 0 ? Color.green : delta < 0 ? Color.red : Color.secondary)
            .lineLimit(1)
        }
    }
}

/// Homey Insights-style chart: smooth line, gradient fill, min/max labels and a dot on the latest value.
struct InsightsChart: View {
    let points: [HistoryPoint]
    var color: Color = W.accent
    var showAxis = true
    var days = 30

    var body: some View {
        let data = Array(points.suffix(days))
        if data.count >= 2 {
            let lo = data.map(\.value).min() ?? 0
            let hi = data.map(\.value).max() ?? 1
            let pad = max(Double(hi - lo) * 0.15, 1)
            Chart(data, id: \.date) { p in
                AreaMark(x: .value("Dag", p.date), yStart: .value("Min", Double(lo) - pad), yEnd: .value("Installaties", Double(p.value)))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Dag", p.date), y: .value("Installaties", Double(p.value)))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                if p.date == data.last?.date {
                    PointMark(x: .value("Dag", p.date), y: .value("Installaties", Double(p.value)))
                        .foregroundStyle(color)
                        .symbolSize(28)
                }
            }
            .chartYScale(domain: (Double(lo) - pad)...(Double(hi) + pad))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [Double(lo), Double(hi)]) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text(W.compact(Int(d))).font(.system(size: 8)) }
                    }
                }
            }
            .chartYAxis(showAxis ? .visible : .hidden)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                Text("Nog geen geschiedenis").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct MiniSparkline: View {
    let points: [HistoryPoint]
    var color: Color = W.accent
    var body: some View {
        let data = Array(points.suffix(30))
        if data.count >= 2 {
            Chart(data, id: \.date) { p in
                LineMark(x: .value("Dag", p.date), y: .value("Installaties", Double(p.value)))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
        } else {
            Color.clear
        }
    }
}

struct StatChip: View {
    let icon: String
    let value: String
    var tint: Color = W.accent
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 9, weight: .bold))
            Text(value).font(.caption2.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

struct CloudLocalBar: View {
    let cloud: Int
    let local: Int
    var body: some View {
        let total = max(cloud + local, 1)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(W.cloud).frame(width: max(2, geo.size.width * CGFloat(cloud) / CGFloat(total)))
                    Rectangle().fill(W.local)
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            HStack {
                Label { Text("Cloud \(W.compact(cloud))") } icon: { Circle().fill(W.cloud).frame(width: 6, height: 6) }
                Spacer(minLength: 4)
                Label { Text("Local \(W.compact(local))") } icon: { Circle().fill(W.local).frame(width: 6, height: 6) }
            }
            .labelStyle(.titleAndIcon)
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image("HomeyLogo").resizable().scaledToFit().frame(width: 30, height: 30)
            Text("Open de app om je gegevens te laden.").font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - 1. Installs (configurable per app)

struct InstallsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "InstallsWidget", intent: SelectAppIntent.self, provider: AppIntentProvider()) { entry in
            InstallsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Installaties")
        .description("Installaties met de Insights-grafiek van je app of van al je apps. Houd ingedrukt → Wijzig widget om een app te kiezen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct InstallsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    /// Selected app; the small widget falls back to your top app so it always shows an app.
    private func subject(_ s: WidgetSnapshot) -> WidgetApp? {
        if let a = s.app(entry.appId) { return a }
        return family == .systemSmall ? s.apps.first : nil
    }

    var body: some View {
        if let s = entry.snapshot, !s.apps.isEmpty {
            let app = subject(s)
            let title = app?.name ?? String(localized: "Alle apps")
            let installs = app?.installs ?? s.totalInstalls
            let history = app?.history ?? s.totalHistory
            let d7 = app?.delta7d ?? (app == nil ? s.totalDelta7d : nil)
            let d30 = app?.delta30d ?? (app == nil ? s.totalDelta30d : nil)
            let color = app.flatMap { Color(hex: $0.brandColor) } ?? W.accent

            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let app { AppIcon(app: app, size: 18) } else { Image("HomeyLogo").resizable().frame(width: 16, height: 16) }
                        Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    Text(W.number(installs))
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6).lineLimit(1)
                    DeltaLabel(delta: d7, suffix: "7d")
                    InsightsChart(points: history, color: color, showAxis: false).frame(maxHeight: .infinity)
                }

            case .systemMedium:
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if let app { AppIcon(app: app, size: 20) } else { Image("HomeyLogo").resizable().frame(width: 18, height: 18) }
                            Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                        }
                        Text(W.number(installs))
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.6).lineLimit(1)
                        DeltaLabel(delta: d7, suffix: "7d")
                        DeltaLabel(delta: d30, suffix: "30d")
                        Spacer(minLength: 0)
                        CloudLocalBar(cloud: app?.cloud ?? s.totalCloud, local: app?.local ?? s.totalLocal)
                    }
                    .frame(width: 128)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            StatChip(icon: "star.fill", value: W.rating(app?.rating ?? s.averageRating), tint: .yellow)
                            StatChip(icon: "sensor.fill", value: W.compact(app?.devices ?? s.totalDevices), tint: .teal)
                            StatChip(icon: "ladybug.fill", value: "\(app?.liveCrashes ?? s.totalLiveCrashes)",
                                     tint: (app?.liveCrashes ?? s.totalLiveCrashes) > 0 ? .red : .green)
                        }
                        InsightsChart(points: history, color: color)
                    }
                }

            default:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let app { AppIcon(app: app, size: 30) } else { Image("HomeyLogo").resizable().frame(width: 26, height: 26) }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(app.map { "v\($0.liveVersion)" } ?? s.accountName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(W.number(installs)).font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                            HStack(spacing: 8) { DeltaLabel(delta: d7, suffix: "7d"); DeltaLabel(delta: d30, suffix: "30d") }
                        }
                    }
                    InsightsChart(points: history, color: color, days: 60).frame(maxHeight: .infinity)
                    CloudLocalBar(cloud: app?.cloud ?? s.totalCloud, local: app?.local ?? s.totalLocal)
                    HStack {
                        StatChip(icon: "star.fill", value: W.rating(app?.rating ?? s.averageRating), tint: .yellow)
                        Spacer()
                        StatChip(icon: "sensor.fill", value: W.compact(app?.devices ?? s.totalDevices), tint: .teal)
                        Spacer()
                        StatChip(icon: "lightbulb.fill", value: "\(app?.suggestions ?? s.totalSuggestions)", tint: .orange)
                        Spacer()
                        StatChip(icon: "ladybug.fill", value: "\(app?.liveCrashes ?? s.totalLiveCrashes)", tint: .red)
                    }
                    if app == nil, !s.topMovers.isEmpty {
                        Divider()
                        Text("Snelste groeiers (7d)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(s.topMovers.prefix(3)) { m in
                            HStack(spacing: 6) {
                                AppIcon(app: m, size: 16)
                                Text(m.name).font(.caption2).lineLimit(1)
                                Spacer()
                                DeltaLabel(delta: m.delta7d)
                            }
                        }
                    }
                }
            }
        } else {
            EmptyWidgetView()
        }
    }
}

// MARK: - 2. Top apps

struct TopAppsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TopAppsWidget", provider: SnapshotProvider()) { entry in
            TopAppsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Top apps")
        .description("Je best geïnstalleerde Homey-apps met trend, groei, rating en status.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TopAppsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot, !s.apps.isEmpty {
            let large = family == .systemLarge
            let apps = Array(s.apps.prefix(large ? 6 : 3))
            VStack(alignment: .leading, spacing: large ? 9 : 6) {
                WidgetHeader(title: String(localized: "Top apps"), trailing: "\(W.compact(s.totalInstalls)) · \(s.apps.count) apps")
                ForEach(apps) { app in
                    HStack(spacing: 8) {
                        AppIcon(app: app, size: large ? 32 : 24)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(app.name).font(.caption.weight(.semibold)).lineLimit(1)
                                if app.inReview { Image(systemName: "hourglass").font(.system(size: 9)).foregroundStyle(.orange) }
                                if app.liveCrashes > 0 { Image(systemName: "ladybug.fill").font(.system(size: 9)).foregroundStyle(.red) }
                            }
                            HStack(spacing: 6) {
                                if !app.liveVersion.isEmpty { Text("v\(app.liveVersion)").foregroundStyle(.green) }
                                if let r = app.rating, r > 0 { Text("★ \(W.rating(r))").foregroundStyle(.yellow) }
                                if large && app.devices > 0 { Text("\(W.compact(app.devices)) dev.").foregroundStyle(.teal) }
                            }
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        MiniSparkline(points: app.history, color: Color(hex: app.brandColor) ?? W.accent)
                            .frame(width: large ? 64 : 48, height: large ? 24 : 18)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(W.compact(app.installs)).font(.caption.weight(.bold).monospacedDigit())
                            DeltaLabel(delta: app.delta7d)
                        }
                        .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                if large {
                    Spacer(minLength: 0)
                    CloudLocalBar(cloud: s.totalCloud, local: s.totalLocal)
                }
            }
        } else {
            EmptyWidgetView()
        }
    }
}

// MARK: - 3. Review & crashes

struct ReviewStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReviewStatusWidget", provider: SnapshotProvider()) { entry in
            ReviewStatusWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Review & crashes")
        .description("Certificering, crashes, suggesties en gekoppelde apparaten in één oogopslag.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ReviewStatusWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: String(localized: "Status"))
                    counter("hourglass", .orange, s.inReview.count, "In review")
                    counter("ladybug.fill", s.totalLiveCrashes > 0 ? .red : .green, s.totalLiveCrashes, "Live crashes")
                    counter("lightbulb.fill", .yellow, s.totalSuggestions, "Suggesties")
                    Spacer(minLength: 0)
                }
            case .systemMedium:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetHeader(title: String(localized: "Status"))
                        counter("hourglass", .orange, s.inReview.count, "In review")
                        counter("ladybug.fill", s.totalLiveCrashes > 0 ? .red : .green, s.totalLiveCrashes, "Live crashes")
                        counter("lightbulb.fill", .yellow, s.totalSuggestions, "Suggesties")
                    }
                    .frame(width: 118, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        reviewList(s, max: 2)
                        crashList(s, max: 2)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            default:
                VStack(alignment: .leading, spacing: 10) {
                    WidgetHeader(title: String(localized: "Developer-status"), trailing: s.accountName)
                    HStack(spacing: 8) {
                        tile("hourglass", .orange, "\(s.inReview.count)", "In review")
                        tile("ladybug.fill", s.totalLiveCrashes > 0 ? .red : .green, "\(s.totalLiveCrashes)", "Live crashes")
                        tile("lightbulb.fill", .yellow, "\(s.totalSuggestions)", "Suggesties")
                        tile("sensor.fill", .teal, W.compact(s.totalDevices), "Apparaten")
                    }
                    reviewList(s, max: 3)
                    crashList(s, max: 3)
                    Spacer(minLength: 0)
                    HStack {
                        Text("Bijgewerkt").foregroundStyle(.secondary)
                        Text(s.updatedAt, style: .relative).foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                }
            }
        } else {
            EmptyWidgetView()
        }
    }

    @ViewBuilder
    private func reviewList(_ s: WidgetSnapshot, max: Int) -> some View {
        Text("In review").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        if s.inReview.isEmpty {
            Label("Niets in review", systemImage: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
        }
        ForEach(s.inReview.prefix(max)) { app in
            HStack(spacing: 6) {
                AppIcon(app: app, size: 18)
                Text(app.name).font(.caption2.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 2)
                Text("v\(app.testVersion)").font(.caption2.monospacedDigit()).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func crashList(_ s: WidgetSnapshot, max: Int) -> some View {
        Text("Crashes per app").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        if s.crashingApps.isEmpty {
            Label("Geen crashes", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
        }
        ForEach(s.crashingApps.prefix(max)) { app in
            HStack(spacing: 6) {
                AppIcon(app: app, size: 18)
                Text(app.name).font(.caption2.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 2)
                Label("\(app.liveCrashes)", systemImage: "ladybug.fill").font(.caption2.monospacedDigit()).foregroundStyle(.red)
            }
        }
    }

    private func counter(_ icon: String, _ tint: Color, _ value: Int, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: -1) {
                Text("\(value)").font(.subheadline.weight(.bold).monospacedDigit())
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func tile(_ icon: String, _ tint: Color, _ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.caption.weight(.bold)).foregroundStyle(tint)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) { InstallsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
#Preview(as: .systemMedium) { InstallsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
#Preview(as: .systemLarge) { TopAppsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
#Preview(as: .systemLarge) { ReviewStatusWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
