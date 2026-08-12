import SwiftUI

/// What the outing has been split into, while it is still happening
/// (issue #276).
///
/// Since issue #265 a change of sport ends one `HKWorkout` and opens another,
/// so a sortie that starts walking and finishes running leaves **two** records
/// in Santé. Until this page, nothing said so before the recap screen: the
/// wearer changed pace, the watch quietly opened a second session, and the
/// first sign of it was in the Santé app that evening.
///
/// **Legs only — no summary block on top.** The obvious header would be the
/// current sport's running totals, and on the commonest outing there are
/// exactly two legs of two sports, which makes that header a word-for-word
/// repeat of the row beneath it. Foulée already has one screen showing the same
/// figures twice; it does not need a second. The per-sport breakdown belongs on
/// the recap, where the outing is over and the grouping is the point.
///
/// **Most recent first.** The leg you are running now is the one you look for,
/// and it is the only one still changing.
struct WatchSessionLegsPage: View {
    let metrics: WatchWorkoutMetrics

    /// Newest first — `WatchWorkoutMetrics.legs` is oldest-first because that is
    /// the order HealthKit closed them in.
    private var legs: [WatchWorkoutSegment] { metrics.legs.reversed() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(legs) { leg in
                    row(leg)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .accessibilityLabel("Portions de la sortie")
    }

    /// One leg: the sport on its own line, the figures under it.
    ///
    /// **Three lines**, not one: the sport, what the leg cost, and how it was
    /// run. A 40 mm gives roughly 150 pt of width, and the first capture of a
    /// row carrying pace *and* cadence on one line wrapped **mid-unit** —
    /// « 7'37"/ » then « km », « pas/ » then « min ». That is the « pa/s » of
    /// issue #261 arriving by another route, and the answer is the same one:
    /// let the line break where a reader would break it.
    private func row(_ leg: WatchWorkoutSegment) -> some View {
        // The whole row rebuilds every second, and only the running leg has
        // anything to change — the closed ones return the same string from the
        // same two dates. Cheaper than giving each row its own timeline, and it
        // keeps `lineText(at:)` the single place a leg is worded.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 1) {
                // One literal, never a `+` concatenation: the image renders
                // only when the whole thing is a single text interpolation.
                Text("\(Image(systemName: leg.activity.icon)) \(leg.activity.label)")
                    .font(.caption.weight(.semibold))
                Text(leg.effortText(at: context.date))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let rhythm = leg.rhythmText(at: context.date) {
                    Text(rhythm)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(leg.activity.label) : \(leg.lineText(at: context.date))")
        }
    }
}
