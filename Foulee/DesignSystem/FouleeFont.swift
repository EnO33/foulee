import SwiftUI

/// Type ramp matching the design's `.t-largetitle … .t-caption` classes.
/// Every token is text-style relative, so it tracks the user's Dynamic Type
/// setting; the weights mirror the original fixed-size design at the
/// default (Large) size.
enum FouleeFont {
    static let largeTitle = Font.system(.largeTitle, weight: .bold)
    static let title2 = Font.system(.title2, weight: .bold)
    static let title3 = Font.system(.title3, weight: .semibold)
    static let headline = Font.system(.headline, weight: .semibold)
    static let body = Font.system(.body, weight: .regular)
    static let callout = Font.system(.callout, weight: .regular)
    static let footnote = Font.system(.footnote, weight: .regular)
    static let caption = Font.system(.caption, weight: .regular)

    /// Rounded design with tabular digits — for big counters and timers.
    /// Frozen at `size`: shipping views must go through `scaledNumericFont`
    /// so the counter tracks Dynamic Type.
    static func numeric(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// `Font.system(size:)` ignores Dynamic Type. This modifier re-derives the
/// point size through `@ScaledMetric` on `.largeTitle`'s curve: display-scale
/// numerals and glyphs grow with the setting, but less steeply than body
/// text, so tight cells and rings stay usable at accessibility sizes.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let numeric: Bool

    func body(content: Content) -> some View {
        let font: Font = numeric
            ? FouleeFont.numeric(size: size * scale, weight: weight)
            : .system(size: size * scale, weight: weight, design: design)
        content.font(font)
    }
}

extension View {
    /// System font frozen at a design point size, rescaled with Dynamic Type.
    func scaledSystemFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, numeric: false))
    }

    /// Dynamic Type-aware counterpart of `FouleeFont.numeric`.
    func scaledNumericFont(size: CGFloat, weight: Font.Weight = .bold) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: .rounded, numeric: true))
    }
}
