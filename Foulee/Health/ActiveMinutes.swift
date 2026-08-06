import Foundation

/// Source-agnostic active-minutes math (issue #181).
///
/// `appleExerciseTime` is read-only and Apple-generated: without an Apple
/// Watch iOS never produces a single sample, so a Garmin-only user (whose
/// Garmin Connect writes its sessions into Health as `HKWorkout`s) would see
/// zero minutes, a dead hero ring and a streak that can never start. Each
/// day's active minutes are therefore derived from both signals:
///
/// - Workout minutes = the time covered by ALL workout activity types that
///   day. This matches `appleExerciseTime` semantics, which credits any
///   exercise — a Garmin user's yoga session is active minutes, exactly like
///   Apple's ring. Never restrict to `.walking`.
/// - Overlapping sessions are unioned before counting, never summed: the same
///   walk written by both Garmin Connect and the Apple Watch is one walk, and
///   adding both would invent minutes the clock never had (issue #183).
/// - A session belongs to the calendar day it starts on (simple and
///   deterministic — a walk crossing midnight credits the day it began).
/// - Day value = `max(appleMinutes, workoutMinutes)`, never a sum: a hybrid
///   Apple Watch + Garmin user's workout is already counted inside
///   `appleExerciseTime`, so adding the two would double-count.
/// - Capped at 1440, the number of minutes in a day.
///
/// The "Aujourd'hui" curve (`mergedHourlyMinutes`) applies the *same* day-level
/// verdict and then draws the winning source's own hourly shape, so the curve
/// always sums back to the day's value instead of contradicting it (#183).
///
/// Pure Foundation so it compiles into both the app and the widget
/// extension (see Project.swift).
enum ActiveMinutes {
    /// Minutes in a civil day — upper bound for any daily total.
    static let dailyCap = 1_440

    /// Minutes in an hour — upper bound for any hourly bucket.
    static let hourlyCap = 60

    /// The two facts about a workout the merge needs, decoupled from
    /// `HKWorkout` so the math stays pure and testable.
    struct WorkoutInterval: Equatable, Sendable {
        var start: Date
        var duration: TimeInterval
    }

    /// One day's merged value: `max(apple, workouts)` clamped to
    /// `0...dailyCap`.
    static func merged(appleMinutes: Int, workoutMinutes: Int) -> Int {
        merged(appleMinutes, with: workoutMinutes)
    }

    /// Folds one more independent measurement of the same day into an
    /// already-merged value, under the same rule. The Connect IQ snapshot's
    /// active minutes (issue #189) enter here: they are a third *term of this
    /// max*, never a third addend — Garmin's intensity minutes and the Garmin
    /// workouts already in Santé are usually the same activity.
    static func merged(_ minutes: Int, with other: Int) -> Int {
        min(max(minutes, other, 0), dailyCap)
    }

    /// Today's active minutes hour by hour, keyed by the hour's start.
    ///
    /// Deliberately **not** a per-hour `max()`: `Σ max(apple, workout) ≥
    /// max(Σ apple, Σ workout)`, so an hourly curve merged bucket by bucket
    /// can total more than the day it belongs to — 45 apple minutes holding a
    /// 40-minute workout used to draw a 55-minute curve under a 45-minute
    /// day. The day's verdict is decided once, on the totals, and the curve is
    /// then the winning source's own shape: the buckets sum back to the day by
    /// construction.
    ///
    /// `appleMinutesByHour` comes straight from HealthKit (which already
    /// merges sources); workout spans are unioned and clipped into the hours
    /// they really span, so a 10:50 → 11:20 session draws 10 + 20 rather than
    /// a 30-minute spike.
    static func mergedHourlyMinutes(
        appleMinutesByHour: [Date: Int],
        workouts: [WorkoutInterval],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        let apple = appleMinutesByHour.mapValues { min(max($0, 0), hourlyCap) }
        let workout = workoutMinutesByHour(workouts, calendar: calendar)
        let appleTotal = apple.values.reduce(0, +)
        let workoutTotal = workout.values.reduce(0, +)
        return appleTotal >= workoutTotal ? apple : workout
    }

    /// Whole workout minutes per day (keyed by the day's start), every
    /// activity type included, each session attributed to the day its span
    /// starts on (simple and deterministic — a walk crossing midnight credits
    /// the day it began).
    ///
    /// Overlapping sessions are unioned before counting, never summed: a
    /// hybrid Apple Watch + Garmin user has the same walk written twice, and
    /// adding both would hand the hero ring, the streak and the widget minutes
    /// the clock never had. Seconds are summed per day before truncating so
    /// short sessions don't each lose up to a minute.
    static func workoutMinutesByDay(
        _ workouts: [WorkoutInterval],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        var secondsByDay: [Date: TimeInterval] = [:]
        for span in unionedSpans(workouts) {
            let day = calendar.startOfDay(for: span.lowerBound)
            secondsByDay[day, default: 0] += span.upperBound.timeIntervalSince(span.lowerBound)
        }
        return secondsByDay.mapValues { Int($0 / 60) }
    }

