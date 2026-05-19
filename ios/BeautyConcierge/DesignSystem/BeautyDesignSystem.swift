import SwiftUI
import UIKit

enum BeautyColor {
    static let ivory = dynamic(light: UIColor(red: 0.982, green: 0.957, blue: 0.913, alpha: 1), dark: UIColor(red: 0.082, green: 0.071, blue: 0.059, alpha: 1))
    static let milk = dynamic(light: UIColor(red: 0.997, green: 0.985, blue: 0.956, alpha: 1), dark: UIColor(red: 0.129, green: 0.114, blue: 0.094, alpha: 1))
    static let ink = dynamic(light: UIColor(red: 0.075, green: 0.070, blue: 0.064, alpha: 1), dark: UIColor(red: 0.965, green: 0.934, blue: 0.865, alpha: 1))
    static let taupe = dynamic(light: UIColor(red: 0.487, green: 0.427, blue: 0.358, alpha: 1), dark: UIColor(red: 0.712, green: 0.652, blue: 0.562, alpha: 1))
    static let warmGray = dynamic(light: UIColor(red: 0.640, green: 0.594, blue: 0.520, alpha: 1), dark: UIColor(red: 0.548, green: 0.501, blue: 0.431, alpha: 1))
    static let lime = dynamic(light: UIColor(red: 0.755, green: 0.900, blue: 0.145, alpha: 1), dark: UIColor(red: 0.705, green: 0.830, blue: 0.175, alpha: 1))
    static let limeInk = Color(red: 0.080, green: 0.085, blue: 0.050)
    static let limeSoft = dynamic(light: UIColor(red: 0.910, green: 0.980, blue: 0.620, alpha: 1), dark: UIColor(red: 0.610, green: 0.740, blue: 0.190, alpha: 1))
    static let orange = Color(red: 0.920, green: 0.390, blue: 0.130)
    static let blush = dynamic(light: UIColor(red: 0.955, green: 0.780, blue: 0.735, alpha: 1), dark: UIColor(red: 0.370, green: 0.224, blue: 0.196, alpha: 1))
    static let champagne = dynamic(light: UIColor(red: 0.890, green: 0.800, blue: 0.660, alpha: 1), dark: UIColor(red: 0.396, green: 0.327, blue: 0.231, alpha: 1))
    static let card = dynamic(light: UIColor(red: 1.000, green: 0.988, blue: 0.962, alpha: 1), dark: UIColor(red: 0.129, green: 0.114, blue: 0.094, alpha: 1))
    static let featuredCard = dynamic(light: UIColor(red: 1.000, green: 0.988, blue: 0.962, alpha: 1), dark: UIColor(red: 0.104, green: 0.090, blue: 0.073, alpha: 1))
    static let quietCard = dynamic(light: UIColor(red: 0.997, green: 0.985, blue: 0.956, alpha: 1), dark: UIColor(red: 0.162, green: 0.142, blue: 0.116, alpha: 1))
    static let line = dynamic(light: UIColor(red: 0.860, green: 0.805, blue: 0.710, alpha: 1), dark: UIColor(red: 0.318, green: 0.286, blue: 0.238, alpha: 1))
    static let success = Color(red: 0.250, green: 0.480, blue: 0.250)
    static let danger = Color(red: 0.720, green: 0.180, blue: 0.120)

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
    static let display = Font.system(size: 42, weight: .semibold, design: .serif)
    static let title = Font.system(size: 30, weight: .semibold, design: .serif)
    static let title2 = Font.system(size: 24, weight: .semibold, design: .serif)
    static let headline = Font.system(size: 18, weight: .semibold, design: .default)
    static let body = Font.system(size: 16, weight: .regular, design: .default)
    static let callout = Font.system(size: 14, weight: .regular, design: .default)
    static let caption = Font.system(size: 12, weight: .semibold, design: .default)
    static let caption2 = Font.system(size: 10, weight: .semibold, design: .default)
}

struct BeautyShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func beautyShadow() -> some View { modifier(BeautyShadow()) }
    func beautyCard() -> some View {
        padding(BeautySpacing.md)
            .background(BeautyColor.card, in: RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous).stroke(BeautyColor.line.opacity(0.42), lineWidth: 1))
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
