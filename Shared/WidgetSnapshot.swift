import Foundation

/// Shared between the app and the widget extension (both targets compile this folder).
/// The app writes a snapshot into the App Group container after every refresh;
/// the widgets only read it, so they never need the account's tokens.
enum AppGroup {
    static let id = "group.nl.lrvdlinden.homeydevtools"
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) }
    static var snapshotURL: URL? { container?.appendingPathComponent("widget-snapshot.json") }
    static func iconURL(for appId: String) -> URL? {
        container?.appendingPathComponent("icons", isDirectory: true)
            .appendingPathComponent(appId.replacingOccurrences(of: "/", with: "_") + ".png")
    }
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
    var brandColor: String

    var inReview: Bool { testState == "in_review" }
}

struct HistoryPoint: Codable, Hashable {
    var date: Date
    var value: Int
}

struct WidgetSnapshot: Codable {
    var updatedAt: Date
    var accountName: String
    var apps: [WidgetApp]
    /// Daily total installs (one point per day, last 90 days).
    var totalHistory: [HistoryPoint]
    /// Daily installs per app id.
    var appHistory: [String: [HistoryPoint]]

    var totalInstalls: Int { apps.reduce(0) { $0 + $1.installs } }
    var totalCloud: Int { apps.reduce(0) { $0 + $1.cloud } }
    var totalLocal: Int { apps.reduce(0) { $0 + $1.local } }
    var inReview: [WidgetApp] { apps.filter(\.inReview) }
    var totalLiveCrashes: Int { apps.reduce(0) { $0 + $1.liveCrashes } }
    var averageRating: Double? {
        let r = apps.compactMap(\.rating).filter { $0 > 0 }
        return r.isEmpty ? nil : r.reduce(0, +) / Double(r.count)
    }

    /// Change over the last `days` days, based on the stored daily history.
    static func delta(_ history: [HistoryPoint], days: Int, current: Int) -> Int? {
        guard let first = history.first else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let base = history.last(where: { $0.date <= cutoff }) ?? first
        guard base.date < Calendar.current.startOfDay(for: Date()) else { return nil }
        return current - base.value
    }

    var totalDelta7d: Int? { Self.delta(totalHistory, days: 7, current: totalInstalls) }
    func delta7d(for app: WidgetApp) -> Int? { Self.delta(appHistory[app.id] ?? [], days: 7, current: app.installs) }

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

    /// Adds/overwrites today's point and keeps 90 days.
    static func record(_ value: Int, into history: [HistoryPoint]) -> [HistoryPoint] {
        let today = Calendar.current.startOfDay(for: Date())
        var h = history.filter { $0.date != today }
        h.append(HistoryPoint(date: today, value: value))
        h.sort { $0.date < $1.date }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: today) ?? today
        return h.filter { $0.date >= cutoff }
    }

    static let placeholder: WidgetSnapshot = {
        let apps = [
            WidgetApp(id: "nl.example.weather", name: "Weather", installs: 6812, cloud: 912, local: 5900, rating: 5, liveVersion: "4.2.0", testVersion: "4.2.2", testState: "in_review", liveCrashes: 2, brandColor: "#1E88E5"),
            WidgetApp(id: "nl.example.alerts", name: "Alerts", installs: 1534, cloud: 210, local: 1324, rating: 4.5, liveVersion: "6.2.4", testVersion: "", testState: "", liveCrashes: 0, brandColor: "#C62828"),
            WidgetApp(id: "nl.example.energy", name: "Energy", installs: 789, cloud: 120, local: 669, rating: nil, liveVersion: "2.2.1", testVersion: "", testState: "", liveCrashes: 0, brandColor: "#43A047"),
        ]
        let now = Date()
        let hist = (0..<14).map { i in
            HistoryPoint(date: Calendar.current.date(byAdding: .day, value: -13 + i, to: now)!, value: 9000 + i * 11 + (i % 3) * 4)
        }
        return WidgetSnapshot(updatedAt: now, accountName: "Homey Developer", apps: apps, totalHistory: hist, appHistory: [:])
    }()
}
