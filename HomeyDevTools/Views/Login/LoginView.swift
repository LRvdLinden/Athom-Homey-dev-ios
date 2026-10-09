import SwiftUI
import WebKit

/// Welcome screen (v1 look: blue blueprint background, app icon, white button).
/// Also reused as "Account toevoegen".
struct LoginView: View {
    var isAddingAccount = false
    /// Called right after a new account was verified, so the screen that presented
    /// this one can close too before the app switches account.
    var onAdded: () -> Void = {}
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var showWebLogin = false
    @State private var showPAT = false

    var body: some View {
        ZStack {
            BlueprintBackground().ignoresSafeArea()

            VStack(spacing: 28) {
                if isAddingAccount {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                                .padding(10).background(.white.opacity(0.18), in: Circle())
                        }
                    }
                }
                Spacer()
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)

                VStack(spacing: 8) {
                    Text(isAddingAccount ? L("Account toevoegen") : "Homey Developer Tools")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Je apps, builds, crashes, organisaties en Homeys – overal bij de hand.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button { showWebLogin = true } label: {
                        HStack(spacing: 10) {
                            HomeyLogo(size: 22)
                            Text("Inloggen met Homey").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.black)
                    }

                    Button { showPAT = true } label: {
                        Label("Inloggen met Personal Access Token", systemImage: "key.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }

                    Text(isAddingAccount
                         ? L("Log in met een ander Homey-account. Je kunt daarna snel wisselen.")
                         : L("Gebruik het e-mailadres en wachtwoord van je Homey-account."))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
        }
        .sheet(isPresented: $showWebLogin) {
            WebLoginSheet { if isAddingAccount { dismiss(); onAdded() } }
        }
        .sheet(isPresented: $showPAT) {
            PATLoginSheet { if isAddingAccount { dismiss(); onAdded() } }
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
                        Text(saving ? L("Account ophalen…") : L("Verbinden met Homey…")).font(.subheadline).foregroundStyle(.secondary)
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
        let pending: AuthManager.PendingAccount
        do {
            pending = try await auth.verifyWebAccount(session)
        } catch {
            saving = false
            self.error = error.localizedDescription
            return
        }
        // Close the login sheet (and the "add account" screen) first, then
        // switch to the account once the presentations are gone.
        await auth.commitAfterDismiss(pending) {
            dismiss()
            onDone()
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
            do {
                let pending = try await auth.verifyPATAccount(token)
                await auth.commitAfterDismiss(pending) {
                    dismiss()
                    onDone()
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
