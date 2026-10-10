import SwiftUI
import WidgetKit

/// Watch face complications: installs, 7-day change and apps in review.
/// They read the summary the watch app stored in the App Group.
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = ComplicationEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

private enum Fmt {
    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }
    static func signed(_ n: Int) -> String { n > 0 ? "+\(compact(n))" : n < 0 ? "−\(compact(-n))" : "±0" }
}

struct InstallsComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 11))
                    Text(s.map { Fmt.compact($0.totalInstalls) } ?? "–")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                }
            }
            .widgetAccentable()
        case .accessoryCorner:
            Text(s.map { Fmt.compact($0.totalInstalls) } ?? "–")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .widgetLabel {
                    Text(s?.totalDelta7d.map { "\(Fmt.signed($0)) 7d" } ?? "Homey Dev")
                }
        case .accessoryInline:
            if let s {
                Text("⬇︎ \(Fmt.compact(s.totalInstalls))\(s.inReview.isEmpty ? "" : " · \(s.inReview.count) review")")
            } else {
                Text("Homey Dev")
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "circle.circle").font(.system(size: 11, weight: .bold))
                    Text("Homey Dev").font(.system(size: 12, weight: .semibold))
                }
                .widgetAccentable()
                if let s {
                    Text(s.totalInstalls.formatted(.number))
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        if let d7 = s.totalDelta7d { Text("\(Fmt.signed(d7)) 7d") }
                        if !s.inReview.isEmpty { Text("⏳ \(s.inReview.count)") }
                        if s.totalLiveCrashes > 0 { Text("🐞 \(s.totalLiveCrashes)") }
                    }
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                } else {
                    Text("Open de iPhone-app").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InstallsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nl.lrvdlinden.homeydevtools.watch.installs", provider: ComplicationProvider()) { entry in
            InstallsComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Installaties")
        .description("Totaal aantal installaties, groei en apps in review.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct HomeyDevComplications: WidgetBundle {
    var body: some Widget {
        InstallsComplication()
    }
}
