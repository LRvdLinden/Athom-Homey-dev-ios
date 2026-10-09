import SwiftUI

/// Send arbitrary requests to the Athom API, Apps API or a Homey's Web API.
struct APIPlaygroundView: View {
    enum Target {
        case athom, apps
        case homey(HomeyClient)

        var label: String {
            switch self {
            case .athom: return "api.athom.com"
            case .apps: return "apps-api.athom.com/api/v1"
            case .homey(let c): return c.homey.name
            }
        }
        var defaultPath: String {
            switch self {
            case .athom: return "/user/me"
            case .apps: return "/app/me"
            case .homey: return "/api/manager/system/"
            }
        }
        var examples: [String] {
            switch self {
            case .athom: return ["/user/me"]
            case .apps: return ["/app/me", "/org"]
            case .homey: return ["/api/manager/system/", "/api/manager/devices/device/", "/api/manager/zones/zone/",
                                 "/api/manager/flow/flow/", "/api/manager/flow/advancedflow/", "/api/manager/apps/app/",
                                 "/api/manager/logic/variable/", "/api/manager/insights/log/", "/api/manager/users/user/"]
            }
        }
    }

    let target: Target
    @Environment(AuthManager.self) private var auth

    @State private var method = "GET"
    @State private var path = ""
    @State private var bodyText = ""
    @State private var result: JSON?
    @State private var error: String?
    @State private var duration: TimeInterval?
    @State private var busy = false

    private let methods = ["GET", "POST", "PUT", "DELETE"]

    var body: some View {
        Form {
            Section {
                Picker("Methode", selection: $method) { ForEach(methods, id: \.self) { Text($0) } }
                    .pickerStyle(.segmented)
                TextField("Pad", text: $path)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if method != "GET" && method != "DELETE" {
                    TextEditor(text: $bodyText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 90)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .overlay(alignment: .topLeading) {
                            if bodyText.isEmpty { Text("JSON body").foregroundStyle(.tertiary).font(.caption).padding(8).allowsHitTesting(false) }
                        }
                }
                Button(action: send) {
                    HStack { Spacer(); if busy { ProgressView() } else { Label("Verstuur", systemImage: "paperplane.fill") }; Spacer() }
                }
                .disabled(busy || path.isEmpty)
            } header: { Text(target.label) }

            Section("Voorbeelden") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(target.examples, id: \.self) { ex in
                            Button(ex) { path = ex; method = "GET" }
                                .font(.caption.monospaced())
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if let error {
                Section("Fout") { Text(error).foregroundStyle(.red).font(.callout.monospaced()).textSelection(.enabled) }
            }
            if let result {
                Section {
                    NavigationLink { JSONInspectorView(title: path, json: result) } label: {
                        Label("Bekijk als boom", systemImage: "list.bullet.indent")
                    }
                    Text(String(result.prettyString.prefix(20_000)))
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text("Response" + (duration.map { String(format: " · %.0f ms", $0 * 1000) } ?? ""))
                }
            }
        }
        .navigationTitle("API Playground")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if path.isEmpty { path = target.defaultPath } }
    }

    private func send() {
        error = nil; result = nil; busy = true
        let start = Date()
        Task {
            defer { busy = false; duration = Date().timeIntervalSince(start) }
            var body: JSON?
            if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, method != "GET" {
                let parsed = JSON.parse(Data(bodyText.utf8))
                guard parsed.isContainer else { error = L("Body is geen geldige JSON."); return }
                body = parsed
            }
            let p = path.hasPrefix("/") ? path : "/" + path
            do {
                switch target {
                case .athom: result = try await auth.athom(p, method: method, json: body)
                case .apps: result = try await AppsAPI(auth: auth).request(p, method: method, json: body)
                case .homey(let c): result = try await c.request(p, method: method, json: body)
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}
