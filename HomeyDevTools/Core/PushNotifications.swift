import Foundation
import UIKit
import OneSignalFramework

/// Direct push notifications through OneSignal.
///
/// The app only registers the device and tags it; a scheduled GitHub Actions job
/// (`notify/notify.mjs`) checks the build status of your apps every few minutes
/// and sends the push through OneSignal. The OneSignal REST API key lives only in
/// that job's secrets, never in the app.
///
/// Tags on this device:
/// - `u_<athomUserId>` = "1" for every saved account (the job targets these)
/// - `k_<kind>` = "1" / "0" for each status kind you turned on or off
@MainActor
enum PushNotifications {
    /// Public OneSignal App ID (safe to ship in the app).
    static let appID = "23f09f93-060f-4aa4-bde2-d11cf1e49be0"
    static let enabledKey = "push.enabled"
    private static let taggedAccountsKey = "push.taggedAccounts"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Called once at launch from the app delegate.
    static func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        OneSignal.initialize(appID, withLaunchOptions: launchOptions)
    }

    /// Asks for permission, opts in and tags the device for every saved account.
    static func enable(auth: AuthManager) async throws {
        let accepted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            OneSignal.Notifications.requestPermission({ accepted in c.resume(returning: accepted) }, fallbackToSettings: true)
        }
        guard accepted else {
            throw APIError(status: 0, message: L("Meldingen staan uit voor deze app. Zet ze aan in Instellingen → Meldingen."), url: "")
        }
        OneSignal.User.pushSubscription.optIn()
        UserDefaults.standard.set(true, forKey: enabledKey)
        sync(auth: auth)
    }

    static func disable() {
        OneSignal.User.pushSubscription.optOut()
        UserDefaults.standard.set(false, forKey: enabledKey)
    }

    /// Updates the account and status tags (after adding/removing an account or
    /// changing which statuses you want).
    static func sync(auth: AuthManager) {
        guard isEnabled else { return }
        let ids = Set(auth.accounts.map(\.id))
        let previous = Set(UserDefaults.standard.stringArray(forKey: taggedAccountsKey) ?? [])
        var tags: [String: String] = [:]
        for id in ids { tags["u_\(tagSafe(id))"] = "1" }
        for kind in StatusNotifier.Kind.allCases { tags["k_\(kind.rawValue)"] = kind.isOn ? "1" : "0" }
        OneSignal.User.addTags(tags)
        let removed = previous.subtracting(ids).map { "u_\(tagSafe($0))" }
        if !removed.isEmpty { OneSignal.User.removeTags(removed) }
        UserDefaults.standard.set(Array(ids), forKey: taggedAccountsKey)
    }

    /// OneSignal tag keys: keep letters, digits and underscores.
    static func tagSafe(_ s: String) -> String {
        String(s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
    }
}

/// Starts OneSignal with the launch options (needed to handle a tapped push).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { PushNotifications.start(launchOptions: launchOptions) }
        WatchSync.shared.activate()
        return true
    }
}
