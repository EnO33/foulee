import Foundation

/// Scalar inputs to the projection — deliberately not `WidgetSnapshot`, so
/// the builder compiles into the watch widget target (which has no snapshot
/// type) and both platforms share one projection policy.
struct WidgetCounters: Equatable, Sendable {
    var steps: Int
    var stepsGoal: Int
    var minutes: Int
    var minutesGoal: Int
    var distanceKm: Double = 0
    var calories: Int = 0
}

/// One projected point of today's counters at a future instant, pre-rendered
/// into a widget timeline so the display keeps moving between two reloads.
/// Steps and minutes are (conservatively) projected; distance and calories are
/// carried through flat — they don't progress predictably enough to fake.
struct WidgetProjectedValue: Equatable, Sendable {
    let date: Date
    let steps: Int
    let minutes: Int
    let distanceKm: Double
    let calories: Int
}

/// Builds the interpolated future entries the daily-counter widgets append
/// after their "now" entry. Everything is produced inside the single
/// getTimeline call each reload slot already makes — more entries, not more
/// reloads, so the daily WidgetKit budget is untouched. The projection is
/// deliberately conservative: bounded, monotonically non-decreasing, and
/// never past local midnight (the zeroed reset entry must stay last).
enum WidgetTimelineBuilder {
    /// Spacing between interpolated entries.
    static let entryStepMinutes = 2
    /// Hard cap so a timeline built long before the next refresh (overnight,
    /// next wake at 08:00) stays small instead of spanning hundreds of points.
    static let maxProjectedEntries = 20
    /// Steps-per-minute pace under which the day reads as idle: the
    /// activity-minutes counter only advances above it.
    static let activePaceStepsPerMinute: Double = 60
    /// The pace is measured from local 06:00, not midnight — counting the
    /// idle night hours would dilute it to nothing by morning.
    static let rateWindowStartHour = 6

    /// The unprojected "now" point followed by projected points every
    /// `entryStepMinutes`, strictly before both `nextRefresh` and
    /// `nextMidnight`.
    static func projectedValues(
        counters: WidgetCounters,
        now: Date,
        nextRefresh: Date,
        nextMidnight: Date,
        calendar: Calendar = .current
    ) -> [WidgetProjectedValue] {
        // Fabricating movement is only safe when the next reload corrects it
        // within one daytime slot. The end-of-window build (next wake 08:00)
        // would otherwise pin a projected value on screen for hours — there,
        // entries are re-dated but flat.
        let correctedSoon = nextRefresh.timeIntervalSince(now)
            <= Double(WidgetRefresh.daytimeStepMinutes * 60)
        let rate = correctedSoon
            ? stepsPerMinute(steps: counters.steps, now: now, calendar: calendar)
            : 0
        // Bounded projection: pace-based, never more than +15 % of the goal
        // within one reload slot — and a projection must never fabricate a
        // goal crossing (a closed ring is a promise; only real steps may
        // close it). Past the goal, twice the goal stays the hard ceiling.
        // `max(steps, …)` keeps a value already beyond a cap flat instead of
        // letting the cap pull it down.
        let steps = counters.steps
        let goalClamp = steps < counters.stepsGoal ? counters.stepsGoal - 1 : counters.stepsGoal * 2
        let stepsCeiling = max(steps, min(steps + (counters.stepsGoal * 15) / 100, goalClamp))
        let minutesGoalClamp = counters.minutes < counters.minutesGoal
            ? counters.minutesGoal - 1
            : counters.minutesGoal * 2
        let minutesCeiling = max(counters.minutes, minutesGoalClamp)
        var values = [point(counters: counters, at: now)]
        for index in 1...maxProjectedEntries {
            guard let date = calendar.date(byAdding: .minute, value: index * entryStepMinutes, to: now),
                  date < nextRefresh, date < nextMidnight else { break }
            let elapsedMinutes = Double(index * entryStepMinutes)
            // Minutes advance at most +1 per elapsed minute, and only while
            // the pace suggests actual activity.
            let minutesAdvance = rate >= activePaceStepsPerMinute ? Int(elapsedMinutes) : 0
            values.append(WidgetProjectedValue(
                date: date,
                steps: min(steps + Int(rate * elapsedMinutes), stepsCeiling),
                minutes: min(counters.minutes + minutesAdvance, minutesCeiling),
                distanceKm: counters.distanceKm,
                calories: counters.calories
            ))
        }
        return values
    }

    /// The snapshot's counters as-is, dated `at` — the anchor every
    /// projection starts from, also useful as a single flat entry.
    static func point(counters: WidgetCounters, at date: Date) -> WidgetProjectedValue {
        WidgetProjectedValue(
            date: date,
            steps: counters.steps,
            minutes: counters.minutes,
            distanceKm: counters.distanceKm,
            calories: counters.calories
        )
    }

    /// Relevance score for a timeline entry: high inside the daytime activity
    /// window so the Smart Stack surfaces the widget while it actually moves.
    static func relevanceScore(at date: Date, calendar: Calendar = .current) -> Float {
        let hour = calendar.component(.hour, from: date)
        let isActiveWindow = hour >= WidgetRefresh.windowStartHour && hour < WidgetRefresh.windowEndHour
        return isActiveWindow ? 1 : 0.2
    }

    /// Average pace since local 06:00, floored at 0 — the conservative slope
    /// the projection extends.
    private static func stepsPerMinute(steps: Int, now: Date, calendar: Calendar) -> Double {
        let dayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .hour, value: rateWindowStartHour, to: dayStart) else {
            return 0
        }
        let elapsedMinutes = now.timeIntervalSince(windowStart) / 60
        guard elapsedMinutes >= 1 else { return 0 }
        return Double(max(steps, 0)) / elapsedMinutes
    }
}
