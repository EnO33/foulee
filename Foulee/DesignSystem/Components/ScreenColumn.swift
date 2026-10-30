import SwiftUI

/// The column a screen's content sits in (#661): the side gutter, and a
/// reading width centred in the window once it is wider than that — the
/// iPhone Duo's inner screen, a sheet presented there. The decision is the
/// space the screen is given, never the device: a phone is narrower than the
/// column, so its layout does not move.
struct ScreenColumn: ViewModifier {
    /// Wide enough for the stats grid and the Bilan's rings side by side,
    /// narrow enough that a line of text stays readable.
    nonisolated static let maxWidth: CGFloat = 640

    var gutter: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, gutter)
            .frame(maxWidth: Self.maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Lays the content out in the screen's reading column (`ScreenColumn`).
    func screenColumn(gutter: CGFloat = 20) -> some View {
        modifier(ScreenColumn(gutter: gutter))
    }
}
