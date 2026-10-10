import Foundation

/// A Homey linked to the account (from `GET api.athom.com/user/me` → `homeys`).
struct HomeyRef: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let platform: String
    /// Model code, e.g. `homey5q` (Pro Early 2023), `homey6q` (Pro mini), `shs`.
    let modelCode: String
    /// Display model, e.g. "Homey Pro (Early 2023)".
    let model: String
    let softwareVersion: String
    let remoteURL: URL
    let localURL: URL?
    let role: String
    let apiVersion: Int
    /// Product images, the same ones my.homey.app shows (`modelImage.light/dark`).
    let imageLight: URL?
    let imageDark: URL?
    let raw: JSON

    init?(_ j: JSON) {
        guard let id = j["id"].string ?? j["_id"].string else { return nil }
        self.id = id
        name = j.firstString("name").isEmpty ? "Homey" : j.firstString("name")
        platform = j.firstString("platform", "platformVersion")
        modelCode = j["model"].string ?? ""
        let named = j.firstString("modelName")
        model = named.isEmpty ? Self.modelName(code: modelCode, platform: platform) : named
        softwareVersion = j.firstString("softwareVersion", "version")
        remoteURL = URL(string: j.firstString("remoteUrl", "remoteUrlForwarded")) ?? URL(string: "https://\(id).connect.athom.com") ?? Config.athomAPI
        localURL = URL(string: j.firstString("localUrlSecure", "localUrl"))
        role = j.firstString("role")
        apiVersion = j["apiVersion"].int ?? 0
        let img: JSON = j["modelImage"]
        if img.isContainer {
            imageLight = URL(string: img.firstString("light", "default", "url"))
            imageDark = URL(string: img.firstString("dark", "light", "default", "url"))
        } else {
            imageLight = URL(string: img.string ?? "")
            imageDark = imageLight
        }
        raw = j
    }

    var isCloud: Bool { platform == "cloud" }
    var isSelfHosted: Bool { modelCode == "shs" }

    /// Same mapping as my.homey.app when the API gives no model name.
    static func modelName(code: String, platform: String) -> String {
        if platform == "cloud" { return "Homey Cloud" }
        switch code {
        case "homey5q": return "Homey Pro (Early 2023)"
        case "homey7q": return "Homey Pro"
        case "homey6q": return "Homey Pro mini"
        case "shs": return "Homey Self-Hosted Server"
        case "homey3s", "homey3d", "homey4d": return "Homey Pro (Early 2019)"
        default: return "Homey Pro"
        }
    }

    var subtitle: String {
        [model, softwareVersion.isEmpty ? "" : "v\(softwareVersion)", role].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// SF Symbol used while the product image loads or when there is none.
    var fallbackSymbol: String {
        if isCloud { return "house.fill" }
        if isSelfHosted { return "server.rack" }
        return "circle.circle.fill"
    }
}

struct HomeyCapability: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let type: String
    let value: JSON
    let units: String
    let setable: Bool
    let min: Double?
    let max: Double?
    let step: Double?
    let decimals: Int?
    let lastUpdated: Date?

    init(id: String, _ j: JSON) {
        self.id = id
        title = j["title"].localized.isEmpty ? id : j["title"].localized
        type = j["type"].string ?? ""
        value = j["value"]
        units = j["units"].localized
        setable = j["setable"].bool ?? false
        min = j["min"].double
        max = j["max"].double
        step = j["step"].double
        decimals = j["decimals"].int
        lastUpdated = j["lastUpdated"].date
    }

    var formattedValue: String {
        switch value {
        case .bool(let b): return b ? L("Aan") : L("Uit")
        case .number(let n):
            let d = decimals ?? (n.rounded() == n ? 0 : 2)
            let s = String(format: "%.\(d)f", type == "number" && max == 1 && min == 0 && units.isEmpty ? n * 100 : n)
            let u = (type == "number" && max == 1 && min == 0 && units.isEmpty) ? "%" : units
            return u.isEmpty ? s : "\(s) \(u)"
        case .null: return "—"
        default: return value.displayString
        }
    }
}

