import SwiftUI

/// A one-shot radial burst of little dots — a tasteful "you did it" flourish
/// shown when a walk is finished. Deterministic (no randomness), animates once
/// on appear, and ignores hit-testing so it never blocks the UI underneath.
struct CelebrationBurst: View {
    var pieceCount = 16
    var radius: CGFloat = 130

    private let palette: [Color] = [
        FouleeColor.accentStart,
        FouleeColor.accentMid,
        FouleeColor.accentEnd,
        FouleeColor.success,
        FouleeColor.warning
    ]

    @State private var expanded = false

    var body: some View {
        ZStack {
            ForEach(0..<pieceCount, id: \.self) { index in
                let angle = (Double(index) / Double(pieceCount)) * 2 * .pi
                Circle()
                    .fill(palette[index % palette.count])
                    .frame(width: 9, height: 9)
                    .offset(
                        x: expanded ? cos(angle) * radius : 0,
                        y: expanded ? sin(angle) * radius : 0
                    )
                    .scaleEffect(expanded ? 0.3 : 1)
                    .opacity(expanded ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { expanded = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.05).ignoresSafeArea()
        CelebrationBurst()
    }
}
