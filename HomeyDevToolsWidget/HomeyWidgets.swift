import WidgetKit
import SwiftUI

// MARK: - Bundle

@main
struct HomeyWidgetBundle: WidgetBundle {
    var body: some Widget {
        InstallsWidget()
        TopAppsWidget()
        ReviewStatusWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var isPlaceholder = false
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load() ?? (context.isPreview ? WidgetSnapshot.placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        // Data is refreshed by the app; re-read the shared snapshot every 30 minutes.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
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
}

struct WidgetHeader: View {
    let title: LocalizedStringKey
    var body: some View {
        HStack(spacing: 5) {
            Image("HomeyLogo").resizable().scaledToFit().frame(width: 14, height: 14)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
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
    var body: some View {
        if let delta {
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "equal")
                Text(W.signed(delta))
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(delta > 0 ? Color.green : delta < 0 ? Color.red : Color.secondary)
        }
    }
}

struct Sparkline: View {
    let points: [HistoryPoint]
    var body: some View {
        GeometryReader { geo in
            let values = points.map { Double($0.value) }
            if values.count >= 2, let lo = values.min(), let hi = values.max() {
                let range = max(hi - lo, 1)
                let step = geo.size.width / CGFloat(values.count - 1)
                let pts = values.enumerated().map { i, v in
                    CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat((v - lo) / range)))
                }
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [W.accent.opacity(0.35), W.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(W.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
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

// MARK: - 1. Installs

struct InstallsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InstallsWidget", provider: SnapshotProvider()) { entry in
            InstallsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Installaties")
        .description("Totaal aantal installaties van je apps, met de groei van de afgelopen 7 dagen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct InstallsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot {
            if family == .systemMedium {
                HStack(spacing: 14) {
                    main(s)
                    VStack(alignment: .leading, spacing: 8) {
                        split(s)
                        HStack {
                            stat("star.fill", s.averageRating.map { String(format: "%.1f", $0) } ?? "—", .yellow)
                            stat("square.stack.3d.up.fill", "\(s.apps.count)", W.accent)
                        }
                        Spacer(minLength: 0)
                        Text(s.updatedAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                main(s)
            }
        } else {
            EmptyWidgetView()
        }
    }

    private func main(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Installaties")
            Text(W.number(s.totalInstalls))
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                DeltaLabel(delta: s.totalDelta7d)
                if s.totalDelta7d != nil { Text("7 d").font(.caption2).foregroundStyle(.secondary) }
            }
            Sparkline(points: s.totalHistory).frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func split(_ s: WidgetSnapshot) -> some View {
        let total = max(s.totalCloud + s.totalLocal, 1)
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(W.cloud).frame(width: geo.size.width * CGFloat(s.totalCloud) / CGFloat(total))
                    Rectangle().fill(W.local)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            HStack(spacing: 10) {
                legend(W.cloud, "Cloud", s.totalCloud)
                legend(W.local, "Local", s.totalLocal)
            }
        }
        .padding(.top, 18)
    }

    private func legend(_ c: Color, _ t: LocalizedStringKey, _ v: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) { Circle().fill(c).frame(width: 6, height: 6); Text(t) }
                .font(.caption2).foregroundStyle(.secondary)
            Text(W.compact(v)).font(.caption.weight(.semibold).monospacedDigit())
        }
    }

    private func stat(_ icon: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).monospacedDigit()
        }
        .font(.caption.weight(.semibold))
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
        .description("Je best geïnstalleerde Homey-apps met versie en groei per app.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TopAppsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot, !s.apps.isEmpty {
            let count = family == .systemLarge ? 6 : 3
            let apps = Array(s.apps.prefix(count))
            let maxInstalls = max(apps.first?.installs ?? 1, 1)
            VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
                HStack {
                    WidgetHeader(title: "Top apps")
                    Text(W.compact(s.totalInstalls)).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                }
                ForEach(apps) { app in
                    HStack(spacing: 9) {
                        AppIcon(app: app, size: family == .systemLarge ? 34 : 26)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(app.name).font(.caption.weight(.semibold)).lineLimit(1)
                                if app.inReview {
                                    Image(systemName: "hourglass").font(.caption2).foregroundStyle(.orange)
                                }
                                Spacer(minLength: 4)
                                Text(W.number(app.installs)).font(.caption.weight(.bold).monospacedDigit())
                            }
                            GeometryReader { geo in
                                Capsule().fill(Color.primary.opacity(0.08))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(W.accent).frame(width: max(4, geo.size.width * CGFloat(app.installs) / CGFloat(maxInstalls)))
                                    }
                            }
                            .frame(height: 4)
                            if family == .systemLarge {
                                HStack(spacing: 8) {
                                    if !app.liveVersion.isEmpty { Text("v\(app.liveVersion)").foregroundStyle(.green) }
                                    if let r = app.rating, r > 0 { Text("★ \(String(format: "%.1f", r))").foregroundStyle(.yellow) }
                                    Spacer(minLength: 0)
                                    DeltaLabel(delta: s.delta7d(for: app))
                                }
                                .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
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
        .description("Welke apps op certificering wachten en hoeveel crashes je live builds hebben.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ReviewStatusWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot {
            if family == .systemMedium {
                HStack(alignment: .top, spacing: 14) {
                    counters(s).frame(width: 110, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("In review").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        if s.inReview.isEmpty {
                            Label("Niets in review", systemImage: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
                        ForEach(s.inReview.prefix(3)) { app in
                            HStack(spacing: 7) {
                                AppIcon(app: app, size: 22)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(app.name).font(.caption.weight(.semibold)).lineLimit(1)
                                    Text("v\(app.testVersion)").font(.caption2.monospacedDigit()).foregroundStyle(.orange)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                counters(s)
            }
        } else {
            EmptyWidgetView()
        }
    }

    private func counters(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Status")
            counter(icon: "hourglass", tint: .orange, value: s.inReview.count, label: "In review")
            counter(icon: "ladybug.fill", tint: s.totalLiveCrashes > 0 ? .red : .green, value: s.totalLiveCrashes, label: "Live crashes")
            Spacer(minLength: 0)
            Text(s.updatedAt, style: .relative).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
    }

    private func counter(icon: String, tint: Color, value: Int, label: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)").font(.title3.weight(.bold).monospacedDigit())
                Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) { InstallsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
#Preview(as: .systemMedium) { TopAppsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
#Preview(as: .systemMedium) { ReviewStatusWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .placeholder) }
