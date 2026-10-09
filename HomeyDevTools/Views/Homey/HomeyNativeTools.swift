import SwiftUI
import Charts
import AVKit

/// Native versions of the Developer Tools "Tools" & "Wireless" pages,
/// using the same Homey Web API manager calls.
enum HomeyTool: String, CaseIterable, Identifiable {
    case system, devices, insights, zigbee, zwave, ble, rf, ir, images, videos, playground, pairing
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .devices: "Devices"
        case .insights: "Insights"
        case .zigbee: "Zigbee"
        case .zwave: "Z-Wave"
        case .ble: "Bluetooth LE"
        case .rf: "RF (433/868 MHz)"
        case .ir: "Infrared"
        case .images: "Images"
        case .videos: "Videos"
        case .playground: "Web API Playground"
        case .pairing: "Pairing"
        }
    }

    var icon: String {
        switch self {
        case .system: "cpu"
        case .devices: "lightbulb.2"
        case .insights: "chart.xyaxis.line"
        case .zigbee: "point.3.filled.connected.trianglepath.dotted"
        case .zwave: "point.3.connected.trianglepath.dotted"
        case .ble: "dot.radiowaves.left.and.right"
        case .rf: "antenna.radiowaves.left.and.right"
        case .ir: "light.beacon.max"
        case .images: "photo.on.rectangle"
        case .videos: "video"
        case .playground: "terminal"
        case .pairing: "plus.circle"
        }
    }

    /// Pairing needs the driver's interactive web views, so it stays on the website.
    var isWeb: Bool { self == .pairing }

    @MainActor @ViewBuilder
    func destination(_ client: HomeyClient) -> some View {
        switch self {
        case .system: SystemToolView(client: client)
        case .devices: DevicesView(client: client)
        case .insights: InsightsToolView(client: client)
        case .zigbee: ZigbeeToolView(client: client)
        case .zwave: ZwaveToolView(client: client)
        case .ble: BLEToolView(client: client)
        case .rf: RFToolView(client: client)
        case .ir: IRToolView(client: client)
        case .images: ImagesToolView(client: client)
        case .videos: VideosToolView(client: client)
        case .playground: APIPlaygroundView(target: .homey(client))
        case .pairing: WebToolsView(start: Config.devTools("/tools/pair"))
        }
    }
}

// MARK: - Small building blocks

struct ToolHeader: View {
    let client: HomeyClient
    var body: some View {
        HStack(spacing: 8) {
            HomeyLogo(size: 18)
            Text(client.homey.name).font(.footnote.weight(.semibold))
            Text(client.homey.subtitle).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
    }
}

/// Loads a JSON state from the Homey with pull-to-refresh and error banner.
@MainActor
@Observable
final class ToolState {
    var json: JSON = .null
    var loading = false
    var error: String?
    var message: String?

    func load(_ op: () async throws -> JSON) async {
        loading = true; defer { loading = false }
        do { json = try await op(); error = nil } catch { self.error = error.localizedDescription }
    }

