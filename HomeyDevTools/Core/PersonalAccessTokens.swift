import Foundation
import Security

extension AuthManager: TokenProvider {}

/// Personal Access Tokens per account. The background status check uses them,
/// because a web session expires and can't be refreshed without a WebView.
@MainActor
enum PersonalAccessTokens {
    /// PAT accounts already have one; web accounts ask Athom for theirs
    /// (the "Reveal" button in Developer Tools → My Account).
    static func token(for acc: StoredAccount, auth: AuthManager) async throws -> String {
        switch acc.credential {
        case .pat(let p):
            return p
        case .web(let session):
            var lastError: Error?
            // Try twice: an expired session of the active account is refreshed by AuthManager in between.
            for attempt in 0..<2 {
                do {
                    let resp: JSON = acc.id == auth.activeID
                        ? try await auth.athom("/user/me/pat/apps")
                        : try await HTTP.send(Config.athomAPI.appendingPathComponent("user/me/pat/apps"),
                                              headers: ["Authorization": "Bearer \(session.accessToken)"]).json
                    if let token = extract(resp), try await isValid(token) { return token }
                    lastError = APIError(status: 0, message: L("Geen Personal Access Token ontvangen."), url: "user/me/pat/apps")
                } catch {
                    lastError = error
                    if let api = error as? APIError, api.status == 404 { break }
                }
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(400)) }
            }
            throw APIError(status: 0,
                           message: L("Kon geen Personal Access Token ophalen (\(lastError?.localizedDescription ?? "–")). Voeg het account toe met een token uit Developer Tools → My Account."),
                           url: "user/me/pat/apps")
        }
    }

    /// Accepts a bare string, `{ token: … }` style objects and arrays of those.
    static func extract(_ json: JSON) -> String? {
        switch json {
        case .string(let s):
            let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
            return t.isEmpty ? nil : t
        case .array(let items):
            return items.lazy.compactMap { extract($0) }.first
        default:
            let t = json.firstString("token", "pat", "accessToken", "access_token", "value")
            return t.isEmpty ? nil : t
        }
    }

    /// A token is only stored when Athom accepts it for a delegation token.
    private static func isValid(_ token: String) async throws -> Bool {
        do {
            _ = try await PATTokenProvider(pat: token).delegationToken(audience: "apps")
            return true
        } catch let error as APIError where error.status == 401 || error.status == 403 {
            return false
        }
    }

    /// Removes the iCloud Keychain item that older versions shared with the Apple TV app.
    static func removeLegacyAppleTVShare() {
        let flag = "legacy.appletv.cleaned"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "nl.lrvdlinden.homeydevtools.shared-accounts",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "appleTVSharingEnabled")
        UserDefaults.standard.set(true, forKey: flag)
    }
}
