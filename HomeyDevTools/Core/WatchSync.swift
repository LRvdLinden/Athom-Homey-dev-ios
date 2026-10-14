import Foundation
import WatchConnectivity

/// Sends the same summary the widgets use (WidgetSnapshot) to the Apple Watch app.
/// The watch never needs a login: it only shows what the iPhone last loaded.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Called after every refresh (and when the watch asks).
    func send(_ snapshot: WidgetSnapshot) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = Self.encode(snapshot) else { return }
        try? session.updateApplicationContext(["snapshot": data, "sentAt": Date().timeIntervalSince1970])
    }

    /// The watch shows at most 30 days, and WatchConnectivity has a size limit
    /// (about 65 KB for an application context), so send a trimmed summary.
    static func encode(_ snapshot: WidgetSnapshot) -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        var maxApps = 30, days = 32
        while true {
            var s = snapshot
            s.apps = Array(s.apps.sorted { $0.installs > $1.installs }.prefix(maxApps)).enumerated().map { i, app in
                var a = app
                a.history = Array(app.history.suffix(i < 15 ? days : 8))
                return a
            }
            s.totalHistory = Array(snapshot.totalHistory.suffix(days))
            guard let data = try? e.encode(s) else { return nil }
            if data.count < 60_000 || maxApps <= 5 { return data }
            maxApps = max(5, maxApps / 2)
            days = max(8, days / 2)
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated, let snapshot = WidgetSnapshot.load() else { return }
        send(snapshot)
    }

    /// The watch asks for the latest summary (pull to refresh on the watch).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let snapshot = WidgetSnapshot.load(), let data = Self.encode(snapshot) else {
            replyHandler(["empty": true])
            return
        }
        replyHandler(["snapshot": data])
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
