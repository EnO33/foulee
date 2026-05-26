import SwiftUI

/// Liquid-glass surface for cards, hero blocks and pills.
///
/// Wraps any view with `.ultraThinMaterial`, a subtle hairline border
/// and a soft shadow — matching the `.glass` primitive from the design.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var strong: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(strong ? .regularMaterial : .ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

extension View {
    /// Apply the Foulée liquid-glass card style.
    func fouleeGlass(cornerRadius: CGFloat = 24, strong: Bool = false) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, strong: strong))
    }
}
