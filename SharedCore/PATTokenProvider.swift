import Foundation

/// Hands out Athom delegation tokens for one Personal Access Token.
/// Used where no web session is available: background checks on the iPhone.
@MainActor
final class PATTokenProvider: TokenProvider {
    let pat: String
    private var delegated: [String: (token: String, expires: Date?)] = [:]

    init(pat: String) { self.pat = pat }

    func delegationToken(audience: String) async throws -> String {
        if let c = delegated[audience], (c.expires ?? .distantFuture) > Date() { return c.token }
        let url = Config.athomAPI.appendingPathComponent("delegation/token")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "audience", value: audience)]
        guard let full = components?.url else { throw APIError(status: 0, message: L("Ongeldig pad"), url: "delegation/token") }
        let resp = try await HTTP.send(full, method: "POST", headers: ["Authorization": "Bearer \(pat)"], body: Data("{}".utf8)).json
        let token: String
        switch resp {
        case .string(let s): token = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        default: token = resp.firstString("token", "access_token")
        }
        guard !token.isEmpty else { throw APIError(status: 0, message: L("Geen delegation token ontvangen (\(audience))."), url: "delegation/token") }
        delegated[audience] = (token, JWT.expiry(token))
        return token
    }

    func invalidateDelegation(_ audience: String) { delegated[audience] = nil }
}
