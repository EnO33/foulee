import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity rendered while a session is active. Three surfaces:
/// - Lock Screen / banner: full row with timer + ring + counters
/// - Dynamic Island compact: activity icon left, elapsed right
/// - Dynamic Island expanded: timer + steps + km + kcal
/// - Dynamic Island minimal: activity icon
///
/// The copy and the glyph are activity-neutral (issue #222): nothing in
/// `WalkActivityAttributes` says whether the session in flight is a walk or a
/// run, and this extension cannot read the preference either — it has no
/// app-group entitlement, so the snapshot the widgets read is out of reach.
/// Making the surface follow the *session's* activity is issue #225; until
/// then « ta sortie » and `ActivityGlyph.mixedCardio` are true for both, which
/// « Marche du midi » and `figure.walk` were not.
struct WalkLiveActivity: Widget {
    /// Neutral stand-in for the running/walking figure, and the one surface
    /// where it stays neutral: this extension has no app-group entitlement
    /// (`FouleeLiveActivity.entitlements` is empty), so unlike the widgets it
    /// cannot read the snapshot that carries the mode. `WalkActivityAttributes`
    /// is the only channel into it — that is issue #225.
    fileprivate static let activityIcon = ActivityGlyph.mixedCardio

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            LockScreenView(
                state: context.state,
                attributes: context.attributes
            )
            .padding(14)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(
                            timerInterval: context.state.timerBasis...Date(timeIntervalSinceNow: 86_400),
                            pauseTime: context.state.pausedAt,
                            countsDown: false,
                            showsHours: true
                        )
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    } icon: {
                        Image(systemName: context.state.isPaused ? "pause.fill" : WalkLiveActivity.activityIcon)
                            .foregroundStyle(.tint)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.distanceKm.kmText())
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        statCell(
                            value: "\(context.state.steps)",
                            label: "pas",
                            icon: "shoe"
                        )
                        statCell(
                            value: "\(context.state.activeCalories)",
                            label: "kcal",
                            icon: "flame.fill"
                        )
                        statCell(
                            value: "\(context.attributes.goalMinutes)",
                            label: "min objectif",
                            icon: "target"
                        )
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : WalkLiveActivity.activityIcon)
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text(
                    timerInterval: context.state.timerBasis...Date(timeIntervalSinceNow: 86_400),
                    pauseTime: context.state.pausedAt,
                    countsDown: false,
                    showsHours: true
                )
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(context.state.isPaused ? .secondary : .primary)
                .frame(maxWidth: 60)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : WalkLiveActivity.activityIcon)
                    .foregroundStyle(.tint)
            }
        }
    }

    private func statCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LockScreenView: View {
    let state: WalkActivityAttributes.WalkActivityState
    let attributes: WalkActivityAttributes

    private var progress: Double {
        let goalSeconds = Double(attributes.goalMinutes * 60)
        guard goalSeconds > 0 else { return 0 }
        return min(state.elapsed / goalSeconds, 1)
    }

    var body: some View {
        HStack(spacing: 14) {
            ring
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    // "Ta sortie" is the phone's own title for the same
                    // session (ActiveWalkScreen, #222) — one voice across the
                    // two surfaces the user sees while a session runs.
                    state.isPaused ? "Ta sortie · En pause" : "Ta sortie",
                    systemImage: state.isPaused ? "pause.fill" : WalkLiveActivity.activityIcon
                )
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(.primary)
                Text(
                    timerInterval: state.timerBasis...Date(timeIntervalSinceNow: 86_400),
                    pauseTime: state.pausedAt,
                    countsDown: false,
                    showsHours: true
                )
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(state.isPaused ? .secondary : .primary)
                Text("\(state.steps) pas · \(state.distanceKm.kmText())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.tint.opacity(0.15), lineWidth: 7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .frame(width: 62, height: 62)
    }
}
