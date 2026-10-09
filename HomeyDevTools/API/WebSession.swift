import Foundation
import WebKit

/// The Developer Tools website stores its Athom session (via the official `homey-api`
/// library) in `localStorage["homey-api"]` as `{ token: { access_token, refresh_token, … }, user: … }`.
/// We log in *on that website* (email + password on Athom's own login page) and reuse
/// that session, so no API client / secret is needed in the app.
struct WebSession: Codable, Equatable, Sendable {
    var store: String

    var json: JSON { JSON.parse(Data(store.utf8)) }
    var accessToken: String { json["token"]["access_token"].string ?? "" }
    var hasToken: Bool { !accessToken.isEmpty }
    var userId: String { json["user"].firstString("_id", "id") }
}

enum WebSessionBridge {
    static let host = "tools.developer.homey.app"
    static let storageKey = "homey-api"

    /// Document-start script that puts a stored session into the website's localStorage.
    @MainActor
    static func injectionScript(_ session: WebSession?) -> WKUserScript? {
        guard let session,
              let data = try? JSONSerialization.data(withJSONObject: [session.store]),
              let literal = String(data: data, encoding: .utf8) else { return nil }
        let js = """
        (function(){ try { if (location.host === '\(host)') { localStorage.setItem('\(storageKey)', \(literal)[0]); } } catch (e) {} })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// Reads the current session from a web view showing Developer Tools.
    @MainActor
    static func readSession(from webView: WKWebView) async -> WebSession? {
        guard webView.url?.host() == host else { return nil }
        let raw = try? await webView.callAsyncJavaScript("return localStorage.getItem('\(storageKey)');", contentWorld: .page) as? String
        guard let raw else { return nil }
        let s = WebSession(store: raw)
        return s.hasToken ? s : nil
    }

    /// Lets the website itself refresh the token (it owns the OAuth client), in an
    /// isolated, invisible web view, and returns the updated session.
    @MainActor
    static func refresh(_ session: WebSession) async throws -> WebSession {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        if let script = injectionScript(session) { cfg.userContentController.addUserScript(script) }
        let loader = WebPageLoader(configuration: cfg)
        try await loader.load(Config.developerToolsWeb)
        let js = """
        for (let i = 0; i < 100 && !globalThis.AthomCloudAPI; i++) { await new Promise(r => setTimeout(r, 100)); }
        if (!globalThis.AthomCloudAPI) { throw new Error('Developer Tools kon niet laden'); }
        await globalThis.AthomCloudAPI.authenticateWithRefreshToken();
        return localStorage.getItem('\(storageKey)');
        """
        do {
            guard let raw = try await loader.webView.callAsyncJavaScript(js, contentWorld: .page) as? String else {
                throw APIError(status: 401, message: "Sessie verlopen. Log opnieuw in voor dit account.", url: "")
            }
            let new = WebSession(store: raw)
            guard new.hasToken else { throw APIError(status: 401, message: "Sessie verlopen. Log opnieuw in voor dit account.", url: "") }
            return new
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError(status: 401, message: "Sessie verversen mislukt: \(error.localizedDescription)", url: "")
        }
    }
}

/// Loads a page in an off-screen web view and waits until it finished.
@MainActor
final class WebPageLoader: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var continuation: CheckedContinuation<Void, Error>?

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(); continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error); continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error); continuation = nil
    }
}
