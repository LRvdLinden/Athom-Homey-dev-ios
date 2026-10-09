import Foundation

/// Homey Pro Web API via Homey Cloud remote URL.
/// Auth: account token → delegation (`audience=homey`) → `POST /api/manager/users/login` → session Bearer.
@MainActor
final class HomeyClient {
    let homey: HomeyRef
    private let auth: AuthManager
    private var session: String?

    init(homey: HomeyRef, auth: AuthManager) {
        self.homey = homey
        self.auth = auth
    }

    var baseURL: URL { homey.remoteURL }

    private func login() async throws -> String {
        if let session { return session }
        let delegation = try await auth.delegationToken(audience: "homey")
        let resp = try await HTTP.send(
            baseURL.appendingPathComponent("api/manager/users/login"),
            method: "POST",
            body: JSON.object(["token": .string(delegation)]).data()
        ).json
        let token = resp.string ?? resp.firstString("token", "session")
        guard !token.isEmpty else { throw APIError(status: 0, message: L("Geen Homey-sessie ontvangen."), url: baseURL.absoluteString) }
        session = token
        return token
    }

    /// Raw request against this Homey. `path` like `/api/manager/devices/device/`.
    func request(_ path: String, method: String = "GET", json body: JSON? = nil) async throws -> JSON {
        guard let url = URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw APIError(status: 0, message: L("Ongeldig pad"), url: path)
        }
        func run() async throws -> HTTP.Response {
            let token = try await login()
            let data = body?.data() ?? ((method == "POST" || method == "PUT") ? Data("{}".utf8) : nil)
            return try await HTTP.send(url, method: method, headers: ["Authorization": "Bearer \(token)"], body: data)
        }
        do { return try await run().json } catch let e as APIError where e.isUnauthorized {
            session = nil
            auth.invalidateDelegation("homey")
            return try await run().json
        }
    }

    // MARK: Managers

    func system() async throws -> JSON {
        (try? await request("/api/manager/system/")) ?? .null
    }

    func zones() async throws -> [HomeyZone] {
        try await request("/api/manager/zones/zone/").items.compactMap(HomeyZone.init)
    }

    func devices() async throws -> [HomeyDevice] {
        let base = baseURL
        return try await request("/api/manager/devices/device/").items
            .compactMap { HomeyDevice($0, baseURL: base) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func device(_ id: String) async throws -> HomeyDevice? {
        HomeyDevice(try await request("/api/manager/devices/device/\(id)"), baseURL: baseURL)
    }

    func setCapability(device: String, capability: String, value: JSON) async throws {
        _ = try await request("/api/manager/devices/device/\(device)/capability/\(capability)", method: "PUT", json: .object(["value": value]))
    }

    func flows() async throws -> [HomeyFlow] {
        async let basic = request("/api/manager/flow/flow/")
        async let adv = request("/api/manager/flow/advancedflow/")
        let b = (try? await basic)?.items.compactMap { HomeyFlow($0, advanced: false) } ?? []
        let a = (try? await adv)?.items.compactMap { HomeyFlow($0, advanced: true) } ?? []
        return (b + a).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func flowFolders() async -> [String: String] {
        let f = (try? await request("/api/manager/flow/flowfolder/"))?.items ?? []
        return Dictionary(f.compactMap { j in j["id"].string.map { ($0, j["name"].string ?? $0) } }, uniquingKeysWith: { a, _ in a })
    }

    func trigger(_ flow: HomeyFlow) async throws {
        let kind = flow.advanced ? "advancedflow" : "flow"
        _ = try await request("/api/manager/flow/\(kind)/\(flow.id)/trigger", method: "POST")
    }

    func apps() async throws -> [HomeyInstalledApp] {
        try await request("/api/manager/apps/app/").items.compactMap(HomeyInstalledApp.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func restartApp(_ id: String) async throws {
        _ = try await request("/api/manager/apps/app/\(id)/restart", method: "POST")
    }

    func appSettings(_ id: String) async throws -> JSON {
        try await request("/api/manager/apps/app/\(id)/setting/")
    }

    func variables() async throws -> [HomeyVariable] {
        try await request("/api/manager/logic/variable/").items.compactMap(HomeyVariable.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func setVariable(_ v: HomeyVariable, value: JSON) async throws {
        _ = try await request("/api/manager/logic/variable/\(v.id)", method: "PUT", json: .object(["variable": .object(["value": value])]))
    }

    func notifications() async throws -> [JSON] {
        try await request("/api/manager/notifications/notification/").items
            .sorted { ($0["dateCreated"].date ?? .distantPast) > ($1["dateCreated"].date ?? .distantPast) }
    }
}
