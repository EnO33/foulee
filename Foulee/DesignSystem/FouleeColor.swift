import SwiftUI

/// Brand palette and gradients shared across the app.
///
/// Brand colors (accent, success, warning, danger) live here; success and
/// warning deepen in light mode to stay readable (`ReadablePalette`, #599).
/// Theme-aware text/background uses SwiftUI's semantic colors directly
/// (`.primary`, `.secondary`, `Color(.systemBackground)`).
enum FouleeColor {
    static let accentStart = Color(hex: 0xD97AFF)
    static let accentMid = Color(hex: 0xBF5AF2)
    static let accentEnd = Color(hex: 0x7C3AED)
    static let accentSecondary = Color(hex: 0x5E5CE6)

    static let success = ReadablePalette.green
    static let warning = ReadablePalette.orange
    static let danger = Color(hex: 0xFF453A)

    /// Water — the hydration card, screen, settings and Bilan block. A token
    /// here rather than on a view: a static on a `View` is main-actor
    /// isolated, and the Réglages page model reads it from a nonisolated
    /// context (issue #405).
    static let water = Color.teal

    static let accentGradient = LinearGradient(
        colors: [accentStart, accentMid, accentEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let streakGradient = LinearGradient(
        colors: [
            warning,
            Color.readable(dark: Color(hex: 0xFF6B00), light: 0xC85400, increasedContrast: 0x8F3D00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Activity (midday-walk minutes) ring — green, distinct from the purple
    /// step ring, echoing the "exercise" colour language.
    static let activityGradient = LinearGradient(
        colors: [
            Color.readable(dark: Color(hex: 0x5BE36B), light: 0x239F42, increasedContrast: 0x1C7F35),
            success,
            Color.readable(dark: Color(hex: 0x1FA845), light: 0x188A36, increasedContrast: 0x177030)
        ],
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
