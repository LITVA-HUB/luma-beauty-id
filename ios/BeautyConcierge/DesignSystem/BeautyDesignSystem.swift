import SwiftUI
import UIKit

enum BeautyColor {
    static let ivory = dynamic(light: UIColor(red: 0.982, green: 0.957, blue: 0.913, alpha: 1), dark: UIColor(red: 0.082, green: 0.071, blue: 0.059, alpha: 1))
    static let milk = dynamic(light: UIColor(red: 0.997, green: 0.985, blue: 0.956, alpha: 1), dark: UIColor(red: 0.129, green: 0.114, blue: 0.094, alpha: 1))
    static let ink = dynamic(light: UIColor(red: 0.075, green: 0.070, blue: 0.064, alpha: 1), dark: UIColor(red: 0.965, green: 0.934, blue: 0.865, alpha: 1))
    static let taupe = dynamic(light: UIColor(red: 0.487, green: 0.427, blue: 0.358, alpha: 1), dark: UIColor(red: 0.712, green: 0.652, blue: 0.562, alpha: 1))
    static let warmGray = dynamic(light: UIColor(red: 0.460, green: 0.420, blue: 0.360, alpha: 1), dark: UIColor(red: 0.640, green: 0.590, blue: 0.510, alpha: 1))
    // Goldapple brand lime sampled from the official spring-promo banner
    // (#E2FE52 = rgb(226,254,82)). Used as a fill (banners, chips); a constant
    // brand colour in both light and dark. Near-black `ink`/`limeInk` on this
    // lime measures ~16.7:1, so keep dark text on it (never white).
    static let lime = dynamic(light: UIColor(red: 0.8863, green: 0.9961, blue: 0.3216, alpha: 1), dark: UIColor(red: 0.8863, green: 0.9961, blue: 0.3216, alpha: 1))
    // Accessible accent for selected/active controls (tab tint): deep chartreuse on light, bright lime on dark.
    static let limeTint = dynamic(light: UIColor(red: 0.360, green: 0.450, blue: 0.060, alpha: 1), dark: UIColor(red: 0.705, green: 0.830, blue: 0.175, alpha: 1))
    static let limeInk = Color(red: 0.080, green: 0.085, blue: 0.050)
    static let limeSoft = dynamic(light: UIColor(red: 0.910, green: 0.980, blue: 0.620, alpha: 1), dark: UIColor(red: 0.610, green: 0.740, blue: 0.190, alpha: 1))
    static let orange = dynamic(light: UIColor(red: 0.860, green: 0.360, blue: 0.100, alpha: 1), dark: UIColor(red: 0.980, green: 0.600, blue: 0.300, alpha: 1))
    static let blush = dynamic(light: UIColor(red: 0.955, green: 0.780, blue: 0.735, alpha: 1), dark: UIColor(red: 0.370, green: 0.224, blue: 0.196, alpha: 1))
    static let champagne = dynamic(light: UIColor(red: 0.890, green: 0.800, blue: 0.660, alpha: 1), dark: UIColor(red: 0.396, green: 0.327, blue: 0.231, alpha: 1))
    static let card = dynamic(light: UIColor(red: 1.000, green: 0.988, blue: 0.962, alpha: 1), dark: UIColor(red: 0.129, green: 0.114, blue: 0.094, alpha: 1))
    static let featuredCard = dynamic(light: UIColor(red: 1.000, green: 0.988, blue: 0.962, alpha: 1), dark: UIColor(red: 0.104, green: 0.090, blue: 0.073, alpha: 1))
    static let quietCard = dynamic(light: UIColor(red: 0.997, green: 0.985, blue: 0.956, alpha: 1), dark: UIColor(red: 0.162, green: 0.142, blue: 0.116, alpha: 1))
    static let line = dynamic(light: UIColor(red: 0.860, green: 0.805, blue: 0.710, alpha: 1), dark: UIColor(red: 0.318, green: 0.286, blue: 0.238, alpha: 1))
    static let success = dynamic(light: UIColor(red: 0.200, green: 0.420, blue: 0.200, alpha: 1), dark: UIColor(red: 0.480, green: 0.800, blue: 0.480, alpha: 1))
    static let danger = dynamic(light: UIColor(red: 0.720, green: 0.180, blue: 0.120, alpha: 1), dark: UIColor(red: 0.980, green: 0.500, blue: 0.450, alpha: 1))

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

enum BeautySpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 44
}

enum BeautyRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 18
    static let lg: CGFloat = 26
    static let xl: CGFloat = 34
}

enum BeautyFont {
    // Brand typeface: Onest (SIL OFL 1.1, bundled in Resources/Fonts). A clean
    // grotesque with first-class Cyrillic, standing in for Goldapple's
    // proprietary GA Sans. Sizes match the previous system-font scale 1:1 so the
    // hierarchy is preserved; only the family/weight change. `.weight()`/`.bold()`
    // at call sites resolve within the Onest typographic family.
    static let regularName = "Onest-Regular"
    static let mediumName = "Onest-Medium"
    static let boldName = "Onest-Bold"

    static let display = Font.custom(boldName, size: 42)
    static let title = Font.custom(boldName, size: 30)
    static let title2 = Font.custom(boldName, size: 24)
    static let headline = Font.custom(boldName, size: 18)
    static let body = Font.custom(regularName, size: 16)
    static let callout = Font.custom(regularName, size: 14)
    static let caption = Font.custom(mediumName, size: 12)
    static let caption2 = Font.custom(mediumName, size: 10)

    /// Brand-font replacement for one-off `.system(size:weight:)` call sites.
    /// Maps the requested weight onto the nearest bundled Onest face.
    static func sized(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold: name = boldName
        case .medium: name = mediumName
        default: name = regularName
        }
        return Font.custom(name, size: size)
    }
}

struct BeautyShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}

/// Single source of truth for the card surface used across the app.
/// Replaces the former `beautyCard()` / `HomeSurfaceCard` / `ProfileSurfaceCard` trio.
struct SurfaceCard<Content: View>: View {
    var tint: Color = BeautyColor.card
    var borderOpacity: Double = 0.42
    var cornerRadius: CGFloat = BeautyRadius.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(BeautySpacing.md)
            .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BeautyColor.line.opacity(borderOpacity), lineWidth: 1)
            )
    }
}

extension View {
    func beautyShadow() -> some View { modifier(BeautyShadow()) }
    /// Convenience wrapper that routes through `SurfaceCard` so card styling stays in one place.
    func beautyCard(tint: Color = BeautyColor.card, borderOpacity: Double = 0.42) -> some View {
        SurfaceCard(tint: tint, borderOpacity: borderOpacity) { self }
    }
}

struct PremiumBackground: View {
    var body: some View {
        ZStack {
            BeautyColor.ivory
            LinearGradient(colors: [BeautyColor.milk.opacity(0.8), BeautyColor.blush.opacity(0.18), BeautyColor.ivory], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image("background_texture")
                .resizable(resizingMode: .tile)
                .opacity(0.16)
        }
        .ignoresSafeArea()
    }
}