    func run(_ success: String, _ op: () async throws -> Void) async {
        do { try await op(); message = success; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private func hex(_ n: Int, width: Int = 4) -> String { "0x" + String(n, radix: 16, uppercase: true).leftPad(width) }
private extension String {
    func leftPad(_ n: Int) -> String { count >= n ? self : String(repeating: "0", count: n - count) + self }
}

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

// MARK: - Insights

struct InsightsToolView: View {
    let client: HomeyClient
    @State private var logs: [JSON] = []
    @State private var search = ""
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } }.listRowBackground(Color.clear) }
            ForEach(groups) { group in
                Section(group.id) {
                    ForEach(Array(group.logs.enumerated()), id: \.offset) { _, log in
                        NavigationLink { InsightsLogView(client: client, log: log) } label: {
                            HStack {
                                Image(systemName: log.firstString("type") == "boolean" ? "switch.2" : "chart.xyaxis.line")
                                    .foregroundStyle(Theme.accent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(titleOrID(log))
                                    Text(log.firstString("id")).font(.caption2.monospaced()).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if !log["lastValue"].isNull {
                                    Text("\(log["lastValue"].displayString) \(log["units"].localized)").font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
                .cardRows()
            }
        }
        .themedList()
        .overlay { if loading && logs.isEmpty { ProgressView() } }
        .searchable(text: $search, prompt: "Zoek log")
        .navigationTitle("Insights")
        .refreshable { await load() }
        .task { await load() }
    }

    struct LogGroup: Identifiable { let id: String; let logs: [JSON] }

    private var groups: [LogGroup] {
        let q = search.lowercased()
        let filtered = q.isEmpty ? logs : logs.filter { ($0["title"].localized + $0.firstString("id", "ownerName")).lowercased().contains(q) }
        let dict = Dictionary(grouping: filtered) { $0.firstString("ownerName", "uriObj").isEmpty ? $0.firstString("uri", "ownerUri") : $0.firstString("ownerName") }
        return dict.keys.sorted().map { LogGroup(id: $0, logs: dict[$0] ?? []) }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { logs = try await client.request("/api/manager/insights/log").items; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct InsightsLogView: View {
    let client: HomeyClient
    let log: JSON
    @State private var resolution = "last24Hours"
    struct Point: Identifiable { let id: Date; let value: Double }
    @State private var points: [Point] = []
    @State private var error: String?

    private var minValue: Double { points.map { $0.value }.min() ?? 0 }
    private var maxValue: Double { points.map { $0.value }.max() ?? 0 }
    private func lastValueText(_ v: Double) -> String {
        let units: String = log["units"].localized
        return units.isEmpty ? twoDecimals(v) : twoDecimals(v) + " " + units
    }

    private let resolutions = ["lastHour", "last24Hours", "last7Days", "last31Days", "last1Year"]
    private func label(_ r: String) -> LocalizedStringKey {
        switch r { case "lastHour": "1u"; case "last24Hours": "24u"; case "last7Days": "7d"; case "last31Days": "31d"; default: "1j" }
    }

    var body: some View {
        List {
            Section {
                Picker("Periode", selection: $resolution) {
                    ForEach(resolutions, id: \.self) { Text(label($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                if points.count > 1 {
                    Chart(points) { p in
                        if log.firstString("type") == "boolean" {
                            LineMark(x: .value("Tijd", p.id), y: .value("Waarde", p.value)).interpolationMethod(.stepEnd)
                        } else {
                            AreaMark(x: .value("Tijd", p.id), y: .value("Waarde", p.value))
                                .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("Tijd", p.id), y: .value("Waarde", p.value)).interpolationMethod(.monotone)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                } else if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                } else {
                    Text("Geen waarden in deze periode.").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if let last = points.last {
                    LabeledContent("Laatste waarde", value: lastValueText(last.value))
                    LabeledContent("Minimum", value: twoDecimals(minValue))
                    LabeledContent("Maximum", value: twoDecimals(maxValue))
                }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(titleOrID(log))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: resolution) { await load() }
    }

    private func load() async {
        let uri = log.firstString("uri", "ownerUri")
        let id = log.firstString("id")
        let path = "/api/manager/insights/log/\(uri.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uri)/\(id)/entry?resolution=\(resolution)"
        do {
            let j = try await client.request(path)
            let values = j["values"].isNull ? j.array : j["values"].array
            points = values.compactMap { v in
                guard let t = v["t"].date ?? v["date"].date, let val = v["v"].double ?? v["value"].double else { return nil }
                return Point(id: t, value: val)
            }
            error = nil
        } catch { self.error = error.localizedDescription; points = [] }
    }
}

// MARK: - Zigbee

struct ZigbeeToolView: View {
    let client: HomeyClient
    @State private var state = ToolState()
    @State private var busy = false

    var body: some View {
        let zInner: JSON = state.json["zigbee_state"]
        let z: JSON = zInner.isNull ? state.json : zInner
        let netInner: JSON = z["net"]
        let net: JSON = netInner.isNull ? state.json["controllerState"] : netInner
        let deviceArray: [JSON] = z["devices"].array
        let devices: [JSON] = deviceArray.isEmpty ? z["nodes"].items : deviceArray
        List {
            Section { ToolHeader(client: client) }.listRowBackground(Color.clear)
            if let e = state.error { ErrorBanner(message: e) { Task { await load() } }.listRowBackground(Color.clear) }
            if let m = state.message { Label(m, systemImage: "checkmark.circle").foregroundStyle(.green).listRowBackground(Color.clear) }

            Section("Netwerk") {
                LabeledContent("Kanaal", value: net["channel"].displayString)
                LabeledContent("PAN ID", value: net["panId"].displayString)
                LabeledContent("Extended PAN ID", value: net.firstString("extPanId", "extendedPanId"))
                LabeledContent("IEEE-adres", value: net.firstString("ieeeAddr", "IEEEAddress"))
                if !z.firstString("currentCommand").isEmpty { LabeledContent("Huidige opdracht", value: z.firstString("currentCommand")) }
                Button {
                    Task { busy = true; await state.run(L("Nodes bijgewerkt")) { _ = try await client.runCommand("zigbee", "UPDATE_NODES", opts: .object(["withLqi": .bool(true)])) }; await load(); busy = false }
                } label: { HStack { Label("Nodes bijwerken (met LQI)", systemImage: "arrow.triangle.2.circlepath"); if busy { Spacer(); ProgressView() } } }
                .disabled(busy)
            }
            .cardRows()

            Section("Apparaten (\(devices.count))") {
                ForEach(Array(devices.enumerated()), id: \.offset) { _, d in
                    NavigationLink { JSONInspectorView(title: d.firstString("name", "modelId", "ieeeAddr"), json: d) } label: {
                        HStack {
                            Image(systemName: icon(d.firstString("type"))).foregroundStyle(Theme.accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.firstString("name", "modelId", "ieeeAddr")).lineLimit(1)
                                Text(detailLine(d.firstString("manufacturerName"), d.firstString("type"), d.firstString("ieeeAddr")))
                                    .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            if let lqi = d["lqi"].int { LQIBadge(lqi: lqi) }
                        }
                    }
                }
            }
            .cardRows()

            Section { NavigationLink("Ruwe data") { JSONInspectorView(title: "Zigbee", json: state.json) } }.cardRows()
        }
        .themedList()
        .overlay { if state.loading && state.json.isNull { ProgressView() } }
        .navigationTitle("Zigbee")
        .refreshable { await load() }
        .task { await load() }
    }

    private func icon(_ type: String) -> String {
        switch type.lowercased() {
        case "coordinator": "dot.radiowaves.up.forward"
        case "router": "wifi.router"
        default: "sensor"
        }
    }

    private func load() async { await state.load { try await client.request("/api/manager/zigbee/state") } }
}

struct LQIBadge: View {
    let lqi: Int
    var body: some View {
        let c: Color = lqi > 150 ? .green : lqi > 80 ? .orange : .red
        Text("LQI \(lqi)").font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(c.opacity(0.15), in: Capsule()).foregroundStyle(c)
    }
}

// MARK: - Z-Wave

struct ZNode: Identifiable { let id: Int; let json: JSON }

struct ZwaveToolView: View {
    let client: HomeyClient
    @State private var state = ToolState()
    @State private var failed: Set<Int> = []
    @State private var working: Set<Int> = []
    @State private var removeNode: Int?

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

    private var stats: [(key: String, value: String)] {
        let json: JSON = zw["stats"]
        return json.object.keys.sorted().map { key in (key: key, value: json[key].displayString) }
    }

    var body: some View {
        let zw: JSON = self.zw
        let nodes: [ZNode] = self.nodes
        List {
            Section { ToolHeader(client: client) }.listRowBackground(Color.clear)
            if let e = state.error { ErrorBanner(message: e) { Task { await load() } }.listRowBackground(Color.clear) }
            if let m = state.message { Label(m, systemImage: "checkmark.circle").foregroundStyle(.green).listRowBackground(Color.clear) }

            Section("Controller") {
                LabeledContent("Home ID", value: homeIdText)
                LabeledContent("Node ID", value: zw["nodeId"].displayString)
                LabeledContent("Regio", value: zw.firstString("softwareRegion", "hardwareRegion"))
                if !zw.firstString("currentCommand").isEmpty { LabeledContent("Huidige opdracht", value: zw.firstString("currentCommand")) }
                Button { Task { await checkFailed() } } label: { Label("Defecte nodes zoeken", systemImage: "stethoscope") }
                Button { Task { await state.run(L("Node Information Frame verstuurd")) { _ = try await client.runCommand("zwave", "sendNodeInformationFrame") } } } label: {
                    Label("Node Information Frame versturen", systemImage: "antenna.radiowaves.left.and.right")
                }
                Button(role: .destructive) {
                    Task { await state.run(L("Onbekende nodes verwijderd")) { _ = try await client.runCommand("zwave", "removeUnknownNodes") }; await load() }
                } label: { Label("Onbekende nodes verwijderen", systemImage: "trash") }
            }
            .cardRows()

            if !stats.isEmpty {
                Section("Statistieken") {
                    ForEach(stats, id: \.key) { item in
                        MonoValueRow(label: item.key, value: item.value)
                    }
                }
                .cardRows()
            }

            Section("Nodes (\(nodes.count))") {
                ForEach(nodes) { node in
                    let id = node.id
                    let n = node.json
                    ZWaveNodeRow(id: id, node: n, isFailed: failed.contains(id), isWorking: working.contains(id))
                    .contextMenu {
                        Button { Task { await nodeCommand(id, "sendTestFrame", L("Test-frame verstuurd"), 15) } } label: { Label("Test-frame versturen", systemImage: "waveform") }
                        Button { Task { await nodeCommand(id, "heal", L("Heal voltooid"), 300) } } label: { Label("Heal (routes herstellen)", systemImage: "bandage") }
                        Button { Task { await nodeCommand(id, "interviewNodeOnRequest", L("Interview aangevraagd"), 60) } } label: { Label("Interview opnieuw", systemImage: "questionmark.bubble") }
                        Button(role: .destructive) { removeNode = id } label: { Label("Defecte node verwijderen", systemImage: "trash") }
                        NavigationLink { JSONInspectorView(title: L("Node \(id)"), json: n) } label: { Label("Ruwe data", systemImage: "curlybraces") }
                    }
                }
            } footer: {
                Text("Houd een node ingedrukt voor test-frame, heal, interview of verwijderen.")
            }
            .cardRows()

            Section { NavigationLink("Ruwe data") { JSONInspectorView(title: "Z-Wave", json: state.json) } }.cardRows()
        }
        .themedList()
        .overlay { if state.loading && state.json.isNull { ProgressView() } }
        .navigationTitle("Z-Wave")
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog("Defecte node verwijderen?", isPresented: Binding(get: { removeNode != nil }, set: { if !$0 { removeNode = nil } }),
                            titleVisibility: .visible, presenting: removeNode) { id in
            Button(L("Node \(id) verwijderen"), role: .destructive) { Task { await nodeCommand(id, "removeFailedNode", L("Node verwijderd"), 60); await load() } }
        } message: { _ in Text("Werkt alleen voor nodes die Homey als defect heeft gemarkeerd.") }
    }

    private func load() async { await state.load { try await client.request("/api/manager/zwave/state") } }

    private func checkFailed() async {
        await state.run(L("Controle voltooid")) {
            let r = try await client.runCommand("zwave", "getFailedNodes")
            failed = Set(r.array.compactMap(\.int))
        }
    }

    private func nodeCommand(_ id: Int, _ command: String, _ success: String, _ timeout: TimeInterval) async {
        working.insert(id); defer { working.remove(id) }
        await state.run(success) { _ = try await client.runCommand("zwave", command, opts: .object(["nodeId": .number(Double(id))]), timeout: timeout) }
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

// MARK: - BLE

struct BLEToolView: View {
    let client: HomeyClient
    @State private var state = ToolState()

    var body: some View {
        let s = state.json["ble_state"].isNull ? state.json : state.json["ble_state"]
        let peripherals = s.isContainer ? s.items : []
        List {
            Section { ToolHeader(client: client) }.listRowBackground(Color.clear)
            if let e = state.error { ErrorBanner(message: e) { Task { await load() } }.listRowBackground(Color.clear) }
            Section {
                ForEach(Array(peripherals.enumerated()), id: \.offset) { _, p in
                    NavigationLink { JSONInspectorView(title: p.firstString("localName", "name", "uuid", "address"), json: p) } label: {
                        HStack {
                            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.firstString("localName", "name", "address", "uuid")).lineLimit(1)
                                Text(detailLine(p.firstString("address", "uuid"), p.firstString("state")))
                                    .font(.caption2.monospaced()).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            if let rssi = p["rssi"].int { Text("\(rssi) dBm").font(.caption2.monospacedDigit()).foregroundStyle(rssiColor(rssi)) }
                        }
                    }
                }
            } header: {
                Text("Peripherals (\(peripherals.count))")
            } footer: {
                Text("Verbindingen en gevonden apparaten van de Bluetooth LE-manager. Trek omlaag om te verversen.")
            }
            .cardRows()
        }
        .themedList()
        .overlay {
            if state.loading && state.json.isNull { ProgressView() }
            else if peripherals.isEmpty && state.error == nil { ContentUnavailableView("Geen BLE-apparaten", systemImage: "dot.radiowaves.left.and.right") }
        }
        .navigationTitle("Bluetooth LE")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        _ = try? await client.runCommand("ble", "REFRESH", timeout: 15)
        await state.load { try await client.request("/api/manager/ble/state") }
    }
}

// MARK: - RF

struct RFToolView: View {
    let client: HomeyClient
    @State private var frequency = "433"
    @State private var recording = false
    @State private var result: JSON = .null
    @State private var emulateData = ""
    @State private var feedback: String?
    @State private var progress = 0.0

    var body: some View {
        List {
            Section { ToolHeader(client: client) }.listRowBackground(Color.clear)
            Section {
                Picker("Frequentie", selection: $frequency) {
                    Text("433 MHz").tag("433")
                    Text("868 MHz").tag("868")
                }
                .pickerStyle(.segmented)
                Button { Task { await record() } } label: {
                    HStack {
                        Label(recording ? L("Opnemen…") : L("Opnemen (5 s)"), systemImage: recording ? "record.circle.fill" : "record.circle")
                            .foregroundStyle(.red)
                        if recording { Spacer(); ProgressView(value: progress).frame(width: 80) }
                    }
                }
                .disabled(recording)
                if !result.isNull {
                    Button { Task { await replay() } } label: { Label("Opname afspelen", systemImage: "play.circle") }
                    NavigationLink { JSONInspectorView(title: L("Opname"), json: result) } label: {
                        Label("Opname bekijken (\(result.items.count) signalen)", systemImage: "waveform")
                    }
                }
            } header: {
                Text("Opnemen & afspelen")
            } footer: {
                Text("Druk op de afstandsbediening terwijl Homey opneemt.")
            }
            .cardRows()

            Section {
                TextField("Pulsen in µs, gescheiden door komma's", text: $emulateData, axis: .vertical)
                    .font(.caption.monospaced())
                    .lineLimit(2...6)
                Button { Task { await emulate() } } label: { Label("Versturen", systemImage: "paperplane") }
                    .disabled(emulateData.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Emuleren")
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("RF")
        .actionFeedback($feedback)
    }

    private func record() async {
        recording = true; progress = 0; result = .null
        let timer = Task { for i in 1...50 { try? await Task.sleep(for: .milliseconds(100)); progress = Double(i) / 50 } }
        defer { recording = false; timer.cancel() }
        do {
            result = try await client.request("/api/manager/rf/record", method: "POST",
                                              json: .object(["timeout": .number(5), "frequency": .string(frequency)]), timeout: 15)
            feedback = result.items.isEmpty ? L("Geen signaal ontvangen") : L("Opname klaar")
        } catch { feedback = error.localizedDescription }
    }

    private func replay() async {
        do {
            for signal in result.items {
                _ = try await client.request("/api/manager/rf/replay", method: "POST", json: .object(["data": signal, "frequency": .string(frequency)]), timeout: 15)
            }
            feedback = L("Afgespeeld")
        } catch { feedback = error.localizedDescription }
    }

    private func emulate() async {
        let data = emulateData.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        do {
            _ = try await client.request("/api/manager/rf/\(frequency)/emulate", method: "POST",
                                         json: .object(["data": .array(data.map { .number(Double($0)) }), "frequency": .string(frequency)]))
            feedback = L("Verstuurd")
        } catch { feedback = error.localizedDescription }
    }
}

// MARK: - Infrared

struct IRToolView: View {
    let client: HomeyClient
    @State private var payload = ""
    @State private var repetitions = 1
    @State private var sending = false
    @State private var feedback: String?

    var body: some View {
        List {
            Section { ToolHeader(client: client) }.listRowBackground(Color.clear)
            Section {
                TextField("0000 006D 0022 0002 …", text: $payload, axis: .vertical)
                    .font(.caption.monospaced())
                    .lineLimit(3...10)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Stepper("Herhalingen: \(repetitions)", value: $repetitions, in: 1...20)
                Button { Task { await send() } } label: {
                    HStack { Label("Verstuur IR-code", systemImage: "light.beacon.max"); if sending { Spacer(); ProgressView() } }
                }
                .disabled(payload.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            } header: {
                Text("Pronto-hex")
            } footer: {
                Text("Plak een IR-code in Pronto-hexformaat. Homey verstuurt hem via de ingebouwde IR-zender.")
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Infrared")
        .actionFeedback($feedback)
    }

    private func send() async {
        sending = true; defer { sending = false }
        do {
            _ = try await client.request("/api/manager/rf/ir/prontohex", method: "POST",
                                         json: .object(["payload": .string(payload.trimmingCharacters(in: .whitespacesAndNewlines)), "repetitions": .number(Double(repetitions))]))
            feedback = L("Verstuurd")
        } catch { feedback = error.localizedDescription }
    }
}

// MARK: - Images

struct ImagesToolView: View {
    let client: HomeyClient
    @State private var images: [JSON] = []
    @State private var loading = true
    @State private var error: String?
    @State private var reloadToken = UUID()

    var body: some View {
        ScrollView {
            if let error { ErrorBanner(message: error) { Task { await load() } }.padding() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                    VStack(alignment: .leading, spacing: 6) {
                        HomeyImage(client: client, path: img.firstString("url", "imageUrl"), reloadToken: reloadToken)
                            .aspectRatio(4 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(titleOrID(img))
                            .font(.caption.weight(.medium)).lineLimit(1)
                        Text(img.firstString("ownerUri", "ownerName")).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    .homeyCard(padding: 8)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay {
            if loading && images.isEmpty { ProgressView() }
            else if images.isEmpty && error == nil { ContentUnavailableView("Geen afbeeldingen", systemImage: "photo") }
        }
        .navigationTitle("Images")
        .toolbar { Button { reloadToken = UUID() } label: { Image(systemName: "arrow.clockwise") } }
        .refreshable { await load(); reloadToken = UUID() }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { images = try await client.request("/api/manager/images/image").items; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

/// Image served by Homey (needs the session token, so AsyncImage can't be used).
struct HomeyImage: View {
    let client: HomeyClient
    let path: String
    var reloadToken = UUID()
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.primary.opacity(0.06)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .task(id: "\(path)\(reloadToken)") {
            guard !path.isEmpty else { failed = true; return }
            let sep = path.contains("?") ? "&" : "?"
            if let data = try? await client.data(at: "\(path)\(sep)_r=\(Int(Date().timeIntervalSince1970))"), let img = UIImage(data: data) {
                image = img; failed = false
            } else { failed = true }
        }
    }
}

// MARK: - Videos

struct VideosToolView: View {
    let client: HomeyClient
    @State private var videos: [JSON] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } }.listRowBackground(Color.clear) }
            ForEach(Array(videos.enumerated()), id: \.offset) { _, v in
                NavigationLink { VideoPlayerToolView(client: client, video: v) } label: {
                    HStack {
                        Image(systemName: "video.fill").foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titleOrID(v))
                            Text(detailLine(v.firstString("type"), v.firstString("ownerUri")))
                                .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                    }
                }
                .cardRows()
            }
        }
        .themedList()
        .overlay {
            if loading && videos.isEmpty { ProgressView() }
            else if videos.isEmpty && error == nil { ContentUnavailableView("Geen video's", systemImage: "video.slash") }
        }
        .navigationTitle("Videos")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { videos = try await client.request("/api/manager/videos/video").items; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct VideoPlayerToolView: View {
    let client: HomeyClient
    let video: JSON
    @State private var player: AVPlayer?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onAppear { player.play() }
            } else if let error {
                ContentUnavailableView {
                    Label("Kan video niet afspelen", systemImage: "video.slash")
                } description: { Text(error) }
            } else {
                ProgressView()
            }
            Spacer()
        }
        .padding()
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(titleOrID(video))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if video.firstString("type").lowercased().contains("webrtc") {
                error = L("WebRTC-camera's worden alleen in de Homey-app ondersteund."); return
            }
            do {
                let r = try await client.request("/api/manager/videos/video/\(video.firstString("id"))/video-url")
                let s = r.string ?? r.firstString("url")
                guard let url = URL(string: s, relativeTo: client.baseURL) else { throw APIError(status: 0, message: L("Geen video-URL"), url: "") }
                player = AVPlayer(url: url.absoluteURL)
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// Opens a tool for the active Homey (iPad sidebar); offers a picker when there are several.
struct NativeToolHost: View {
    let tool: HomeyTool
    @Environment(AuthManager.self) private var auth
    @AppStorage("activeHomeyId") private var activeHomeyId = ""
    @State private var client: HomeyClient?

    var body: some View {
        let homeys = auth.homeys
        Group {
            if let client {
                tool.destination(client)
                    .id(client.homey.id)
                    .toolbar {
                        if homeys.count > 1 {
                            Menu {
                                Picker("Homey", selection: $activeHomeyId) {
                                    ForEach(homeys) { Text($0.name).tag($0.id) }
                                }
                            } label: { Label(client.homey.name, systemImage: "circle.circle") }
                        }
                    }
            } else if homeys.isEmpty {
                ContentUnavailableView("Geen Homeys", systemImage: "circle.circle")
            } else {
                HomeyLogo(size: 54, spinning: true)
            }
        }
        .onAppear(perform: resolve)
        .onChange(of: activeHomeyId) { _, _ in resolve() }
        .onChange(of: auth.user) { _, _ in resolve() }
    }

    private func resolve() {
        let homeys = auth.homeys
        guard let h = homeys.first(where: { $0.id == activeHomeyId }) ?? homeys.first else { client = nil; return }
        if client?.homey.id != h.id { client = HomeyClient(homey: h, auth: auth) }
    }
}
