import SwiftUI

/// Live session screen — uses a `TimelineView` so the elapsed clock keeps
/// ticking even when the store hasn't pushed an update yet (HealthKit
/// metric updates arrive every few seconds, the clock needs to be smoother).
///
/// The content **scrolls**, like the home does, and that is not cosmetic. The
/// elapsed clock, four metric tiles and « Arrêter » need about 225 pt; a 40 mm
/// watch offers roughly 170 pt of safe area. Laid out in a bare `VStack` this
/// overflowed at both ends, and the overflow was measured, not guessed: on a
/// 46 mm the stop button's capsule ran ~13 pt past the bottom edge, and on a
/// 40 mm SE the button was off screen entirely — label and all — with nothing
/// to scroll, so **a session could not be stopped from this screen**. The same
/// overflow pushed the 38 pt clock up into the top-right corner watchOS draws
/// its own time in, where the two overprinted each other.
///
/// A `ScrollView` fixes both at once: its content starts below the system time
/// instead of under it (the same inset `WatchTodayView` already gets), and
/// « Arrêter » is always reachable whatever the wrist. The `TimelineView` sits
/// *inside* it so the per-second rebuild cannot disturb the scroll offset.
struct WatchActiveWalkView: View {
    let metrics: WatchWorkoutMetrics
    var onStop: () -> Void

    var body: some View {
        ScrollView {
            ticking
        }
    }

    private var ticking: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(spacing: 8) {
                Text(metrics.elapsed.walkClockText)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                currentActivity

                HStack(spacing: 10) {
                    metric(value: "\(metrics.steps)", label: "pas", icon: "shoe")
                    metric(value: metrics.distanceKm.kmValue(), label: "km", icon: "location.fill")
                }
                HStack(spacing: 10) {
                    metric(
                        value: "\(metrics.activeCalories)",
                        label: "kcal",
                        icon: "flame.fill"
                    )
                    metric(
                        value: metrics.heartRate.map { "\($0)" } ?? "—",
                        label: "bpm",
                        icon: "heart.fill"
                    )
                }
                .padding(.top, 4)

                // Was a `Spacer(minLength: 4)`, which only ever pushed the
                // button to the bottom of a container this content is too
                // tall for. Inside a scroll view the height is unbounded,
                // so the gap has to be stated rather than sprung.
                Button(role: .destructive, action: onStop) {
                    Label("Arrêter", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 6)
        }
    }

    /// What the watch is recording right now, and how much of it there has been
    /// (issue #250).
    ///
    /// Below the global block, never above it, and visibly secondary. The
    /// hierarchy is the design: this screen is read in a fraction of a second
    /// while moving, and two symmetric sets of numbers would leave the reader
    /// working out which is which. The big clock stays the session; this reads
    /// as a detail of it.
    ///
    /// **Two flowing lines of text, not tiles, and not a row of columns.** The
    /// first attempt gave each counter an equal share of the width, which on a
    /// 40 mm cut « pas » into « pa / s » and « kcal » into « kc / al » — at the
    /// *default* text size, before Dynamic Type entered into it. A paragraph
    /// wraps at its separators instead, so the largest sizes cost extra lines
    /// rather than legibility, and the scroll view of issue #241 is what makes
    /// extra lines affordable: « Arrêter » stays reachable however tall this
    /// grows.
    private var currentActivity: some View {
        VStack(spacing: 3) {
            Divider()
            // The figure and the word together: « figure.walk » and
            // « figure.run » are two thin silhouettes at this size, and this is
            // the line that answers « est-ce que la montre a compris que je
            // cours ? ». Interpolated into the text rather than placed beside
            // it so the whole line wraps as one.
            Text("\(Image(systemName: metrics.activity.icon)) \(metrics.activityHeadlineText)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
            if metrics.hasMeasuredActivityTotals {
                Text(metrics.activityTotals.countersText)
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metrics.activitySummaryText)
    }

    private func metric(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
