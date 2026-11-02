import SwiftUI

/// LRvdLinden house style (from lrvdlinden.app): accent blue, ink, surface, line
/// and muted text, each with its dark-mode value.
enum Brand {
    static let url = URL(string: "https://lrvdlinden.app")!
    static let accent = Color(light: 0x2747E8, dark: 0x8A9DFF)
    static let accentSoft = Color(light: 0xE6EBFF, dark: 0x1D2547)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0D1018)
    static let ink = Color(light: 0x121726, dark: 0xE9ECF4)
    static let muted = Color(light: 0x5D6578, dark: 0x98A0B3)
    static let surface = Color(light: 0xFFFFFF, dark: 0x161B27)
    static let line = Color(light: 0xDDE2EC, dark: 0x262D3D)
    /// The logo tile is always the dark ink, with the blue dot.
    static let logoTile = Color(red: 0x12 / 255, green: 0x17 / 255, blue: 0x26 / 255)
    static let logoDot = Color(red: 0x4C / 255, green: 0x6B / 255, blue: 0xFF / 255)
}

/// The "LR" mark from lrvdlinden.app, drawn natively (512 × 512 design grid).
struct LRLogo: View {
    var size: CGFloat = 60

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 512
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: 116 * s, style: .continuous),
                     with: .color(Brand.logoTile))

            var letters = Path()
            // L
            letters.move(to: p(132, 146)); letters.addLine(to: p(132, 370)); letters.addLine(to: p(232, 370))
            // R: stem + bowl
            letters.move(to: p(292, 370)); letters.addLine(to: p(292, 146)); letters.addLine(to: p(340, 146))
            letters.addArc(center: p(340, 208), radius: 62 * s, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            letters.addLine(to: p(292, 270))
            // R: leg
            letters.move(to: p(338, 270)); letters.addLine(to: p(390, 370))
            ctx.stroke(letters, with: .color(.white),
                       style: StrokeStyle(lineWidth: 46 * s, lineCap: .round, lineJoin: .round))

            let dot = Path(ellipseIn: CGRect(x: (404 - 34) * s, y: (126 - 34) * s, width: 68 * s, height: 68 * s))
            ctx.fill(dot, with: .color(Brand.logoDot))
            ctx.stroke(dot, with: .color(Brand.logoTile), lineWidth: 14 * s)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "More apps from the developer" card for the bottom of the Account page, in the
/// LRvdLinden house style. Opens lrvdlinden.app. Texts come from Localizable.xcstrings
/// (Dutch, English, German, French), so they follow the app's language.
struct MoreAppsCard: View {
    @ScaledMetric(relativeTo: .body) private var logoSize: CGFloat = 60

    var body: some View {
        Link(destination: Brand.url) {
            HStack(spacing: 14) {
                LRLogo(size: logoSize)
                    .overlay(RoundedRectangle(cornerRadius: logoSize * 116 / 512, style: .continuous)
                        .strokeBorder(Brand.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Meer apps van de ontwikkelaar")
                        .font(.headline)
                        .foregroundStyle(Brand.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Apps voor iPhone, iPad, Apple TV en Homey")
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                VStack(spacing: 4) {
                    Text("Bekijk")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Brand.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Brand.accent, in: Capsule())
                    Text(verbatim: "lrvdlinden.app")
                        .font(.caption2)
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                }
                .fixedSize()
            }
            .padding(16)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Brand.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: L("Meer apps van de ontwikkelaar") + ". " + L("Apps voor iPhone, iPad, Apple TV en Homey")))
        .accessibilityHint(Text(verbatim: "lrvdlinden.app"))
        .accessibilityAddTraits(.isLink)
    }
}

#Preview {
    VStack(spacing: 20) {
        MoreAppsCard()
        MoreAppsCard().environment(\.colorScheme, .dark)
    }
    .padding()
}