    /// Whole workout minutes per hour bucket (keyed by the hour's start),
    /// each workout **clipped** to the hours it actually spans: a session
    /// from 10:50 to 11:20 credits 10 minutes to the 10 o'clock hour and 20
    /// to the 11 o'clock one. Unlike the daily attribution (which credits the
    /// whole session to its start day), the hourly chart is a shape — putting
    /// 30 minutes into a single bucket would draw a spike that never happened.
    ///
    /// Overlapping sessions are unioned before clipping, not summed: a hybrid
    /// Apple Watch + Garmin user has the same walk written twice, and adding
    /// both would invent minutes the clock never had.
    static func workoutMinutesByHour(
        _ workouts: [WorkoutInterval],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        var secondsByHour: [Date: TimeInterval] = [:]
        for span in unionedSpans(workouts) {
            var bucket = calendar.dateInterval(of: .hour, for: span.lowerBound)?.start ?? span.lowerBound
            while bucket < span.upperBound {
                let next = calendar.date(byAdding: .hour, value: 1, to: bucket)
                    ?? bucket.addingTimeInterval(3_600)
                guard next > bucket else { break }
                let overlap = min(next, span.upperBound).timeIntervalSince(max(bucket, span.lowerBound))
                if overlap > 0 { secondsByHour[bucket, default: 0] += overlap }
                bucket = next
            }
        }
        return wholeMinutes(secondsByHour)
    }

    /// Seconds per bucket → whole minutes, truncated on the *running* total so
    /// the buckets sum back to `Int(totalSeconds / 60)` — the same whole-minute
    /// figure `workoutMinutesByDay` reports. Truncating each bucket on its own
    /// turned two 90-second sessions into 1 + 1 = 2 minutes against a daily 3;
    /// carrying the leftover seconds forward keeps the curve and the day equal.
    private static func wholeMinutes(_ secondsByBucket: [Date: TimeInterval]) -> [Date: Int] {
        var running: TimeInterval = 0
        var minutesByBucket: [Date: Int] = [:]
        for key in secondsByBucket.keys.sorted() {
            let before = Int(running / 60)
            running += secondsByBucket[key] ?? 0
            minutesByBucket[key] = Int(running / 60) - before
        }
        return minutesByBucket
    }

    /// The stretch of clock a session covers: `start..<start + duration`,
    /// half-open. `nil` for a zero or negative duration — a session with no
    /// length covers no clock and can neither add minutes nor overlap
    /// anything.
    ///
    /// Exposed so the 7-day résumé builds its spans exactly like the minute
    /// count does (#218): a sheet measuring sessions from `endDate` while the
    /// ring measures them from `duration` would disagree about which sessions
    /// are the same one as soon as a workout carries a pause.
    static func span(of interval: WorkoutInterval) -> Range<Date>? {
        guard interval.duration > 0 else { return nil }
        return interval.start..<interval.start.addingTimeInterval(interval.duration)
    }

    /// Two spans overlap when each starts strictly before the other ends.
    ///
    /// Strict on purpose: spans are half-open, so a session ending exactly
    /// when the next starts (10:00→10:30 then 10:30→11:00) does **not**
    /// overlap. That is a back-to-back pair the user really did twice, not one
    /// session written twice, and the résumé must keep listing both (#218).
    ///
    /// The minute count (#183) and the résumé's deduplication (#218) share this
    /// predicate instead of each carrying a copy, so neither can quietly grow
    /// its own idea of "overlapping". They are not the *same rule*, though:
    /// `unionedSpans` folds touching spans on top of this predicate (see there),
    /// and the résumé deliberately does not. That fold is invisible while both
    /// halves of a back-to-back pair fall on one day — it only shows across
    /// midnight, where it decides which day is credited: 23:30→00:00 then
    /// 00:00→00:30 is 60 minutes on the first day for the ring and two 30-minute
    /// rows on two days for the résumé. Pre-dates #218 and is left alone there:
    /// folding those rows would delete a session the user really did twice.
    static func overlap(_ lhs: Range<Date>, _ rhs: Range<Date>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    /// Positive-length workout spans, sorted and merged so overlapping (or
    /// duplicated) sessions count once.
    private static func unionedSpans(_ workouts: [WorkoutInterval]) -> [Range<Date>] {
        let spans = workouts
            .compactMap(span(of:))
            .sorted { $0.lowerBound < $1.lowerBound }
        var unioned: [Range<Date>] = []
        for span in spans {
            // Touching spans fold in here as well as overlapping ones, unlike
            // the résumé's rule: for *counting* minutes 10:00→10:30 followed by
            // 10:30→11:00 covers the very same clock whether it is one range or
            // two, and folding keeps this loop's invariant (one range per
            // uninterrupted stretch of covered clock).
            let touches = span.lowerBound == unioned.last?.upperBound
            guard let last = unioned.last, overlap(span, last) || touches else {
                unioned.append(span)
                continue
            }
            unioned[unioned.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
        }
        return unioned
    }
}
