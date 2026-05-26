import SwiftUI

/// Soft pastel blob backdrop that the glass surfaces sit over.
/// Mirrors the four `.wallpaper .blob` elements from the design.
struct Wallpaper: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            blob(.init(hex: 0xF7D6FF), size: 360, offset: .init(width: -120, height: -260))
            blob(.init(hex: 0xE9D4FF), size: 320, offset: .init(width: 160, height: -40))
            blob(.init(hex: 0xD6E4FF), size: 280, offset: .init(width: -140, height: 280))
            blob(.init(hex: 0xFFE6F3), size: 260, offset: .init(width: 140, height: 220))
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, size: CGFloat, offset: CGSize) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 70)
            .offset(offset)
    }
}
