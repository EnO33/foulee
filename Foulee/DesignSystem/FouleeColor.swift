import SwiftUI

/// Brand palette and gradients shared across the app.
///
/// Constant colors (accent, success, warning, danger) live here.
/// Theme-aware text/background uses SwiftUI's semantic colors directly
/// (`.primary`, `.secondary`, `Color(.systemBackground)`).
enum FouleeColor {
    static let accent = Color("AccentColor")
    static let accentStart = Color(hex: 0xD97AFF)
    static let accentMid = Color(hex: 0xBF5AF2)
    static let accentEnd = Color(hex: 0x7C3AED)
    static let accentSecondary = Color(hex: 0x5E5CE6)

    static let success = Color(hex: 0x30D158)
    static let warning = Color(hex: 0xFF9F0A)
    static let danger = Color(hex: 0xFF453A)

    static let accentGradient = LinearGradient(
        colors: [accentStart, accentMid, accentEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let streakGradient = LinearGradient(
        colors: [Color(hex: 0xFF9F0A), Color(hex: 0xFF6B00)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Activity (midday-walk minutes) ring — green, distinct from the purple
    /// step ring, echoing the "exercise" colour language.
    static let activityGradient = LinearGradient(
        colors: [Color(hex: 0x5BE36B), success, Color(hex: 0x1FA845)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    /// Build a color from a 0xRRGGBB literal.
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
