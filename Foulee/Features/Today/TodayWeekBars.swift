import SwiftUI

/// 7 mini bars showing minutes per weekday vs. goal, plus the
/// "X / 5 marches" chip and weekday labels.
struct TodayWeekBars: View {
    var snapshot: TodaySnapshot
    var activeDays: Set<Weekday>
    private let labels = ["L", "M", "M", "J", "V", "S", "D"]
    private let dayNames = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]

    /// weekMinutes is Monday-first, so index 0 maps to `Weekday.monday` (raw 1).
    private func isActive(dayIndex index: Int) -> Bool {
        Weekday(rawValue: index + 1).map(activeDays.contains) ?? false
    }

    private var weekSpokenSummary: String {
        zip(dayNames, snapshot.weekMinutes)
            .map { "\($0): \($1) minutes" }
            .joined(separator: ", ")
    }

    private var todayIndex: Int {
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: snapshot.date)
        // ISO weekday: Monday=2, Sunday=1 → map to L=0, D=6.
        return weekday == 1 ? 6 : weekday - 2
    }

    /// Active days this week whose goal was met — the numerator of the chip.
    private var completedCount: Int {
        snapshot.weekMinutes.enumerated().filter { index, minutes in
            isActive(dayIndex: index) && minutes >= snapshot.weekGoal
        }.count
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Cette semaine")
                    .font(FouleeFont.headline)
                Spacer()
                Chip(
                    label: "\(completedCount) / \(activeDays.count) marches",
                    systemIcon: FouleeIcon.check,
                    tint: FouleeColor.success,
                    fill: Color.gray.opacity(0.16)
                )
            }
            bars
            weekdayLabels
        }
        .padding(18)
        .fouleeGlass(cornerRadius: 24)
        .accessibilityElement(children: .contain)
    }

    private var bars: some View {
        GeometryReader { proxy in
            let maxValue = max(snapshot.weekMinutes.max() ?? 0, snapshot.weekGoal)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(snapshot.weekMinutes.enumerated()), id: \.offset) { index, value in
                    let height = maxValue > 0
                        ? CGFloat(value) / CGFloat(maxValue) * proxy.size.height
                        : 0
                    bar(height: height, isToday: index == todayIndex, isActive: isActive(dayIndex: index))
                }
            }
        }
        .frame(height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Minutes de marche par jour cette semaine")
        .accessibilityValue(weekSpokenSummary)
    }

    private func bar(height: CGFloat, isToday: Bool, isActive: Bool) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                // Rest days are muted grey so the planned (active) days pop.
                .fill(isActive ? AnyShapeStyle(FouleeColor.accentGradient) : AnyShapeStyle(Color.gray.opacity(0.3)))
                .frame(maxWidth: .infinity)
                .frame(height: max(height, 4))
                .opacity(height > 0 ? 1 : 0)
                .overlay(alignment: .top) {
                    if isToday {
                        Circle()
                            .fill(FouleeColor.accentMid)
                            .frame(width: 6, height: 6)
                            .offset(y: -10)
                    }
                }
        }
    }

    private var weekdayLabels: some View {
        HStack(spacing: 8) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(FouleeFont.caption.weight(index == todayIndex ? .semibold : .regular))
                    .foregroundStyle(index == todayIndex ? FouleeColor.accentMid : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}
