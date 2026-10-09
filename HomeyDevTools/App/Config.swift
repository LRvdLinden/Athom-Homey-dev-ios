import Foundation

enum Config {
    static let athomAPI = URL(string: "https://api.athom.com")!
    static let appsAPI = URL(string: "https://apps-api.athom.com/api/v1")!
    static let appsAssetHost = "https://apps-api.athom.com"
    static let developerToolsWeb = URL(string: "https://tools.developer.homey.app/")!
    static let apiClientsPage = URL(string: "https://tools.developer.homey.app/api/clients")!
    static let webhooksPage = URL(string: "https://tools.developer.homey.app/webhooks")!
    static let accountPage = URL(string: "https://tools.developer.homey.app/me")!
    static let passwordForgotten = URL(string: "https://accounts.athom.com/login/password-forgotten")!

    static func appStorePage(_ appId: String) -> URL? { URL(string: "https://homey.app/a/\(appId)/") }
    static func devToolsAppPage(_ appId: String) -> URL? { URL(string: "https://tools.developer.homey.app/apps/app/\(appId)") }
    static func devToolsOrgPage(_ orgId: String) -> URL? { URL(string: "https://tools.developer.homey.app/orgs/\(orgId)") }
    static func devTools(_ path: String) -> URL { URL(string: "https://tools.developer.homey.app" + path)! }

    /// The Homey tools from the Developer Tools sidebar ("Tools" + "Wireless").
    static let webTools: [(title: String, icon: String, path: String)] = [
        ("System", "cpu", "/tools/system"),
        ("Pairing", "plus.circle", "/tools/pair"),
        ("Devices", "lightbulb.2", "/tools/devices"),
        ("Images", "photo", "/tools/images"),
        ("Videos", "video", "/tools/videos"),
        ("Bluetooth LE", "dot.radiowaves.left.and.right", "/tools/ble"),
        ("Infrared", "light.beacon.max", "/tools/ir"),
        ("RF", "antenna.radiowaves.left.and.right", "/tools/signals"),
        ("Zigbee", "point.3.filled.connected.trianglepath.dotted", "/tools/zigbee"),
        ("Z-Wave", "point.3.connected.trianglepath.dotted", "/tools/zwave"),
        ("Web API Playground", "terminal", "/tools/api-playground"),
    ]
}
