import SwiftUI

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
