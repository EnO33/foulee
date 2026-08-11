import SwiftUI

/// What this outing is doing to the day, while it is still happening
/// (issue #280).
///
/// The one page here that is not about the session. It is a **deliberate
/// departure from the Workout HIG**, which says not to give access to the rest
/// of the app during a session — and the argument for it has to be made rather
/// than assumed, because the same paragraph is what rules Now Playing out of
/// `WatchSessionPager`. Foulée's whole premise is that an outing exists to feed
/// a day and keep a streak alive; « me reste-t-il de quoi valider aujourd'hui ? »
/// is the question that decides whether the wearer turns back now or walks
/// another ten minutes. That question cannot be answered from the session's own
/// figures.
///
/// The streak and the goals cost nothing to draw — they are the phone's, read
/// out of the app group synchronously — so this page appears filled and only
/// its two bars arrive a moment late.
struct WatchSessionDayPage: View {
    let today: WatchTodayStore

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                streak
                goal(
                    label: "pas",
                    icon: "shoeprints.fill",
                    tint: .purple,
                    value: today.steps,
                    goal: today.stepsGoal
                )
                goal(
                    label: "min",
                    icon: "timer",
                    tint: .green,
                    value: today.minutes,
                    goal: today.minutesGoal
                )
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .accessibilityLabel("Ta journée")
    }

    /// The same flame and the same figure the home draws, smaller. Repeated
    /// rather than extracted into a shared view: the home's hero is a card with
    /// its own background and 34 pt digits, and pulling one view over both
    /// would make every future change to the home a change to a session screen.
    private var streak: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.orange)
            Text("\(today.streak)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("j de série")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Série de \(today.streak) jours")
    }

    /// « 8 240 / 10 000 pas » over a bar.
    ///
    /// A bar rather than the home's tile grid: a tile answers « combien ? » and
    /// this page is read to answer « est-ce que ça suffit ? », which is a
    /// proportion. `ProgressView` also clamps past 100 % on its own, so a day
    /// already validated draws a full bar instead of overflowing.
    private func goal(label: String, icon: String, tint: Color, value: Int, goal: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text("\(value.formatted()) / \(goal.formatted()) \(label)")
                    .font(.caption2)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            ProgressView(value: Self.fraction(value, of: goal))
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label) sur \(goal)")
    }

    /// Guarded against a goal of zero, which a payload written by an older
    /// phone build can carry — dividing by it would draw a `NaN` bar, and
    /// `ProgressView` renders `NaN` as a bar stuck empty with no hint why.
    ///
    /// Clamped at 1 as well: a day already past its goal draws a full bar
    /// rather than overflowing the track.
    ///
    /// Static and internal so the two edge cases are asserted rather than
    /// eyeballed — a `View`'s body is not somewhere a test can reach.
    static func fraction(_ value: Int, of goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(value) / Double(goal))
    }
}
