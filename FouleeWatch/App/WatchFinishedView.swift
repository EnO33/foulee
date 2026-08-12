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
                if !metrics.splits.isEmpty, !saveFailed {
                    kilometres
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

    /// Each kilometre and what it cost (issue #301).
    ///
    /// **Here rather than on the session screen**, and not for want of room:
    /// a list that grows every kilometre has no fixed height, and this screen
    /// already scrolls by design (issue #241). It is also the only screen in
    /// the app no App Store board photographs, so it costs no page, no swipe
    /// and no seed.
    ///
    /// **Hidden when the save failed.** That path already carries an icon, a
    /// two-line title, HealthKit's own message and two buttons, and
    /// « Réessayer » is the only way to keep a sortie that did not land. A list
    /// of kilometres pushing it further down would be splits winning an
    /// argument against the workout itself.
    ///
    /// No sport beside a kilometre: a boundary is a fact of the outing, and one
    /// that straddles a change of sport belongs to neither.
    private var kilometres: some View {
        VStack(spacing: 2) {
            Divider()
                .padding(.vertical, 2)
            ForEach(metrics.splits) { split in
                // mm:ss and never tenths: a boundary is interpolated between
                // two deliveries, so the second it lands on is already the
                // finest thing worth stating.
                Text("km \(split.kilometre) · \(split.duration.walkClockText)")
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            metrics.splits
                .map { "Kilomètre \($0.kilometre) en \($0.duration.walkClockText)" }
                .joined(separator: ", ")
        )
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
