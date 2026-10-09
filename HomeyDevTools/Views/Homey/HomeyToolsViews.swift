import SwiftUI

struct FlowsView: View {
    let client: HomeyClient
    @State private var flows: [HomeyFlow] = []
    @State private var folders: [String: String] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""
    @State private var feedback: String?
    @State private var running: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            ForEach(sections, id: \.self) { folder in
                Section(folder) {
                    ForEach(filtered.filter { folderName($0) == folder }) { f in
                        HStack(spacing: 12) {
                            Image(systemName: f.advanced ? "point.3.connected.trianglepath.dotted" : "arrow.triangle.branch")
                                .foregroundStyle(f.broken ? .red : (f.enabled ? Color.accentColor : .secondary))
                                .frame(width: 26)
                            NavigationLink {
                                JSONInspectorView(title: f.name, json: f.raw)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name).lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(f.advanced ? "Advanced" : "Standaard")
                                        if !f.enabled { Text("Uitgeschakeld").foregroundStyle(.orange) }
                                        if f.broken { Text("Defect").foregroundStyle(.red) }
                                    }
                                    .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            if f.triggerable && f.enabled {
                                Button { Task { await trigger(f) } } label: {
                                    if running == f.id { ProgressView() } else {
                                        Image(systemName: "play.circle.fill").font(.title2)
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .overlay { if loading && flows.isEmpty { ProgressView() } }
        .searchable(text: $search, prompt: "Zoek flow")
        .themedList()
        .navigationTitle("Flows (\(flows.count))")
        .refreshable { await load() }
        .task { if flows.isEmpty { await load() } }
        .actionFeedback($feedback)
    }

    private var filtered: [HomeyFlow] {
        let q = search.lowercased()
        return q.isEmpty ? flows : flows.filter { $0.name.lowercased().contains(q) }
    }
    private func folderName(_ f: HomeyFlow) -> String { f.folder.flatMap { folders[$0] } ?? "Zonder map" }
    private var sections: [String] { Array(Set(filtered.map(folderName))).sorted() }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            flows = try await client.flows()
            folders = await client.flowFolders()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func trigger(_ f: HomeyFlow) async {
        running = f.id; defer { running = nil }
        do { try await client.trigger(f); feedback = "\u{25B6}\u{FE0E} \(f.name) gestart" } catch { feedback = error.localizedDescription }
    }
}

struct HomeyAppsView: View {
    let client: HomeyClient
    @State private var feedback: String?

    var body: some View {
        Loader(load: { try await client.apps() }) { (apps: [HomeyInstalledApp], reload) in
            List(apps) { app in
                NavigationLink {
                    HomeyAppDetailView(client: client, app: app)
                } label: {
                    HStack(spacing: 12) {
                        AppIconView(url: app.iconURL.flatMap { URL(string: $0.absoluteString, relativeTo: client.baseURL) }, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).lineLimit(1)
                            Text("\(app.id) · v\(app.version)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if app.crashed { StateBadge(state: "failed") }
                        else if !app.enabled { StateBadge(state: "disabled") }
                        else if !app.origin.isEmpty && app.origin != "appstore" { StateBadge(state: app.origin) }
                    }
                }
            }
            .refreshable { await reload() }
        }
        .navigationTitle("Apps")
        .actionFeedback($feedback)
    }
}

struct HomeyAppDetailView: View {
    let client: HomeyClient
    let app: HomeyInstalledApp
    @State private var feedback: String?
    @State private var restarting = false
    @State private var confirmRestart = false

    var body: some View {
        List {
            Section {
                LabeledContent("ID", value: app.id).textSelection(.enabled)
                LabeledContent("Versie", value: app.version)
                LabeledContent("Status", value: app.state.isEmpty ? "—" : app.state)
                LabeledContent("Ingeschakeld", value: app.enabled ? "Ja" : "Nee")
                if !app.origin.isEmpty { LabeledContent("Bron", value: app.origin) }
            }
            Section {
                Button { confirmRestart = true } label: {
                    HStack { Label("Herstart app", systemImage: "arrow.clockwise"); if restarting { Spacer(); ProgressView() } }
                }
                .disabled(restarting)
                NavigationLink("App-instellingen") {
                    Loader(load: { try await client.appSettings(app.id) }) { (j: JSON, _) in
                        JSONInspectorView(title: "Instellingen", json: j)
                    }
                }
                NavigationLink("Ruwe API-data") { JSONInspectorView(title: app.name, json: app.raw) }
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("\(app.name) herstarten?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Herstart", role: .destructive) { Task { await restart() } }
        }
        .actionFeedback($feedback)
    }

    private func restart() async {
        restarting = true; defer { restarting = false }
        do { try await client.restartApp(app.id); feedback = "\(app.name) wordt herstart" } catch { feedback = error.localizedDescription }
    }
}

struct VariablesView: View {
    let client: HomeyClient
    @State private var editing: HomeyVariable?
    @State private var text = ""
    @State private var feedback: String?

    var body: some View {
        Loader(load: { try await client.variables() }) { (vars: [HomeyVariable], reload) in
            List(vars) { v in
                Button {
                    if v.type == "boolean" {
                        Task { await save(v, .bool(!(v.value.bool ?? false))); await reload() }
                    } else {
                        text = v.value.displayString; editing = v
                    }
                } label: {
                    HStack {
                        Image(systemName: icon(v.type)).frame(width: 24).foregroundStyle(Color.accentColor)
                        Text(v.name).foregroundStyle(.primary)
                        Spacer()
                        Text(v.value.displayString).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .refreshable { await reload() }
            .alert("Waarde van \(editing?.name ?? "")", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField("Waarde", text: $text)
                    .keyboardType(editing?.type == "number" ? .decimalPad : .default)
                Button("Annuleer", role: .cancel) { editing = nil }
                Button("Bewaar") {
                    if let v = editing {
                        let value: JSON = v.type == "number" ? .number(Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0) : .string(text)
                        Task { await save(v, value); await reload() }
                    }
                    editing = nil
                }
            }
        }
        .navigationTitle("Logic-variabelen")
        .actionFeedback($feedback)
    }

    private func icon(_ t: String) -> String {
        switch t { case "boolean": "switch.2"; case "number": "number"; default: "textformat" }
    }

    private func save(_ v: HomeyVariable, _ value: JSON) async {
        do { try await client.setVariable(v, value: value); feedback = "\(v.name) bijgewerkt" } catch { feedback = error.localizedDescription }
    }
}

struct NotificationsView: View {
    let client: HomeyClient
    var body: some View {
        Loader(load: { try await client.notifications() }) { (items: [JSON], reload) in
            List(Array(items.enumerated()), id: \.offset) { _, n in
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.firstString("excerpt", "title", "message").replacingOccurrences(of: "**", with: ""))
                    HStack {
                        Text(n.firstString("ownerUri").replacingOccurrences(of: "homey:", with: ""))
                        Spacer()
                        Text(Fmt.relative(n["dateCreated"].date))
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .overlay { if items.isEmpty { ContentUnavailableView("Tijdlijn is leeg", systemImage: "bell.slash") } }
            .refreshable { await reload() }
        }
        .navigationTitle("Tijdlijn")
    }
}

struct SystemView: View {
    let client: HomeyClient
    var body: some View {
        Loader(load: { () async throws -> JSON in
            let sys = try await client.system()
            if sys.isNull { return try await client.request("/api/manager/system/info") }
            return sys
        }) { (j: JSON, _) in
            JSONInspectorView(title: "Systeem", json: j)
        }
        .navigationTitle("Systeem")
    }
}
