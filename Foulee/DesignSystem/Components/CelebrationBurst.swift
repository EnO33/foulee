import FouleeKit
import SwiftUI

/// A one-shot radial burst of little dots — a tasteful "you did it" flourish
/// shown when a walk is finished. Deterministic (no randomness), animates once
/// on appear, and ignores hit-testing so it never blocks the UI underneath.
/// With « Réduire les animations », the dots only fade in place (issue #598).
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = CelebrationBurstLayout(pieceCount: pieceCount, radius: radius, reduceMotion: reduceMotion)
        ZStack {
            ForEach(0..<pieceCount, id: \.self) { index in
                let piece = layout.piece(index, expanded: expanded)
                Circle()
                    .fill(palette[index % palette.count])
                    .frame(width: 9, height: 9)
                    .offset(x: piece.x, y: piece.y)
                    .scaleEffect(piece.scale)
                    .opacity(piece.opacity)
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
