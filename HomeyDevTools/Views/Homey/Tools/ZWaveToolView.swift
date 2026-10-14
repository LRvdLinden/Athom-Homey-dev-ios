import SwiftUI

// MARK: - Z-Wave

struct ZNode: Identifiable { let id: Int; let json: JSON }

struct ZWaveStat: Identifiable {
    let id: String
    let value: String
}

struct ZwaveToolView: View {
    let client: HomeyClient
    @State private var state = ToolState()
    @State private var failed: Set<Int> = []
    @State private var working: Set<Int> = []
    @State private var removeNode: Int?

    // MARK: Data

    private var zw: JSON {
        let inner: JSON = state.json["zw_state"]
        return inner.isNull ? state.json : inner
    }

    private var nodes: [ZNode] {
        var out: [ZNode] = []
        for (key, value) in zw["nodes"].object {
            let fallback: Int? = value["nodeId"].int
            if let id = Int(key) ?? fallback { out.append(ZNode(id: id, json: value)) }
        }
        return out.sorted { $0.id < $1.id }
    }

    private var homeIdText: String {
        let raw: JSON = zw["homeId"]
        if let v = raw.int { return hex(v, width: 8) }
        return raw.displayString
    }

    private var nodeIdText: String { zw["nodeId"].displayString }
    private var regionText: String { zw.firstString("softwareRegion", "hardwareRegion") }
    private var currentCommand: String { zw.firstString("currentCommand") }

    private var stats: [ZWaveStat] {
        let json: JSON = zw["stats"]
        var out: [ZWaveStat] = []
        for key in json.object.keys.sorted() {
            out.append(ZWaveStat(id: key, value: json[key].displayString))
        }
        return out
    }

    private var removeBinding: Binding<Bool> {
        Binding(get: { removeNode != nil }, set: { if !$0 { removeNode = nil } })
    }

    // MARK: Body

