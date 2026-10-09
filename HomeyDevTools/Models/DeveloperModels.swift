import Foundation

func assetURL(_ raw: String) -> URL? {
    let t = raw.trimmingCharacters(in: .whitespaces)
    if t.isEmpty { return nil }
    if t.hasPrefix("http") || t.hasPrefix("data:") { return URL(string: t) }
    if t.hasPrefix("//") { return URL(string: "https:\(t)") }
    if t.hasPrefix("/") { return URL(string: Config.appsAssetHost + t) }
    return URL(string: t)
}

/// A Homey app as returned by the Apps API (`/app/me`, `/app/:id`, org apps).
struct DevApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let installs: Int
    let installsCloud: Int
    let installsLocal: Int
    let rating: Double?
    let ratingCount: Int
    let liveVersion: String
    let testVersion: String
    let liveState: String
    let testState: String
    let liveBuildId: Int?
    let testBuildId: Int?
    let liveCrashes: Int
    let testCrashes: Int
    let iconURL: URL?
    let imageURL: URL?
    let brandColor: String
    let liveUpdatedAt: Date?
    let raw: JSON

    init?(_ j: JSON) {
        guard let id = j["id"].string, !id.isEmpty else { return nil }
        let live = j["liveBuild"], test = j["testBuild"]
        self.id = id
        let n = j["name"].localized
        name = n.isEmpty ? (live["name"].localized.isEmpty ? id : live["name"].localized) : n
        installs = j["installs"].int ?? 0
        installsCloud = j["installsCloud"].int ?? 0
        installsLocal = j["installsLocal"].int ?? 0
        rating = j["rating"].double
        ratingCount = j["ratingCount"].int ?? j["ratings"].int ?? 0
        liveVersion = j["liveVersion"].string ?? live["version"].string ?? ""
        testVersion = j["testVersion"].string ?? test["version"].string ?? ""
        liveState = live["state"].string ?? ""
        testState = test["state"].string ?? ""
        liveBuildId = live["id"].int
        testBuildId = test["id"].int
        liveCrashes = live["crashes"].int ?? 0
        testCrashes = test["crashes"].int ?? 0
        // App icons are SVG (not renderable by AsyncImage), so prefer the small PNG/JPG image.
        let iconCandidates = [
            live.firstString("imageSmall"), test.firstString("imageSmall"), j.firstString("imageSmall"),
            live.firstString("icon"), test.firstString("icon"), j.firstString("icon"),
            live.firstString("imageLarge"), j.firstString("imageLarge"),
        ]
        iconURL = iconCandidates.lazy
            .filter { !$0.isEmpty && !$0.lowercased().hasSuffix(".svg") }
            .compactMap(assetURL).first
        imageURL = assetURL(live.firstString("imageLarge", "imageSmall")) ?? assetURL(test.firstString("imageLarge", "imageSmall")) ?? assetURL(j.firstString("imageLarge", "imageSmall"))
        brandColor = live.firstString("brandColor").isEmpty ? (test.firstString("brandColor").isEmpty ? j.firstString("brandColor") : test.firstString("brandColor")) : live.firstString("brandColor")
        liveUpdatedAt = j["liveBuildUpdatedAt"].date
        raw = j
    }

    var inReview: Bool { testState == "in_review" || liveState == "in_review" }
}

struct DevOrganization: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let appRefs: [JSON]
    let members: [JSON]
    let imageURL: URL?
    let descriptionText: String
    /// Your own role in this organisation: owner / admin / developer / support.
    let myRole: String
    let verified: Bool
    let raw: JSON

    init?(_ j: JSON) {
        guard let id = j["id"].string ?? j["_id"].string else { return nil }
        self.id = id
        name = j.firstString("name", "title").isEmpty ? id : j.firstString("name", "title")
        appRefs = j["apps"].array
        members = j["members"].array.isEmpty ? j["users"].array : j["members"].array
        let img = j["image"].isContainer ? j["image"].firstString("small", "medium", "large", "url") : j.firstString("image", "avatar", "logo", "icon")
        imageURL = img.lowercased().hasSuffix(".svg") ? nil : assetURL(img)
        descriptionText = j["description"].localized
        myRole = j.firstString("role")
        verified = j["verified"].bool ?? false
        raw = j
    }
}

extension DevOrganization {
    var canManageMembers: Bool { myRole == "owner" || myRole == "admin" }
    var canChangeRoles: Bool { myRole == "owner" }
}

/// Organisation member (`org.members[]`: id, userId, name, email, role, avatarUrl).
struct OrgMember: Identifiable, Hashable, Sendable {
    let id: String
    let userId: String
    let name: String
    let email: String
    let role: String
    let avatarURL: URL?

