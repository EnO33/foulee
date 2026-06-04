import SwiftUI

/// Two concentric progress rings (Fitness-style) for showing two independent
/// goals at once: an `outer` ring and an inset `inner` ring, each with its own
/// gradient, plus a centred label slot. Both progresses are clamped to `0...1`.
struct DualProgressRing<Label: View>: View {
    var outerProgress: Double
    var innerProgress: Double
    var lineWidth: CGFloat = 9
    var outerGradient: LinearGradient = FouleeColor.accentGradient
    var innerGradient: LinearGradient = FouleeColor.activityGradient
    var trackColor: Color = .black.opacity(0.06)
    @ViewBuilder var label: () -> Label

    private var inset: CGFloat { lineWidth + 5 }

    var body: some View {
        ZStack {
            ring(progress: outerProgress, gradient: outerGradient)
            ring(progress: innerProgress, gradient: innerGradient)
                .padding(inset)
            label()
        }
    }

    private func ring(progress: Double, gradient: LinearGradient) -> some View {
        let clamped = min(max(progress, 0), 1)
        return ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: clamped)
        }
    }
}
