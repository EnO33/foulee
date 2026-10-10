import SwiftUI

/// One day of a recap as a ring (issue #346): the minutes against the goal,
/// in the green of the home's activity ring and the streak calendar's inner
/// ring — the same day reads the same everywhere.
///
/// A rest day with nothing done is a dashed outline, never an empty ring: it
/// was not missed.
struct RecapDayRing: View {
    let day: Recap.Day
    let goalMinutes: Int
    var lineWidth: CGFloat = 4
    /// `false` draws the ring empty, so the reveal can fill it.
    var isRevealed = true

    private var progress: Double {
        guard isRevealed, goalMinutes > 0 else { return 0 }
        return min(Double(day.minutes) / Double(goalMinutes), 1)
    }

    private var metGoal: Bool { day.minutes >= goalMinutes && day.minutes > 0 }

    var body: some View {
        ZStack {
            if day.isPlanned || day.minutes > 0 {
                Circle()
                    .stroke(Color.gray.opacity(0.18), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(FouleeColor.activityGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if metGoal, isRevealed {
                    Circle()
                        .fill(FouleeColor.success.opacity(0.16))
                        .padding(lineWidth * 1.5)
                }
            } else {
                Circle()
                    .strokeBorder(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
    }
}

/// « ↑ 12 % » — the change from the period before, or nothing when there was
/// nothing before. An arrow as well as a colour, so the sign never rests on
/// colour alone.
struct RecapChangeChip: View {
    let old: Double
    let new: Double

    var body: some View {
        if let change = Recap.change(from: old, to: new) {
            let percent = Int((change * 100).rounded())
            let isUp = percent >= 0
            Label {
                Text(percent == 0 ? "=" : "\(abs(percent)) %")
            } icon: {
                Image(systemName: percent == 0 ? "equal" : (isUp ? "arrow.up" : "arrow.down"))
            }
            .font(FouleeFont.caption.weight(.bold))
            .foregroundStyle(isUp ? FouleeColor.success : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((isUp ? FouleeColor.success : Color.gray).opacity(0.14), in: Capsule())
            .accessibilityLabel(percent == 0 ? "Stable" : "\(isUp ? "En hausse" : "En baisse") de \(abs(percent)) %")
        }
    }
}

/// The period day by day: seven rings for a week, a calendar for a month.
struct RecapDaysView: View {
    let recap: Recap
    var isRevealed = true

    private static let weekdayLetters = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        switch recap.period.kind {
        case .week: week
        case .month: month
        }
    }

    private var week: some View {
        HStack(spacing: 8) {
            ForEach(Array(recap.days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 6) {
                    RecapDayRing(day: day, goalMinutes: recap.goalMinutes, lineWidth: 5, isRevealed: isRevealed)
                        .animation(.easeOut(duration: 0.6).delay(Double(index) * 0.05), value: isRevealed)
                    Text(Self.weekdayLetters[index % 7])
                        .font(FouleeFont.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(day.minutes > 0 ? "\(day.minutes)" : "–")
                        .font(FouleeFont.caption.monospacedDigit())
                        .foregroundStyle(day.minutes > 0 ? .primary : .tertiary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(for: day))
            }
        }
    }

    private var month: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let leading = recap.days.first.map { Self.mondayOffset(of: $0.date) } ?? 0
        return VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(Self.weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(FouleeFont.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                ForEach(Array(recap.days.enumerated()), id: \.element.id) { index, day in
                    RecapDayRing(day: day, goalMinutes: recap.goalMinutes, lineWidth: 3, isRevealed: isRevealed)
                        .overlay {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .animation(.easeOut(duration: 0.6).delay(Double(index) * 0.012), value: isRevealed)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityText(for: day))
                }
            }
        }
    }

    private func accessibilityText(for day: Recap.Day) -> String {
        let date = Self.dayFormatter.string(from: day.date)
        guard day.isPlanned || day.minutes > 0 else { return "\(date) : jour de repos" }
        let held = day.minutes >= recap.goalMinutes && day.minutes > 0 ? ", objectif tenu" : ""
        return "\(date) : \(day.minutes) minutes\(held)"
    }

    /// Columns before the 1st in a Monday-first grid.
    private static func mondayOffset(of date: Date) -> Int {
        (Calendar.iso8601Monday.component(.weekday, from: date) + 5) % 7
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}
