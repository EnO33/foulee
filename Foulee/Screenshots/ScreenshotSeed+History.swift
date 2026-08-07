#if DEBUG
import Foundation

/// The seeded twelve months of history, and everything the app derives from it.
///
/// One generator, several readings: the streak, the calendar rings, the daily
/// charts and the résumé all come out of `minutes(offset:)`, so the number on
/// the hero card is arithmetically the same number the calendar sheet counts.
/// Nothing is hard-coded twice, and nothing reads the wall clock — `offset` is
/// counted from `ScreenshotSeed.instant`.
extension ScreenshotSeed {
    /// Days of history the seed answers for — the window every streak surface
    /// fetches, so the record shown on the home is computed over exactly the
    /// months the calendar sheet browses.
    static var historyDays: Int { StreakCalculator.historyWindowDays }

    /// Length of the ordinary runs further back, so the record stands out.
    private static let olderRunLength = 15

    /// The last week, spelled out: these are the durations the résumé shows,
    /// the bars of the current week, and the last points of the Minutes chart.
    /// Keyed by day offset — 0 = Thursday (today), 3 = Monday, 6 = last Friday;
    /// offsets 4 and 5 are the weekend and fall through to `restDayMinutes`.
    ///
    /// Today's entry is `todayMinutes` rather than a literal: the watch shows
    /// that number without any history behind it, so it is a shared constant
    /// (`ScreenshotSeedCore`) and this table reads it back.
    private static let pinnedMinutes: [Int: Int] = [0: todayMinutes, 1: 36, 2: 33, 3: 38, 6: 31]

    // MARK: - The history itself

    /// Active minutes for `offset` days ago, or 0 beyond the seeded window.
    static func minutes(offset: Int) -> Int {
        minutesByOffset.indices.contains(offset) ? minutesByOffset[offset] : 0
    }

    /// Built once, walking backwards from today and numbering the *active* days
    /// as it goes — the streak counts active days, not calendar days, so the
    /// run lengths have to be decided on that numbering.
    private static let minutesByOffset: [Int] = {
        let activeWeekdays = Weekday.workWeek.calendarWeekdays
        var result: [Int] = []
        result.reserveCapacity(historyDays)
        var activeIndex = 0
        for offset in 0..<historyDays {
            let weekday = calendar.component(.weekday, from: day(offset: offset))
            guard activeWeekdays.contains(weekday) else {
                result.append(restDayMinutes(offset: offset))
                continue
            }
            result.append(activeDayMinutes(activeIndex: activeIndex, offset: offset))
            activeIndex += 1
        }
        return result
    }()

    private static func activeDayMinutes(activeIndex: Int, offset: Int) -> Int {
        if let pinned = pinnedMinutes[offset] { return pinned }
        guard !isMissedActiveDay(activeIndex: activeIndex) else { return 0 }
        return minutesGoal + 1 + (activeIndex * 5) % 16
    }

    /// A rest day still logs some incidental activity — but never enough to
    /// reach the goal, so the calendar reads it as a rest day and not as a
    /// completed one. No session is recorded on those days either
    /// (`workout(offset:)` only fires above the goal), which is what puts the
    /// "aucune sortie" placeholder in the résumé.
    private static func restDayMinutes(offset: Int) -> Int {
        offset.isMultiple(of: 2) ? 14 : 17
    }

    /// Where the runs break, in active-day numbering: the current streak ends
    /// at `currentStreak`, the record run sits right behind it, and everything
    /// older alternates in shorter runs.
    private static func isMissedActiveDay(activeIndex: Int) -> Bool {
        if activeIndex < currentStreak { return false }
        if activeIndex == currentStreak { return true }
        let older = activeIndex - (currentStreak + 1)
        if older < bestStreak { return false }
        return (older - bestStreak).isMultiple(of: olderRunLength + 1)
    }

    // MARK: - Derived daily values

    static func steps(offset: Int) -> Int {
        guard offset != 0 else { return todaySteps }
        let daily = minutes(offset: offset)
        return daily == 0 ? 3_200 : 7_600 + daily * 70
    }

    static func distanceKm(offset: Int) -> Double {
        distanceKm(steps: steps(offset: offset))
    }

    static func calories(offset: Int) -> Int {
        calories(minutes: minutes(offset: offset))
    }

    // MARK: - Series

    static func dailyMinutes(daysBack: Int) -> [DailyMinutes] {
        (0..<max(daysBack, 0)).reversed().map {
            DailyMinutes(date: day(offset: $0), minutes: minutes(offset: $0))
        }
    }

    static func metricSeries(_ metric: WalkMetric, daysBack: Int) -> [MetricPoint] {
        (0..<max(daysBack, 0)).reversed().map { offset in
            MetricPoint(date: day(offset: offset), value: dailyValue(metric, offset: offset))
        }
    }

