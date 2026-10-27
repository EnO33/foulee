import ActivityKit
import FouleeKit
import SwiftUI
import WidgetKit

/// Live Activity rendered while a session is active. Three surfaces:
/// - Lock Screen / banner: full row with timer + ring + counters
/// - Dynamic Island compact: activity icon left, elapsed right
/// - Dynamic Island expanded: timer + km and climb + steps + kcal
/// - Dynamic Island minimal: activity icon
///
/// The copy and the glyph follow the session's own activity (issue #225):
/// a run announces itself as a run. This extension has no app-group
/// entitlement, so the snapshot the widgets read is out of reach and
/// `WalkActivityAttributes.activity` is the only channel that carries the
/// information — the title and the glyph are derived there, once, so the four
/// places below that draw the figure cannot disagree. The neutral « Ta sortie »
/// and `ActivityGlyph.mixedCardio` that #222 put here stay for one payload
/// only: an activity started by a build older than #225, which never recorded
/// what it was.
struct WalkLiveActivity: Widget {
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
                        Image(systemName: context.state.isPaused ? "pause.fill" : context.attributes.glyph)
                            .foregroundStyle(.tint)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(context.state.distanceKm.kmText())
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                        // The climb under the distance, when there is one
                        // (issue #576); never in the compact views.
                        if let elevation = context.state.elevation, let text = elevation.text {
                            Text(text)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(elevation.spokenText ?? text)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        statCell(
                            value: context.state.steps.groupedText(),
                            label: "pas",
                            icon: "shoe"
                        )
                        statCell(
                            value: context.state.activeCalories.map { "\($0)" } ?? "—",
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
                Image(systemName: context.state.isPaused ? "pause.fill" : context.attributes.glyph)
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
                Image(systemName: context.state.isPaused ? "pause.fill" : context.attributes.glyph)
                    .foregroundStyle(.tint)
            }
        }
    }

    private func statCell(value: String, label: LocalizedStringResource, icon: String) -> some View {
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
                    // « Ta marche » / « Ta course », and « Ta sortie » only
                    // when the payload predates #225 — spelled in
                    // `WalkActivityAttributes` so the Dynamic Island above
                    // draws the same figure this row does.
                    attributes.title(isPaused: state.isPaused),
                    systemImage: state.isPaused ? "pause.fill" : attributes.glyph
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
                Text("\(state.steps.groupedText()) pas · \(state.distanceKm.kmText())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // Its own line: beside the steps and the distance it would
                // truncate on a small phone (issue #576).
                if let elevation = state.elevation, let text = elevation.text {
                    Text(text)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(elevation.spokenText ?? text)
                }
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
