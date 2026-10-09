import Foundation

/// Athom Apps API (the data behind Homey Developer Tools → Apps).
/// Auth: account token → delegation token with `audience=apps` → Bearer.
@MainActor
struct AppsAPI {
    let auth: AuthManager

    func request(_ path: String, method: String = "GET", json body: JSON? = nil) async throws -> JSON {
        guard let url = URL(string: Config.appsAPI.absoluteString + path) else {
            throw APIError(status: 0, message: "Ongeldig pad", url: path)
        }
        func run() async throws -> JSON {
            let token = try await auth.delegationToken(audience: "apps")
            return try await HTTP.send(url, method: method, headers: ["Authorization": "Bearer \(token)"], body: body?.data()).json
        }
        do { return try await run() } catch let e as APIError where e.isUnauthorized {
            auth.invalidateDelegation("apps")
            return try await run()
        }
    }

    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? s }

    func myApps() async throws -> [DevApp] {
        try await request("/app/me").array.compactMap(DevApp.init).sorted { $0.installs > $1.installs }
    }

    func organizations() async throws -> [DevOrganization] {
        try await request("/org").array.compactMap(DevOrganization.init).sorted { $0.name < $1.name }
    }

    func organization(_ id: String) async throws -> DevOrganization? {
        DevOrganization(try await request("/org/\(enc(id))"))
    }

    func app(_ id: String) async throws -> DevApp? {
        DevApp(try await request("/app/\(enc(id))"))
    }

    /// Organisation app refs are sometimes only ids; hydrate those (sequentially, like Developer Checker).
    func apps(of org: DevOrganization) async throws -> [DevApp] {
        var out: [DevApp] = []
        for ref in org.appRefs {
            if case .object = ref, !ref["installs"].isNull || !ref["liveBuild"].isNull || !ref["testBuild"].isNull,
               let a = DevApp(ref) {
                out.append(a); continue
            }
            let id = ref.string ?? ref["id"].string ?? ""
            guard !id.isEmpty else { continue }
            if let a = try? await app(id) { out.append(a) } else if let a = DevApp(.object(["id": .string(id)])) { out.append(a) }
        }
        return out.sorted { $0.installs > $1.installs }
    }

    func builds(_ appId: String) async throws -> [DevBuild] {
        try await request("/app/\(enc(appId))/build").array.compactMap(DevBuild.init).sorted { $0.id > $1.id }
    }

    func build(_ appId: String, _ buildId: Int) async throws -> DevBuild? {
        DevBuild(try await request("/app/\(enc(appId))/build/\(buildId)"))
    }

    func crashes(_ appId: String, buildId: Int) async throws -> [DevCrash] {
        try await request("/app/\(enc(appId))/build/\(buildId)/crash").array.enumerated()
            .map { DevCrash($1, index: $0) }
            .sorted { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }
    }

    func suggestions(_ appId: String) async throws -> [DevSuggestion] {
        try await request("/app/\(enc(appId))/suggestion").array.enumerated()
            .map { DevSuggestion($1, index: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    func installStats(_ appId: String) async throws -> [StatPoint] {
        StatPoint.parse(try await request("/app/\(enc(appId))/install/stats"))
    }

    func driverStats(_ appId: String) async throws -> [DriverStat] {
        try await request("/app/\(enc(appId))/drivers/stats").object.map { key, series in
            let pts = StatPoint.parse(series)
            return DriverStat(driverId: key, count: Int(pts.last?.value ?? 0), series: pts)
        }.sorted { $0.count > $1.count }
    }

    /// Loads everything for one app in parallel; individual failures are collected, not fatal.
    func detail(for app: DevApp) async -> AppDetail {
        var d = AppDetail(app: app)
        if let fresh = try? await self.app(app.id) { d.app = fresh }
        let a = d.app
        async let builds = capture { try await self.builds(a.id) }
        async let stats = capture { try await self.installStats(a.id) }
        async let drivers = capture { try await self.driverStats(a.id) }
        async let sugg = capture { try await self.suggestions(a.id) }
        async let live = capture { () -> DevBuild? in
            guard let b = a.liveBuildId else { return nil }
            return try await self.build(a.id, b)
        }
        async let crashes = capture { () -> [DevCrash] in
            guard let b = a.liveBuildId else { return [] }
            return try await self.crashes(a.id, buildId: b)
        }
        var errors: [String] = []
        func take<T>(_ r: Result<T, Error>, _ label: String, _ fallback: T) -> T {
            switch r { case .success(let v): return v
            case .failure(let e): errors.append("\(label): \(e.localizedDescription)"); return fallback }
        }
        d.builds = take(await builds, "Builds", [])
        d.installStats = take(await stats, "Statistieken", [])
        d.drivers = take(await drivers, "Drivers", [])
        d.suggestions = take(await sugg, "Suggesties", [])
        d.liveBuild = take(await live, "Live build", nil)
        d.liveCrashes = take(await crashes, "Crashes", [])
        d.errors = errors
        return d
    }

    private func capture<T>(_ op: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await op()) } catch { return .failure(error) }
    }
}
