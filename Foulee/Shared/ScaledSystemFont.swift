import SwiftUI

/// `Font.system(size:)` ignores Dynamic Type. This modifier re-derives the
/// point size through `@ScaledMetric` on `.largeTitle`'s curve: display-scale
/// numerals and glyphs grow with the setting, but less steeply than body
/// text, so tight cells and rings stay usable at accessibility sizes.
///
/// Shared with the watch (issue #600), whose counters were frozen the same way.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let numeric: Bool

    func body(content: Content) -> some View {
        let font = Font.system(size: size * scale, weight: weight, design: design)
        content.font(numeric ? font.monospacedDigit() : font)
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
