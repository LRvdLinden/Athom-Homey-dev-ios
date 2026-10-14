import SwiftUI

// MARK: - System

struct SystemToolView: View {
    let client: HomeyClient
    @State private var info: JSON = .null
    @State private var memory: JSON = .null
    @State private var storage: JSON = .null
    @State private var updates: [JSON] = []
    @State private var experiments: [JSON] = []
    @State private var error: String?
    @State private var feedback: String?
    @State private var newName = ""
    @State private var renaming = false
    @State private var confirmReboot = false

    var body: some View {
        List {
            Section { ToolHeader(client: client) }.listRowBackground(Color.clear)
            if let error { ErrorBanner(message: error) { Task { await load() } }.listRowBackground(Color.clear) }

            Section("Systeem") {
                row("Naam", info.firstString("homeyName", "name"))
                row("Model", info.firstString("homeyModelName", "modelName", "model"))
                row("Software", info.firstString("homeyVersion", "softwareVersion", "version"))
                row("Platform", info.firstString("homeyPlatform", "platform"))
                row("Uptime", uptime(info["uptime"].double))
                row("WiFi", info.firstString("wifiSsid"))
                row("IP-adres", info.firstString("address", "ipAddress"))
                row("Tijdzone", info.firstString("timezone"))
                Button { newName = info.firstString("homeyName", "name"); renaming = true } label: { Label("Naam wijzigen", systemImage: "pencil") }
                Button(role: .destructive) { confirmReboot = true } label: { Label("Homey herstarten", systemImage: "restart") }
            }
            .cardRows()

            if !memory.isNull { usageSection("Geheugen", memory) }
            if !storage.isNull { usageSection("Opslag", storage) }

            if !updates.isEmpty {
                Section("Updates") {
                    ForEach(Array(updates.enumerated()), id: \.offset) { _, u in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("v\(u.firstString("version"))").font(.body.weight(.semibold))
                            Text(u["changelog"].localized).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(4)
                        }
                    }
                }
                .cardRows()
            }

            if !experiments.isEmpty {
                Section("Experimenten") {
                    ForEach(Array(experiments.enumerated()), id: \.offset) { _, e in
                        Toggle(isOn: Binding(get: { e["enabled"].bool ?? false }, set: { on in Task { await toggleExperiment(e, on) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(titleOrID(e))
                                if !e["description"].localized.isEmpty {
                                    Text(e["description"].localized).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(3)
                                }
                            }
                        }
                    }
                }
                .cardRows()
            }

            Section { NavigationLink("Ruwe data") { JSONInspectorView(title: "System", json: info) } }.cardRows()
        }
        .themedList()
        .navigationTitle("System")
        .refreshable { await load() }
        .task { await load() }
        .alert("Naam wijzigen", isPresented: $renaming) {
            TextField("Naam", text: $newName)
            Button("Annuleer", role: .cancel) {}
            Button("Bewaar") { Task { await rename() } }
        }
        .confirmationDialog("Homey herstarten?", isPresented: $confirmReboot, titleVisibility: .visible) {
            Button("Herstart", role: .destructive) { Task { await reboot() } }
        } message: { Text("Homey is een paar minuten niet bereikbaar.") }
        .actionFeedback($feedback)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(label, value: value.isEmpty ? "—" : value)
    }

    private func uptime(_ s: Double?) -> String {
        guard let s, s > 0 else { return "" }
        let f = DateComponentsFormatter(); f.allowedUnits = [.day, .hour, .minute]; f.unitsStyle = .abbreviated
        return f.string(from: s) ?? ""
    }

    @ViewBuilder
    private func usageSection(_ title: LocalizedStringKey, _ j: JSON) -> some View {
        let total = j["total"].double ?? (j["size"].double ?? 0)
        let free = j["free"].double ?? 0
        let used = total > 0 ? total - free : (j["used"].double ?? 0)
        Section(title) {
            if total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: used, total: total).tint(used / total > 0.85 ? .red : Theme.accent)
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .memory))")
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
            }
            NavigationLink("Details") { JSONInspectorView(title: "Details", json: j) }
        }
        .cardRows()
    }

    private func load() async {
        do {
            info = try await client.request("/api/manager/system/")
            error = nil
        } catch { self.error = error.localizedDescription }
        memory = (try? await client.request("/api/manager/system/memory")) ?? .null
        storage = (try? await client.request("/api/manager/system/storage")) ?? .null
        updates = (try? await client.request("/api/manager/updates/update"))?.items ?? []
        experiments = (try? await client.request("/api/manager/experiments/experiment"))?.items
            .sorted { $0["title"].localized < $1["title"].localized } ?? []
    }

    private func rename() async {
        do {
            _ = try await client.request("/api/manager/system/name", method: "PUT", json: .object(["name": .string(newName)]))
            feedback = L("Naam gewijzigd"); await load()
        } catch { feedback = error.localizedDescription }
    }

    private func reboot() async {
        do { _ = try await client.request("/api/manager/system/reboot", method: "POST"); feedback = L("Homey wordt herstart") }
        catch { feedback = error.localizedDescription }
    }

    private func toggleExperiment(_ e: JSON, _ on: Bool) async {
        let id = e.firstString("id")
        do {
            _ = try await client.request("/api/manager/experiments/experiment/\(id)/\(on ? "enable" : "disable")", method: "PUT")
            await load()
        } catch { feedback = error.localizedDescription }
    }
}
