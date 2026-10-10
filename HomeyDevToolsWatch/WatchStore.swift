import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// Receives the summary from the iPhone (WatchConnectivity) and keeps it on the
/// watch, also for the complications (App Group).
@MainActor
@Observable
final class WatchStore: NSObject {
    private(set) var snapshot: WidgetSnapshot?
    private(set) var refreshing = false
    private(set) var message: String?

    private static let cacheKey = "watch.snapshot"

    override init() {
        super.init()
        snapshot = WidgetSnapshot.load() ?? Self.cached()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Asks the iPhone for its latest summary.
    func refresh() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            message = String(localized: "iPhone niet bereikbaar. Open Homey Dev op je iPhone.")
            return
        }
        refreshing = true
        message = nil
        session.sendMessage(["request": "snapshot"], replyHandler: { reply in
            let data = reply["snapshot"] as? Data
            Task { @MainActor in
                self.refreshing = false
                if let data { self.apply(data) } else { self.message = String(localized: "Open Homey Dev op je iPhone om gegevens te laden.") }
            }
        }, errorHandler: { error in
            let text = error.localizedDescription
            Task { @MainActor in
                self.refreshing = false
                self.message = text
            }
        })
    }

    private func apply(_ data: Data) {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let new = try? d.decode(WidgetSnapshot.self, from: data) else { return }
        snapshot = new
        new.save()                                        // App Group, for the complications
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func cached() -> WidgetSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["snapshot"] as? Data
        Task { @MainActor in
            if let data { self.apply(data) }
            if self.snapshot == nil { self.refresh() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["snapshot"] as? Data
        Task { @MainActor in if let data { self.apply(data) } }
    }
}
