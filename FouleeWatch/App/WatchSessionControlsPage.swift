import SwiftUI

/// One page, one job: stop the session (issue #274).
///
/// It carries a clock too, at half the size of the one next door. Not
/// decoration — a page whose only content is a destructive button gives no clue
/// which session it would end, and the gesture that reaches it (scroll down
/// from « Séance ») is the same one that used to reach « Arrêter » at the
/// bottom of the old scroll view. Keeping the elapsed time in view keeps the
/// two continuous.
///
/// There is no pause here, and adding one is not a matter of drawing a second
/// button: `splitIfDue` compares 15 s of *wall* time and back-dates the
/// boundary, `MovementClassifier` divides by wall time, and
/// `WatchWorkoutSegment.elapsed(at:)` is wall time throughout. Pausing means
/// reworking all three, which is why it lives in its own issue rather than
/// riding along here.
struct WatchSessionControlsPage: View {
    let metrics: WatchWorkoutMetrics
    var onStop: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchSessionClock(metrics: metrics, size: 22)
                    .foregroundStyle(.secondary)

                Button(role: .destructive, action: onStop) {
                    Label("Arrêter", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
        }
        .accessibilityLabel("Contrôles")
    }
}
