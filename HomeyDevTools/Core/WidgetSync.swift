import Foundation
import UIKit
import WidgetKit

/// Writes the portfolio of the active account into the App Group for the widgets.
enum WidgetSync {
    @MainActor
    static func update(apps: [DevApp], accountName: String) async {
        guard AppGroup.container != nil else { return }   // App Group not configured (signing)
        let previous = WidgetSnapshot.load()
        let sameAccount = previous?.accountName == accountName
        let widgetApps = apps.map {
            WidgetApp(id: $0.id, name: $0.name, installs: $0.installs, cloud: $0.installsCloud, local: $0.installsLocal,
                      rating: $0.rating, liveVersion: $0.liveVersion, testVersion: $0.testVersion, testState: $0.testState,
                      liveCrashes: $0.liveCrashes, brandColor: $0.brandColor)
        }
        let total = widgetApps.reduce(0) { $0 + $1.installs }
        var appHistory = sameAccount ? (previous?.appHistory ?? [:]) : [:]
        for a in widgetApps { appHistory[a.id] = WidgetSnapshot.record(a.installs, into: appHistory[a.id] ?? []) }
        let snapshot = WidgetSnapshot(
            updatedAt: Date(),
            accountName: accountName,
            apps: widgetApps.sorted { $0.installs > $1.installs },
            totalHistory: WidgetSnapshot.record(total, into: sameAccount ? (previous?.totalHistory ?? []) : []),
            appHistory: appHistory
        )
        snapshot.save()
        await saveIcons(for: Array(apps.sorted { $0.installs > $1.installs }.prefix(8)))
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
