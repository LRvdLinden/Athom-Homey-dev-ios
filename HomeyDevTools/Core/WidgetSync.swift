import Foundation
import UIKit
import WidgetKit

/// Writes the portfolio of the active account into the App Group for the widgets,
/// enriched with install history (Athom install stats), suggestions and paired devices.
enum WidgetSync {
    private static let enrichedCount = 12

    @MainActor
    static func update(apps: [DevApp], accountName: String, auth: AuthManager) async {
        guard AppGroup.container != nil else { return }   // App Group not configured (signing)
        let previous = WidgetSnapshot.load()
        let sameAccount = previous?.accountName == accountName
        let api = AppsAPI(auth: auth)
        let sorted = apps.sorted { $0.installs > $1.installs }

        var widgetApps: [WidgetApp] = []
        for (index, app) in sorted.enumerated() {
            var history: [HistoryPoint] = []
            var suggestions = 0
            var devices = 0
            if index < enrichedCount {
                async let stats = try? api.installStats(app.id)
                async let sugg = try? api.suggestions(app.id)
                async let drivers = try? api.driverStats(app.id)
                let (st, sg, dr) = await (stats, sugg, drivers)
                history = HistoryMath.daily((st ?? []).map { HistoryPoint(date: $0.date, value: Int($0.value)) })
                suggestions = sg?.count ?? 0
                devices = (dr ?? []).reduce(0) { $0 + $1.count }
            }
            if history.isEmpty {
                // Fallback: build our own daily history from previous snapshots.
                let old = sameAccount ? (previous?.apps.first { $0.id == app.id }?.history ?? []) : []
                history = HistoryMath.record(app.installs, into: old)
            }
            widgetApps.append(WidgetApp(
                id: app.id, name: app.name, installs: app.installs, cloud: app.installsCloud, local: app.installsLocal,
                rating: app.rating, liveVersion: app.liveVersion, testVersion: app.testVersion, testState: app.testState,
                liveCrashes: app.liveCrashes, testCrashes: app.testCrashes, suggestions: suggestions, devices: devices,
                brandColor: app.brandColor, history: history
            ))
        }

        let snapshot = WidgetSnapshot(
            updatedAt: Date(),
            accountName: accountName,
            apps: widgetApps,
            totalHistory: HistoryMath.sum(widgetApps.map(\.history))
        )
        snapshot.save()
        await saveIcons(for: Array(sorted.prefix(enrichedCount)))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Widgets can't load images from the network, so store small PNG icons.
    private static func saveIcons(for apps: [DevApp]) async {
        guard let dir = AppGroup.container?.appendingPathComponent("icons", isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for app in apps {
            guard let src = app.iconURL, let dest = AppGroup.iconURL(for: app.id) else { continue }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
               let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 86_400 { continue }
            guard let (data, _) = try? await URLSession.shared.data(from: src), let image = UIImage(data: data) else { continue }
            let size = CGSize(width: 120, height: 120)
            let png = UIGraphicsImageRenderer(size: size).pngData { _ in
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let w = image.size.width * scale, h = image.size.height * scale
                image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            }
            try? png.write(to: dest, options: .atomic)
        }
    }
}
