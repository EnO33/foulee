import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity rendered while a walk session is active. Three surfaces:
/// - Lock Screen / banner: full row with timer + ring + counters
/// - Dynamic Island compact: walk icon left, elapsed right
/// - Dynamic Island expanded: timer + steps + km + kcal
/// - Dynamic Island minimal: walk icon
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
                        Text(context.state.elapsed.walkClockText)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: context.state.isPaused ? "pause.fill" : "figure.walk")
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
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.walk")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text(context.state.elapsed.walkClockText)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(context.state.isPaused ? .secondary : .primary)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.walk")
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
                    state.isPaused ? "Marche du midi · En pause" : "Marche du midi",
                    systemImage: state.isPaused ? "pause.fill" : "figure.walk"
                )
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(.primary)
                Text(state.elapsed.walkClockText)
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
