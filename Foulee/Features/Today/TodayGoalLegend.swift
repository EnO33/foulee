import SwiftUI

/// The two independent daily goals, side by side under the hero ring: the
/// all-day step goal (purple, the outer ring) and the activity-minutes goal
/// (green, the inner ring). Colours match `DualProgressRing` so each pill reads
/// as the legend for its ring.
struct TodayGoalLegend: View {
    var steps: Int
    var stepsGoal: Int
    var minutes: Int
    var minutesGoal: Int

    var body: some View {
        HStack(spacing: 10) {
            item(
                tint: FouleeColor.accentMid,
                label: "Pas",
                value: "\(steps.formattedFR) / \(stepsGoal.formattedFR)"
            )
            item(
                tint: FouleeColor.success,
                label: "Activité",
                value: "\(minutes) / \(minutesGoal) min"
            )
        }
    }

    private func item(tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(FouleeFont.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(FouleeFont.numeric(size: 14, weight: .semibold))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
