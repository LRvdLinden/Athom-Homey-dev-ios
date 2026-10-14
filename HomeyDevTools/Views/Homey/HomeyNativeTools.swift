import SwiftUI

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
            HomeyModelImage(homey: client.homey, size: 24)
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
        if client?.homey.id != h.id { client = HomeyClients.client(for: h, auth: auth) }
    }
}
