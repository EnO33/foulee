import SwiftUI

/// Soft blob backdrop that the glass surfaces sit over. Two distinct
/// palettes — pastel pinks/lavenders/peaches in light mode, deep
/// purple/navy in dark mode — so the dark theme stops looking like
/// "light wallpaper turned black" and gets its own moody identity.
struct Wallpaper: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemBackground)
            ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                Circle()
                    .fill(blob.color)
                    .frame(width: blob.size, height: blob.size)
                    .blur(radius: 70)
                    .offset(blob.offset)
                    .opacity(blob.opacity)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var blobs: [Blob] {
        colorScheme == .dark ? Self.darkBlobs : Self.lightBlobs
    }

    private static let lightBlobs: [Blob] = [
        Blob(color: Color(hex: 0xF7D6FF), size: 360, offset: .init(width: -120, height: -260), opacity: 1),
        Blob(color: Color(hex: 0xE9D4FF), size: 320, offset: .init(width: 160, height: -40), opacity: 1),
        Blob(color: Color(hex: 0xD6E4FF), size: 280, offset: .init(width: -140, height: 280), opacity: 1),
        Blob(color: Color(hex: 0xFFE6F3), size: 260, offset: .init(width: 140, height: 220), opacity: 1)
    ]

    private static let darkBlobs: [Blob] = [
        Blob(color: Color(hex: 0x2A0A4A), size: 420, offset: .init(width: -140, height: -280), opacity: 0.85),
        Blob(color: Color(hex: 0x350A30), size: 360, offset: .init(width: 180, height: -60), opacity: 0.75),
        Blob(color: Color(hex: 0x1A0A3A), size: 320, offset: .init(width: -160, height: 300), opacity: 0.7),
        Blob(color: Color(hex: 0x061030), size: 300, offset: .init(width: 160, height: 240), opacity: 0.75)
    ]
}

private struct Blob {
    let color: Color
    let size: CGFloat
    let offset: CGSize
    let opacity: Double
}
