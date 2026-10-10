import SwiftUI

/// The week so far as a row of day rings (issue #348) — the minutes against
/// the goal, in the recap's language (#346): a rest day is a dashed circle, a
/// day still to come a pale track, today is named in the accent.
///
/// It took the place of the week's bars (#327) under the « Semaine » tab.
struct TodayWeekRings: View {
    var snapshot: TodaySnapshot
    var activeDays: Set<Weekday>

    private static let letters = ["L", "M", "M", "J", "V", "S", "D"]
    private static let dayNames = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]

    /// The week's days, Monday first, from the snapshot's own figures.
    private var days: [Recap.Day] {
        let monday = ISOWeek.days(containing: snapshot.date).first ?? snapshot.date
        return snapshot.weekMinutes.enumerated().map { index, minutes in
            Recap.Day(
                date: Calendar.iso8601Monday.date(byAdding: .day, value: index, to: monday) ?? monday,
                minutes: minutes,
                isPlanned: Weekday(rawValue: index + 1).map(activeDays.contains) ?? false
            )
        }
    }

    private var todayIndex: Int {
        let weekday = Calendar.iso8601Monday.component(.weekday, from: snapshot.date)
        return (weekday + 5) % 7
    }

    /// Planned days so far whose goal was met — the chip's numerator.
    private var completedCount: Int {
        days.filter { $0.isPlanned && $0.minutes >= snapshot.weekGoal }.count
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Minutes par jour")
                    .font(FouleeFont.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Chip(
                    label: "\(completedCount) / \(activeDays.count) sorties",
                    systemIcon: FouleeIcon.check,
                    tint: FouleeColor.success,
                    fill: Color.gray.opacity(0.16)
                )
            }
            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let isToday = index == todayIndex
                    VStack(spacing: 6) {
                        RecapDayRing(
                            day: day,
                            goalMinutes: snapshot.weekGoal,
                            lineWidth: 5,
                            isUpcoming: index > todayIndex
                        )
                        Text(Self.letters[index])
                            .font(FouleeFont.caption.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? FouleeColor.accentMid : .secondary)
                        Text(day.minutes > 0 ? "\(day.minutes)" : "–")
                            .font(FouleeFont.caption.monospacedDigit())
                            .foregroundStyle(day.minutes > 0 ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if isToday {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(FouleeColor.accentMid.opacity(0.1))
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Minutes d'activité par jour cette semaine")
            .accessibilityValue(spokenSummary)
        }
    }

    private var spokenSummary: String {
        zip(Self.dayNames, snapshot.weekMinutes)
            .map { "\($0) : \($1) minutes" }
            .joined(separator: ", ")
    }
}
