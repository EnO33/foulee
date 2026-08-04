import Foundation
import Testing
@testable import Foulee

@Suite("ActiveMinutes")
struct ActiveMinutesTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_716_768_000) // 2024-05-27, stable anchor

    private var startOfToday: Date { calendar.startOfDay(for: today) }

    @Test("Garmin-only day: workouts alone drive the minutes")
    func garminOnlyDay() {
        let workouts = [interval(hour: 12, minutes: 25)]
        let byDay = ActiveMinutes.workoutMinutesByDay(workouts, calendar: calendar)
        #expect(ActiveMinutes.merged(appleMinutes: 0, workoutMinutes: byDay[startOfToday] ?? 0) == 25)
    }

    @Test("Hybrid day: apple minutes already cover the workout — max, never addition")
    func hybridDay() {
        let byDay = ActiveMinutes.workoutMinutesByDay([interval(hour: 12, minutes: 20)], calendar: calendar)
        #expect(ActiveMinutes.merged(appleMinutes: 30, workoutMinutes: byDay[startOfToday] ?? 0) == 30)
    }

    @Test("Apple-only day unchanged (regression pin)")
    func appleOnlyDay() {
        let byDay = ActiveMinutes.workoutMinutesByDay([], calendar: calendar)
        #expect(ActiveMinutes.merged(appleMinutes: 30, workoutMinutes: byDay[startOfToday] ?? 0) == 30)
    }

    @Test("Empty day is 0")
    func emptyDay() {
        #expect(ActiveMinutes.workoutMinutesByDay([], calendar: calendar).isEmpty)
        #expect(ActiveMinutes.merged(appleMinutes: 0, workoutMinutes: 0) == 0)
    }

    @Test("Multiple workouts on one day sum their durations")
    func multiWorkoutDay() {
        let workouts = [interval(hour: 8, minutes: 10), interval(hour: 18, minutes: 15)]
        #expect(ActiveMinutes.workoutMinutesByDay(workouts, calendar: calendar)[startOfToday] == 25)
    }

    @Test("Midnight-crossing workout belongs to its start day")
    func midnightCrossing() {
        let start = startOfToday.addingTimeInterval(23 * 3_600 + 30 * 60) // 23:30
        let workouts = [ActiveMinutes.WorkoutInterval(start: start, duration: 3_600)]
        let byDay = ActiveMinutes.workoutMinutesByDay(workouts, calendar: calendar)
        #expect(byDay == [startOfToday: 60])
    }

    @Test("Daily total is capped at 1440")
    func cappedAtDayLength() {
        #expect(ActiveMinutes.merged(appleMinutes: 0, workoutMinutes: 2_000) == 1_440)
        #expect(ActiveMinutes.merged(appleMinutes: 2_000, workoutMinutes: 0) == 1_440)
    }

    @Test("Seconds are summed per day before truncating to minutes")
    func secondsSummedBeforeTruncation() {
        let workouts = [
            ActiveMinutes.WorkoutInterval(start: startOfToday.addingTimeInterval(8 * 3_600), duration: 90),
            ActiveMinutes.WorkoutInterval(start: startOfToday.addingTimeInterval(9 * 3_600), duration: 90)
        ]
        #expect(ActiveMinutes.workoutMinutesByDay(workouts, calendar: calendar)[startOfToday] == 3)
    }

    @Test("Negative inputs clamp to 0")
    func negativeInputs() {
        #expect(ActiveMinutes.merged(appleMinutes: -5, workoutMinutes: -3) == 0)
        // A backwards span isn't a zero-minute day, it's not a day at all:
        // it's dropped rather than keyed at 0, so an empty-but-present day
        // can't masquerade as recorded activity.
        let backwards = [ActiveMinutes.WorkoutInterval(start: startOfToday, duration: -600)]
        #expect(ActiveMinutes.workoutMinutesByDay(backwards, calendar: calendar)[startOfToday] == nil)
    }

    @Test("The same walk written by two sources counts once on the daily path")
    func duplicateSourcesCountOncePerDay() {
        // Hybrid Apple Watch + Garmin Connect: one midday walk, two HKWorkouts
        // with slightly different bounds. Summing would hand the hero ring,
        // the streak and the widget snapshot 80 minutes for a 42-minute walk.
        let watch = interval(hour: 12, minutes: 40)
        let garmin = ActiveMinutes.WorkoutInterval(
            start: watch.start.addingTimeInterval(120), duration: 40 * 60
        )
        #expect(ActiveMinutes.workoutMinutesByDay([watch, garmin], calendar: calendar) == [startOfToday: 42])
    }

    @Test("An exactly duplicated workout counts once")
    func exactDuplicateCountsOnce() {
        let walk = interval(hour: 9, minutes: 30)
        #expect(ActiveMinutes.workoutMinutesByDay([walk, walk], calendar: calendar) == [startOfToday: 30])
    }

    private func interval(hour: Int, minutes: Int) -> ActiveMinutes.WorkoutInterval {
        ActiveMinutes.WorkoutInterval(
            start: startOfToday.addingTimeInterval(TimeInterval(hour * 3_600)),
            duration: TimeInterval(minutes * 60)
        )
    }
}

