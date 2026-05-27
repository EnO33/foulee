import SwiftUI

/// Lightweight background for `.sheet` and `.fullScreenCover` presentations.
///
/// `Wallpaper` (four blurred 70 pt circles) looks great on the main
/// surfaces but is GPU-heavy to composite during a sheet animation —
/// every animation frame re-renders the blurs above the already-blurred
/// presenting view. Sheets get this cheaper static linear gradient
/// instead, mounted via `.presentationBackground` so iOS handles the
/// lifecycle (no re-render during drag-to-dismiss, etc.).
struct SheetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: stops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var stops: [Color] {
        colorScheme == .dark
            ? [Color(hex: 0x1A0A3A), Color(hex: 0x350A30), Color(hex: 0x0A0A20)]
            : [Color(hex: 0xF7D6FF), Color(hex: 0xFFE6F3), Color(hex: 0xD6E4FF)]
    }
}
