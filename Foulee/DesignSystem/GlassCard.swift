import SwiftUI

/// Liquid-glass surface for cards, hero blocks and pills.
///
/// Tuned per color scheme so dark mode actually feels deliberate:
/// `.regularMaterial` instead of `.ultraThinMaterial`, a brighter
/// hairline border to read against the deep purple backdrop, and a
/// punchier drop shadow.
struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat
    var strong: Bool

    private var material: Material {
        if strong { return .regularMaterial }
        return colorScheme == .dark ? .regularMaterial : .ultraThinMaterial
    }

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .white.opacity(0.5)
    }

    private var shadowOpacity: Double {
        colorScheme == .dark ? 0.4 : 0.08
    }

    func body(content: Content) -> some View {
        content
            .background(
                // A single shadow cast by the *shape* (not the whole content):
                // the offscreen pass rasterises only this rounded rectangle, not
                // the material + text on top of it. Halves the offscreen passes
                // per card and keeps the look. Big win when many cards scroll.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .shadow(color: .black.opacity(shadowOpacity), radius: 12, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                strokeColor,
                                strokeColor.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

extension View {
    /// Apply the Foulée liquid-glass card style.
    func fouleeGlass(cornerRadius: CGFloat = 24, strong: Bool = false) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, strong: strong))
    }
}
