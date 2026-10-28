import SwiftUI
import Testing
import UIKit
@testable import Foulee

/// The brand's bright shades stay readable on a light background (issue #599).
@Suite("Readable palette")
struct ReadablePaletteTests {
    /// The grouped background, the lightest a card sits on, and plain white.
    private static let lightBackgrounds: [UInt32] = [0xF2F2F7, 0xFFFFFF]

    private static let colors: [(String, Color)] = [
        ("green", ReadablePalette.green),
        ("cyan", ReadablePalette.cyan),
        ("orange", ReadablePalette.orange)
    ]

    @Test("Light mode reaches 3:1, the threshold for a figure or a ring")
    func lightMode() throws {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        for (name, color) in Self.colors {
            for background in Self.lightBackgrounds {
                let ratio = try Self.contrast(color, on: background, traits: traits)
                #expect(ratio >= 3, "\(name) on \(String(background, radix: 16)): \(ratio)")
            }
        }
    }

    @Test("« Augmenter le contraste » reaches 4.5:1, the threshold for text")
    func increasedContrast() throws {
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = .light
            traits.accessibilityContrast = .high
        }
        for (name, color) in Self.colors {
            for background in Self.lightBackgrounds {
                let ratio = try Self.contrast(color, on: background, traits: traits)
                #expect(ratio >= 4.5, "\(name) on \(String(background, radix: 16)): \(ratio)")
            }
        }
    }

    @Test("Dark mode keeps the bright shades")
    func darkMode() throws {
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        let green = try Self.components(ReadablePalette.green, traits: traits)
        let orange = try Self.components(ReadablePalette.orange, traits: traits)
        #expect(Self.hex(green) == 0x30D158)
        #expect(Self.hex(orange) == 0xFF9F0A)
        let cyan = try Self.components(ReadablePalette.cyan, traits: traits)
        let systemCyan = try Self.components(.cyan, traits: traits)
        #expect(Self.hex(cyan) == Self.hex(systemCyan))
    }

    @Test("The metrics and the sports draw with the readable shades")
    func tokensUseThePalette() {
        #expect(MetricPalette.minutes == ReadablePalette.green)
        #expect(MetricPalette.calories == ReadablePalette.orange)
        #expect(ActivityPalette.walk == ReadablePalette.cyan)
        #expect(ActivityPalette.run == ReadablePalette.orange)
        #expect(FouleeColor.success == ReadablePalette.green)
        #expect(FouleeColor.warning == ReadablePalette.orange)
    }

    // MARK: - WCAG 2 contrast

    private static func contrast(_ color: Color, on background: UInt32, traits: UITraitCollection) throws -> Double {
        let foreground = luminance(try components(color, traits: traits))
        let backdrop = luminance([background >> 16, background >> 8, background].map { Double($0 & 0xFF) / 255 })
        return (max(foreground, backdrop) + 0.05) / (min(foreground, backdrop) + 0.05)
    }

    private static func components(_ color: Color, traits: UITraitCollection) throws -> [Double] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        try #require(UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [red, green, blue].map { Double($0) }
    }

    private static func luminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { $0 <= 0.040_45 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    private static func hex(_ rgb: [Double]) -> UInt32 {
        rgb.reduce(0) { ($0 << 8) | UInt32(($1 * 255).rounded()) }
    }
}
