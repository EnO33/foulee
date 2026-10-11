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
/// « Pause » sits above « Arrêter » (issue #384): the one is reached for far
/// more often than the other, and a stop is the move that cannot be undone, so
/// it stays the second thing on the page, not the first.
struct WatchSessionControlsPage: View {
    let metrics: WatchWorkoutMetrics
    var isSaving = false
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchSessionClock(metrics: metrics, size: 22)
                    .foregroundStyle(.secondary)

                Button(action: onTogglePause) {
                    Label(
                        metrics.isPaused ? "Reprendre" : "Pause",
                        systemImage: metrics.isPaused ? "play.fill" : "pause.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .tint(metrics.isPaused ? .green : .yellow)
                .disabled(isSaving)

                Button(role: .destructive, action: onStop) {
                    Label("Arrêter", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                // A second tap while the outing saves would read as « it did
                // not work » (issue #380): the store ignores it, and so does this.
                .disabled(isSaving)
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
        }
        .accessibilityLabel("Contrôles")
    }
}

/// Shown over the session from the tap on « Arrêter » until the summary
/// (issue #380): ending the workout and writing it, route included, to Santé
/// takes a few seconds, and a screen that does not move in the meantime reads
/// as a tap that was missed.
struct WatchSavingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Enregistrement…")
                .font(.headline)
            Text("Ta sortie part dans Santé")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
        .accessibilityElement(children: .combine)
    }
}
