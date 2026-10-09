import SwiftUI
import WebKit
import CryptoKit

/// The full Homey Developer Tools website inside the app, so every feature of the
/// web version (publishing builds, certification, webhooks, wireless tools, …) is available.
/// Each saved account gets its own persistent website data store, and is signed in
/// automatically with that account's session.
struct WebToolsView: View {
    var start: URL = Config.developerToolsWeb
    @Environment(AuthManager.self) private var auth
    @State private var model = WebModel()

    var body: some View {
        DevToolsWebView(model: model, start: start, accountID: auth.activeID, session: auth.activeWebSession) { session in
            auth.adoptWebSession(session)
        }
        .background(Theme.background)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            if model.progress < 1 {
                ProgressView(value: model.progress).progressViewStyle(.linear).tint(Theme.accent)
            }
        }
        .navigationTitle(model.title.isEmpty ? "Developer Tools" : model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.webView?.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!model.canGoBack)
                Menu {
                    Button { model.load(Config.developerToolsWeb) } label: { Label("Home", systemImage: "house") }
                    Button { model.load(Config.devTools("/apps")) } label: { Label("My Apps", systemImage: "square.stack.3d.up") }
                    Button { model.load(Config.devTools("/orgs")) } label: { Label("My Organizations", systemImage: "building.2") }
                    Button { model.load(Config.apiClientsPage) } label: { Label("My API Clients", systemImage: "person.badge.key") }
                    Button { model.load(Config.webhooksPage) } label: { Label("My Webhooks", systemImage: "link") }
                    Divider()
                    if let url = model.webView?.url {
                        ShareLink(item: url) { Label("Deel link", systemImage: "square.and.arrow.up") }
                        Button { UIApplication.shared.open(url) } label: { Label("Open in Safari", systemImage: "safari") }
                    }
                    Button { model.webView?.reload() } label: { Label("Herladen", systemImage: "arrow.clockwise") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
}

@MainActor
@Observable
final class WebModel {
    var title = ""
    var progress: Double = 0
    var canGoBack = false
    var canGoForward = false
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored var observations: [NSKeyValueObservation] = []

    func load(_ url: URL) { webView?.load(URLRequest(url: url)) }

    func attach(_ wv: WKWebView) {
        webView = wv
        observations = [
            wv.observe(\.title) { [weak self] w, _ in Task { @MainActor in self?.title = w.title ?? "" } },
            wv.observe(\.estimatedProgress) { [weak self] w, _ in Task { @MainActor in self?.progress = w.estimatedProgress } },
            wv.observe(\.canGoBack) { [weak self] w, _ in Task { @MainActor in self?.canGoBack = w.canGoBack } },
            wv.observe(\.canGoForward) { [weak self] w, _ in Task { @MainActor in self?.canGoForward = w.canGoForward } },
        ]
    }
}

enum WebDataStores {
    /// Stable per-account identifier for `WKWebsiteDataStore(forIdentifier:)`.
    static func identifier(for accountID: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(accountID.utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }

    @MainActor
    static func store(for accountID: String?) -> WKWebsiteDataStore {
        guard let accountID else { return .default() }
        return WKWebsiteDataStore(forIdentifier: identifier(for: accountID))
    }
}

struct DevToolsWebView: UIViewRepresentable {
    let model: WebModel
    let start: URL
    let accountID: String?
    let session: WebSession?
    let onSession: (WebSession) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSession: onSession) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WebDataStores.store(for: accountID)
        cfg.allowsInlineMediaPlayback = true
        if let session, let data = try? JSONSerialization.data(withJSONObject: [session.store]),
           let literal = String(data: data, encoding: .utf8) {
            let homeyID = UserDefaults.standard.string(forKey: "activeHomeyId") ?? ""
            let homeyLiteral = (try? JSONSerialization.data(withJSONObject: [homeyID])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            // Only seed the session when this account's website storage has none yet,
            // so tokens the website rotates itself are never overwritten.
            let js = """
            (function(){ try {
              if (location.host !== '\(WebSessionBridge.host)') return;
              var cur = localStorage.getItem('\(WebSessionBridge.storageKey)');
              var ok = false; try { var j = JSON.parse(cur || '{}'); ok = !!(j && j.token && j.token.access_token); } catch (e) {}
              if (!ok) localStorage.setItem('\(WebSessionBridge.storageKey)', \(literal)[0]);
              var hid = \(homeyLiteral)[0]; if (hid) localStorage.setItem('activeHomeyId', hid);
            } catch (e) {} })();
            """
            cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.allowsBackForwardNavigationGestures = true
        wv.uiDelegate = context.coordinator
        wv.navigationDelegate = context.coordinator
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = refresh
        model.attach(wv)
        wv.load(URLRequest(url: start))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onSession = onSession
    }

    @MainActor
    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var onSession: (WebSession) -> Void
        init(onSession: @escaping (WebSession) -> Void) { self.onSession = onSession }

        @objc func refresh(_ sender: UIRefreshControl) {
            (sender.superview?.superview as? WKWebView)?.reload()
            sender.endRefreshing()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Keep the app in sync when the website refreshed its tokens.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if let s = await WebSessionBridge.readSession(from: webView) { onSession(s) }
            }
        }

        // OAuth popups / target=_blank: open in the same web view.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}
