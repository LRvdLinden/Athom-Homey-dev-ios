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

    static func encode(_ snapshot: WidgetSnapshot) -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        return try? e.encode(snapshot)
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
