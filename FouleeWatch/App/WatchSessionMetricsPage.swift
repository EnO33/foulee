import SwiftUI

/// The page a session opens on: how long, which sport, and the four counters
/// (issue #274). Everything here was on the single screen this replaces —
/// nothing new is measured.
///
/// Still a `ScrollView`, though at default text size on a 40 mm there is now
/// nothing to scroll. The scroll is for the largest Dynamic Type sizes, where
/// the four tiles alone outgrow any wrist; the point of issue #274 is that the
/// *ordinary* reading no longer needs it.
struct WatchSessionMetricsPage: View {
    let metrics: WatchWorkoutMetrics
    /// What went wrong while the outing carried on (issue #290 and after).
    ///
    /// **On this page, not only on the recap.** A split that fails no longer
    /// ends the sortie — which is right — but it can leave it with no session,
    /// so nothing more is measured. The counters simply stop moving, and a
    /// wearer glancing at a frozen screen has no way to tell that from a quiet
    /// stretch. The reason existed in `lastError` and reached nobody, which is
    /// exactly what issue #256 cost two versions to learn.
    var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                WatchSessionClock(metrics: metrics, size: 34)

                if let errorMessage {
                    warning(errorMessage)
                } else {
                    currentActivity
                }

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
            }
            .padding(.horizontal, 6)
        }
        // Named for VoiceOver rather than drawn on screen — see the pager's own
        // documentation for why no page here carries a visible header.
        .accessibilityLabel("Séance")
    }

    /// What the watch is recording right now, and how much of it there has been
    /// (issue #250).
    ///
    /// Below the clock, never above it, and visibly secondary. The hierarchy is
    /// the design: this screen is read in a fraction of a second while moving,
    /// and two symmetric sets of numbers would leave the reader working out
    /// which is which. The big clock stays the session; this reads as a detail
    /// of it.
    ///
    /// **One line, since issue #299.** It used to carry the sport's three
    /// counters underneath — « 830 pas  0,8 km  48 kcal » — and that line has
    /// been redundant since issue #276 gave the legs a page of their own, which
    /// shows the same breakdown *per leg* and with a pace besides.
    ///
    /// Redundant, and unaffordable: with the capture seed telling the truth
    /// about a split outing, those three counters pushed « bpm » off the bottom
    /// of a 40 mm. The capture sentinel caught it, which is what that sentinel
    /// is for.
    ///
    /// What stays is the line that answers « est-ce que la montre a compris que
    /// je cours ? », and the sport's own elapsed beside it — one line, and the
    /// only thing here the tiles above cannot say.
    private var currentActivity: some View {
        VStack(spacing: 3) {
            // The `Divider()` that used to open this block is gone, and it is
            // the last ~9 pt the 40 mm needed. It was drawing a separation the
            // secondary foreground style already draws — the block reads as a
            // detail of the clock either way, which is all issue #250 asked of
            // it.
            //
            // The figure and the word together: « figure.walk » and
            // « figure.run » are two thin silhouettes at this size, and this is
            // the line that answers « est-ce que la montre a compris que je
            // cours ? ». Interpolated into the text rather than placed beside
            // it so the whole line wraps as one.
            Text("\(Image(systemName: metrics.activity.icon)) \(metrics.activityHeadlineText)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()

        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metrics.activitySummaryText)
    }

    /// Takes the activity line's place rather than adding to it: the sport and
    /// the pace are stale the moment measurement stops, so there is nothing to
    /// lose by replacing them and a line of height to gain.
    private func warning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
    }

    /// Two columns at most, and labels of four characters at most. The « pa/s »
    /// of issue #261 came from a row of three sharing the width equally.
    ///
    /// **Two lines, not three.** The icon used to sit on its own line above the
    /// figure, which cost about 15 pt per row — and the first capture of the
    /// paged screen showed why that matters: on a *46 mm*, the roomiest watch
    /// in the set, « kcal » and « bpm » were still cut off the bottom. The
    /// estimate that justified this whole split (~150 pt for the page) was made
    /// on paper and was simply wrong; a `.verticalPage` `TabView` keeps more
    /// room above its content than a plain scroll view does. Measured on the
    /// board, not reasoned about: the icon moved down beside the label, which
    /// buys back the two lines and reads the same while moving.
    private func metric(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
