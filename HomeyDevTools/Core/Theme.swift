import SwiftUI
import UIKit

/// Visual language taken from tools.developer.homey.app (dark #121319 surface,
/// #222329 cards with 10pt radius, #0082FA accent) and homey.app (blue→cyan pill
/// buttons, rainbow ring). Every colour has a light and a dark variant.
enum Theme {
    static let accent = Color(light: 0x0082FA, dark: 0x1A8CFF)
    static let background = Color(light: 0xF2F3F7, dark: 0x121319)
    static let card = Color(light: 0xFFFFFF, dark: 0x222329)
    static let cardRaised = Color(light: 0xF7F8FA, dark: 0x2A2B32)
    static let separator = Color(light: 0xE3E5EA, dark: 0x30313A)
    static let textSecondary = Color(light: 0x6B6E78, dark: 0x9A9CA6)
    static let sidebar = Color(light: 0xFFFFFF, dark: 0x1A1B21)

    static let buttonGradient = LinearGradient(
        colors: [Color(hex: "#2F6BFF")!, Color(hex: "#21C8F0")!],
        startPoint: .leading, endPoint: .trailing
    )

    /// The colourful waves behind the Developer Tools home page.
    static let waveColors: [Color] = [Color(hex: "#C1121F")!, Color(hex: "#F0541E")!, Color(hex: "#F7A41D")!, Color(hex: "#FFD84A")!]
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}

/// System / Light / Dark — chosen under Account, default follows the device.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self { case .system: "Automatisch (toestel)"; case .light: "Licht"; case .dark: "Donker" }
    }
    var icon: String {
        switch self { case .system: "circle.lefthalf.filled"; case .light: "sun.max"; case .dark: "moon" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

struct HomeyCard: ViewModifier {
    var padding: CGFloat = 16
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: scheme == .dark ? 14 : 8, y: 4)
    }
}

struct GradientPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(Theme.buttonGradient, in: Capsule())
            .shadow(color: Color(hex: "#21C8F0")!.opacity(0.35), radius: 12, y: 6)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct OutlinePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func homeyCard(padding: CGFloat = 16) -> some View { modifier(HomeyCard(padding: padding)) }

    /// Lists/Forms on the Developer Tools background with card-coloured rows.
    func themedList() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }

    /// Card-coloured row background for List sections.
    func cardRows() -> some View { listRowBackground(Theme.card) }
}

/// Rainbow ring like the Homey logo.
struct HomeyRing: View {
    var lineWidth: CGFloat = 6
    var body: some View {
        Circle().strokeBorder(
            AngularGradient(colors: [.yellow, .green, .cyan, .blue, .purple, .pink, .red, .orange, .yellow], center: .center),
            lineWidth: lineWidth
        )
    }
}

/// The colourful wave backdrop from the Developer Tools home page, drawn natively.
struct WaveBackdrop: View {
    var height: CGFloat = 320

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .top) {
                Theme.background
                ForEach(Array(Theme.waveColors.enumerated()), id: \.offset) { i, color in
                    WaveShape(phase: CGFloat(i) * 0.18, depth: height * (0.55 + CGFloat(i) * 0.12))
                        .fill(color.opacity(0.95 - Double(i) * 0.12))
                        .frame(width: w, height: height * (1.1 - CGFloat(i) * 0.12))
                        .blendMode(.normal)
                }
                LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
                    .frame(height: height)
                    .offset(y: height * 0.15)
            }
        }
        .ignoresSafeArea()
    }
}

struct WaveShape: Shape {
    var phase: CGFloat
    var depth: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: depth * 0.55))
        p.addCurve(
            to: CGPoint(x: 0, y: depth * (0.9 + phase * 0.3)),
            control1: CGPoint(x: rect.width * (0.7 - phase), y: depth * 1.25),
            control2: CGPoint(x: rect.width * (0.35 - phase * 0.5), y: depth * (0.25 + phase))
        )
        p.closeSubpath()
        return p
    }
}

/// The official Homey logo (asset "HomeyLogo"), optionally spinning.
struct HomeyLogo: View {
    var size: CGFloat = 40
    var spinning = false
    @State private var angle: Double = 0

    var body: some View {
        Image("HomeyLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard spinning else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { angle = 360 }
            }
            .accessibilityLabel("Homey")
    }
}

/// Animated splash that continues seamlessly from the static launch screen
/// (same background colour and logo position), with the logo spinning.
struct SplashView: View {
    @State private var showTitle = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            HomeyLogo(size: 110, spinning: true)
            VStack(spacing: 6) {
                Text("Developer Tools").font(.system(size: 24, weight: .bold))
                Text("for Homey").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            .offset(y: 110)
            .opacity(showTitle ? 1 : 0)
            .offset(y: showTitle ? 0 : 8)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5).delay(0.15)) { showTitle = true } }
    }
}
