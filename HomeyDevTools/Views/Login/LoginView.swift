import SwiftUI
import WebKit

/// Welcome screen (no account yet) — also reused as "Account toevoegen".
struct LoginView: View {
    var isAddingAccount = false
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var showWebLogin = false
    @State private var showPAT = false

    var body: some View {
        ZStack(alignment: .top) {
            WaveBackdrop(height: 360)

            VStack(spacing: 0) {
                if isAddingAccount {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.headline).padding(10).background(.ultraThinMaterial, in: Circle())
                        }
                        .foregroundStyle(.primary)
                    }
                    .padding(.horizontal)
                }
                Spacer(minLength: 40)

                VStack(spacing: 22) {
                    HStack(spacing: 12) {
                        HomeyLogo(size: 40)
                        Text("Developer Tools").font(.system(size: 26, weight: .bold))
                    }

                    VStack(spacing: 8) {
                        Text(isAddingAccount ? "Account toevoegen" : "Develop for Homey")
                            .font(.system(size: 30, weight: .regular))
                        Text("Je apps, builds, crashes, organisaties en Homeys – overal bij de hand.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        Button { showWebLogin = true } label: {
                            HStack(spacing: 10) {
                                HomeyLogo(size: 22)
                                Text("Inloggen met Homey")
                            }
                        }
                        .buttonStyle(GradientPillButtonStyle())

                        Button { showPAT = true } label: {
                            Label("Personal Access Token", systemImage: "key.fill")
                        }
                        .buttonStyle(OutlinePillButtonStyle())
                    }

                    Text("Log in met het e-mailadres en wachtwoord van je Homey-account. Je kunt meerdere accounts toevoegen en snel wisselen.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .homeyCard(padding: 24)
                .padding(.horizontal, 20)
                .frame(maxWidth: 480)

                if !isAddingAccount && !auth.accounts.isEmpty {
                    Text("\(auth.accounts.count) opgeslagen account(s)").font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showWebLogin) {
            WebLoginSheet { if isAddingAccount { dismiss() } }
        }
        .sheet(isPresented: $showPAT) {
            PATLoginSheet { if isAddingAccount { dismiss() } }
        }
    }
}

/// Athom's own login page (email + password), hosted by the Developer Tools website.
struct WebLoginSheet: View {
    var onDone: () -> Void = {}
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var connecting = true
    @State private var saving = false
    @State private var error: String?
    @State private var reloadID = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyWebLogin(connecting: $connecting) { session in
                    Task { await finish(session) }
                }
                .id(reloadID)

                if connecting || saving {
                    VStack(spacing: 14) {
                        HomeyLogo(size: 54, spinning: true)
                        Text(saving ? "Account ophalen…" : "Verbinden met Homey…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error {
                    ErrorBanner(message: error) { self.error = nil; reloadID = UUID(); connecting = true }
                        .padding()
                }
            }
            .navigationTitle("Inloggen met Homey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { reloadID = UUID(); connecting = true } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func finish(_ session: WebSession) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try await auth.addWebAccount(session)
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct HomeyWebLogin: UIViewRepresentable {
    @Binding var connecting: Bool
    let onSession: (WebSession) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        // Fresh, isolated cookie jar per login: lets you add a *different* account
        // without being auto-logged-in as the previous one.
        cfg.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.load(URLRequest(url: Config.developerToolsWeb))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: HomeyWebLogin
        private var delivered = false

        init(_ parent: HomeyWebLogin) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if webView.url?.host() == WebSessionBridge.host { parent.connecting = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView.url?.host() == WebSessionBridge.host else {
                parent.connecting = false   // Athom login page is visible now
                return
            }
            Task { await inspect(webView) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.connecting = false
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }

        private func inspect(_ webView: WKWebView) async {
            let js = """
            const hasCode = new URLSearchParams(location.search).has('code');
            for (let i = 0; i < (hasCode ? 200 : 8); i++) {
              try {
                const s = localStorage.getItem('\(WebSessionBridge.storageKey)');
                if (s) { const j = JSON.parse(s); if (j && j.token && j.token.access_token) { return s; } }
              } catch (e) {}
              await new Promise(r => setTimeout(r, 100));
            }
            if (!hasCode) {
              for (let i = 0; i < 80 && !globalThis.AthomCloudAPI; i++) { await new Promise(r => setTimeout(r, 100)); }
              if (globalThis.AthomCloudAPI) {
                location.href = globalThis.AthomCloudAPI.getLoginUrl() + '&state=' + encodeURIComponent('origin=/');
                return 'redirect';
              }
            }
            return null;
            """
            let result = try? await webView.callAsyncJavaScript(js, contentWorld: .page)
            guard let raw = result as? String, raw != "redirect" else {
                if result == nil { parent.connecting = false }
                return
            }
            let session = WebSession(store: raw)
            guard session.hasToken, !delivered else { return }
            delivered = true
            parent.onSession(session)
        }
    }
}

struct PATLoginSheet: View {
    var onDone: () -> Void = {}
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Personal Access Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } footer: {
                    Text("Maak een token aan in Developer Tools onder **My Account → Personal Access Tokens**. Het token blijft alleen in de iOS-sleutelhanger op dit toestel.")
                }
                .cardRows()
                if let error { Section { Text(error).foregroundStyle(.red) }.cardRows() }
                Section {
                    Button("Open Developer Tools → My Account") { openURL(Config.accountPage) }
                }
                .cardRows()
            }
            .themedList()
            .navigationTitle("Personal Access Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Toevoegen") { submit() }.disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func submit() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await auth.addPATAccount(token); dismiss(); onDone() } catch { self.error = error.localizedDescription }
        }
    }
}
