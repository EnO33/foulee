import SwiftUI

/// Post-session summary — quick recap + a button to clear the slate. When the
/// workout could not be saved to Health, says so and offers a retry instead
/// of celebrating a session that never landed.
struct WatchFinishedView: View {
    let metrics: WatchWorkoutMetrics
    var saveFailed: Bool
    var onRetry: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: saveFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: saveFailed ? 32 : 40, weight: .bold))
                .foregroundStyle(saveFailed ? AnyShapeStyle(.orange) : AnyShapeStyle(Color("AccentColor")))
            // "Sortie", the app's single user-facing noun (issue #222), and
            // exactly as many characters as the "Marche" it replaces — this
            // line already wraps to two on the smallest watch.
            Text(saveFailed ? "Sortie non enregistrée dans Santé" : "Bravo")
                .font(saveFailed ? .caption : .headline)
                .multilineTextAlignment(.center)
            VStack(spacing: 2) {
                Text(metrics.elapsed.walkClockText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("\(metrics.steps) pas · \(metrics.distanceKm.kmText())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if saveFailed {
                Button(action: onRetry) {
                    Text("Réessayer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("AccentColor"))
                Button(action: onDone) {
                    Text("Terminer")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button(action: onDone) {
                    Text("Terminer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("AccentColor"))
            }
        }
        .padding(.horizontal, 8)
    }
}
