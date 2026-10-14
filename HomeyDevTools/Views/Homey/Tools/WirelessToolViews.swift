import SwiftUI

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
