import Foundation
import UserNotifications
import BackgroundTasks

/// Status notifications for your apps: new build, Test, in review, approved,
/// rejected and live. There is no server, so the app compares the build status
/// of every app with what it saw last time — whenever it refreshes, and in the
/// background (Background App Refresh; iOS decides how often) — and shows a
/// local notification for every change.
@MainActor
enum StatusNotifier {
    static let taskID = "nl.lrvdlinden.homeydevtools.status-refresh"
    static let enabledKey = "notifications.enabled"

    /// The kinds of changes you can be notified about (each can be turned off).
    enum Kind: String, CaseIterable, Identifiable {
        case draft, test, inReview, approved, rejected, live
        var id: String { rawValue }

        var title: String {
            switch self {
            case .draft: L("Nieuwe build (draft)")
            case .test: L("In Test gezet")
            case .inReview: L("Ingediend voor certificering")
            case .approved: L("Goedgekeurd")
            case .rejected: L("Afgekeurd")
            case .live: L("Live gezet")
            }
        }

        var icon: String {
            switch self {
            case .draft: "shippingbox"
            case .test: "testtube.2"
            case .inReview: "hourglass"
            case .approved: "checkmark.seal"
            case .rejected: "xmark.octagon"
            case .live: "dot.radiowaves.left.and.right"
            }
        }

        func body(version: String) -> String {
            let v = version.isEmpty ? "" : "v\(version) "
            switch self {
            case .draft: return L("\(v)is geüpload als draft.")
            case .test: return L("\(v)staat nu in Test.")
            case .inReview: return L("\(v)is ingediend voor certificering.")
            case .approved: return L("\(v)is goedgekeurd door Athom.")
            case .rejected: return L("\(v)is afgekeurd. Bekijk de opmerkingen van de reviewer.")
            case .live: return L("\(v)staat nu live.")
            }
        }

        var key: String { "notifications.kind.\(rawValue)" }
        var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    // MARK: Setup

    /// Asks for permission and stores a Personal Access Token per account, so the
    /// background check can run without the (short-lived) web session.
    /// Returns a warning when only foreground checks are possible.
    @discardableResult
    static func enable(auth: AuthManager) async throws -> String? {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else {
            throw APIError(status: 0, message: L("Meldingen staan uit voor deze app. Zet ze aan in Instellingen → Meldingen."), url: "")
        }
        var warning: String?
        do {
            try await storeTokens(auth: auth)
        } catch {
            warning = L("Controleren op de achtergrond lukt niet (\(error.localizedDescription)). Je krijgt meldingen wanneer de app ververst.")
        }
        UserDefaults.standard.set(true, forKey: enabledKey)
        // Remember the current status as the starting point (no flood of old changes).
        await checkAll(notify: false)
        scheduleBackgroundCheck()
        return warning
    }

    static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        NotificationTokens.save([:])
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
    }

    /// Fetches (or reveals) the Personal Access Token of every saved account.
    static func storeTokens(auth: AuthManager) async throws {
        var tokens: [String: NotificationTokens.Entry] = [:]
        var lastError: Error?
        for acc in auth.accounts {
            do {
                let pat = try await AppleTVSharing.personalAccessToken(for: acc, auth: auth)
                tokens[acc.id] = .init(pat: pat, name: acc.name.isEmpty ? acc.email : acc.name)
            } catch { lastError = error }
        }
        if tokens.isEmpty, let lastError { throw lastError }
        NotificationTokens.save(tokens)
    }

    // MARK: Checking

    /// Called after the app loaded the portfolio of the active account.
    static func check(apps: [DevApp], accountID: String, accountName: String, multipleAccounts: Bool) {
        guard isEnabled else { return }
        compare(apps, accountID: accountID, accountName: multipleAccounts ? accountName : nil, notify: true)
    }

    /// Checks every account that has a stored token. Used by the background task.
    static func checkAll(notify: Bool = true) async {
        let tokens = NotificationTokens.load()
        for (accountID, entry) in tokens {
            let api = AppsAPI(auth: PATTokenProvider(pat: entry.pat))
            guard let apps = try? await allApps(api) else { continue }
            compare(apps, accountID: accountID, accountName: tokens.count > 1 ? entry.name : nil, notify: notify)
        }
    }

    private static func allApps(_ api: AppsAPI) async throws -> [DevApp] {
        var out = try await api.myApps()
        if let orgs = try? await api.organizations() {
            for org in orgs {
                let full = (try? await api.organization(org.id)) ?? org
                if let apps = try? await api.apps(of: full) { out += apps }
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }

    /// What we remember per app.
    struct Seen: Codable, Equatable {
        var liveBuildId: Int?
        var testBuildId: Int?
        var testState: String
    }

    private static func compare(_ apps: [DevApp], accountID: String, accountName: String?, notify: Bool) {
        let key = "notifications.seen.\(accountID)"
        let decoder = JSONDecoder()
        let previous: [String: Seen] = (UserDefaults.standard.data(forKey: key)).flatMap { try? decoder.decode([String: Seen].self, from: $0) } ?? [:]
        var current: [String: Seen] = [:]

        for app in apps {
            let now = Seen(liveBuildId: app.liveBuildId, testBuildId: app.testBuildId, testState: app.testState)
            current[app.id] = now
            guard notify, let before = previous[app.id], before != now else { continue }

            if let live = now.liveBuildId, live != before.liveBuildId {
                post(.live, app: app, version: app.liveVersion, accountName: accountName)
            }
            let testChanged = now.testBuildId != before.testBuildId || now.testState != before.testState
            if testChanged, now.testBuildId != nil, let kind = kind(forTestState: now.testState) {
                post(kind, app: app, version: app.testVersion, accountName: accountName)
            }
        }
        if let data = try? JSONEncoder().encode(current) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func kind(forTestState state: String) -> Kind? {
        switch state {
        case "draft": .draft
        case "test": .test
        case "in_review": .inReview
        case "reviewed_approved", "approved": .approved
        case "reviewed_rejected", "rejected": .rejected
        default: nil
        }
    }

    private static func post(_ kind: Kind, app: DevApp, version: String, accountName: String?) {
        guard kind.isOn else { return }
        let content = UNMutableNotificationContent()
        content.title = app.name
        if let accountName { content.subtitle = accountName }
        content.body = kind.body(version: version)
        content.sound = .default
        content.threadIdentifier = app.id
        content.userInfo = ["appId": app.id, "kind": kind.rawValue]
        let request = UNNotificationRequest(identifier: "\(app.id).\(kind.rawValue).\(version)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Shows a sample notification so you can see what they look like.
    static func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Weather Alerts"
        content.body = Kind.live.body(version: "1.4.2")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "test.\(UUID().uuidString)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Background

    /// Asks iOS to run the check again in about 15 minutes (iOS picks the exact moment).
    static func scheduleBackgroundCheck() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Personal Access Tokens used by the background check, per account (iOS Keychain).
enum NotificationTokens {
    struct Entry: Codable {
        var pat: String
        var name: String
    }

    private static let key = "notification-tokens"

    static func load() -> [String: Entry] { Keychain.load([String: Entry].self, for: key) ?? [:] }

    static func save(_ tokens: [String: Entry]) {
        if tokens.isEmpty { Keychain.delete(key) } else { Keychain.save(tokens, for: key) }
    }
}

/// Shows notifications while the app is open too.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