struct HomeyDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let zoneId: String
    let deviceClass: String
    let driverId: String
    let available: Bool
    let unavailableMessage: String
    let iconURL: URL?
    let capabilities: [HomeyCapability]
    let raw: JSON

    init?(_ j: JSON, baseURL: URL) {
        guard let id = j["id"].string else { return nil }
        self.id = id
        name = j["name"].string ?? id
        zoneId = j["zone"].string ?? ""
        deviceClass = j["class"].string ?? ""
        driverId = j.firstString("driverId", "driverUri")
        available = j["available"].bool ?? true
        unavailableMessage = j["unavailableMessage"].string ?? ""
        let icon = j["iconObj"]["url"].string ?? ""
        iconURL = icon.isEmpty || icon.hasSuffix(".svg") ? nil : URL(string: icon, relativeTo: baseURL)
        let order = j["capabilities"].array.compactMap(\.string)
        let obj = j["capabilitiesObj"].object
        let keys = order.isEmpty ? obj.keys.sorted() : order
        capabilities = keys.compactMap { k in obj[k].map { HomeyCapability(id: k, $0) } }
        raw = j
    }

    var onoff: HomeyCapability? { capabilities.first { $0.id == "onoff" } }

    var systemImage: String {
        switch deviceClass {
        case "light": return "lightbulb"
        case "socket": return "poweroutlet.type.f"
        case "sensor": return "sensor"
        case "thermostat", "heater": return "thermometer.medium"
        case "lock": return "lock"
        case "speaker", "tv", "amplifier": return "hifispeaker"
        case "camera": return "video"
        case "doorbell": return "bell"
        case "windowcoverings", "blinds", "curtain", "sunshade": return "blinds.vertical.closed"
        case "fan": return "fan"
        case "vacuumcleaner": return "humidifier"
        case "button", "remote": return "button.programmable"
        case "solarpanel": return "sun.max"
        case "evcharger", "car": return "bolt.car"
        case "homealarm": return "shield"
        default: return "square.grid.2x2"
        }
    }
}

struct HomeyZone: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let parent: String?
    let icon: String
    init?(_ j: JSON) {
        guard let id = j["id"].string else { return nil }
        self.id = id
        name = j["name"].string ?? id
        parent = j["parent"].string
        icon = j["icon"].string ?? ""
    }
}

struct HomeyFlow: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let enabled: Bool
    let broken: Bool
    let triggerable: Bool
    let folder: String?
    let advanced: Bool
    let raw: JSON
    init?(_ j: JSON, advanced: Bool) {
        guard let id = j["id"].string else { return nil }
        self.id = id
        name = j["name"].string ?? id
        enabled = j["enabled"].bool ?? true
        broken = j["broken"].bool ?? false
        triggerable = j["triggerable"].bool ?? advanced
        folder = j["folder"].string
        self.advanced = advanced
        raw = j
    }
}

struct HomeyInstalledApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let state: String
    let enabled: Bool
    let origin: String
    let crashed: Bool
    let iconURL: URL?
    let raw: JSON
    init?(_ j: JSON) {
        guard let id = j["id"].string else { return nil }
        self.id = id
        name = j["name"].localized.isEmpty ? id : j["name"].localized
        version = j["version"].string ?? ""
        state = j["state"].string ?? (j["ready"].bool == true ? "running" : "")
        enabled = j["enabled"].bool ?? true
        origin = j["origin"].string ?? ""
        crashed = j["crashed"].bool ?? false
        let img = j["images"]["small"].string ?? ""
        iconURL = URL(string: img)
        raw = j
    }
}

struct HomeyVariable: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let type: String
    let value: JSON
    init?(_ j: JSON) {
        guard let id = j["id"].string else { return nil }
        self.id = id
        name = j["name"].string ?? id
        type = j["type"].string ?? ""
        value = j["value"]
    }
}
