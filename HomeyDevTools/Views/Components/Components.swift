import SwiftUI

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static let homeyRainbow = AngularGradient(
        colors: [.yellow, .green, .cyan, .blue, .purple, .pink, .red, .orange, .yellow],
        center: .center
    )
}

enum Fmt {
    static func number(_ n: Int) -> String { n.formatted(.number) }
    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }
    static func rating(_ r: Double?) -> String { r.map { String(format: "%.1f", $0) } ?? "—" }
    static func relative(_ d: Date?) -> String {
        guard let d else { return "—" }
        return d.formatted(.relative(presentation: .named))
    }
    static func date(_ d: Date?) -> String { d?.formatted(date: .abbreviated, time: .shortened) ?? "—" }
}

struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String = "number"
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct AppIconView: View {
    let url: URL?
    var brand: String = ""
    var size: CGFloat = 44

    var body: some View {
        let bg = Color(hex: brand) ?? Color.accentColor.opacity(0.15)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(bg)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Image(systemName: "app.dashed").foregroundStyle(.white.opacity(0.8))
                    }
                }
            } else {
                Image(systemName: "app.dashed").foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct StateBadge: View {
    let state: String

    var body: some View {
        if !state.isEmpty {
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
        }
    }

    private var label: String {
        switch state {
        case "in_review": return "In review"
        case "live": return "Live"
        case "test": return "Test"
        case "draft": return "Draft"
        case "processing": return "Verwerken"
        case "approved": return "Goedgekeurd"
        case "rejected": return "Afgewezen"
        case "canceled", "cancelled": return "Geannuleerd"
        default: return state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var color: Color {
        switch state {
        case "live", "approved": return .green
        case "test": return .blue
        case "in_review", "processing": return .orange
        case "rejected", "failed": return .red
        default: return .secondary
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            if let retry { Button("Opnieuw", action: retry).font(.footnote.weight(.semibold)) }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Generic loader: runs `load`, shows progress / error / content, supports pull-to-refresh.
struct Loader<T, Content: View>: View {
    let load: () async throws -> T
    @ViewBuilder let content: (T, @escaping () async -> Void) -> Content

    @State private var value: T?
    @State private var error: String?

    var body: some View {
        Group {
            if let value {
                content(value, reload)
            } else if let error {
                ContentUnavailableView {
                    Label("Laden mislukt", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("Opnieuw proberen") { Task { await reload() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if value == nil { await reload() } }
    }

    private func reload() async {
        do { value = try await load(); error = nil } catch {
            if value == nil { self.error = error.localizedDescription }
        }
    }
}

/// Toast-like feedback for actions.
struct ActionFeedback: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.spring, value: message)
    }
}

extension View {
    func actionFeedback(_ message: Binding<String?>) -> some View { modifier(ActionFeedback(message: message)) }
}