    private static func dailyValue(_ metric: WalkMetric, offset: Int) -> Double {
        switch metric {
        case .steps: Double(steps(offset: offset))
        case .minutes: Double(minutes(offset: offset))
        case .distance: distanceKm(offset: offset)
        case .calories: Double(calories(offset: offset))
        }
    }

    /// Shape of a day: quiet night, a commute bump, the midday session, an
    /// afternoon tail. Only the hours up to the seeded one are emitted, and the
    /// weights are renormalised over them so the curve always sums back to the
    /// day total the rest of the app shows.
    private static let hourWeights: [Double] = [
        0, 0, 0, 0, 0, 0.01, 0.05, 0.09, 0.07, 0.05, 0.04, 0.05,
        0.28, 0.13, 0.06, 0.05, 0.04, 0.03, 0.03, 0.02, 0.02, 0.01, 0.01, 0
    ]

    static func hourlyToday(_ metric: WalkMetric) -> [MetricPoint] {
        let hour = calendar.component(.hour, from: instant)
        let weights = Array(hourWeights.prefix(hour + 1))
        let sum = weights.reduce(0, +)
        let total = dailyValue(metric, offset: 0)
        guard sum > 0 else { return [] }
        var values = weights.map { total * $0 / sum }
        if metric.fractionDigits == 0 { values = rounded(values, to: total) }
        let start = today
        return values.enumerated().map { index, value in
            MetricPoint(
                date: calendar.date(byAdding: .hour, value: index, to: start) ?? start,
                value: value
            )
        }
    }

    /// Round every bucket and give the rounding slack to the tallest one, so
    /// the chart's own "Total" still reads the day total exactly.
    private static func rounded(_ values: [Double], to total: Double) -> [Double] {
        var buckets = values.map { $0.rounded() }
        guard let peak = buckets.indices.max(by: { buckets[$0] < buckets[$1] }) else { return buckets }
        buckets[peak] += total.rounded() - buckets.reduce(0, +)
        return buckets
    }

    // MARK: - Sessions

    /// Newest first, one session per day that reached the goal — so the résumé's
    /// "aucune sortie" placeholder lands on exactly the weekend days the week
    /// bars show empty.
    static func recentWorkouts(daysBack: Int) -> [WorkoutSummary] {
        (0..<max(daysBack, 0)).compactMap(workout(offset:))
    }

    private static func workout(offset: Int) -> WorkoutSummary? {
        let daily = minutes(offset: offset)
        guard daily >= minutesGoal else { return nil }
        let start = calendar.date(
            bySettingHour: 12, minute: 5 + (offset * 7) % 25, second: 0, of: day(offset: offset)
        ) ?? day(offset: offset)
        let duration = TimeInterval(daily * 60)
        return WorkoutSummary(
            id: identifier(offset: offset),
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            durationSeconds: duration,
            distanceKm: Double(daily) * 0.1,
            activeCalories: Int(Double(daily) * 7.4),
            steps: daily * 118,
            elevationMeters: Double(12 + (offset * 5) % 30),
            sourceName: sourceName(offset: offset)
        )
    }

    /// Today's session is Foulée's own; the rest alternate between the two
    /// watches the app reads from, which is the point of the résumé.
    private static func sourceName(offset: Int) -> String {
        guard offset != 0 else { return "Foulée" }
        switch offset % 3 {
        case 0: return "Forerunner 965"
        case 1: return "Apple Watch"
        default: return "Foulée"
        }
    }

    private static func identifier(offset: Int) -> UUID {
        UUID(uuidString: "5C0EE7ED-0000-4000-8000-\(String(format: "%012d", offset))") ?? UUID()
    }

    /// A plausible heart-rate curve for the workout drill-down: a warm-up ramp
    /// with a slow drift, sampled every twelve seconds. Pure arithmetic on the
    /// sample's position — no randomness, no clock.
    static func workoutDetail(_ summary: WorkoutSummary) -> WorkoutDetail {
        let seconds = Int(summary.durationSeconds)
        let samples = stride(from: 0, through: seconds, by: 12).enumerated().map { index, offset in
            let progress = Double(offset) / Double(max(seconds, 1))
            return HeartRateSample(
                id: UUID(uuidString: "5C0EE7ED-0001-4000-8000-\(String(format: "%012d", index))") ?? UUID(),
                date: summary.startedAt.addingTimeInterval(TimeInterval(offset)),
                bpm: Int(102 + progress * 26 + sin(progress * 7) * 5)
            )
        }
        return WorkoutDetail(summary: summary, heartRateSamples: samples, stepsCount: summary.steps)
    }
}
#endif
