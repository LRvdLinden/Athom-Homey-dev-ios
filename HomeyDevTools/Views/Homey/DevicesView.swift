import SwiftUI

struct DevicesView: View {
    let client: HomeyClient
    @State private var devices: [HomeyDevice] = []
    @State private var zones: [String: HomeyZone] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var search = ""
    @State private var feedback: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            ForEach(grouped) { group in
                Section(group.id) {
                    ForEach(group.devices) { d in
                        NavigationLink {
                            DeviceDetailView(client: client, device: d, zoneName: group.id)
                        } label: {
                            DeviceRow(device: d) { on in await toggle(d, on) }
                        }
                    }
                }
            }
        }
        .overlay { if loading && devices.isEmpty { ProgressView() } }
        .searchable(text: $search, prompt: "Zoek apparaat, klasse of driver")
        .themedList()
        .navigationTitle("Apparaten (\(devices.count))")
        .refreshable { await load() }
        .task { if devices.isEmpty { await load() } }
        .actionFeedback($feedback)
    }

    struct ZoneGroup: Identifiable {
        let id: String
        let devices: [HomeyDevice]
    }

    private var grouped: [ZoneGroup] {
        let q = search.lowercased()
        let list = q.isEmpty ? devices : devices.filter {
            $0.name.lowercased().contains(q) || $0.deviceClass.contains(q) || $0.driverId.lowercased().contains(q)
        }
        let dict = Dictionary(grouping: list) { zones[$0.zoneId]?.name ?? L("Overig") }
        return dict.keys.sorted().map { ZoneGroup(id: $0, devices: dict[$0] ?? []) }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            async let z = client.zones()
            async let d = client.devices()
            let (zs, ds) = try await (z, d)
            zones = Dictionary(zs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            devices = ds
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func toggle(_ d: HomeyDevice, _ on: Bool) async {
        do {
            try await client.setCapability(device: d.id, capability: "onoff", value: .bool(on))
            feedback = on ? L("\(d.name) aan") : L("\(d.name) uit")
            if let fresh = try? await client.device(d.id), let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = fresh }
        } catch { feedback = error.localizedDescription }
    }
}

struct DeviceRow: View {
    let device: HomeyDevice
    let onToggle: (Bool) async -> Void
    @State private var isOn = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.systemImage)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(device.available ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).lineLimit(1)
                Text(summary).font(.caption).foregroundStyle(device.available ? Color.secondary : Color.red).lineLimit(1)
            }
            Spacer()
            if let onoff = device.onoff, onoff.setable {
                Button {
                    isOn.toggle()
                    let v = isOn
                    Task { await onToggle(v) }
                } label: {
                    Image(systemName: "power.circle.fill")
                        .font(.title)
                        .foregroundStyle(isOn ? Color.yellow : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isOn ? L("Zet uit") : L("Zet aan"))
            }
        }
        .onAppear { isOn = device.onoff?.value.bool ?? false }
        .onChange(of: device) { _, d in isOn = d.onoff?.value.bool ?? false }
    }

    private var summary: String {
        if !device.available { return device.unavailableMessage.isEmpty ? L("Niet beschikbaar") : device.unavailableMessage }
        let caps = device.capabilities.filter { $0.id != "onoff" && !$0.value.isNull }.prefix(2).map(\.formattedValue)
        return caps.isEmpty ? device.deviceClass : caps.joined(separator: " · ")
    }
}

struct DeviceDetailView: View {
    let client: HomeyClient
    @State var device: HomeyDevice
    let zoneName: String
    @State private var feedback: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Zone", value: zoneName)
                LabeledContent("Klasse", value: device.deviceClass)
                LabeledContent("Driver", value: device.driverId).font(.caption)
                LabeledContent("Beschikbaar", value: device.available ? L("Ja") : L("Nee"))
                LabeledContent("ID", value: device.id).font(.caption).textSelection(.enabled)
            }
            Section("Capabilities (\(device.capabilities.count))") {
                ForEach(device.capabilities) { cap in
                    CapabilityRow(cap: cap, raw: device.raw["capabilitiesObj"][cap.id]) { value in
                        await set(cap, value)
                    }
                }
            }
            Section {
                NavigationLink("Settings") { JSONInspectorView(title: "Settings", json: device.raw["settings"]) }
                NavigationLink("Ruwe API-data") { JSONInspectorView(title: device.name, json: device.raw) }
            }
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .actionFeedback($feedback)
    }

    private func set(_ cap: HomeyCapability, _ value: JSON) async {
        do {
            try await client.setCapability(device: device.id, capability: cap.id, value: value)
            feedback = L("\(cap.title) bijgewerkt")
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        } catch { feedback = error.localizedDescription }
    }

    private func refresh() async {
        if let fresh = try? await client.device(device.id) { device = fresh }
    }
}

struct CapabilityRow: View {
    let cap: HomeyCapability
    let raw: JSON
    let onSet: (JSON) async -> Void
    @State private var bool = false
    @State private var number: Double = 0
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cap.title)
                    Text(cap.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                control
            }
            if cap.setable, cap.type == "number", let min = cap.min, let max = cap.max, max > min {
                Slider(value: $number, in: min...max, step: cap.step ?? ((max - min) <= 1 ? 0.01 : 1)) { e in
                    editing = e
                    if !e { Task { await onSet(.number(number)) } }
                }
            }
            if let updated = cap.lastUpdated {
                Text("Bijgewerkt \(Fmt.relative(updated))").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .onAppear(perform: sync)
        .onChange(of: cap) { _, _ in if !editing { sync() } }
    }

    @ViewBuilder private var control: some View {
        if cap.type == "boolean" && cap.setable {
            Toggle("", isOn: Binding(get: { bool }, set: { v in bool = v; Task { await onSet(.bool(v)) } })).labelsHidden()
        } else if cap.type == "enum" && cap.setable, !raw["values"].array.isEmpty {
            Menu(cap.formattedValue) {
                ForEach(raw["values"].array, id: \.self) { v in
                    Button(v["title"].localized.isEmpty ? (v["id"].string ?? "") : v["title"].localized) {
                        Task { await onSet(v["id"]) }
                    }
                }
            }
        } else if cap.setable && cap.type == "number" {
            Text(editing ? String(format: "%.2f", number) : cap.formattedValue).monospacedDigit().foregroundStyle(.secondary)
        } else {
            Text(cap.formattedValue).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func sync() {
        bool = cap.value.bool ?? false
        number = cap.value.double ?? cap.min ?? 0
    }
}
