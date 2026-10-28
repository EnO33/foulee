import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The brand's bright shades, kept readable on a light background (issue #599).
///
/// They are made for a dark screen: on white, the minutes' green, the walk's
/// cyan and the orange fall near 2:1, under the 3:1 a figure or a ring needs.
/// Light mode takes a deeper shade of the same hue, at least 3:1 on the grouped
/// background, and « Augmenter le contraste » a deeper one still, at least
/// 4.5:1, the threshold for text. Dark mode keeps the bright shade, and so
/// does the watch, whose screen is always dark.
///
/// SwiftUI-only, like `ActivityPalette` and `MetricPalette`, so the watch
/// compiles the same table.
nonisolated enum ReadablePalette {
    /// Minutes, success, hiking.
    static let green = Color.readable(
        dark: brightGreen,
        light: 0x239F42,
        increasedContrast: 0x1C7F35
    )
    /// Walking. The system cyan in dark mode, as before.
    static let cyan = Color.readable(dark: .cyan, light: 0x0097B7, increasedContrast: 0x007891)
    /// Calories, warnings, running, the streak.
    static let orange = Color.readable(
        dark: brightOrange,
        light: 0xD96C00,
        increasedContrast: 0xA84E00
    )

    private static let brightGreen = Color(.sRGB, red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    private static let brightOrange = Color(.sRGB, red: 255 / 255, green: 159 / 255, blue: 10 / 255)

    // MARK: Small text (issue #658)

    // A brand colour on small text — a tile's label, a chip, a selected day.
    // Text needs 4.5:1, on a card's glass and on a chip's own tint, where the
    // shades above reach 3:1: light mode takes a deeper one still, the same
    // with « Augmenter le contraste ». Dark mode keeps the bright shade.

    static let greenText = Color.readable(
        dark: brightGreen,
        light: 0x15632A,
        increasedContrast: 0x15632A
    )
    static let orangeText = Color.readable(
        dark: brightOrange,
        light: 0x894000,
        increasedContrast: 0x894000
    )
    /// Steps, and the accent on text.
    static let purpleText = Color.readable(
        dark: Color(.sRGB, red: 191 / 255, green: 90 / 255, blue: 242 / 255),
        light: 0x751BC9,
        increasedContrast: 0x751BC9
    )
    static let blueText = Color.readable(
        dark: Color(.sRGB, red: 10 / 255, green: 132 / 255, blue: 255 / 255),
        light: 0x0050A5,
        increasedContrast: 0x0050A5
    )
    /// The rest day's indigo.
    static let indigoText = Color.readable(
        dark: Color(.sRGB, red: 94 / 255, green: 92 / 255, blue: 230 / 255),
        light: 0x3230DF,
        increasedContrast: 0x3230DF
    )
}

nonisolated extension Color {
    /// `dark` in dark mode and on the watch; in light mode, `light`, or
    /// `increasedContrast` when « Augmenter le contraste » is on.
    static func readable(dark: Color, light: UInt32, increasedContrast: UInt32) -> Color {
        #if os(iOS)
        Color(UIColor { traits in
            guard traits.userInterfaceStyle != .dark else { return UIColor(dark).resolvedColor(with: traits) }
            return UIColor(rgb: traits.accessibilityContrast == .high ? increasedContrast : light)
        })
        #else
        dark
        #endif
    }
}

#if os(iOS)
nonisolated private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