    init(_ j: JSON, index: Int) {
        let u = j["user"].isContainer ? j["user"] : j
        id = j.firstString("id", "_id").isEmpty ? "\(index)" : j.firstString("id", "_id")
        userId = j.firstString("userId").isEmpty ? u.firstString("_id", "id") : j.firstString("userId")
        let full = "\(u["firstname"].string ?? "") \(u["lastname"].string ?? "")".trimmingCharacters(in: .whitespaces)
        let n = j.firstString("name", "fullname").isEmpty ? (full.isEmpty ? u.firstString("fullname", "name") : full) : j.firstString("name", "fullname")
        email = j.firstString("email").isEmpty ? u.firstString("email") : j.firstString("email")
        name = n.isEmpty ? email : n
        role = j.firstString("role", "roleId")
        var avatar = j.firstString("avatarUrl", "avatarURL")
        if avatar.isEmpty {
            let a = u["avatar"]
            avatar = a.isContainer ? a.firstString("medium", "large", "small", "url") : (a.string ?? "")
        }
        avatarURL = assetURL(avatar)
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return parts.isEmpty ? String(email.prefix(1)).uppercased() : parts.uppercased()
    }
}

struct DevBuild: Identifiable, Hashable, Sendable {
    let id: Int
    let version: String
    let state: String
    let createdAt: Date?
    let stateChangedAt: Date?
    let installs: Int
    let crashes: Int
    let platforms: [String]
    let sdk: String
    let changelog: String
    let raw: JSON

    init?(_ j: JSON) {
        guard let id = j["id"].int else { return nil }
        self.id = id
        version = j["version"].string ?? ""
        state = j["state"].string ?? ""
        createdAt = j["createdAt"].date
        stateChangedAt = j["stateChangedAt"].date
        installs = j["installs"].int ?? 0
        crashes = j["crashes"].int ?? 0
        platforms = j["platforms"].array.compactMap(\.string)
        sdk = j["sdk"].string ?? j["compatibility"].string ?? ""
        changelog = j["changelog"].localized
        raw = j
    }
}

struct DevCrash: Identifiable, Hashable, Sendable {
    let id: String
    let count: Int
    let homeyVersion: String
    let stack: String
    let createdAt: Date?
    let updatedAt: Date?
    let raw: JSON

    init(_ j: JSON, index: Int) {
        id = j["id"].string ?? j["_id"].string ?? "\(index)"
        count = j["count"].int ?? 1
        homeyVersion = j["homeyVersion"].string ?? ""
        stack = j.firstString("stack", "message", "error")
        createdAt = j["createdAt"].date
        updatedAt = j["updatedAt"].date
        raw = j
    }

    var firstLine: String {
        stack.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? L("Onbekende crash")
    }
}

struct DevSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let createdAt: Date?
    let raw: JSON

    init(_ j: JSON, index: Int) {
        id = j["id"].string ?? "\(index)"
        text = j.firstString("suggestionText", "text", "message")
        createdAt = j["createdAt"].date
        raw = j
    }
}

struct StatPoint: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let value: Double

    static func parse(_ j: JSON) -> [StatPoint] {
        j.array.compactMap { p -> StatPoint? in
            let t = p["date"].isNull ? (p["t"].isNull ? p["timestamp"] : p["t"]) : p["date"]
            guard let d = t.date, let v = (p["value"].isNull ? p["v"] : p["value"]).double, v.isFinite else { return nil }
            return StatPoint(date: d, value: v)
        }.sorted { $0.date < $1.date }
    }
}

struct DriverStat: Identifiable, Hashable, Sendable {
    var id: String { driverId }
    let driverId: String
    let count: Int
    let series: [StatPoint]
}

/// Everything shown on the app detail screen.
struct AppDetail: Sendable {
    var app: DevApp
    var builds: [DevBuild] = []
    var installStats: [StatPoint] = []
    var drivers: [DriverStat] = []
    var suggestions: [DevSuggestion] = []
    var liveCrashes: [DevCrash] = []
    var liveBuild: DevBuild?
    var errors: [String] = []

    var deviceCount: Int { drivers.reduce(0) { $0 + $1.count } }
    var totalCrashes: Int { builds.reduce(0) { $0 + $1.crashes } }
}

struct PortfolioTotals {
    var apps = 0, installs = 0, cloud = 0, local = 0, inReview = 0, crashes = 0
    var avgRating: Double = 0

    init(_ apps: [DevApp]) {
        self.apps = apps.count
        installs = apps.reduce(0) { $0 + $1.installs }
        cloud = apps.reduce(0) { $0 + $1.installsCloud }
        local = apps.reduce(0) { $0 + $1.installsLocal }
        inReview = apps.filter(\.inReview).count
        crashes = apps.reduce(0) { $0 + $1.liveCrashes + $1.testCrashes }
        let rated = apps.compactMap(\.rating).filter { $0 > 0 }
        avgRating = rated.isEmpty ? 0 : rated.reduce(0, +) / Double(rated.count)
    }
}