    var body: some View {
        List {
            headerSection
            controllerSection
            statsSection
            nodesSection
            rawSection
        }
        .themedList()
        .overlay { loadingOverlay }
        .navigationTitle("Z-Wave")
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog("Defecte node verwijderen?", isPresented: removeBinding, titleVisibility: .visible, presenting: removeNode) { (id: Int) in
            Button(L("Node \(id) verwijderen"), role: .destructive) {
                Task { await removeFailed(id) }
            }
        } message: { (_: Int) in
            Text("Werkt alleen voor nodes die Homey als defect heeft gemarkeerd.")
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if state.loading && state.json.isNull { ProgressView() }
    }

    @ViewBuilder
    private var headerSection: some View {
        Section { ToolHeader(client: client) }
            .listRowBackground(Color.clear)
        if let e = state.error {
            ErrorBanner(message: e) { Task { await load() } }
                .listRowBackground(Color.clear)
        }
        if let m = state.message {
            Label(m, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .listRowBackground(Color.clear)
        }
    }

    private var controllerSection: some View {
        Section("Controller") {
            LabeledContent("Home ID", value: homeIdText)
            LabeledContent("Node ID", value: nodeIdText)
            LabeledContent("Regio", value: regionText)
            if !currentCommand.isEmpty {
                LabeledContent("Huidige opdracht", value: currentCommand)
            }
            Button { Task { await checkFailed() } } label: {
                Label("Defecte nodes zoeken", systemImage: "stethoscope")
            }
            Button { Task { await sendNIF() } } label: {
                Label("Node Information Frame versturen", systemImage: "antenna.radiowaves.left.and.right")
            }
            Button(role: .destructive) { Task { await removeUnknown() } } label: {
                Label("Onbekende nodes verwijderen", systemImage: "trash")
            }
        }
        .cardRows()
    }

    @ViewBuilder
    private var statsSection: some View {
        let items: [ZWaveStat] = stats
        if !items.isEmpty {
            Section("Statistieken") {
                ForEach(items) { (item: ZWaveStat) in
                    MonoValueRow(label: item.id, value: item.value)
                }
            }
            .cardRows()
        }
    }

    private var nodesSection: some View {
        let list: [ZNode] = nodes
        return Section {
            ForEach(list) { (node: ZNode) in
                nodeRow(node)
            }
        } header: {
            Text("Nodes (\(list.count))")
        } footer: {
            Text("Houd een node ingedrukt voor test-frame, heal, interview of verwijderen.")
        }
        .cardRows()
    }

    private func nodeRow(_ node: ZNode) -> some View {
        let id: Int = node.id
        return ZWaveNodeRow(id: id, node: node.json, isFailed: failed.contains(id), isWorking: working.contains(id))
            .contextMenu { nodeMenu(node) }
    }

    @ViewBuilder
    private func nodeMenu(_ node: ZNode) -> some View {
        let id: Int = node.id
        Button { Task { await nodeCommand(id, "sendTestFrame", L("Test-frame verstuurd"), 15) } } label: {
            Label("Test-frame versturen", systemImage: "waveform")
        }
        Button { Task { await nodeCommand(id, "heal", L("Heal voltooid"), 300) } } label: {
            Label("Heal (routes herstellen)", systemImage: "bandage")
        }
        Button { Task { await nodeCommand(id, "interviewNodeOnRequest", L("Interview aangevraagd"), 60) } } label: {
            Label("Interview opnieuw", systemImage: "questionmark.bubble")
        }
        Button(role: .destructive) { removeNode = id } label: {
            Label("Defecte node verwijderen", systemImage: "trash")
        }
        NavigationLink { JSONInspectorView(title: L("Node \(id)"), json: node.json) } label: {
            Label("Ruwe data", systemImage: "curlybraces")
        }
    }

    private var rawSection: some View {
        Section {
            NavigationLink("Ruwe data") { JSONInspectorView(title: "Z-Wave", json: state.json) }
        }
        .cardRows()
    }

    // MARK: Actions

    private func load() async { await state.load { try await client.request("/api/manager/zwave/state") } }

    private func checkFailed() async {
        await state.run(L("Controle voltooid")) {
            let r = try await client.runCommand("zwave", "getFailedNodes")
            failed = Set(r.array.compactMap(\.int))
        }
    }

    private func sendNIF() async {
        await state.run(L("Node Information Frame verstuurd")) {
            _ = try await client.runCommand("zwave", "sendNodeInformationFrame")
        }
    }

    private func removeUnknown() async {
        await state.run(L("Onbekende nodes verwijderd")) {
            _ = try await client.runCommand("zwave", "removeUnknownNodes")
        }
        await load()
    }

    private func removeFailed(_ id: Int) async {
        await nodeCommand(id, "removeFailedNode", L("Node verwijderd"), 60)
        await load()
    }

    private func nodeCommand(_ id: Int, _ command: String, _ success: String, _ timeout: TimeInterval) async {
        working.insert(id); defer { working.remove(id) }
        let opts: JSON = .object(["nodeId": .number(Double(id))])
        await state.run(success) { _ = try await client.runCommand("zwave", command, opts: opts, timeout: timeout) }
    }
}

/// One Z-Wave node in the list. Kept as its own view so the type checker stays fast.
struct ZWaveNodeRow: View {
    let id: Int
    let node: JSON
    let isFailed: Bool
    let isWorking: Bool

    private var title: String {
        let name = node.firstString("name", "deviceName", "product", "productName")
        return name.isEmpty ? L("Node \(id)") : name
    }

    private var subtitle: String {
        let defect: String = isFailed ? L("defect") : ""
        return detailLine(node.firstString("manufacturer", "manufacturerName"), node.firstString("state", "status"), defect)
    }

    private var badgeColor: Color { isFailed ? Color.red : Theme.accent }
    private var subtitleColor: Color { isFailed ? Color.red : Theme.textSecondary }

    var body: some View {
        HStack {
            Text(String(id))
                .font(Font.caption.monospacedDigit().weight(.bold))
                .frame(width: 30, height: 30)
                .background(badgeColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
            Spacer()
            if isWorking { ProgressView() }
        }
    }
}

/// Label + monospaced value, as its own view so the type checker stays fast.
struct MonoValueRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
        } label: {
            Text(label)
        }
        .font(Font.caption.monospaced())
    }
}

func twoDecimals(_ v: Double) -> String { String(format: "%.2f", v) }

/// Joins the non-empty parts with " · ".
func detailLine(_ parts: String...) -> String {
    parts.filter { !$0.isEmpty }.joined(separator: " · ")
}

func rssiColor(_ rssi: Int) -> Color {
    if rssi > -70 { return .green }
    if rssi > -85 { return .orange }
    return .red
}