/// Hourly clipping — the "Aujourd'hui" curve on the stats screen (#183).
@Suite("ActiveMinutes hourly")
struct ActiveMinutesHourlyTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_716_768_000) // 2024-05-27, stable anchor

    private var startOfToday: Date { calendar.startOfDay(for: today) }

    @Test("A workout inside one hour credits that hour only")
    func withinOneHour() {
        let byHour = ActiveMinutes.workoutMinutesByHour(
            [interval(at: "10:05", minutes: 25)], calendar: calendar
        )
        #expect(byHour == [hour(10): 25])
    }

    @Test("A workout crossing an hour boundary is split, not spiked")
    func crossingHours() {
        let byHour = ActiveMinutes.workoutMinutesByHour(
            [interval(at: "10:50", minutes: 30)], calendar: calendar
        )
        #expect(byHour == [hour(10): 10, hour(11): 20])
    }

    @Test("A workout spanning several hours fills the middle ones")
    func spanningSeveralHours() {
        let byHour = ActiveMinutes.workoutMinutesByHour(
            [interval(at: "09:30", minutes: 150)], calendar: calendar
        )
        #expect(byHour == [hour(9): 30, hour(10): 60, hour(11): 60])
    }

    @Test("A workout crossing midnight credits both days' hours")
    func crossingMidnight() {
        let byHour = ActiveMinutes.workoutMinutesByHour(
            [interval(at: "23:50", minutes: 30)], calendar: calendar
        )
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        #expect(byHour == [hour(23): 10, nextMidnight: 20])
    }

    @Test("Several workouts in the same hour add up but never exceed 60")
    func multipleWorkoutsSameHour() {
        let backToBack = ActiveMinutes.workoutMinutesByHour(
            [interval(at: "14:00", minutes: 20), interval(at: "14:30", minutes: 20)],
            calendar: calendar
        )
        #expect(backToBack == [hour(14): 40])
        // Adjacent sessions that fill the whole hour stay at the 60 ceiling.
        let wallToWall = ActiveMinutes.workoutMinutesByHour(
            [interval(at: "14:00", minutes: 30), interval(at: "14:30", minutes: 30)],
            calendar: calendar
        )
        #expect(wallToWall == [hour(14): 60])
    }

    @Test("The same walk written by two sources counts once, not twice")
    func duplicateSourcesAreUnioned() {
        // Hybrid Apple Watch + Garmin: one 40-min walk, two HKWorkouts with
        // slightly different bounds. Summing would invent 80 minutes.
        let byHour = ActiveMinutes.workoutMinutesByHour(
            [interval(at: "16:00", minutes: 40), interval(at: "16:02", minutes: 40)],
            calendar: calendar
        )
        #expect(byHour == [hour(16): 42])
    }

    @Test("Zero-length and backwards workouts are ignored")
    func degenerateWorkouts() {
        let byHour = ActiveMinutes.workoutMinutesByHour(
            [interval(at: "08:00", minutes: 0), interval(at: "09:00", minutes: -20)],
            calendar: calendar
        )
        #expect(byHour.isEmpty)
    }

    @Test("Hourly buckets sum back to the daily whole-minute total")
    func hourlyRoundingMatchesDaily() {
        // Two 90-second sessions in different hours: truncating each bucket on
        // its own gave 1 + 1 = 2 minutes against a daily 3.
        let workouts = [
            ActiveMinutes.WorkoutInterval(start: hour(8), duration: 90),
            ActiveMinutes.WorkoutInterval(start: hour(9), duration: 90)
        ]
        let byHour = ActiveMinutes.workoutMinutesByHour(workouts, calendar: calendar)
        let byDay = ActiveMinutes.workoutMinutesByDay(workouts, calendar: calendar)
        #expect(byDay[startOfToday] == 3)
        #expect(byHour.values.reduce(0, +) == 3)
    }

    @Test("The curve sums back to the day's merged value, never above it")
    func curveSumsToMergedDay() {
        // Reviewer's case: 45 apple minutes that already contain a 40-minute
        // workout. A per-hour max() totalled 55 under a 45-minute day.
        let workouts = [interval(at: "10:00", minutes: 40)]
        let apple = [hour(8): 5, hour(10): 40]
        let curve = ActiveMinutes.mergedHourlyMinutes(
            appleMinutesByHour: apple, workouts: workouts, calendar: calendar
        )
        let daily = ActiveMinutes.merged(
            appleMinutes: apple.values.reduce(0, +),
            workoutMinutes: ActiveMinutes.workoutMinutesByDay(workouts, calendar: calendar)[startOfToday] ?? 0
        )
        #expect(daily == 45)
        #expect(curve.values.reduce(0, +) == daily)
        #expect(curve == apple)
    }

    @Test("Garmin-only day: the curve is the workouts' own shape")
    func garminOnlyCurve() {
        let workouts = [interval(at: "10:50", minutes: 30)]
        let curve = ActiveMinutes.mergedHourlyMinutes(
            appleMinutesByHour: [:], workouts: workouts, calendar: calendar
        )
        #expect(curve == [hour(10): 10, hour(11): 20])
        #expect(curve.values.reduce(0, +) == 30)
    }

    @Test("Apple-only day: the curve is HealthKit's own buckets, clamped to 60")
    func appleOnlyCurve() {
        let curve = ActiveMinutes.mergedHourlyMinutes(
            appleMinutesByHour: [hour(7): 12, hour(8): 90, hour(9): -4],
            workouts: [],
            calendar: calendar
        )
        #expect(curve == [hour(7): 12, hour(8): 60, hour(9): 0])
    }

    @Test("Duplicated sources never inflate the curve above the day")
    func duplicateSourcesDontInflateCurve() {
        // Same walk from the Watch and from Garmin, no appleExerciseTime.
        let watch = interval(at: "16:00", minutes: 40)
        let garmin = ActiveMinutes.WorkoutInterval(
            start: watch.start.addingTimeInterval(120), duration: 40 * 60
        )
        let curve = ActiveMinutes.mergedHourlyMinutes(
            appleMinutesByHour: [:], workouts: [watch, garmin], calendar: calendar
        )
        let byDay = ActiveMinutes.workoutMinutesByDay([watch, garmin], calendar: calendar)
        #expect(curve.values.reduce(0, +) == byDay[startOfToday])
        #expect(curve == [hour(16): 42])
    }

    /// Hour bucket key for today at `hour` o'clock.
    private func hour(_ value: Int) -> Date {
        startOfToday.addingTimeInterval(TimeInterval(value * 3_600))
    }

    /// A workout starting at `"HH:mm"` today, lasting `minutes`.
    private func interval(at clock: String, minutes: Int) -> ActiveMinutes.WorkoutInterval {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        let offset = TimeInterval((parts.first ?? 0) * 3_600 + (parts.last ?? 0) * 60)
        return ActiveMinutes.WorkoutInterval(
            start: startOfToday.addingTimeInterval(offset),
            duration: TimeInterval(minutes * 60)
        )
    }
}
