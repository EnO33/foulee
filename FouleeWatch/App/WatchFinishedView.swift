import SwiftUI

/// Post-session summary — quick recap + a button to clear the slate. When the
/// workout could not be saved to Health, says so and offers a retry instead
/// of celebrating a session that never landed.
///
/// **Scrolls**, for the reason the session pages do (issue #241): on a
/// 40 mm wrist, at large text sizes, a bare `VStack` pushed « Réessayer » off
/// the bottom — and on this screen that button is the only way to keep a
/// session that failed to save. The failure line added by issue #256 makes the
/// content taller still, and an error message that costs the user their walk
/// would be a poor trade.
struct WatchFinishedView: View {
    let metrics: WatchWorkoutMetrics
    var saveFailed: Bool
    /// What HealthKit actually said, when it said anything (issue #256).
    ///
    /// Shown *here*, on the screen where the failure happens. It used to go to
    /// `lastError`, rendered only on the home screen — which `reset()` clears
    /// on the way out, so in practice nobody ever read it. A session died
    /// outdoors on `v1.38` and the one sentence that would have explained why
    /// was produced and thrown away.
    var errorMessage: String?
    var onRetry: () -> Void
    var onDone: () -> Void

    var body: some View {
        ScrollView {
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
                if !metrics.perSport.isEmpty {
                    breakdown
                }
                if let reasonText {
                    reason(reasonText)
                }
                buttons
                    .padding(.top, 10)
            }
            .padding(.horizontal, 8)
        }
    }

    /// What to print under the summary, if anything.
    ///
    /// A computed property rather than a condition buried in `body`, because
    /// this is the rule worth pinning: the message appears **only** on a
    /// failure. A success that printed a stale error would be worse than one
    /// that printed nothing — and `lastError` outlives the failure that set it,
    /// so the guard is load-bearing, not decorative.
    var reasonText: String? { saveFailed ? errorMessage : nil }

    /// One line per sport, when the outing changed sport (issue #265).
    ///
    /// A change ends one `HKWorkout` and opens another, so Santé shows a walk
    /// *and* a run — and this is where that is said before the wearer goes
    /// looking. Absent from a single-sport outing: the totals above already say
    /// it, and repeating them would be noise on a screen that has none to
    /// spare.
    private var breakdown: some View {
        VStack(spacing: 2) {
            Divider()
                .padding(.vertical, 2)
            ForEach(metrics.perSport) { sport in
                // One literal, never a `+` concatenation: the image only
                // renders when the whole thing is a single text interpolation.
                Text("\(Image(systemName: sport.activity.icon)) \(sport.text)")
                    .font(.caption2)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.secondary)
    }

    /// The raw message, unwrapped and untranslated.
    ///
    /// Deliberately not rephrased into something friendlier: this text exists to
    /// be *reported*, and a reassuring paraphrase would throw away the only
    /// evidence a wrist can produce. It is small and secondary so it does not
    /// dominate a screen the user reads after an outing.
    private func reason(_ message: String) -> some View {
        Text(message)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    @ViewBuilder
    private var buttons: some View {
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
}
