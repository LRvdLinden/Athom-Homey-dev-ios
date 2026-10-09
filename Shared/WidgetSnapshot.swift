import Foundation

/// Shared between the app and the widget extension (both targets compile this folder).
/// The app writes a snapshot into the App Group container after every refresh;
/// the widgets only read it, so they never need the account's tokens.
enum AppGroup {
    static let id = "group.nl.lrvdlinden.homeydevtools"
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) }
    static var snapshotURL: URL? { container?.appendingPathComponent("widget-snapshot-v2.json") }
    static func iconURL(for appId: String) -> URL? {
        container?.appendingPathComponent("icons", isDirectory: true)
            .appendingPathComponent(appId.replacingOccurrences(of: "/", with: "_") + ".png")
    }
}

struct HistoryPoint: Codable, Hashable {
    var date: Date
    var value: Int
}

struct WidgetApp: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var installs: Int
    var cloud: Int
    var local: Int
    var rating: Double?
    var liveVersion: String
    var testVersion: String
    var testState: String
    var liveCrashes: Int
    var testCrashes: Int
    var suggestions: Int
    var devices: Int
    var brandColor: String
    /// Daily installs (from Athom install stats, the same data Developer Tools charts), max 90 days.
    var history: [HistoryPoint]

    var inReview: Bool { testState == "in_review" }
    var delta7d: Int? { HistoryMath.delta(history, days: 7) }
    var delta30d: Int? { HistoryMath.delta(history, days: 30) }
}

enum HistoryMath {
    /// Change over the last `days` days.
    static func delta(_ history: [HistoryPoint], days: Int) -> Int? {
        guard let last = history.last, history.count >= 2 else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: last.date) ?? last.date
        guard let base = history.last(where: { $0.date <= cutoff }) ?? history.first, base.date < last.date else { return nil }
        return last.value - base.value
    }

    /// Converts raw (possibly hourly / irregular) points into one value per day,
    /// forward-filled, limited to the last `days` days.
    static func daily(_ points: [HistoryPoint], days: Int = 90) -> [HistoryPoint] {
        guard !points.isEmpty else { return [] }
        let cal = Calendar.current
        var byDay: [Date: Int] = [:]
        for p in points.sorted(by: { $0.date < $1.date }) { byDay[cal.startOfDay(for: p.date)] = p.value }
        let today = cal.startOfDay(for: Date())
        let start = max(byDay.keys.min() ?? today, cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today)
        var out: [HistoryPoint] = []
        var current = byDay.filter { $0.key < start }.max(by: { $0.key < $1.key })?.value ?? 0
        var d = start
        while d <= today {
            if let v = byDay[d] { current = v }
            out.append(HistoryPoint(date: d, value: current))
            d = cal.date(byAdding: .day, value: 1, to: d) ?? today.addingTimeInterval(86_400)
        }
        return out
    }

    /// Sum of several daily series (missing days before an app's first point count as 0).
    static func sum(_ series: [[HistoryPoint]]) -> [HistoryPoint] {
        let days = Set(series.flatMap { $0.map(\.date) }).sorted()
        return days.map { day in
            HistoryPoint(date: day, value: series.reduce(0) { acc, s in
                acc + (s.last(where: { $0.date <= day })?.value ?? 0)
            })
        }
    }

    /// Adds/overwrites today's point (fallback when no install stats are available).
    static func record(_ value: Int, into history: [HistoryPoint]) -> [HistoryPoint] {
        let today = Calendar.current.startOfDay(for: Date())
        var h = history.filter { $0.date != today }
        h.append(HistoryPoint(date: today, value: value))
        return h.sorted { $0.date < $1.date }.suffix(90).map { $0 }
    }
}

struct WidgetSnapshot: Codable {
    var updatedAt: Date
    var accountName: String
    var apps: [WidgetApp]
    /// Daily total installs over all apps.
    var totalHistory: [HistoryPoint]

    var totalInstalls: Int { apps.reduce(0) { $0 + $1.installs } }
    var totalCloud: Int { apps.reduce(0) { $0 + $1.cloud } }
    var totalLocal: Int { apps.reduce(0) { $0 + $1.local } }
    var totalDevices: Int { apps.reduce(0) { $0 + $1.devices } }
    var totalSuggestions: Int { apps.reduce(0) { $0 + $1.suggestions } }
    var totalLiveCrashes: Int { apps.reduce(0) { $0 + $1.liveCrashes } }
    var inReview: [WidgetApp] { apps.filter(\.inReview) }
    var crashingApps: [WidgetApp] { apps.filter { $0.liveCrashes + $0.testCrashes > 0 }.sorted { $0.liveCrashes > $1.liveCrashes } }
    var averageRating: Double? {
        let r = apps.compactMap(\.rating).filter { $0 > 0 }
        return r.isEmpty ? nil : r.reduce(0, +) / Double(r.count)
    }
    var totalDelta7d: Int? { HistoryMath.delta(totalHistory, days: 7) }
    var totalDelta30d: Int? { HistoryMath.delta(totalHistory, days: 30) }
    /// Apps sorted by 7-day growth.
    var topMovers: [WidgetApp] { apps.filter { ($0.delta7d ?? 0) != 0 }.sorted { ($0.delta7d ?? 0) > ($1.delta7d ?? 0) } }

    func app(_ id: String?) -> WidgetApp? { id.flatMap { id in apps.first { $0.id == id } } }

    // MARK: Persistence

    static func load() -> WidgetSnapshot? {
        guard let url = AppGroup.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = AppGroup.snapshotURL else { return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(self) { try? data.write(to: url, options: .atomic) }
    }

    static let placeholder: WidgetSnapshot = {
        let cal = Calendar.current
        func hist(_ base: Int, _ slope: Int) -> [HistoryPoint] {
            (0..<30).map { i in
                HistoryPoint(date: cal.date(byAdding: .day, value: -29 + i, to: cal.startOfDay(for: .now))!,
                             value: base + i * slope + Int(sin(Double(i) / 2.5) * Double(slope) * 2))
            }
        }
        let apps = [
            WidgetApp(id: "nl.example.weather", name: "Weather", installs: 6812, cloud: 912, local: 5900, rating: 5, liveVersion: "4.2.0",
                      testVersion: "4.2.2", testState: "in_review", liveCrashes: 3, testCrashes: 0, suggestions: 12, devices: 7420,
                      brandColor: "#1E88E5", history: hist(6400, 14)),
            WidgetApp(id: "nl.example.alerts", name: "Alerts", installs: 1534, cloud: 210, local: 1324, rating: 4.5, liveVersion: "6.2.4",
                      testVersion: "", testState: "", liveCrashes: 1, testCrashes: 0, suggestions: 4, devices: 1610,
                      brandColor: "#C62828", history: hist(1400, 5)),
            WidgetApp(id: "nl.example.energy", name: "Energy", installs: 789, cloud: 120, local: 669, rating: nil, liveVersion: "2.2.1",
                      testVersion: "", testState: "", liveCrashes: 0, testCrashes: 0, suggestions: 1, devices: 802,
                      brandColor: "#43A047", history: hist(700, 3)),
        ]
        return WidgetSnapshot(updatedAt: .now, accountName: "Homey Developer", apps: apps,
                              totalHistory: HistoryMath.sum(apps.map(\.history)))
    }()
}
