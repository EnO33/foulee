import SwiftUI

/// Circular progress ring with a gradient stroke and a centred label slot.
///
/// `progress` is clamped to `0...1`. Animates with an `.easeOut(0.6)` curve
/// so quick HealthKit updates feel snappy without jitter.
struct ProgressRing<Label: View>: View {
    var progress: Double
    var lineWidth: CGFloat = 12
    var gradient: LinearGradient = FouleeColor.accentGradient
    var trackColor: Color = .black.opacity(0.06)
    @ViewBuilder var label: () -> Label

    private var clamped: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: clamped)
            label()
        }
    }
}
